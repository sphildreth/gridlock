import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:decentdb/decentdb.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../domain/sqlite_import_models.dart';
import '../domain/workspace_models.dart';

Future<SqliteImportInspection> inspectSqliteSourceInBackground(
  String sourcePath,
) {
  return Isolate.run(() => inspectSqliteSourceFile(sourcePath));
}

SqliteImportInspection inspectSqliteSourceFile(String sourcePath) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    throw BridgeFailure('SQLite source file does not exist: $sourcePath');
  }

  final database = sqlite.sqlite3.open(
    sourcePath,
    mode: sqlite.OpenMode.readOnly,
  );
  try {
    database.execute('PRAGMA foreign_keys = ON;');
    final tables = <SqliteImportTableDraft>[];
    final warnings = <String>[];
    for (final table in _listUserTables(database)) {
      final draft = _inspectTable(database, table.name, table.sql);
      tables.add(draft);
      if (draft.strict) {
        warnings.add(
          '${draft.sourceName} uses STRICT in SQLite; Decent Bench imports it as a regular DecentDB table.',
        );
      }
      if (draft.withoutRowId) {
        warnings.add(
          '${draft.sourceName} uses WITHOUT ROWID in SQLite; Decent Bench preserves data and keys but not WITHOUT ROWID storage semantics.',
        );
      }
      for (final column in draft.columns) {
        if (column.generatedVirtual) {
          warnings.add(
            '${draft.sourceName}.${column.sourceName} is a VIRTUAL generated column in SQLite; Decent Bench imports its current values into a regular DecentDB column because DecentDB supports STORED generated columns.',
          );
        }
      }
    }

    return SqliteImportInspection(
      sourcePath: sourcePath,
      tables: tables,
      warnings: warnings,
    );
  } finally {
    database.close();
  }
}

Future<SqliteImportPreview> loadSqlitePreviewInBackground(
  String sourcePath,
  String tableName, {
  int limit = 8,
}) {
  return Isolate.run(
    () => loadSqlitePreview(sourcePath, tableName, limit: limit),
  );
}

SqliteImportPreview loadSqlitePreview(
  String sourcePath,
  String tableName, {
  int limit = 8,
}) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    throw BridgeFailure('SQLite source file does not exist: $sourcePath');
  }

  final database = sqlite.sqlite3.open(
    sourcePath,
    mode: sqlite.OpenMode.readOnly,
  );
  try {
    final quotedTable = _quoteSqliteIdent(tableName);
    final rows = database.select('SELECT * FROM $quotedTable LIMIT $limit');
    final previewRows = <Map<String, Object?>>[
      for (final row in rows)
        <String, Object?>{for (final column in row.keys) column: row[column]},
    ];
    return SqliteImportPreview(tableName: tableName, rows: previewRows);
  } finally {
    database.close();
  }
}

@pragma('vm:entry-point')
Future<void> sqliteImportWorkerMain(List<Object?> bootstrap) async {
  final mainPort = bootstrap[0]! as SendPort;
  final libraryPath = bootstrap[1]! as String;
  final request = SqliteImportRequest.fromMap(
    (bootstrap[2]! as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key as String, value),
    ),
  );

  final commandPort = ReceivePort();
  mainPort.send(commandPort.sendPort);

  var cancelled = false;
  late final StreamSubscription<Object?> commandSubscription;
  commandSubscription = commandPort.listen((message) {
    if (message == 'cancel') {
      cancelled = true;
    }
  });

  try {
    final summary = await _runSqliteImport(
      request: request,
      libraryPath: libraryPath,
      sendUpdate: (update) => mainPort.send(update.toMap()),
      isCancelled: () => cancelled,
    );
    mainPort.send(
      SqliteImportUpdate(
        kind: cancelled
            ? SqliteImportUpdateKind.cancelled
            : SqliteImportUpdateKind.completed,
        jobId: request.jobId,
        summary: summary,
      ).toMap(),
    );
  } on _SqliteImportCancelled catch (error) {
    mainPort.send(
      SqliteImportUpdate(
        kind: SqliteImportUpdateKind.cancelled,
        jobId: request.jobId,
        summary: error.summary,
        message: error.summary.statusMessage,
      ).toMap(),
    );
  } catch (error) {
    mainPort.send(
      SqliteImportUpdate(
        kind: SqliteImportUpdateKind.failed,
        jobId: request.jobId,
        message: error.toString(),
      ).toMap(),
    );
  } finally {
    await commandSubscription.cancel();
    commandPort.close();
  }
}

Future<SqliteImportSummary> _runSqliteImport({
  required SqliteImportRequest request,
  required String libraryPath,
  required void Function(SqliteImportUpdate update) sendUpdate,
  required bool Function() isCancelled,
}) async {
  if (request.selectedTables.isEmpty) {
    throw const BridgeFailure('Select at least one SQLite table to import.');
  }

  _validateRequestNames(request);

  final sourceFile = File(request.sourcePath);
  if (!sourceFile.existsSync()) {
    throw BridgeFailure(
      'SQLite source file does not exist: ${request.sourcePath}',
    );
  }

  final targetFile = File(request.targetPath);
  if (request.importIntoExistingTarget) {
    if (!targetFile.existsSync()) {
      throw BridgeFailure(
        'Target DecentDB file does not exist: ${request.targetPath}',
      );
    }
  } else {
    targetFile.parent.createSync(recursive: true);
    if (targetFile.existsSync()) {
      if (!request.replaceExistingTarget) {
        throw BridgeFailure(
          'Refusing to replace an existing DecentDB file without confirmation: ${request.targetPath}',
        );
      }
      targetFile.deleteSync();
      final walFile = File('${request.targetPath}-wal');
      if (walFile.existsSync()) {
        walFile.deleteSync();
      }
    }
  }

  final source = sqlite.sqlite3.open(
    request.sourcePath,
    mode: sqlite.OpenMode.readOnly,
  );
  final target = Database.open(request.targetPath, libraryPath: libraryPath);
  var transactionOpen = false;
  final rowsCopied = <String, int>{};
  final indexesCreated = <String>[];
  final skippedItems = <SqliteImportSkippedItem>[
    for (final table in request.selectedTables) ...table.skippedItems,
  ];
  final warnings = <String>[];

  try {
    source.execute('PRAGMA foreign_keys = ON;');

    final orderedTables = _toposortSelectedTables(
      request.selectedTables,
      warnings,
    );

    final existingTables = target.schema.listTables().toSet();
    final colliding = orderedTables
        .map((table) => table.targetName)
        .where(existingTables.contains)
        .toList();
    if (colliding.isNotEmpty) {
      throw BridgeFailure(
        'Target already contains table(s): ${colliding.join(", ")}. Rename them or choose another DecentDB file.',
      );
    }
    final usedIndexNames = target.schema
        .listIndexes()
        .map((index) => index.name)
        .toSet();

    target.begin();
    transactionOpen = true;

    for (var i = 0; i < orderedTables.length; i++) {
      final table = orderedTables[i];
      _throwIfCancelled(isCancelled);
      target.execute(
        _buildCreateTableSql(table, orderedTables, skippedItems, warnings),
      );
      sendUpdate(
        SqliteImportUpdate(
          kind: SqliteImportUpdateKind.progress,
          jobId: request.jobId,
          progress: SqliteImportProgress(
            jobId: request.jobId,
            currentTable: table.targetName,
            completedTables: i,
            totalTables: orderedTables.length,
            currentTableRowsCopied: 0,
            currentTableRowCount: table.rowCount,
            totalRowsCopied: rowsCopied.values.fold<int>(
              0,
              (sum, value) => sum + value,
            ),
            message: 'Created table ${table.targetName}.',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    for (var i = 0; i < orderedTables.length; i++) {
      final table = orderedTables[i];
      final copied = await _copyTableData(
        source: source,
        target: target,
        request: request,
        table: table,
        completedTables: i,
        totalTables: orderedTables.length,
        priorRowsCopied: rowsCopied.values.fold<int>(
          0,
          (sum, value) => sum + value,
        ),
        sendUpdate: sendUpdate,
        isCancelled: isCancelled,
      );
      rowsCopied[table.targetName] = copied;
    }

    for (final table in orderedTables) {
      _throwIfCancelled(isCancelled);
      for (final index in table.indexes) {
        final indexName = _allocateImportedIndexName(
          index.name,
          usedIndexNames,
        );
        final createIndexSql = _buildCreateIndexSql(
          table,
          index,
          indexName: indexName,
        );
        try {
          target.execute(createIndexSql);
          indexesCreated.add(indexName);
          usedIndexNames.add(indexName);
        } catch (error) {
          skippedItems.add(
            SqliteImportSkippedItem(
              name: index.name,
              tableName: table.sourceName,
              reason:
                  'Index was skipped because DecentDB rejected the translated definition: ${_compactErrorMessage(error)}',
            ),
          );
          warnings.add(
            'Skipping index ${table.sourceName}.${index.name} because DecentDB rejected the translated definition: ${_compactErrorMessage(error)}',
          );
        }
      }
      await Future<void>.delayed(Duration.zero);
    }

    target.commit();
    transactionOpen = false;

    return SqliteImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: orderedTables.map((table) => table.targetName).toList(),
      rowsCopiedByTable: rowsCopied,
      indexesCreated: indexesCreated,
      skippedItems: skippedItems,
      warnings: warnings,
      statusMessage:
          'Imported ${rowsCopied.values.fold<int>(0, (sum, value) => sum + value)} rows from ${orderedTables.length} SQLite table${orderedTables.length == 1 ? '' : 's'}.',
      rolledBack: false,
    );
  } on _SqliteImportCancelledSignal {
    if (transactionOpen) {
      try {
        target.rollback();
      } catch (_) {
        // Best-effort rollback for cancellation.
      }
    }
    final summary = SqliteImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: rowsCopied.keys.toList(),
      rowsCopiedByTable: rowsCopied,
      indexesCreated: indexesCreated,
      skippedItems: skippedItems,
      warnings: warnings,
      statusMessage: 'SQLite import cancelled and rolled back.',
      rolledBack: true,
    );
    throw _SqliteImportCancelled(summary);
  } catch (_) {
    if (transactionOpen) {
      try {
        target.rollback();
      } catch (_) {
        // Best-effort rollback on failure.
      }
    }
    rethrow;
  } finally {
    target.close();
    source.close();
  }
}

Future<int> _copyTableData({
  required sqlite.Database source,
  required Database target,
  required SqliteImportRequest request,
  required SqliteImportTableDraft table,
  required int completedTables,
  required int totalTables,
  required int priorRowsCopied,
  required void Function(SqliteImportUpdate update) sendUpdate,
  required bool Function() isCancelled,
}) async {
  final insertedColumns = table.columns
      .where((column) => !_importsAsGeneratedStored(column))
      .toList(growable: false);
  final sourceColumns = insertedColumns.isEmpty
      ? '1 AS _import_row_marker'
      : insertedColumns
            .map((column) => _quoteSqliteIdent(column.sourceName))
            .join(', ');
  final sourceStatement = source.prepare(
    'SELECT $sourceColumns FROM ${_quoteSqliteIdent(table.sourceName)}',
  );
  final placeholders = <String>[
    for (var i = 0; i < insertedColumns.length; i++)
      _placeholderForType(insertedColumns[i].targetType, i + 1),
  ];
  final targetStatement = target.prepare(
    insertedColumns.isEmpty
        ? 'INSERT INTO ${_quoteDecentIdent(table.targetName)} DEFAULT VALUES'
        : 'INSERT INTO ${_quoteDecentIdent(table.targetName)} '
              '(${insertedColumns.map((column) => _quoteDecentIdent(column.targetName)).join(", ")}) '
              'VALUES (${placeholders.join(", ")})',
  );

  var copied = 0;
  try {
    final cursor = sourceStatement.selectCursor();
    while (cursor.moveNext()) {
      _throwIfCancelled(isCancelled);
      final row = cursor.current;
      final values = <Object?>[
        for (final column in insertedColumns)
          _adaptImportValue(row[column.sourceName], column.targetType),
      ];
      targetStatement.reset();
      targetStatement.clearBindings();
      if (insertedColumns.isNotEmpty) {
        targetStatement.bindAll(values);
      }
      targetStatement.execute();
      copied++;

      if (copied == 1 || copied % 200 == 0 || copied == table.rowCount) {
        sendUpdate(
          SqliteImportUpdate(
            kind: SqliteImportUpdateKind.progress,
            jobId: request.jobId,
            progress: SqliteImportProgress(
              jobId: request.jobId,
              currentTable: table.targetName,
              completedTables: completedTables,
              totalTables: totalTables,
              currentTableRowsCopied: copied,
              currentTableRowCount: table.rowCount,
              totalRowsCopied: priorRowsCopied + copied,
              message: 'Copying ${table.targetName}...',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
  } finally {
    targetStatement.dispose();
    sourceStatement.close();
  }
  return copied;
}

void _validateRequestNames(SqliteImportRequest request) {
  final selectedTables = request.selectedTables;
  final targetTableNames = <String>{};
  for (final table in selectedTables) {
    final targetTableName = table.targetName.trim();
    if (targetTableName.isEmpty) {
      throw BridgeFailure(
        'Each selected SQLite table needs a target DecentDB table name.',
      );
    }
    if (!targetTableNames.add(targetTableName)) {
      throw BridgeFailure(
        'Target table names must be unique. Duplicate: $targetTableName',
      );
    }

    final targetColumnNames = <String>{};
    for (final column in table.columns) {
      final targetColumnName = column.targetName.trim();
      if (targetColumnName.isEmpty) {
        throw BridgeFailure(
          'Each imported column needs a target name (${table.sourceName}.${column.sourceName}).',
        );
      }
      if (!targetColumnNames.add(targetColumnName)) {
        throw BridgeFailure(
          'Target column names must be unique within ${table.targetName}. Duplicate: $targetColumnName',
        );
      }
    }
  }
}

void _throwIfCancelled(bool Function() isCancelled) {
  if (!isCancelled()) {
    return;
  }
  throw const _SqliteImportCancelledSignal();
}

List<({String name, String? sql})> _listUserTables(sqlite.Database database) {
  final result = database.select(
    "SELECT name, sql FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  return <({String name, String? sql})>[
    for (final row in result)
      (name: row['name']! as String, sql: row['sql'] as String?),
  ];
}

SqliteImportTableDraft _inspectTable(
  sqlite.Database database,
  String tableName,
  String? tableSql,
) {
  final parsedTableSql = _parseTableSqlMetadata(tableSql);
  final columns = <SqliteImportColumnDraft>[];
  final columnIndex = <String, int>{};
  final skippedItems = <SqliteImportSkippedItem>[];
  final columnInfo =
      database
          .select('PRAGMA table_xinfo(${_quoteSqliteIdent(tableName)})')
          .toList()
        ..sort(
          (left, right) => ((left['cid'] as int?) ?? 0).compareTo(
            (right['cid'] as int?) ?? 0,
          ),
        );

  for (final row in columnInfo) {
    final hidden = (row['hidden'] as int?) ?? 0;
    if (hidden == 1) {
      continue;
    }
    final sourceName = row['name']! as String;
    final declaredType = (row['type'] as String?) ?? '';
    final inferredType = mapSqliteDeclaredTypeToDecentDb(declaredType);
    final column = SqliteImportColumnDraft(
      sourceName: sourceName,
      targetName: sourceName,
      declaredType: declaredType,
      inferredTargetType: inferredType,
      targetType: inferredType,
      notNull: (row['notnull'] as int?) == 1,
      primaryKey: ((row['pk'] as int?) ?? 0) > 0,
      unique: false,
      defaultExpr: row['dflt_value'] as String?,
      generatedExpr: parsedTableSql.generatedExprByColumn[sourceName],
      generatedStored: hidden == 3,
      generatedVirtual: hidden == 2,
    );
    columnIndex[sourceName] = columns.length;
    columns.add(column);
  }

  final foreignKeys = <SqliteImportForeignKey>[];
  final foreignKeyGroups = <int, List<sqlite.Row>>{};
  final foreignKeyRows = database.select(
    'PRAGMA foreign_key_list(${_quoteSqliteIdent(tableName)})',
  );
  for (final row in foreignKeyRows) {
    final id = (row['id'] as int?) ?? 0;
    foreignKeyGroups.putIfAbsent(id, () => <sqlite.Row>[]).add(row);
  }
  final orderedForeignKeyIds = foreignKeyGroups.keys.toList()..sort();
  for (final id in orderedForeignKeyIds) {
    final group = foreignKeyGroups[id]!
      ..sort(
        (left, right) =>
            ((left['seq'] as int?) ?? 0).compareTo((right['seq'] as int?) ?? 0),
      );
    if (group.length != 1) {
      final parentTable = group.first['table']! as String;
      final fromColumns = group.map((row) => row['from']! as String).join(', ');
      final toColumns = group
          .map((row) => (row['to'] as String?) ?? '<primary key>')
          .join(', ');
      skippedItems.add(
        SqliteImportSkippedItem(
          name: 'fk_$id',
          tableName: tableName,
          reason:
              'Composite foreign key ($fromColumns) -> $parentTable($toColumns) is not imported because DecentDB imports currently support single-column foreign keys only.',
        ),
      );
      continue;
    }
    final row = group.single;
    final toTable = row['table']! as String;
    foreignKeys.add(
      SqliteImportForeignKey(
        fromColumn: row['from']! as String,
        toTable: toTable,
        toColumn:
            row['to'] as String? ??
            _inferSinglePrimaryKeyColumn(database, toTable),
        onDelete: _normalizeSqliteForeignKeyAction(row['on_delete']),
        onUpdate: _normalizeSqliteForeignKeyAction(row['on_update']),
      ),
    );
  }

  final indexes = <SqliteImportIndex>[];
  final indexRows =
      database
          .select('PRAGMA index_list(${_quoteSqliteIdent(tableName)})')
          .toList()
        ..sort(
          (left, right) => ((left['seq'] as int?) ?? 0).compareTo(
            (right['seq'] as int?) ?? 0,
          ),
        );
  for (final row in indexRows) {
    final indexName = row['name']! as String;
    final unique = (row['unique'] as int?) == 1;
    final origin = ((row['origin'] as String?) ?? '').toLowerCase();
    if (origin == 'pk') {
      continue;
    }
    final indexInfo =
        database
            .select('PRAGMA index_xinfo(${_quoteSqliteIdent(indexName)})')
            .toList()
          ..sort(
            (left, right) => ((left['seqno'] as int?) ?? 0).compareTo(
              (right['seqno'] as int?) ?? 0,
            ),
          );
    final keyRows = indexInfo
        .where((item) => (item['key'] as int?) != 0)
        .toList(growable: false);
    if (_indexHasDescendingKey(keyRows)) {
      skippedItems.add(
        SqliteImportSkippedItem(
          name: indexName,
          tableName: tableName,
          reason:
              'Descending SQLite indexes are not imported because DecentDB does not preserve descending index keys.',
        ),
      );
      continue;
    }
    if (_indexHasCustomCollation(keyRows)) {
      skippedItems.add(
        SqliteImportSkippedItem(
          name: indexName,
          tableName: tableName,
          reason:
              'SQLite indexes that depend on custom collations are not imported because DecentDB does not preserve SQLite collation metadata.',
        ),
      );
      continue;
    }
    final parsedIndexSql = _parseIndexSql(
      _lookupSqliteMasterObjectSql(database, type: 'index', name: indexName),
    );
    final elements =
        (parsedIndexSql?.elements ?? _extractPlainIndexElements(keyRows))
            .map((element) => element.trim())
            .where((element) => element.isNotEmpty)
            .toList(growable: false);
    if (elements.isEmpty) {
      skippedItems.add(
        SqliteImportSkippedItem(
          name: indexName,
          tableName: tableName,
          reason:
              'SQLite index definition could not be translated into DecentDB SQL.',
        ),
      );
      continue;
    }
    final whereSql = parsedIndexSql?.whereSql;
    final singleColumnConstraint =
        unique &&
        origin == 'u' &&
        (whereSql == null || whereSql.trim().isEmpty) &&
        elements.length == 1;
    final constrainedColumn = singleColumnConstraint
        ? _findSourceColumnForIndexElement(columns, elements.single)
        : null;
    if (constrainedColumn != null &&
        columnIndex.containsKey(constrainedColumn)) {
      final idx = columnIndex[constrainedColumn]!;
      columns[idx] = columns[idx].copyWith(unique: true);
      continue;
    }
    indexes.add(
      SqliteImportIndex(
        name: indexName,
        elements: elements,
        unique: unique,
        whereSql: whereSql,
      ),
    );
  }

  final rowCountResult = database.select(
    'SELECT COUNT(*) AS row_count FROM ${_quoteSqliteIdent(tableName)}',
  );
  final rowCount = rowCountResult.first['row_count']! as int;

  return SqliteImportTableDraft(
    sourceName: tableName,
    targetName: tableName,
    selected: true,
    rowCount: rowCount,
    strict: _tableSqlHasOption(tableSql, 'STRICT'),
    withoutRowId: _tableSqlHasOption(tableSql, 'WITHOUT ROWID'),
    columns: columns,
    foreignKeys: foreignKeys,
    checks: parsedTableSql.checks,
    indexes: indexes,
    skippedItems: skippedItems,
    previewRows: const <Map<String, Object?>>[],
    previewLoaded: false,
  );
}

List<SqliteImportTableDraft> _toposortSelectedTables(
  List<SqliteImportTableDraft> tables,
  List<String> warnings,
) {
  final bySourceName = <String, SqliteImportTableDraft>{
    for (final table in tables) table.sourceName: table,
  };
  final dependencies = <String, Set<String>>{
    for (final table in tables) table.sourceName: <String>{},
  };
  final reverseEdges = <String, Set<String>>{
    for (final table in tables) table.sourceName: <String>{},
  };

  for (final table in tables) {
    for (final foreignKey in table.foreignKeys) {
      final target = bySourceName[foreignKey.toTable];
      if (target == null) {
        warnings.add(
          'Skipping foreign key ${table.sourceName}.${foreignKey.fromColumn} -> ${_describeForeignKeyTarget(foreignKey)} because the referenced table is not selected.',
        );
        continue;
      }
      dependencies[table.sourceName]!.add(target.sourceName);
      reverseEdges[target.sourceName]!.add(table.sourceName);
    }
  }

  final indegree = <String, int>{
    for (final entry in dependencies.entries) entry.key: entry.value.length,
  };
  final queue = Queue<String>()
    ..addAll(
      indegree.entries
          .where((entry) => entry.value == 0)
          .map((entry) => entry.key),
    );

  final ordered = <SqliteImportTableDraft>[];
  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    ordered.add(bySourceName[current]!);
    for (final dependent in reverseEdges[current]!) {
      indegree[dependent] = indegree[dependent]! - 1;
      if (indegree[dependent] == 0) {
        queue.add(dependent);
      }
    }
  }

  if (ordered.length != tables.length) {
    final cycle =
        indegree.entries
            .where((entry) => entry.value > 0)
            .map((entry) => entry.key)
            .toList()
          ..sort();
    throw BridgeFailure(
      'SQLite import cannot preserve the selected foreign key cycle: ${cycle.join(", ")}. Import a different table set or rename/drop the dependency first.',
    );
  }

  return ordered;
}

String _buildCreateTableSql(
  SqliteImportTableDraft table,
  List<SqliteImportTableDraft> selectedTables,
  List<SqliteImportSkippedItem> skippedItems,
  List<String> warnings,
) {
  final selectedBySource = <String, SqliteImportTableDraft>{
    for (final selected in selectedTables) selected.sourceName: selected,
  };
  final foreignKeyByColumn = <String, SqliteImportForeignKey>{
    for (final foreignKey in table.foreignKeys)
      foreignKey.fromColumn: foreignKey,
  };
  final primaryKeyColumns = table.columns
      .where((column) => column.primaryKey)
      .toList();
  final hasCompositePrimaryKey = primaryKeyColumns.length > 1;
  final sourceToTargetColumns = _sourceToTargetColumnMap(table);

  final definitions = <String>[];
  for (final column in table.columns) {
    final importsAsGeneratedStored = _importsAsGeneratedStored(column);
    if (column.generatedVirtual) {
      warnings.add(
        'Importing ${table.sourceName}.${column.sourceName} as a regular DecentDB column because SQLite VIRTUAL generated columns are not supported by DecentDB.',
      );
    } else if (column.generatedStored && !importsAsGeneratedStored) {
      warnings.add(
        'Importing ${table.sourceName}.${column.sourceName} as a regular DecentDB column because its generated expression could not be reconstructed from the SQLite schema.',
      );
    }
    final parts = <String>[
      _quoteDecentIdent(column.targetName),
      column.targetType,
    ];

    if (column.primaryKey && !hasCompositePrimaryKey) {
      parts.add('PRIMARY KEY');
    } else {
      if (column.notNull || column.primaryKey) {
        parts.add('NOT NULL');
      }
      if (column.unique) {
        parts.add('UNIQUE');
      }
    }
    if (column.hasDefault) {
      parts.add('DEFAULT ${column.defaultExpr}');
    }
    if (importsAsGeneratedStored) {
      parts.add(
        'GENERATED ALWAYS AS (${_rewriteSqlIdentifiers(column.generatedExpr!, sourceToTargetColumns, sourceTableName: table.sourceName, targetTableName: table.targetName)}) STORED',
      );
    }

    final foreignKey = foreignKeyByColumn[column.sourceName];
    final targetTable = foreignKey == null
        ? null
        : selectedBySource[foreignKey.toTable];
    if (foreignKey != null && targetTable != null) {
      final targetColumn = _resolveForeignKeyTargetColumn(
        foreignKey,
        targetTable,
      );
      if (targetColumn != null) {
        parts.add(
          'REFERENCES ${_quoteDecentIdent(targetTable.targetName)}'
          '(${_quoteDecentIdent(targetColumn)})',
        );
        if (_shouldEmitForeignKeyAction(foreignKey.onDelete)) {
          parts.add('ON DELETE ${foreignKey.onDelete!.trim()}');
        }
        if (_shouldEmitForeignKeyAction(foreignKey.onUpdate)) {
          parts.add('ON UPDATE ${foreignKey.onUpdate!.trim()}');
        }
      } else {
        skippedItems.add(
          SqliteImportSkippedItem(
            name: '${table.sourceName}.${column.sourceName}',
            tableName: table.sourceName,
            reason:
                'Foreign key to ${_describeForeignKeyTarget(foreignKey)} skipped because the referenced primary key could not be resolved.',
          ),
        );
        warnings.add(
          'Skipping foreign key ${table.sourceName}.${column.sourceName} -> ${_describeForeignKeyTarget(foreignKey)} because the referenced primary key could not be resolved.',
        );
      }
    } else if (foreignKey != null) {
      skippedItems.add(
        SqliteImportSkippedItem(
          name: '${table.sourceName}.${column.sourceName}',
          tableName: table.sourceName,
          reason:
              'Foreign key to ${_describeForeignKeyTarget(foreignKey)} skipped because that table is not selected.',
        ),
      );
      warnings.add(
        'Skipping foreign key ${table.sourceName}.${column.sourceName} -> ${_describeForeignKeyTarget(foreignKey)} because the referenced table is not selected.',
      );
    }

    definitions.add(parts.join(' '));
  }

  if (hasCompositePrimaryKey) {
    definitions.add(
      'PRIMARY KEY (${primaryKeyColumns.map((column) => _quoteDecentIdent(column.targetName)).join(", ")})',
    );
  }
  for (final check in table.checks) {
    final exprSql = _rewriteSqlIdentifiers(
      check.exprSql,
      sourceToTargetColumns,
      sourceTableName: table.sourceName,
      targetTableName: table.targetName,
    );
    final name = check.name?.trim();
    definitions.add(
      name == null || name.isEmpty
          ? 'CHECK ($exprSql)'
          : 'CONSTRAINT ${_quoteDecentIdent(name)} CHECK ($exprSql)',
    );
  }

  return 'CREATE TABLE ${_quoteDecentIdent(table.targetName)} (${definitions.join(", ")})';
}

String _buildCreateIndexSql(
  SqliteImportTableDraft table,
  SqliteImportIndex index, {
  required String indexName,
}) {
  final elementsSql = index.resolvedElements
      .map((element) => _translateIndexElementSql(table, element))
      .join(', ');
  final buffer = StringBuffer(
    index.unique ? 'CREATE UNIQUE INDEX ' : 'CREATE INDEX ',
  );
  buffer.write(_quoteDecentIdent(indexName));
  buffer.write(' ON ${_quoteDecentIdent(table.targetName)} ($elementsSql)');
  final whereSql = index.whereSql?.trim();
  if (whereSql != null && whereSql.isNotEmpty) {
    buffer.write(
      ' WHERE ${_rewriteSqlIdentifiers(whereSql, _sourceToTargetColumnMap(table), sourceTableName: table.sourceName, targetTableName: table.targetName)}',
    );
  }
  return buffer.toString();
}

String _translateIndexElementSql(
  SqliteImportTableDraft table,
  String elementSql,
) {
  final sourceColumn = _findSourceColumnForIndexElement(
    table.columns,
    elementSql,
  );
  if (sourceColumn != null) {
    return _quoteDecentIdent(_targetColumnName(table, sourceColumn));
  }
  return _rewriteSqlIdentifiers(
    elementSql,
    _sourceToTargetColumnMap(table),
    sourceTableName: table.sourceName,
    targetTableName: table.targetName,
  );
}

String _targetColumnName(
  SqliteImportTableDraft table,
  String sourceColumnName,
) {
  for (final column in table.columns) {
    if (column.sourceName == sourceColumnName) {
      return column.targetName;
    }
  }
  return sourceColumnName;
}

String? _inferSinglePrimaryKeyColumn(
  sqlite.Database database,
  String tableName,
) {
  final tableInfo = database.select(
    'PRAGMA table_xinfo(${_quoteSqliteIdent(tableName)})',
  );
  final primaryKeyColumns = <String>[
    for (final row in tableInfo)
      if (((row['pk'] as int?) ?? 0) > 0) row['name']! as String,
  ];
  if (primaryKeyColumns.length == 1) {
    return primaryKeyColumns.single;
  }
  return null;
}

String _describeForeignKeyTarget(SqliteImportForeignKey foreignKey) {
  final toColumn = foreignKey.toColumn;
  if (toColumn == null || toColumn.trim().isEmpty) {
    return '${foreignKey.toTable}.<primary key>';
  }
  return '${foreignKey.toTable}.$toColumn';
}

String? _resolveForeignKeyTargetColumn(
  SqliteImportForeignKey foreignKey,
  SqliteImportTableDraft targetTable,
) {
  final toColumn = foreignKey.toColumn;
  if (toColumn != null && toColumn.trim().isNotEmpty) {
    return _targetColumnName(targetTable, toColumn);
  }
  final primaryKeyColumns = targetTable.columns
      .where((column) => column.primaryKey)
      .toList(growable: false);
  if (primaryKeyColumns.length == 1) {
    return primaryKeyColumns.single.targetName;
  }
  return null;
}

bool _importsAsGeneratedStored(SqliteImportColumnDraft column) {
  return column.generatedStored &&
      column.generatedExpr != null &&
      column.generatedExpr!.trim().isNotEmpty;
}

Map<String, String> _sourceToTargetColumnMap(SqliteImportTableDraft table) {
  return <String, String>{
    for (final column in table.columns) column.sourceName: column.targetName,
  };
}

String? _normalizeSqliteForeignKeyAction(Object? value) {
  final action = (value as String?)?.trim();
  if (action == null || action.isEmpty) {
    return null;
  }
  final normalized = action.toUpperCase();
  return normalized == 'NO ACTION' ? null : normalized;
}

bool _shouldEmitForeignKeyAction(String? value) {
  return value != null && value.trim().isNotEmpty;
}

bool _indexHasDescendingKey(List<sqlite.Row> rows) {
  for (final row in rows) {
    if ((row['desc'] as int?) == 1) {
      return true;
    }
  }
  return false;
}

bool _indexHasCustomCollation(List<sqlite.Row> rows) {
  for (final row in rows) {
    final collation = (row['coll'] as String?)?.trim();
    if (collation != null &&
        collation.isNotEmpty &&
        collation.toUpperCase() != 'BINARY') {
      return true;
    }
  }
  return false;
}

List<String> _extractPlainIndexElements(List<sqlite.Row> rows) {
  final elements = <String>[];
  for (final row in rows) {
    final name = row['name'] as String?;
    final cid = row['cid'] as int?;
    if (name == null || name.trim().isEmpty || cid == null || cid < 0) {
      return const <String>[];
    }
    elements.add(name);
  }
  return elements;
}

String? _findSourceColumnForIndexElement(
  List<SqliteImportColumnDraft> columns,
  String elementSql,
) {
  for (final column in columns) {
    if (_sqlIdentifierMatches(elementSql, column.sourceName)) {
      return column.sourceName;
    }
  }
  return null;
}

String _allocateImportedIndexName(String sourceName, Set<String> usedNames) {
  final baseName = sourceName.trim().isEmpty
      ? 'imported_index'
      : sourceName.trim();
  if (!usedNames.contains(baseName)) {
    return baseName;
  }
  var suffix = 2;
  while (usedNames.contains('${baseName}_$suffix')) {
    suffix++;
  }
  return '${baseName}_$suffix';
}

String _compactErrorMessage(Object error) {
  final raw = error is BridgeFailure ? error.message : error.toString();
  return raw.replaceFirst(RegExp(r'^[A-Za-z_]+Exception:\s*'), '').trim();
}

_ParsedTableSqlMetadata _parseTableSqlMetadata(String? tableSql) {
  final body = _extractCreateTableBody(tableSql);
  if (body == null || body.trim().isEmpty) {
    return const _ParsedTableSqlMetadata();
  }
  final generatedExprByColumn = <String, String>{};
  final checks = <SqliteImportCheckConstraint>[];
  for (final definition in _splitTopLevelCommaSeparated(body)) {
    final trimmed = definition.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    if (_isTableConstraintDefinition(trimmed)) {
      final check = _parseStandaloneCheckConstraint(trimmed);
      if (check != null) {
        checks.add(check);
      }
      continue;
    }
    final identifier = _readSqlIdentifier(trimmed, 0);
    if (identifier == null) {
      continue;
    }
    final generatedExpr = _extractGeneratedExpression(trimmed);
    if (generatedExpr != null && generatedExpr.trim().isNotEmpty) {
      generatedExprByColumn[identifier.value] = generatedExpr.trim();
    }
    checks.addAll(_extractInlineCheckConstraints(trimmed));
  }
  return _ParsedTableSqlMetadata(
    generatedExprByColumn: generatedExprByColumn,
    checks: checks,
  );
}

_ParsedIndexSql? _parseIndexSql(String? indexSql) {
  if (indexSql == null || indexSql.trim().isEmpty) {
    return null;
  }
  final openParen = _findFirstUnquotedChar(indexSql, '(');
  if (openParen < 0) {
    return null;
  }
  final closeParen = _findMatchingParen(indexSql, openParen);
  if (closeParen < 0) {
    return null;
  }
  final elements = _splitTopLevelCommaSeparated(
    indexSql.substring(openParen + 1, closeParen),
  );
  final trailing = indexSql.substring(closeParen + 1).trim();
  String? whereSql;
  if (_startsWithKeyword(trailing, 'WHERE')) {
    whereSql = trailing.substring(5).trim();
  }
  return _ParsedIndexSql(elements: elements, whereSql: whereSql);
}

String? _lookupSqliteMasterObjectSql(
  sqlite.Database database, {
  required String type,
  required String name,
}) {
  final rows = database.select(
    'SELECT sql FROM sqlite_master '
    'WHERE type = ${_quoteSqliteStringLiteral(type)} '
    'AND name = ${_quoteSqliteStringLiteral(name)} '
    'LIMIT 1',
  );
  if (rows.isEmpty) {
    return null;
  }
  return rows.first['sql'] as String?;
}

String? _extractCreateTableBody(String? tableSql) {
  if (tableSql == null || tableSql.trim().isEmpty) {
    return null;
  }
  final openParen = _findFirstUnquotedChar(tableSql, '(');
  if (openParen < 0) {
    return null;
  }
  final closeParen = _findMatchingParen(tableSql, openParen);
  if (closeParen < 0) {
    return null;
  }
  return tableSql.substring(openParen + 1, closeParen);
}

bool _tableSqlHasOption(String? tableSql, String option) {
  if (tableSql == null || tableSql.trim().isEmpty) {
    return false;
  }
  final openParen = _findFirstUnquotedChar(tableSql, '(');
  if (openParen < 0) {
    return false;
  }
  final closeParen = _findMatchingParen(tableSql, openParen);
  if (closeParen < 0) {
    return false;
  }
  final trailing = tableSql.substring(closeParen + 1);
  return RegExp(RegExp.escape(option), caseSensitive: false).hasMatch(trailing);
}

bool _isTableConstraintDefinition(String definition) {
  final trimmed = definition.trimLeft();
  if (_startsWithKeyword(trimmed, 'PRIMARY KEY') ||
      _startsWithKeyword(trimmed, 'UNIQUE') ||
      _startsWithKeyword(trimmed, 'CHECK') ||
      _startsWithKeyword(trimmed, 'FOREIGN KEY')) {
    return true;
  }
  if (!_startsWithKeyword(trimmed, 'CONSTRAINT')) {
    return false;
  }
  final name = _readSqlIdentifier(trimmed, 'CONSTRAINT'.length);
  if (name == null) {
    return false;
  }
  final remainder = trimmed.substring(name.nextIndex).trimLeft();
  return _startsWithKeyword(remainder, 'PRIMARY KEY') ||
      _startsWithKeyword(remainder, 'UNIQUE') ||
      _startsWithKeyword(remainder, 'CHECK') ||
      _startsWithKeyword(remainder, 'FOREIGN KEY');
}

SqliteImportCheckConstraint? _parseStandaloneCheckConstraint(
  String definition,
) {
  var working = definition.trim();
  String? name;
  if (_startsWithKeyword(working, 'CONSTRAINT')) {
    final parsedName = _readSqlIdentifier(working, 'CONSTRAINT'.length);
    if (parsedName == null) {
      return null;
    }
    name = parsedName.value;
    working = working.substring(parsedName.nextIndex).trimLeft();
  }
  if (!_startsWithKeyword(working, 'CHECK')) {
    return null;
  }
  final exprSql = _extractParenthesizedExpressionAfterKeyword(
    working,
    working.indexOf(RegExp('CHECK', caseSensitive: false)),
    'CHECK'.length,
  );
  if (exprSql == null) {
    return null;
  }
  return SqliteImportCheckConstraint(exprSql: exprSql, name: name);
}

List<SqliteImportCheckConstraint> _extractInlineCheckConstraints(
  String definition,
) {
  final constraints = <SqliteImportCheckConstraint>[];
  var searchFrom = 0;
  while (true) {
    final checkIndex = _findTopLevelKeyword(
      definition,
      'CHECK',
      start: searchFrom,
    );
    if (checkIndex < 0) {
      return constraints;
    }
    final exprSql = _extractParenthesizedExpressionAfterKeyword(
      definition,
      checkIndex,
      'CHECK'.length,
    );
    if (exprSql == null) {
      return constraints;
    }
    constraints.add(
      SqliteImportCheckConstraint(
        exprSql: exprSql,
        name: _extractConstraintNameBefore(definition, checkIndex),
      ),
    );
    final openParen = _skipSqlWhitespace(
      definition,
      checkIndex + 'CHECK'.length,
    );
    final closeParen =
        openParen < definition.length && definition[openParen] == '('
        ? _findMatchingParen(definition, openParen)
        : -1;
    searchFrom = closeParen < 0 ? definition.length : closeParen + 1;
  }
}

String? _extractGeneratedExpression(String definition) {
  final generatedIndex = _findTopLevelKeyword(definition, 'GENERATED');
  if (generatedIndex < 0) {
    return null;
  }
  final asIndex = _findTopLevelKeyword(
    definition,
    'AS',
    start: generatedIndex + 'GENERATED'.length,
  );
  if (asIndex < 0) {
    return null;
  }
  return _extractParenthesizedExpressionAfterKeyword(
    definition,
    asIndex,
    'AS'.length,
  );
}

String? _extractConstraintNameBefore(String definition, int keywordIndex) {
  final prefix = definition.substring(0, keywordIndex).trimRight();
  final constraintIndex = _lastTopLevelKeyword(prefix, 'CONSTRAINT');
  if (constraintIndex < 0) {
    return null;
  }
  final between = prefix
      .substring(constraintIndex + 'CONSTRAINT'.length)
      .trim();
  final parsed = _readSqlIdentifier(between, 0);
  if (parsed == null) {
    return null;
  }
  if (between.substring(parsed.nextIndex).trim().isNotEmpty) {
    return null;
  }
  return parsed.value;
}

String _rewriteSqlIdentifiers(
  String sql,
  Map<String, String> identifierMap, {
  required String sourceTableName,
  required String targetTableName,
}) {
  final loweredMap = <String, String>{
    for (final entry in identifierMap.entries)
      entry.key.toLowerCase(): entry.value,
  };
  final buffer = StringBuffer();
  var index = 0;
  while (index < sql.length) {
    final char = sql[index];
    if (char == "'") {
      final next = _skipSingleQuotedString(sql, index);
      buffer.write(sql.substring(index, next));
      index = next;
      continue;
    }
    if (char == '"' ||
        char == '`' ||
        char == '[' ||
        _isIdentifierStartChar(char)) {
      final identifier = _readSqlIdentifier(sql, index);
      if (identifier != null) {
        final nextNonWhitespace = _nextNonWhitespaceIndex(
          sql,
          identifier.nextIndex,
        );
        final replacement =
            nextNonWhitespace < sql.length &&
                sql[nextNonWhitespace] == '.' &&
                _equalsIgnoreCase(identifier.value, sourceTableName)
            ? targetTableName
            : loweredMap[identifier.value.toLowerCase()];
        if (replacement != null) {
          buffer.write(_quoteDecentIdent(replacement));
        } else {
          buffer.write(sql.substring(index, identifier.nextIndex));
        }
        index = identifier.nextIndex;
        continue;
      }
    }
    buffer.write(char);
    index++;
  }
  return buffer.toString();
}

bool _sqlIdentifierMatches(String sqlIdentifier, String expected) {
  final parsed = _readSqlIdentifier(sqlIdentifier.trim(), 0);
  if (parsed == null) {
    return false;
  }
  return parsed.nextIndex == sqlIdentifier.trim().length &&
      _equalsIgnoreCase(parsed.value, expected);
}

List<String> _splitTopLevelCommaSeparated(String sql) {
  final parts = <String>[];
  var start = 0;
  var depth = 0;
  var index = 0;
  while (index < sql.length) {
    final char = sql[index];
    if (char == "'") {
      index = _skipSingleQuotedString(sql, index);
      continue;
    }
    if (char == '"' || char == '`') {
      index = _skipQuotedIdentifier(sql, index, char);
      continue;
    }
    if (char == '[') {
      index = _skipBracketIdentifier(sql, index);
      continue;
    }
    if (char == '(') {
      depth++;
      index++;
      continue;
    }
    if (char == ')') {
      if (depth > 0) {
        depth--;
      }
      index++;
      continue;
    }
    if (char == ',' && depth == 0) {
      parts.add(sql.substring(start, index).trim());
      start = index + 1;
    }
    index++;
  }
  parts.add(sql.substring(start).trim());
  return parts.where((part) => part.isNotEmpty).toList(growable: false);
}

String? _extractParenthesizedExpressionAfterKeyword(
  String sql,
  int keywordIndex,
  int keywordLength,
) {
  final openParen = _skipSqlWhitespace(sql, keywordIndex + keywordLength);
  if (openParen >= sql.length || sql[openParen] != '(') {
    return null;
  }
  final closeParen = _findMatchingParen(sql, openParen);
  if (closeParen < 0) {
    return null;
  }
  return sql.substring(openParen + 1, closeParen).trim();
}

int _findTopLevelKeyword(String sql, String keyword, {int start = 0}) {
  var depth = 0;
  var index = start;
  while (index <= sql.length - keyword.length) {
    final char = sql[index];
    if (char == "'") {
      index = _skipSingleQuotedString(sql, index);
      continue;
    }
    if (char == '"' || char == '`') {
      index = _skipQuotedIdentifier(sql, index, char);
      continue;
    }
    if (char == '[') {
      index = _skipBracketIdentifier(sql, index);
      continue;
    }
    if (char == '(') {
      depth++;
      index++;
      continue;
    }
    if (char == ')') {
      if (depth > 0) {
        depth--;
      }
      index++;
      continue;
    }
    if (depth == 0 && _matchesKeywordAt(sql, keyword, index)) {
      return index;
    }
    index++;
  }
  return -1;
}

int _lastTopLevelKeyword(String sql, String keyword) {
  var lastIndex = -1;
  var searchFrom = 0;
  while (true) {
    final next = _findTopLevelKeyword(sql, keyword, start: searchFrom);
    if (next < 0) {
      return lastIndex;
    }
    lastIndex = next;
    searchFrom = next + keyword.length;
  }
}

bool _startsWithKeyword(String sql, String keyword) {
  final trimmed = sql.trimLeft();
  return _matchesKeywordAt(trimmed, keyword, 0);
}

bool _matchesKeywordAt(String sql, String keyword, int index) {
  if (index < 0 || index + keyword.length > sql.length) {
    return false;
  }
  if (!sql
      .substring(index, index + keyword.length)
      .toUpperCase()
      .startsWith(keyword.toUpperCase())) {
    return false;
  }
  final before = index == 0 ? null : sql[index - 1];
  final after = index + keyword.length >= sql.length
      ? null
      : sql[index + keyword.length];
  return !_isIdentifierChar(before) && !_isIdentifierChar(after);
}

({String value, int nextIndex})? _readSqlIdentifier(String sql, int start) {
  final index = _skipSqlWhitespace(sql, start);
  if (index >= sql.length) {
    return null;
  }
  final char = sql[index];
  if (char == '"') {
    final next = _skipQuotedIdentifier(sql, index, '"');
    return (
      value: sql.substring(index + 1, next - 1).replaceAll('""', '"'),
      nextIndex: next,
    );
  }
  if (char == '`') {
    final next = _skipQuotedIdentifier(sql, index, '`');
    return (
      value: sql.substring(index + 1, next - 1).replaceAll('``', '`'),
      nextIndex: next,
    );
  }
  if (char == '[') {
    final next = _skipBracketIdentifier(sql, index);
    return (value: sql.substring(index + 1, next - 1), nextIndex: next);
  }
  if (!_isIdentifierStartChar(char)) {
    return null;
  }
  var next = index + 1;
  while (next < sql.length && _isIdentifierChar(sql[next])) {
    next++;
  }
  return (value: sql.substring(index, next), nextIndex: next);
}

int _skipSqlWhitespace(String sql, int start) {
  var index = start;
  while (index < sql.length && _isWhitespace(sql[index])) {
    index++;
  }
  return index;
}

int _findFirstUnquotedChar(String sql, String char) {
  var index = 0;
  while (index < sql.length) {
    final current = sql[index];
    if (current == "'") {
      index = _skipSingleQuotedString(sql, index);
      continue;
    }
    if (current == '"' || current == '`') {
      index = _skipQuotedIdentifier(sql, index, current);
      continue;
    }
    if (current == '[') {
      index = _skipBracketIdentifier(sql, index);
      continue;
    }
    if (current == char) {
      return index;
    }
    index++;
  }
  return -1;
}

int _findMatchingParen(String sql, int openParenIndex) {
  var depth = 0;
  var index = openParenIndex;
  while (index < sql.length) {
    final char = sql[index];
    if (char == "'") {
      index = _skipSingleQuotedString(sql, index);
      continue;
    }
    if (char == '"' || char == '`') {
      index = _skipQuotedIdentifier(sql, index, char);
      continue;
    }
    if (char == '[') {
      index = _skipBracketIdentifier(sql, index);
      continue;
    }
    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) {
        return index;
      }
    }
    index++;
  }
  return -1;
}

int _skipSingleQuotedString(String sql, int start) {
  var index = start + 1;
  while (index < sql.length) {
    if (sql[index] == "'") {
      if (index + 1 < sql.length && sql[index + 1] == "'") {
        index += 2;
        continue;
      }
      return index + 1;
    }
    index++;
  }
  return sql.length;
}

int _skipQuotedIdentifier(String sql, int start, String quote) {
  var index = start + 1;
  while (index < sql.length) {
    if (sql[index] == quote) {
      if (index + 1 < sql.length && sql[index + 1] == quote) {
        index += 2;
        continue;
      }
      return index + 1;
    }
    index++;
  }
  return sql.length;
}

int _skipBracketIdentifier(String sql, int start) {
  var index = start + 1;
  while (index < sql.length) {
    if (sql[index] == ']') {
      return index + 1;
    }
    index++;
  }
  return sql.length;
}

int _nextNonWhitespaceIndex(String sql, int start) {
  var index = start;
  while (index < sql.length && _isWhitespace(sql[index])) {
    index++;
  }
  return index;
}

bool _isIdentifierStartChar(String value) {
  if (value.isEmpty) {
    return false;
  }
  final codeUnit = value.codeUnitAt(0);
  return (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122) ||
      value == '_';
}

bool _isIdentifierChar(String? value) {
  if (value == null || value.isEmpty) {
    return false;
  }
  final codeUnit = value.codeUnitAt(0);
  return (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122) ||
      (codeUnit >= 48 && codeUnit <= 57) ||
      value == '_' ||
      value == r'$';
}

bool _isWhitespace(String value) {
  return value == ' ' || value == '\n' || value == '\r' || value == '\t';
}

bool _equalsIgnoreCase(String left, String right) {
  return left.toLowerCase() == right.toLowerCase();
}

String _placeholderForType(String targetType, int index) {
  if (_isDecimalType(targetType) || _isUuidType(targetType)) {
    return 'CAST(\$$index AS $targetType)';
  }
  return '\$$index';
}

Object? _adaptImportValue(Object? value, String targetType) {
  if (value == null) {
    return null;
  }
  if (targetType == 'BOOLEAN') {
    if (value is bool) {
      return value;
    }
    if (value is int && (value == 0 || value == 1)) {
      return value == 1;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
    return value;
  }
  if (targetType == 'TEXT' && value is Uint8List) {
    return formatCellValue(value);
  }
  if (targetType == 'BLOB' && value is String) {
    return Uint8List.fromList(value.codeUnits);
  }
  if (targetType == 'TIMESTAMP' && value is String) {
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc() ?? value;
  }
  if (targetType == 'TIMESTAMP' && value is DateTime) {
    return value.toUtc();
  }
  if (_isDecimalType(targetType) && value is num) {
    return value.toString();
  }
  return value;
}

String mapSqliteDeclaredTypeToDecentDb(String declaredType) {
  final normalized = declaredType.trim().toUpperCase();
  if (normalized.isEmpty) {
    return 'TEXT';
  }
  if (normalized.contains('BOOL')) {
    return 'BOOLEAN';
  }
  if (normalized.contains('INT')) {
    return 'INTEGER';
  }
  if (normalized.contains('UUID') ||
      normalized.contains('GUID') ||
      normalized.contains('UNIQUEIDENTIFIER') ||
      normalized.contains('CHAR(36)')) {
    return 'UUID';
  }
  if (normalized.contains('REAL') ||
      normalized.contains('FLOA') ||
      normalized.contains('DOUB')) {
    return 'FLOAT64';
  }
  if (normalized.contains('BLOB')) {
    return 'BLOB';
  }
  if (normalized.contains('DECIMAL') || normalized.contains('NUMERIC')) {
    final mapped = normalized.replaceAll('NUMERIC', 'DECIMAL');
    if (mapped.contains('(')) {
      return mapped;
    }
    return 'DECIMAL(18,6)';
  }
  if (normalized.contains('DATE') || normalized.contains('TIME')) {
    return 'TIMESTAMP';
  }
  if (normalized.contains('CHAR') ||
      normalized.contains('CLOB') ||
      normalized.contains('TEXT') ||
      normalized.contains('VARCHAR') ||
      normalized.contains('JSON')) {
    return 'TEXT';
  }
  return 'TEXT';
}

String _quoteSqliteIdent(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

String _quoteSqliteStringLiteral(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _quoteDecentIdent(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

bool _isDecimalType(String targetType) {
  return targetType.startsWith('DECIMAL') || targetType.startsWith('NUMERIC');
}

bool _isUuidType(String targetType) {
  return targetType == 'UUID';
}

class _ParsedTableSqlMetadata {
  const _ParsedTableSqlMetadata({
    this.generatedExprByColumn = const <String, String>{},
    this.checks = const <SqliteImportCheckConstraint>[],
  });

  final Map<String, String> generatedExprByColumn;
  final List<SqliteImportCheckConstraint> checks;
}

class _ParsedIndexSql {
  const _ParsedIndexSql({required this.elements, this.whereSql});

  final List<String> elements;
  final String? whereSql;
}

class _SqliteImportCancelled implements Exception {
  const _SqliteImportCancelled(this.summary);

  final SqliteImportSummary summary;
}

class _SqliteImportCancelledSignal implements Exception {
  const _SqliteImportCancelledSignal();
}
