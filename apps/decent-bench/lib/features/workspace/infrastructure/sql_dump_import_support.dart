import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:decentdb/decentdb.dart';

import '../domain/sql_dump_import_models.dart';
import '../domain/workspace_models.dart';

const int _sqlDumpPreviewRowLimit = 8;
const int _sqlDumpProgressBatchSize = 200;

Future<SqlDumpImportInspection> inspectSqlDumpSourceInBackground(
  String sourcePath, {
  required String encoding,
}) {
  return Isolate.run(
    () => inspectSqlDumpSourceFile(sourcePath, encoding: encoding),
  );
}

SqlDumpImportInspection inspectSqlDumpSourceFile(
  String sourcePath, {
  required String encoding,
}) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    throw BridgeFailure('SQL dump source file does not exist: $sourcePath');
  }

  final decoded = _decodeSqlDumpSource(file, encoding: encoding);
  final parseResult = _parseDumpText(decoded.text);

  return SqlDumpImportInspection(
    sourcePath: sourcePath,
    requestedEncoding: encoding,
    resolvedEncoding: decoded.resolvedEncoding,
    tables: parseResult.tables.values
        .map((table) => table.toDraft())
        .toList(growable: false),
    warnings: <String>[...decoded.warnings, ...parseResult.warnings],
    skippedStatements: parseResult.skippedStatements,
    totalStatements: parseResult.totalStatements,
  );
}

@pragma('vm:entry-point')
Future<void> sqlDumpImportWorkerMain(List<Object?> bootstrap) async {
  final mainPort = bootstrap[0]! as SendPort;
  final libraryPath = bootstrap[1]! as String;
  final request = SqlDumpImportRequest.fromMap(
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
    final summary = await _runSqlDumpImport(
      request: request,
      libraryPath: libraryPath,
      sendUpdate: (update) => mainPort.send(update.toMap()),
      isCancelled: () => cancelled,
    );
    mainPort.send(
      SqlDumpImportUpdate(
        kind: cancelled
            ? SqlDumpImportUpdateKind.cancelled
            : SqlDumpImportUpdateKind.completed,
        jobId: request.jobId,
        summary: summary,
      ).toMap(),
    );
  } on _SqlDumpImportCancelled catch (error) {
    mainPort.send(
      SqlDumpImportUpdate(
        kind: SqlDumpImportUpdateKind.cancelled,
        jobId: request.jobId,
        summary: error.summary,
        message: error.summary.statusMessage,
      ).toMap(),
    );
  } catch (error) {
    mainPort.send(
      SqlDumpImportUpdate(
        kind: SqlDumpImportUpdateKind.failed,
        jobId: request.jobId,
        message: error.toString(),
      ).toMap(),
    );
  } finally {
    await commandSubscription.cancel();
    commandPort.close();
  }
}

Future<SqlDumpImportSummary> _runSqlDumpImport({
  required SqlDumpImportRequest request,
  required String libraryPath,
  required void Function(SqlDumpImportUpdate update) sendUpdate,
  required bool Function() isCancelled,
}) async {
  if (request.selectedTables.isEmpty) {
    throw const BridgeFailure('Select at least one parsed table to import.');
  }

  _validateRequestNames(request);

  final sourceFile = File(request.sourcePath);
  if (!sourceFile.existsSync()) {
    throw BridgeFailure(
      'SQL dump source file does not exist: ${request.sourcePath}',
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

  final decoded = _decodeSqlDumpSource(sourceFile, encoding: request.encoding);
  final statements = _splitSqlStatements(decoded.text);
  final target = Database.open(request.targetPath, libraryPath: libraryPath);
  var transactionOpen = false;
  final rowsCopied = <String, int>{};
  final warnings = <String>[...decoded.warnings];
  final skippedStatements = <SqlDumpImportSkippedStatement>[];
  final selectedBySource = <String, SqlDumpImportTableDraft>{
    for (final table in request.selectedTables) table.sourceName: table,
  };

  try {
    final existingTables = target.schema.listTables().toSet();
    final colliding = request.selectedTables
        .map((table) => table.targetName)
        .where(existingTables.contains)
        .toList();
    if (colliding.isNotEmpty) {
      throw BridgeFailure(
        'Target already contains table(s): ${colliding.join(", ")}. Rename them or choose another DecentDB file.',
      );
    }

    target.begin();
    transactionOpen = true;

    for (var i = 0; i < request.selectedTables.length; i++) {
      final table = request.selectedTables[i];
      _throwIfCancelled(isCancelled);
      target.execute(_buildCreateTableSql(table));
      sendUpdate(
        SqlDumpImportUpdate(
          kind: SqlDumpImportUpdateKind.progress,
          jobId: request.jobId,
          progress: SqlDumpImportProgress(
            jobId: request.jobId,
            currentTable: table.targetName,
            completedTables: i,
            totalTables: request.selectedTables.length,
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

    final preparedStatements = <String, Statement>{};
    try {
      for (final table in request.selectedTables) {
        preparedStatements[table.sourceName] = target.prepare(
          'INSERT INTO ${_quoteDecentIdent(table.targetName)} '
          '(${table.columns.map((column) => _quoteDecentIdent(column.targetName)).join(", ")}) '
          'VALUES (${[for (var i = 0; i < table.columns.length; i++) _placeholderForType(table.columns[i].targetType, i + 1)].join(", ")})',
        );
      }

      for (var ordinal = 0; ordinal < statements.length; ordinal++) {
        _throwIfCancelled(isCancelled);
        final statement = statements[ordinal];
        final create = _tryParseCreateTable(statement, ordinal + 1);
        if (create != null) {
          warnings.addAll(create.warnings);
          if (create.skipped != null) {
            skippedStatements.add(create.skipped!);
            warnings.add(create.skipped!.reason);
          }
          continue;
        }

        final insert = _tryParseInsertSafely(statement, ordinal + 1);
        if (insert != null) {
          if (insert.skipped != null) {
            skippedStatements.add(insert.skipped!);
            warnings.add(insert.skipped!.reason);
            continue;
          }
          final parsedInsert = insert.insert;
          if (parsedInsert == null) {
            continue;
          }
          final tableDraft = selectedBySource[parsedInsert.tableName];
          if (tableDraft == null) {
            continue;
          }
          final prepared = preparedStatements[parsedInsert.tableName];
          if (prepared == null) {
            throw BridgeFailure(
              'Missing prepared import statement for ${parsedInsert.tableName}.',
            );
          }

          final sourceColumns =
              parsedInsert.columnNames ??
              <String>[
                for (final column in tableDraft.columns) column.sourceName,
              ];
          final sourceIndexes = <String, int>{
            for (var i = 0; i < sourceColumns.length; i++) sourceColumns[i]: i,
          };

          for (final row in parsedInsert.rows) {
            _throwIfCancelled(isCancelled);
            final boundValues = <Object?>[
              for (final column in tableDraft.columns)
                _adaptImportValue(
                  sourceIndexes.containsKey(column.sourceName) &&
                          sourceIndexes[column.sourceName]! < row.length
                      ? row[sourceIndexes[column.sourceName]!]
                      : null,
                  column.targetType,
                ),
            ];
            prepared.reset();
            prepared.clearBindings();
            prepared.bindAll(boundValues);
            prepared.execute();

            final copied = (rowsCopied[tableDraft.targetName] ?? 0) + 1;
            rowsCopied[tableDraft.targetName] = copied;
            if (copied == 1 ||
                copied % _sqlDumpProgressBatchSize == 0 ||
                copied == tableDraft.rowCount) {
              sendUpdate(
                SqlDumpImportUpdate(
                  kind: SqlDumpImportUpdateKind.progress,
                  jobId: request.jobId,
                  progress: SqlDumpImportProgress(
                    jobId: request.jobId,
                    currentTable: tableDraft.targetName,
                    completedTables: request.selectedTables.indexOf(tableDraft),
                    totalTables: request.selectedTables.length,
                    currentTableRowsCopied: copied,
                    currentTableRowCount: tableDraft.rowCount,
                    totalRowsCopied: rowsCopied.values.fold<int>(
                      0,
                      (sum, value) => sum + value,
                    ),
                    message: 'Copying ${tableDraft.targetName}...',
                  ),
                ),
              );
              await Future<void>.delayed(Duration.zero);
            }
          }
          continue;
        }

        final skipped = _classifySkippedStatement(statement, ordinal + 1);
        if (skipped != null) {
          skippedStatements.add(skipped);
          warnings.add(skipped.reason);
        }
      }
    } finally {
      for (final statement in preparedStatements.values) {
        statement.dispose();
      }
    }

    target.commit();
    transactionOpen = false;

    return SqlDumpImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: request.selectedTables
          .map((table) => table.targetName)
          .toList(),
      rowsCopiedByTable: rowsCopied,
      skippedStatementCount: skippedStatements.length,
      warnings: warnings,
      skippedStatements: skippedStatements,
      statusMessage:
          'Imported ${rowsCopied.values.fold<int>(0, (sum, value) => sum + value)} rows from ${request.selectedTables.length} parsed table${request.selectedTables.length == 1 ? '' : 's'}. Skipped ${skippedStatements.length} unsupported statement${skippedStatements.length == 1 ? '' : 's'}.',
      rolledBack: false,
    );
  } on _SqlDumpImportCancelledSignal {
    if (transactionOpen) {
      try {
        target.rollback();
      } catch (_) {
        // Best-effort rollback for cancellation.
      }
    }
    final summary = SqlDumpImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: rowsCopied.keys.toList(),
      rowsCopiedByTable: rowsCopied,
      skippedStatementCount: skippedStatements.length,
      warnings: warnings,
      skippedStatements: skippedStatements,
      statusMessage: 'SQL dump import cancelled and rolled back.',
      rolledBack: true,
    );
    throw _SqlDumpImportCancelled(summary);
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
  }
}

_DecodedSqlText _decodeSqlDumpSource(File file, {required String encoding}) {
  final bytes = file.readAsBytesSync();
  if (encoding == 'utf8') {
    return _DecodedSqlText(
      text: _stripBom(utf8.decode(bytes)),
      resolvedEncoding: 'utf8',
      warnings: const <String>[],
    );
  }
  if (encoding == 'latin1') {
    return _DecodedSqlText(
      text: _stripBom(latin1.decode(bytes)),
      resolvedEncoding: 'latin1',
      warnings: const <String>[],
    );
  }
  if (encoding != 'auto') {
    throw BridgeFailure('Unsupported SQL dump encoding option: $encoding');
  }

  try {
    return _DecodedSqlText(
      text: _stripBom(utf8.decode(bytes)),
      resolvedEncoding: 'utf8',
      warnings: const <String>[],
    );
  } on FormatException {
    return _DecodedSqlText(
      text: _stripBom(latin1.decode(bytes)),
      resolvedEncoding: 'latin1',
      warnings: const <String>[
        'Auto-detect fell back to Latin-1 because UTF-8 decoding failed.',
      ],
    );
  }
}

String _stripBom(String value) {
  return value.startsWith('\ufeff') ? value.substring(1) : value;
}

_DumpParseResult _parseDumpText(String text) {
  final statements = _splitSqlStatements(text);
  final tables = <String, _ParsedDumpTable>{};
  final warnings = <String>[];
  final skippedStatements = <SqlDumpImportSkippedStatement>[];

  for (var ordinal = 0; ordinal < statements.length; ordinal++) {
    final statement = statements[ordinal];
    final create = _tryParseCreateTable(statement, ordinal + 1);
    if (create != null) {
      warnings.addAll(create.warnings);
      if (create.skipped != null) {
        skippedStatements.add(create.skipped!);
        warnings.add(create.skipped!.reason);
      } else if (create.table != null) {
        tables[create.table!.name] = create.table!;
      }
      continue;
    }

    final insert = _tryParseInsertSafely(statement, ordinal + 1);
    if (insert != null) {
      if (insert.skipped != null) {
        skippedStatements.add(insert.skipped!);
        warnings.add(insert.skipped!.reason);
        continue;
      }
      final parsedInsert = insert.insert;
      if (parsedInsert == null) {
        continue;
      }
      final table = tables[parsedInsert.tableName];
      if (table == null) {
        final skipped = SqlDumpImportSkippedStatement(
          ordinal: ordinal + 1,
          kind: 'INSERT',
          reason:
              'Skipping INSERT for ${parsedInsert.tableName} because no supported CREATE TABLE was parsed first.',
          snippet: _statementSnippet(statement),
        );
        skippedStatements.add(skipped);
        warnings.add(skipped.reason);
        continue;
      }
      if (parsedInsert.columnNames != null &&
          parsedInsert.columnNames!.length != _rowWidth(parsedInsert)) {
        final skipped = SqlDumpImportSkippedStatement(
          ordinal: ordinal + 1,
          kind: 'INSERT',
          reason:
              'Skipping INSERT for ${parsedInsert.tableName} because the explicit column list does not match row width.',
          snippet: _statementSnippet(statement),
        );
        skippedStatements.add(skipped);
        warnings.add(skipped.reason);
        continue;
      }
      table.absorbInsert(parsedInsert);
      continue;
    }

    final skipped = _classifySkippedStatement(statement, ordinal + 1);
    if (skipped != null) {
      skippedStatements.add(skipped);
      warnings.add(skipped.reason);
    }
  }

  return _DumpParseResult(
    tables: tables,
    warnings: warnings,
    skippedStatements: skippedStatements,
    totalStatements: statements.length,
  );
}

int _rowWidth(_ParsedInsertStatement insert) {
  if (insert.rows.isEmpty) {
    return insert.columnNames?.length ?? 0;
  }
  return insert.rows.first.length;
}

_InsertParseResult? _tryParseInsertSafely(String statement, int ordinal) {
  final normalized = statement.trimLeft();
  if (!_startsWithKeyword(normalized, 'INSERT')) {
    return null;
  }
  try {
    return _InsertParseResult.insert(_tryParseInsert(statement, ordinal)!);
  } on BridgeFailure catch (error) {
    return _InsertParseResult.skipped(
      SqlDumpImportSkippedStatement(
        ordinal: ordinal,
        kind: 'INSERT',
        reason: error.message,
        snippet: _statementSnippet(statement),
      ),
    );
  }
}

List<String> _splitSqlStatements(String text) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  var inBacktick = false;
  var inLineComment = false;
  var inBlockComment = false;
  var escape = false;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    final next = i + 1 < text.length ? text[i + 1] : '';

    if (inLineComment) {
      if (char == '\n') {
        inLineComment = false;
      }
      continue;
    }
    if (inBlockComment) {
      if (char == '*' && next == '/') {
        inBlockComment = false;
        i++;
      }
      continue;
    }
    if (!inSingle && !inDouble && !inBacktick) {
      if (char == '-' &&
          next == '-' &&
          (i + 2 >= text.length || _isWhitespace(text[i + 2]))) {
        inLineComment = true;
        i++;
        continue;
      }
      if (char == '#') {
        inLineComment = true;
        continue;
      }
      if (char == '/' && next == '*') {
        inBlockComment = true;
        i++;
        continue;
      }
    }

    buffer.write(char);

    if (escape) {
      escape = false;
      continue;
    }
    if ((inSingle || inDouble) && char == r'\') {
      escape = true;
      continue;
    }
    if (char == "'" && !inDouble && !inBacktick) {
      if (inSingle && next == "'") {
        buffer.write(next);
        i++;
      } else {
        inSingle = !inSingle;
      }
      continue;
    }
    if (char == '"' && !inSingle && !inBacktick) {
      inDouble = !inDouble;
      continue;
    }
    if (char == '`' && !inSingle && !inDouble) {
      inBacktick = !inBacktick;
      continue;
    }
    if (char == ';' && !inSingle && !inDouble && !inBacktick) {
      final statement = buffer.toString().trim();
      if (statement.isNotEmpty) {
        statements.add(statement.substring(0, statement.length - 1).trim());
      }
      buffer.clear();
    }
  }

  final trailing = buffer.toString().trim();
  if (trailing.isNotEmpty) {
    statements.add(trailing);
  }
  return statements;
}

_CreateTableParseResult? _tryParseCreateTable(String statement, int ordinal) {
  final normalized = statement.trimLeft();
  if (!_startsWithKeyword(normalized, 'CREATE')) {
    return null;
  }

  final createMatch = RegExp(
    r'^CREATE\s+(?:TEMPORARY\s+)?TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?',
    caseSensitive: false,
  ).firstMatch(normalized);
  if (createMatch == null) {
    return null;
  }

  var index = createMatch.end;
  final tableNameToken = _readQualifiedIdentifier(normalized, index);
  if (tableNameToken == null) {
    final skipped = SqlDumpImportSkippedStatement(
      ordinal: ordinal,
      kind: 'CREATE TABLE',
      reason:
          'Skipping CREATE TABLE because the table name could not be parsed.',
      snippet: _statementSnippet(statement),
    );
    return _CreateTableParseResult.skipped(skipped);
  }
  index = tableNameToken.nextIndex;
  while (index < normalized.length && _isWhitespace(normalized[index])) {
    index++;
  }
  if (index >= normalized.length || normalized[index] != '(') {
    final skipped = SqlDumpImportSkippedStatement(
      ordinal: ordinal,
      kind: 'CREATE TABLE',
      reason:
          'Skipping CREATE TABLE for ${tableNameToken.value} because the column definition block could not be parsed.',
      snippet: _statementSnippet(statement),
    );
    return _CreateTableParseResult.skipped(skipped);
  }

  final closeIndex = _findMatchingParen(normalized, index);
  if (closeIndex == null) {
    final skipped = SqlDumpImportSkippedStatement(
      ordinal: ordinal,
      kind: 'CREATE TABLE',
      reason:
          'Skipping CREATE TABLE for ${tableNameToken.value} because the column definition block is unbalanced.',
      snippet: _statementSnippet(statement),
    );
    return _CreateTableParseResult.skipped(skipped);
  }

  final body = normalized.substring(index + 1, closeIndex);
  final segments = _splitTopLevel(body, delimiter: ',');
  final parsedColumns = <_ParsedDumpColumn>[];
  final warnings = <String>[];
  final primaryKeyColumns = <String>[];
  final singleColumnUnique = <String>{};

  for (final segment in segments) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final upper = trimmed.toUpperCase();
    if (upper.startsWith('PRIMARY KEY')) {
      primaryKeyColumns.addAll(_parseKeyColumnNames(trimmed));
      continue;
    }
    if (upper.startsWith('UNIQUE KEY') ||
        upper.startsWith('UNIQUE INDEX') ||
        upper.startsWith('UNIQUE ')) {
      final columns = _parseKeyColumnNames(trimmed);
      if (columns.length == 1) {
        singleColumnUnique.add(columns.single);
      } else if (columns.isNotEmpty) {
        warnings.add(
          'Skipping multi-column UNIQUE definition on ${tableNameToken.value}: ${columns.join(", ")}.',
        );
      }
      continue;
    }
    if (upper.startsWith('KEY ') ||
        upper.startsWith('INDEX ') ||
        upper.startsWith('FULLTEXT ') ||
        upper.startsWith('SPATIAL ')) {
      warnings.add(
        'Skipping index definition on ${tableNameToken.value}: ${_statementSnippet(trimmed)}',
      );
      continue;
    }
    if (upper.startsWith('CONSTRAINT ') ||
        upper.startsWith('FOREIGN KEY') ||
        upper.startsWith('CHECK ')) {
      warnings.add(
        'Skipping constraint definition on ${tableNameToken.value}: ${_statementSnippet(trimmed)}',
      );
      continue;
    }

    final column = _parseCreateColumn(trimmed);
    if (column == null) {
      warnings.add(
        'Skipping unrecognized column definition on ${tableNameToken.value}: ${_statementSnippet(trimmed)}',
      );
      continue;
    }
    parsedColumns.add(column);
  }

  for (var i = 0; i < parsedColumns.length; i++) {
    final column = parsedColumns[i];
    parsedColumns[i] = column.copyWith(
      primaryKey:
          column.primaryKey || primaryKeyColumns.contains(column.sourceName),
      unique: column.unique || singleColumnUnique.contains(column.sourceName),
    );
  }

  return _CreateTableParseResult.table(
    _ParsedDumpTable(name: tableNameToken.value, columns: parsedColumns),
    warnings,
  );
}

_ParsedDumpColumn? _parseCreateColumn(String segment) {
  final identifier = _readIdentifier(segment, 0);
  if (identifier == null) {
    return null;
  }
  final remainder = segment.substring(identifier.nextIndex).trimLeft();
  if (remainder.isEmpty) {
    return null;
  }
  final constraintIndex = _findConstraintIndex(remainder);
  final declaredType =
      (constraintIndex == null
              ? remainder
              : remainder.substring(0, constraintIndex))
          .trim();
  final constraints =
      (constraintIndex == null ? '' : remainder.substring(constraintIndex))
          .toUpperCase();

  return _ParsedDumpColumn(
    sourceIndex: 0,
    sourceName: identifier.value,
    declaredType: declaredType,
    targetType: mapMySqlDeclaredTypeToDecentDb(declaredType),
    notNull: constraints.contains('NOT NULL'),
    primaryKey: constraints.contains('PRIMARY KEY'),
    unique: constraints.contains('UNIQUE'),
  );
}

int? _findConstraintIndex(String remainder) {
  const keywords = <String>[
    ' NOT NULL',
    ' NULL',
    ' DEFAULT',
    ' AUTO_INCREMENT',
    ' PRIMARY KEY',
    ' UNIQUE',
    ' COMMENT',
    ' COLLATE',
    ' CHARACTER SET',
    ' REFERENCES',
    ' CHECK',
    ' ON UPDATE',
    ' GENERATED ALWAYS',
    ' AS ',
    ' VIRTUAL',
    ' STORED',
  ];

  var parenDepth = 0;
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < remainder.length; i++) {
    final char = remainder[i];
    if (char == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (char == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (inSingle || inDouble) {
      continue;
    }
    if (char == '(') {
      parenDepth++;
      continue;
    }
    if (char == ')') {
      parenDepth = parenDepth > 0 ? parenDepth - 1 : 0;
      continue;
    }
    if (parenDepth > 0) {
      continue;
    }
    final suffix = remainder.substring(i).toUpperCase();
    for (final keyword in keywords) {
      if (suffix.startsWith(keyword)) {
        return i;
      }
    }
  }
  return null;
}

_ParsedInsertStatement? _tryParseInsert(String statement, int ordinal) {
  final normalized = statement.trimLeft();
  if (!_startsWithKeyword(normalized, 'INSERT')) {
    return null;
  }

  var index = 'INSERT'.length;
  final upper = normalized.toUpperCase();
  while (index < normalized.length) {
    while (index < normalized.length && _isWhitespace(normalized[index])) {
      index++;
    }
    if (upper.substring(index).startsWith('LOW_PRIORITY')) {
      index += 'LOW_PRIORITY'.length;
      continue;
    }
    if (upper.substring(index).startsWith('DELAYED')) {
      index += 'DELAYED'.length;
      continue;
    }
    if (upper.substring(index).startsWith('HIGH_PRIORITY')) {
      index += 'HIGH_PRIORITY'.length;
      continue;
    }
    if (upper.substring(index).startsWith('IGNORE')) {
      index += 'IGNORE'.length;
      continue;
    }
    break;
  }
  while (index < normalized.length && _isWhitespace(normalized[index])) {
    index++;
  }
  if (!upper.substring(index).startsWith('INTO')) {
    return null;
  }
  index += 'INTO'.length;
  while (index < normalized.length && _isWhitespace(normalized[index])) {
    index++;
  }

  final tableNameToken = _readQualifiedIdentifier(normalized, index);
  if (tableNameToken == null) {
    throw BridgeFailure(
      'Failed to parse table name for INSERT statement #$ordinal.',
    );
  }
  index = tableNameToken.nextIndex;
  while (index < normalized.length && _isWhitespace(normalized[index])) {
    index++;
  }

  List<String>? columnNames;
  if (index < normalized.length && normalized[index] == '(') {
    final closeIndex = _findMatchingParen(normalized, index);
    if (closeIndex == null) {
      throw BridgeFailure(
        'Failed to parse explicit column list for INSERT statement #$ordinal.',
      );
    }
    final columnList = normalized.substring(index + 1, closeIndex);
    columnNames = _splitTopLevel(columnList, delimiter: ',')
        .map((item) => _unquoteIdentifier(item.trim()))
        .where((item) => item.isNotEmpty)
        .toList();
    index = closeIndex + 1;
  }

  while (index < normalized.length && _isWhitespace(normalized[index])) {
    index++;
  }
  if (!upper.substring(index).startsWith('VALUES')) {
    throw BridgeFailure(
      'Only INSERT ... VALUES statements are supported in MVP-lite SQL dump import.',
    );
  }
  index += 'VALUES'.length;
  final valuesClause = normalized.substring(index).trim();
  return _ParsedInsertStatement(
    tableName: tableNameToken.value,
    columnNames: columnNames,
    rows: _parseInsertRows(valuesClause, ordinal),
  );
}

List<List<Object?>> _parseInsertRows(String valuesClause, int ordinal) {
  final rows = <List<Object?>>[];
  var index = 0;
  while (index < valuesClause.length) {
    while (index < valuesClause.length &&
        (_isWhitespace(valuesClause[index]) || valuesClause[index] == ',')) {
      index++;
    }
    if (index >= valuesClause.length) {
      break;
    }
    if (valuesClause[index] != '(') {
      throw BridgeFailure(
        'Unsupported INSERT row syntax in statement #$ordinal near ${_statementSnippet(valuesClause.substring(index))}.',
      );
    }
    final closeIndex = _findMatchingParen(valuesClause, index);
    if (closeIndex == null) {
      throw BridgeFailure(
        'Unbalanced INSERT row tuple in statement #$ordinal.',
      );
    }
    final tupleText = valuesClause.substring(index + 1, closeIndex);
    rows.add(
      _splitTopLevel(
        tupleText,
        delimiter: ',',
      ).map(_decodeSqlLiteral).toList(growable: false),
    );
    index = closeIndex + 1;
  }
  return rows;
}

Object? _decodeSqlLiteral(String token) {
  final trimmed = token.trim();
  if (trimmed.isEmpty || trimmed.toUpperCase() == 'NULL') {
    return null;
  }
  if (trimmed.toUpperCase() == 'TRUE') {
    return true;
  }
  if (trimmed.toUpperCase() == 'FALSE') {
    return false;
  }
  if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
    return _decodeHexBytes(trimmed.substring(2));
  }
  if ((trimmed.startsWith("x'") || trimmed.startsWith("X'")) &&
      trimmed.endsWith("'")) {
    return _decodeHexBytes(trimmed.substring(2, trimmed.length - 1));
  }
  if ((trimmed.startsWith("b'") || trimmed.startsWith("B'")) &&
      trimmed.endsWith("'")) {
    return int.tryParse(trimmed.substring(2, trimmed.length - 1), radix: 2);
  }
  if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
      (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
    return _decodeQuotedString(trimmed);
  }
  final intValue = int.tryParse(trimmed);
  if (intValue != null) {
    return intValue;
  }
  final doubleValue = double.tryParse(trimmed);
  if (doubleValue != null) {
    return doubleValue;
  }
  return trimmed;
}

Uint8List _decodeHexBytes(String hex) {
  final normalized = hex.length.isOdd ? '0$hex' : hex;
  final bytes = <int>[];
  for (var i = 0; i < normalized.length; i += 2) {
    bytes.add(int.parse(normalized.substring(i, i + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}

String _decodeQuotedString(String token) {
  final quote = token[0];
  final body = token.substring(1, token.length - 1);
  final buffer = StringBuffer();
  var escape = false;
  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    final next = i + 1 < body.length ? body[i + 1] : '';
    if (escape) {
      buffer.write(switch (char) {
        '0' => '\u0000',
        'b' => '\b',
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        'Z' => '\u001a',
        _ => char,
      });
      escape = false;
      continue;
    }
    if (char == r'\') {
      escape = true;
      continue;
    }
    if (char == quote && next == quote) {
      buffer.write(quote);
      i++;
      continue;
    }
    buffer.write(char);
  }
  return buffer.toString();
}

SqlDumpImportSkippedStatement? _classifySkippedStatement(
  String statement,
  int ordinal,
) {
  final trimmed = statement.trimLeft();
  if (trimmed.isEmpty) {
    return null;
  }

  final upper = trimmed.toUpperCase();
  String kind;
  if (upper.startsWith('SET ')) {
    kind = 'SET';
  } else if (upper.startsWith('LOCK TABLES')) {
    kind = 'LOCK TABLES';
  } else if (upper.startsWith('UNLOCK TABLES')) {
    kind = 'UNLOCK TABLES';
  } else if (upper.startsWith('DROP TABLE')) {
    kind = 'DROP TABLE';
  } else if (upper.startsWith('ALTER TABLE')) {
    kind = 'ALTER TABLE';
  } else if (upper.startsWith('CREATE VIEW')) {
    kind = 'CREATE VIEW';
  } else if (upper.startsWith('INSERT')) {
    kind = 'INSERT';
  } else {
    final firstSpace = upper.indexOf(' ');
    kind = firstSpace < 0 ? upper : upper.substring(0, firstSpace);
  }

  return SqlDumpImportSkippedStatement(
    ordinal: ordinal,
    kind: kind,
    reason: 'Skipping unsupported $kind statement #$ordinal.',
    snippet: _statementSnippet(statement),
  );
}

List<String> _parseKeyColumnNames(String segment) {
  final start = segment.indexOf('(');
  if (start < 0) {
    return const <String>[];
  }
  final end = _findMatchingParen(segment, start);
  if (end == null) {
    return const <String>[];
  }
  return _splitTopLevel(segment.substring(start + 1, end), delimiter: ',')
      .map((item) => _unquoteIdentifier(item.trim()))
      .where((item) => item.isNotEmpty)
      .toList();
}

String mapMySqlDeclaredTypeToDecentDb(String declaredType) {
  final normalized = declaredType.trim().toUpperCase();
  if (normalized.isEmpty) {
    return 'TEXT';
  }
  if (normalized.contains('BOOL') ||
      normalized.startsWith('BIT(1') ||
      normalized.startsWith('TINYINT(1')) {
    return 'BOOLEAN';
  }
  if (normalized.contains('UUID') ||
      normalized.contains('GUID') ||
      normalized.contains('UNIQUEIDENTIFIER') ||
      normalized.contains('CHAR(36)')) {
    return 'UUID';
  }
  if (normalized.contains('BIGINT') ||
      normalized.contains('SMALLINT') ||
      normalized.contains('TINYINT') ||
      normalized.contains('MEDIUMINT') ||
      normalized.contains(' INT') ||
      normalized.startsWith('INT') ||
      normalized.startsWith('YEAR')) {
    return 'INTEGER';
  }
  if (normalized.contains('DECIMAL') || normalized.contains('NUMERIC')) {
    final mapped = normalized.replaceAll('NUMERIC', 'DECIMAL');
    if (mapped.contains('(')) {
      return mapped;
    }
    return 'DECIMAL(18,6)';
  }
  if (normalized.contains('FLOAT') ||
      normalized.contains('DOUBLE') ||
      normalized.contains('REAL')) {
    return 'FLOAT64';
  }
  if (normalized.contains('BLOB') ||
      normalized.contains('BINARY') ||
      normalized.contains('VARBINARY')) {
    return 'BLOB';
  }
  if (normalized.contains('DATE') || normalized.contains('TIMESTAMP')) {
    return 'TIMESTAMP';
  }
  return 'TEXT';
}

void _validateRequestNames(SqlDumpImportRequest request) {
  final selectedTables = request.selectedTables;
  final targetTableNames = <String>{};
  for (final table in selectedTables) {
    final targetTableName = table.targetName.trim();
    if (targetTableName.isEmpty) {
      throw const BridgeFailure(
        'Each selected parsed table needs a target DecentDB table name.',
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
          'Table ${table.sourceName} has an empty target column name.',
        );
      }
      if (!targetColumnNames.add(targetColumnName)) {
        throw BridgeFailure(
          'Table ${table.sourceName} has duplicate target column names. Duplicate: $targetColumnName',
        );
      }
    }
  }
}

String _buildCreateTableSql(SqlDumpImportTableDraft table) {
  final primaryKeyColumns = table.columns.where((column) => column.primaryKey);
  final hasCompositePrimaryKey = primaryKeyColumns.length > 1;
  final columnSql = <String>[
    for (final column in table.columns)
      [
        _quoteDecentIdent(column.targetName),
        column.targetType,
        if (column.notNull || column.primaryKey) 'NOT NULL',
        if (!hasCompositePrimaryKey && column.primaryKey) 'PRIMARY KEY',
        if (!column.primaryKey && column.unique) 'UNIQUE',
      ].join(' '),
    if (hasCompositePrimaryKey)
      'PRIMARY KEY (${primaryKeyColumns.map((column) => _quoteDecentIdent(column.targetName)).join(", ")})',
  ];
  return 'CREATE TABLE ${_quoteDecentIdent(table.targetName)} (${columnSql.join(", ")})';
}

String _quoteDecentIdent(String value) {
  return '"${value.replaceAll('"', '""')}"';
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
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
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

bool _isDecimalType(String targetType) {
  return targetType.startsWith('DECIMAL') || targetType.startsWith('NUMERIC');
}

bool _isUuidType(String targetType) {
  return targetType == 'UUID';
}

void _throwIfCancelled(bool Function() isCancelled) {
  if (isCancelled()) {
    throw const _SqlDumpImportCancelledSignal();
  }
}

bool _startsWithKeyword(String value, String keyword) {
  return value.toUpperCase().startsWith(keyword.toUpperCase());
}

bool _isWhitespace(String char) {
  return char == ' ' ||
      char == '\n' ||
      char == '\r' ||
      char == '\t' ||
      char == '\f';
}

List<String> _splitTopLevel(String text, {required String delimiter}) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var parenDepth = 0;
  var inSingle = false;
  var inDouble = false;
  var inBacktick = false;
  var escape = false;

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    final next = i + 1 < text.length ? text[i + 1] : '';

    if (escape) {
      buffer.write(char);
      escape = false;
      continue;
    }
    if ((inSingle || inDouble) && char == r'\') {
      buffer.write(char);
      escape = true;
      continue;
    }
    if (char == "'" && !inDouble && !inBacktick) {
      buffer.write(char);
      if (inSingle && next == "'") {
        buffer.write(next);
        i++;
      } else {
        inSingle = !inSingle;
      }
      continue;
    }
    if (char == '"' && !inSingle && !inBacktick) {
      buffer.write(char);
      inDouble = !inDouble;
      continue;
    }
    if (char == '`' && !inSingle && !inDouble) {
      buffer.write(char);
      inBacktick = !inBacktick;
      continue;
    }
    if (!inSingle && !inDouble && !inBacktick) {
      if (char == '(') {
        parenDepth++;
      } else if (char == ')') {
        parenDepth = parenDepth > 0 ? parenDepth - 1 : 0;
      } else if (parenDepth == 0 && char == delimiter) {
        parts.add(buffer.toString());
        buffer.clear();
        continue;
      }
    }
    buffer.write(char);
  }

  parts.add(buffer.toString());
  return parts;
}

int? _findMatchingParen(String text, int openIndex) {
  var depth = 0;
  var inSingle = false;
  var inDouble = false;
  var inBacktick = false;
  var escape = false;

  for (var i = openIndex; i < text.length; i++) {
    final char = text[i];
    final next = i + 1 < text.length ? text[i + 1] : '';

    if (escape) {
      escape = false;
      continue;
    }
    if ((inSingle || inDouble) && char == r'\') {
      escape = true;
      continue;
    }
    if (char == "'" && !inDouble && !inBacktick) {
      if (!(inSingle && next == "'")) {
        inSingle = !inSingle;
      } else {
        i++;
      }
      continue;
    }
    if (char == '"' && !inSingle && !inBacktick) {
      inDouble = !inDouble;
      continue;
    }
    if (char == '`' && !inSingle && !inDouble) {
      inBacktick = !inBacktick;
      continue;
    }
    if (inSingle || inDouble || inBacktick) {
      continue;
    }

    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;
      if (depth == 0) {
        return i;
      }
    }
  }
  return null;
}

_IdentifierToken? _readQualifiedIdentifier(String text, int start) {
  var index = start;
  final parts = <String>[];
  while (true) {
    while (index < text.length && _isWhitespace(text[index])) {
      index++;
    }
    final part = _readIdentifier(text, index);
    if (part == null) {
      break;
    }
    parts.add(part.value);
    index = part.nextIndex;
    while (index < text.length && _isWhitespace(text[index])) {
      index++;
    }
    if (index < text.length && text[index] == '.') {
      index++;
      continue;
    }
    break;
  }
  if (parts.isEmpty) {
    return null;
  }
  return _IdentifierToken(parts.last, index);
}

_IdentifierToken? _readIdentifier(String text, int start) {
  if (start >= text.length) {
    return null;
  }
  if (text[start] == '`') {
    final end = text.indexOf('`', start + 1);
    if (end < 0) {
      return null;
    }
    return _IdentifierToken(text.substring(start + 1, end), end + 1);
  }

  final match = RegExp(
    r'^[A-Za-z_][A-Za-z0-9_$]*',
  ).matchAsPrefix(text.substring(start));
  if (match == null) {
    return null;
  }
  return _IdentifierToken(match.group(0)!, start + match.group(0)!.length);
}

String _unquoteIdentifier(String value) {
  final trimmed = value.trim();
  if (trimmed.startsWith('`') && trimmed.endsWith('`') && trimmed.length >= 2) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

String _statementSnippet(String statement, {int maxLength = 120}) {
  final compact = statement.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= maxLength) {
    return compact;
  }
  return '${compact.substring(0, maxLength - 1)}…';
}

class _DecodedSqlText {
  const _DecodedSqlText({
    required this.text,
    required this.resolvedEncoding,
    required this.warnings,
  });

  final String text;
  final String resolvedEncoding;
  final List<String> warnings;
}

class _DumpParseResult {
  const _DumpParseResult({
    required this.tables,
    required this.warnings,
    required this.skippedStatements,
    required this.totalStatements,
  });

  final Map<String, _ParsedDumpTable> tables;
  final List<String> warnings;
  final List<SqlDumpImportSkippedStatement> skippedStatements;
  final int totalStatements;
}

class _CreateTableParseResult {
  const _CreateTableParseResult._({
    this.table,
    this.skipped,
    this.warnings = const <String>[],
  });

  factory _CreateTableParseResult.table(
    _ParsedDumpTable table,
    List<String> warnings,
  ) {
    return _CreateTableParseResult._(table: table, warnings: warnings);
  }

  factory _CreateTableParseResult.skipped(
    SqlDumpImportSkippedStatement skipped,
  ) {
    return _CreateTableParseResult._(skipped: skipped);
  }

  final _ParsedDumpTable? table;
  final SqlDumpImportSkippedStatement? skipped;
  final List<String> warnings;
}

class _InsertParseResult {
  const _InsertParseResult._({this.insert, this.skipped});

  factory _InsertParseResult.insert(_ParsedInsertStatement insert) {
    return _InsertParseResult._(insert: insert);
  }

  factory _InsertParseResult.skipped(SqlDumpImportSkippedStatement skipped) {
    return _InsertParseResult._(skipped: skipped);
  }

  final _ParsedInsertStatement? insert;
  final SqlDumpImportSkippedStatement? skipped;
}

class _ParsedDumpTable {
  _ParsedDumpTable({
    required this.name,
    required List<_ParsedDumpColumn> columns,
  }) : columns = <_ParsedDumpColumn>[
         for (var i = 0; i < columns.length; i++)
           columns[i].copyWith(sourceIndex: i),
       ];

  final String name;
  final List<_ParsedDumpColumn> columns;
  final List<Map<String, Object?>> previewRows = <Map<String, Object?>>[];
  int rowCount = 0;

  void absorbInsert(_ParsedInsertStatement insert) {
    final sourceColumns =
        insert.columnNames ??
        <String>[for (final column in columns) column.sourceName];
    final sourceIndexes = <String, int>{
      for (var i = 0; i < sourceColumns.length; i++) sourceColumns[i]: i,
    };
    for (final row in insert.rows) {
      rowCount++;
      if (previewRows.length < _sqlDumpPreviewRowLimit) {
        previewRows.add(<String, Object?>{
          for (final column in columns)
            column.sourceName:
                sourceIndexes.containsKey(column.sourceName) &&
                    sourceIndexes[column.sourceName]! < row.length
                ? row[sourceIndexes[column.sourceName]!]
                : null,
        });
      }
    }
  }

  SqlDumpImportTableDraft toDraft() {
    return SqlDumpImportTableDraft(
      sourceName: name,
      targetName: name,
      selected: true,
      rowCount: rowCount,
      columns: <SqlDumpImportColumnDraft>[
        for (final column in columns)
          SqlDumpImportColumnDraft(
            sourceIndex: column.sourceIndex,
            sourceName: column.sourceName,
            targetName: column.sourceName,
            declaredType: column.declaredType,
            inferredTargetType: column.targetType,
            targetType: column.targetType,
            notNull: column.notNull,
            primaryKey: column.primaryKey,
            unique: column.unique,
          ),
      ],
      previewRows: previewRows,
    );
  }
}

class _ParsedDumpColumn {
  const _ParsedDumpColumn({
    required this.sourceIndex,
    required this.sourceName,
    required this.declaredType,
    required this.targetType,
    required this.notNull,
    required this.primaryKey,
    required this.unique,
  });

  final int sourceIndex;
  final String sourceName;
  final String declaredType;
  final String targetType;
  final bool notNull;
  final bool primaryKey;
  final bool unique;

  _ParsedDumpColumn copyWith({
    int? sourceIndex,
    bool? primaryKey,
    bool? unique,
  }) {
    return _ParsedDumpColumn(
      sourceIndex: sourceIndex ?? this.sourceIndex,
      sourceName: sourceName,
      declaredType: declaredType,
      targetType: targetType,
      notNull: notNull,
      primaryKey: primaryKey ?? this.primaryKey,
      unique: unique ?? this.unique,
    );
  }
}

class _ParsedInsertStatement {
  const _ParsedInsertStatement({
    required this.tableName,
    required this.columnNames,
    required this.rows,
  });

  final String tableName;
  final List<String>? columnNames;
  final List<List<Object?>> rows;
}

class _IdentifierToken {
  const _IdentifierToken(this.value, this.nextIndex);

  final String value;
  final int nextIndex;
}

class _SqlDumpImportCancelled implements Exception {
  const _SqlDumpImportCancelled(this.summary);

  final SqlDumpImportSummary summary;
}

class _SqlDumpImportCancelledSignal implements Exception {
  const _SqlDumpImportCancelledSignal();
}
