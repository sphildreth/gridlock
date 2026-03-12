import 'workspace_models.dart';

enum SqliteImportWizardStep {
  source,
  target,
  preview,
  transforms,
  execute,
  summary,
}

enum SqliteImportJobPhase {
  idle,
  inspecting,
  ready,
  running,
  cancelling,
  completed,
  failed,
  cancelled,
}

enum SqliteImportUpdateKind { progress, completed, failed, cancelled }

class SqliteImportForeignKey {
  const SqliteImportForeignKey({
    required this.fromColumn,
    required this.toTable,
    this.toColumn,
    this.onDelete,
    this.onUpdate,
  });

  final String fromColumn;
  final String toTable;
  final String? toColumn;
  final String? onDelete;
  final String? onUpdate;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'fromColumn': fromColumn,
      'toTable': toTable,
      'toColumn': toColumn,
      'onDelete': onDelete,
      'onUpdate': onUpdate,
    };
  }

  factory SqliteImportForeignKey.fromMap(Map<String, Object?> map) {
    return SqliteImportForeignKey(
      fromColumn: map['fromColumn']! as String,
      toTable: map['toTable']! as String,
      toColumn: map['toColumn'] as String?,
      onDelete: map['onDelete'] as String?,
      onUpdate: map['onUpdate'] as String?,
    );
  }
}

class SqliteImportIndex {
  const SqliteImportIndex({
    required this.name,
    this.column,
    List<String>? elements,
    required this.unique,
    this.whereSql,
  }) : elements = elements ?? const <String>[];

  final String name;
  final String? column;
  final List<String> elements;
  final bool unique;
  final String? whereSql;

  List<String> get resolvedElements => elements.isNotEmpty
      ? elements
      : (column == null ? const <String>[] : <String>[column!]);

  bool get isComposite => resolvedElements.length > 1;
  bool get isPartial => whereSql != null && whereSql!.trim().isNotEmpty;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'column': column,
      'elements': resolvedElements,
      'unique': unique,
      'whereSql': whereSql,
    };
  }

  factory SqliteImportIndex.fromMap(Map<String, Object?> map) {
    final storedElements = ((map['elements'] as List?) ?? const <Object?>[])
        .cast<String>();
    return SqliteImportIndex(
      name: map['name']! as String,
      column: storedElements.isEmpty ? map['column'] as String? : null,
      elements: storedElements.isEmpty ? null : storedElements,
      unique: map['unique']! as bool,
      whereSql: map['whereSql'] as String?,
    );
  }
}

class SqliteImportCheckConstraint {
  const SqliteImportCheckConstraint({required this.exprSql, this.name});

  final String exprSql;
  final String? name;

  Map<String, Object?> toMap() {
    return <String, Object?>{'exprSql': exprSql, 'name': name};
  }

  factory SqliteImportCheckConstraint.fromMap(Map<String, Object?> map) {
    return SqliteImportCheckConstraint(
      exprSql: (map['exprSql'] ?? map['sql'])! as String,
      name: map['name'] as String?,
    );
  }
}

class SqliteImportSkippedItem {
  const SqliteImportSkippedItem({
    required this.name,
    required this.reason,
    this.tableName,
  });

  final String name;
  final String reason;
  final String? tableName;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'name': name,
      'reason': reason,
      'tableName': tableName,
    };
  }

  factory SqliteImportSkippedItem.fromMap(Map<String, Object?> map) {
    return SqliteImportSkippedItem(
      name: map['name']! as String,
      reason: map['reason']! as String,
      tableName: map['tableName'] as String?,
    );
  }
}

class SqliteImportColumnDraft {
  const SqliteImportColumnDraft({
    required this.sourceName,
    required this.targetName,
    required this.declaredType,
    required this.inferredTargetType,
    required this.targetType,
    required this.notNull,
    required this.primaryKey,
    required this.unique,
    this.defaultExpr,
    this.generatedExpr,
    this.generatedStored = false,
    this.generatedVirtual = false,
  });

  final String sourceName;
  final String targetName;
  final String declaredType;
  final String inferredTargetType;
  final String targetType;
  final bool notNull;
  final bool primaryKey;
  final bool unique;
  final String? defaultExpr;
  final String? generatedExpr;
  final bool generatedStored;
  final bool generatedVirtual;

  bool get hasDefault => defaultExpr != null && defaultExpr!.trim().isNotEmpty;
  bool get isGenerated => generatedStored || generatedVirtual;

  SqliteImportColumnDraft copyWith({
    String? sourceName,
    String? targetName,
    String? declaredType,
    String? inferredTargetType,
    String? targetType,
    bool? notNull,
    bool? primaryKey,
    bool? unique,
    Object? defaultExpr = _unset,
    Object? generatedExpr = _unset,
    bool? generatedStored,
    bool? generatedVirtual,
  }) {
    return SqliteImportColumnDraft(
      sourceName: sourceName ?? this.sourceName,
      targetName: targetName ?? this.targetName,
      declaredType: declaredType ?? this.declaredType,
      inferredTargetType: inferredTargetType ?? this.inferredTargetType,
      targetType: targetType ?? this.targetType,
      notNull: notNull ?? this.notNull,
      primaryKey: primaryKey ?? this.primaryKey,
      unique: unique ?? this.unique,
      defaultExpr: defaultExpr == _unset
          ? this.defaultExpr
          : defaultExpr as String?,
      generatedExpr: generatedExpr == _unset
          ? this.generatedExpr
          : generatedExpr as String?,
      generatedStored: generatedStored ?? this.generatedStored,
      generatedVirtual: generatedVirtual ?? this.generatedVirtual,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourceName': sourceName,
      'targetName': targetName,
      'declaredType': declaredType,
      'inferredTargetType': inferredTargetType,
      'targetType': targetType,
      'notNull': notNull,
      'primaryKey': primaryKey,
      'unique': unique,
      'defaultExpr': defaultExpr,
      'generatedExpr': generatedExpr,
      'generatedStored': generatedStored,
      'generatedVirtual': generatedVirtual,
    };
  }

  factory SqliteImportColumnDraft.fromMap(Map<String, Object?> map) {
    return SqliteImportColumnDraft(
      sourceName: map['sourceName']! as String,
      targetName: map['targetName']! as String,
      declaredType: map['declaredType']! as String,
      inferredTargetType: map['inferredTargetType']! as String,
      targetType: map['targetType']! as String,
      notNull: map['notNull']! as bool,
      primaryKey: map['primaryKey']! as bool,
      unique: map['unique']! as bool,
      defaultExpr: map['defaultExpr'] as String?,
      generatedExpr: map['generatedExpr'] as String?,
      generatedStored: map['generatedStored'] as bool? ?? false,
      generatedVirtual: map['generatedVirtual'] as bool? ?? false,
    );
  }
}

class SqliteImportTableDraft {
  const SqliteImportTableDraft({
    required this.sourceName,
    required this.targetName,
    required this.selected,
    required this.rowCount,
    required this.strict,
    required this.withoutRowId,
    required this.columns,
    required this.foreignKeys,
    this.checks = const <SqliteImportCheckConstraint>[],
    required this.indexes,
    required this.skippedItems,
    required this.previewRows,
    required this.previewLoaded,
    this.previewError,
  });

  final String sourceName;
  final String targetName;
  final bool selected;
  final int rowCount;
  final bool strict;
  final bool withoutRowId;
  final List<SqliteImportColumnDraft> columns;
  final List<SqliteImportForeignKey> foreignKeys;
  final List<SqliteImportCheckConstraint> checks;
  final List<SqliteImportIndex> indexes;
  final List<SqliteImportSkippedItem> skippedItems;
  final List<Map<String, Object?>> previewRows;
  final bool previewLoaded;
  final String? previewError;

  bool get hasCompositePrimaryKey =>
      columns.where((column) => column.primaryKey).length > 1;

  List<String> get sourceColumnNames =>
      columns.map((column) => column.sourceName).toList();

  SqliteImportTableDraft copyWith({
    String? sourceName,
    String? targetName,
    bool? selected,
    int? rowCount,
    bool? strict,
    bool? withoutRowId,
    List<SqliteImportColumnDraft>? columns,
    List<SqliteImportForeignKey>? foreignKeys,
    List<SqliteImportCheckConstraint>? checks,
    List<SqliteImportIndex>? indexes,
    List<SqliteImportSkippedItem>? skippedItems,
    List<Map<String, Object?>>? previewRows,
    bool? previewLoaded,
    Object? previewError = _unset,
  }) {
    return SqliteImportTableDraft(
      sourceName: sourceName ?? this.sourceName,
      targetName: targetName ?? this.targetName,
      selected: selected ?? this.selected,
      rowCount: rowCount ?? this.rowCount,
      strict: strict ?? this.strict,
      withoutRowId: withoutRowId ?? this.withoutRowId,
      columns: columns ?? this.columns,
      foreignKeys: foreignKeys ?? this.foreignKeys,
      checks: checks ?? this.checks,
      indexes: indexes ?? this.indexes,
      skippedItems: skippedItems ?? this.skippedItems,
      previewRows: previewRows ?? this.previewRows,
      previewLoaded: previewLoaded ?? this.previewLoaded,
      previewError: previewError == _unset
          ? this.previewError
          : previewError as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourceName': sourceName,
      'targetName': targetName,
      'selected': selected,
      'rowCount': rowCount,
      'strict': strict,
      'withoutRowId': withoutRowId,
      'columns': <Map<String, Object?>>[
        for (final column in columns) column.toMap(),
      ],
      'foreignKeys': <Map<String, Object?>>[
        for (final foreignKey in foreignKeys) foreignKey.toMap(),
      ],
      'checks': <Map<String, Object?>>[
        for (final check in checks) check.toMap(),
      ],
      'indexes': <Map<String, Object?>>[
        for (final index in indexes) index.toMap(),
      ],
      'skippedItems': <Map<String, Object?>>[
        for (final item in skippedItems) item.toMap(),
      ],
      'previewRows': previewRows,
      'previewLoaded': previewLoaded,
      'previewError': previewError,
    };
  }

  factory SqliteImportTableDraft.fromMap(Map<String, Object?> map) {
    return SqliteImportTableDraft(
      sourceName: map['sourceName']! as String,
      targetName: map['targetName']! as String,
      selected: map['selected']! as bool,
      rowCount: map['rowCount']! as int,
      strict: map['strict']! as bool,
      withoutRowId: map['withoutRowId']! as bool,
      columns: ((map['columns'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (column) => SqliteImportColumnDraft.fromMap(
              column.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      foreignKeys: ((map['foreignKeys'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (foreignKey) => SqliteImportForeignKey.fromMap(
              foreignKey.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      checks: ((map['checks'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (check) => SqliteImportCheckConstraint.fromMap(
              check.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      indexes: ((map['indexes'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (index) => SqliteImportIndex.fromMap(
              index.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      skippedItems: ((map['skippedItems'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (item) => SqliteImportSkippedItem.fromMap(
              item.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      previewRows: ((map['previewRows'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map((row) => row.map((key, value) => MapEntry(key as String, value)))
          .toList(),
      previewLoaded: map['previewLoaded']! as bool,
      previewError: map['previewError'] as String?,
    );
  }
}

class SqliteImportInspection {
  const SqliteImportInspection({
    required this.sourcePath,
    required this.tables,
    required this.warnings,
  });

  final String sourcePath;
  final List<SqliteImportTableDraft> tables;
  final List<String> warnings;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourcePath': sourcePath,
      'tables': <Map<String, Object?>>[
        for (final table in tables) table.toMap(),
      ],
      'warnings': warnings,
    };
  }

  factory SqliteImportInspection.fromMap(Map<String, Object?> map) {
    return SqliteImportInspection(
      sourcePath: map['sourcePath']! as String,
      tables: ((map['tables'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (table) => SqliteImportTableDraft.fromMap(
              table.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      warnings: ((map['warnings'] as List?) ?? const <Object?>[])
          .cast<String>(),
    );
  }
}

class SqliteImportPreview {
  const SqliteImportPreview({required this.tableName, required this.rows});

  final String tableName;
  final List<Map<String, Object?>> rows;

  Map<String, Object?> toMap() {
    return <String, Object?>{'tableName': tableName, 'rows': rows};
  }

  factory SqliteImportPreview.fromMap(Map<String, Object?> map) {
    return SqliteImportPreview(
      tableName: map['tableName']! as String,
      rows: ((map['rows'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map((row) => row.map((key, value) => MapEntry(key as String, value)))
          .toList(),
    );
  }
}

class SqliteImportRequest {
  const SqliteImportRequest({
    required this.jobId,
    required this.sourcePath,
    required this.targetPath,
    required this.importIntoExistingTarget,
    required this.replaceExistingTarget,
    required this.tables,
  });

  final String jobId;
  final String sourcePath;
  final String targetPath;
  final bool importIntoExistingTarget;
  final bool replaceExistingTarget;
  final List<SqliteImportTableDraft> tables;

  List<SqliteImportTableDraft> get selectedTables =>
      tables.where((table) => table.selected).toList();

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'importIntoExistingTarget': importIntoExistingTarget,
      'replaceExistingTarget': replaceExistingTarget,
      'tables': <Map<String, Object?>>[
        for (final table in tables) table.toMap(),
      ],
    };
  }

  factory SqliteImportRequest.fromMap(Map<String, Object?> map) {
    return SqliteImportRequest(
      jobId: map['jobId']! as String,
      sourcePath: map['sourcePath']! as String,
      targetPath: map['targetPath']! as String,
      importIntoExistingTarget: map['importIntoExistingTarget']! as bool,
      replaceExistingTarget: map['replaceExistingTarget']! as bool,
      tables: ((map['tables'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (table) => SqliteImportTableDraft.fromMap(
              table.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
    );
  }
}

class SqliteImportProgress {
  const SqliteImportProgress({
    required this.jobId,
    required this.currentTable,
    required this.completedTables,
    required this.totalTables,
    required this.currentTableRowsCopied,
    required this.currentTableRowCount,
    required this.totalRowsCopied,
    required this.message,
  });

  final String jobId;
  final String currentTable;
  final int completedTables;
  final int totalTables;
  final int currentTableRowsCopied;
  final int currentTableRowCount;
  final int totalRowsCopied;
  final String message;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'currentTable': currentTable,
      'completedTables': completedTables,
      'totalTables': totalTables,
      'currentTableRowsCopied': currentTableRowsCopied,
      'currentTableRowCount': currentTableRowCount,
      'totalRowsCopied': totalRowsCopied,
      'message': message,
    };
  }

  factory SqliteImportProgress.fromMap(Map<String, Object?> map) {
    return SqliteImportProgress(
      jobId: map['jobId']! as String,
      currentTable: map['currentTable']! as String,
      completedTables: map['completedTables']! as int,
      totalTables: map['totalTables']! as int,
      currentTableRowsCopied: map['currentTableRowsCopied']! as int,
      currentTableRowCount: map['currentTableRowCount']! as int,
      totalRowsCopied: map['totalRowsCopied']! as int,
      message: map['message']! as String,
    );
  }
}

class SqliteImportSummary {
  const SqliteImportSummary({
    required this.jobId,
    required this.sourcePath,
    required this.targetPath,
    required this.importedTables,
    required this.rowsCopiedByTable,
    required this.indexesCreated,
    required this.skippedItems,
    required this.warnings,
    required this.statusMessage,
    required this.rolledBack,
  });

  final String jobId;
  final String sourcePath;
  final String targetPath;
  final List<String> importedTables;
  final Map<String, int> rowsCopiedByTable;
  final List<String> indexesCreated;
  final List<SqliteImportSkippedItem> skippedItems;
  final List<String> warnings;
  final String statusMessage;
  final bool rolledBack;

  String? get firstImportedTable =>
      importedTables.isEmpty ? null : importedTables.first;

  int get totalRowsCopied =>
      rowsCopiedByTable.values.fold<int>(0, (sum, value) => sum + value);

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'importedTables': importedTables,
      'rowsCopiedByTable': rowsCopiedByTable,
      'indexesCreated': indexesCreated,
      'skippedItems': <Map<String, Object?>>[
        for (final item in skippedItems) item.toMap(),
      ],
      'warnings': warnings,
      'statusMessage': statusMessage,
      'rolledBack': rolledBack,
    };
  }

  factory SqliteImportSummary.fromMap(Map<String, Object?> map) {
    return SqliteImportSummary(
      jobId: map['jobId']! as String,
      sourcePath: map['sourcePath']! as String,
      targetPath: map['targetPath']! as String,
      importedTables: ((map['importedTables'] as List?) ?? const <Object?>[])
          .cast<String>(),
      rowsCopiedByTable:
          ((map['rowsCopiedByTable'] as Map?) ?? const <Object?, Object?>{})
              .map((key, value) => MapEntry(key as String, value as int)),
      indexesCreated: ((map['indexesCreated'] as List?) ?? const <Object?>[])
          .cast<String>(),
      skippedItems: ((map['skippedItems'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (item) => SqliteImportSkippedItem.fromMap(
              item.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      warnings: ((map['warnings'] as List?) ?? const <Object?>[])
          .cast<String>(),
      statusMessage: map['statusMessage']! as String,
      rolledBack: map['rolledBack']! as bool,
    );
  }
}

class SqliteImportUpdate {
  const SqliteImportUpdate({
    required this.kind,
    required this.jobId,
    this.progress,
    this.summary,
    this.message,
  });

  final SqliteImportUpdateKind kind;
  final String jobId;
  final SqliteImportProgress? progress;
  final SqliteImportSummary? summary;
  final String? message;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'kind': kind.name,
      'jobId': jobId,
      'progress': progress?.toMap(),
      'summary': summary?.toMap(),
      'message': message,
    };
  }

  factory SqliteImportUpdate.fromMap(Map<String, Object?> map) {
    return SqliteImportUpdate(
      kind: SqliteImportUpdateKind.values.byName(map['kind']! as String),
      jobId: map['jobId']! as String,
      progress: map['progress'] is Map<Object?, Object?>
          ? SqliteImportProgress.fromMap(
              (map['progress']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key as String, value),
              ),
            )
          : null,
      summary: map['summary'] is Map<Object?, Object?>
          ? SqliteImportSummary.fromMap(
              (map['summary']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key as String, value),
              ),
            )
          : null,
      message: map['message'] as String?,
    );
  }
}

class SqliteImportSession {
  const SqliteImportSession({
    required this.step,
    required this.phase,
    required this.sourcePath,
    required this.targetPath,
    required this.importIntoExistingTarget,
    required this.replaceExistingTarget,
    required this.tables,
    required this.warnings,
    this.focusedTable,
    this.progress,
    this.summary,
    this.error,
    this.jobId,
    this.loadingPreviewTable,
  });

  final SqliteImportWizardStep step;
  final SqliteImportJobPhase phase;
  final String sourcePath;
  final String targetPath;
  final bool importIntoExistingTarget;
  final bool replaceExistingTarget;
  final List<SqliteImportTableDraft> tables;
  final List<String> warnings;
  final String? focusedTable;
  final SqliteImportProgress? progress;
  final SqliteImportSummary? summary;
  final String? error;
  final String? jobId;
  final String? loadingPreviewTable;

  factory SqliteImportSession.initial({String sourcePath = ''}) {
    return SqliteImportSession(
      step: SqliteImportWizardStep.source,
      phase: SqliteImportJobPhase.idle,
      sourcePath: sourcePath,
      targetPath: '',
      importIntoExistingTarget: false,
      replaceExistingTarget: false,
      tables: const <SqliteImportTableDraft>[],
      warnings: const <String>[],
    );
  }

  List<SqliteImportTableDraft> get selectedTables =>
      tables.where((table) => table.selected).toList();

  SqliteImportTableDraft? get focusedTableDraft {
    if (focusedTable == null) {
      return selectedTables.isEmpty ? null : selectedTables.first;
    }
    for (final table in tables) {
      if (table.sourceName == focusedTable) {
        return table;
      }
    }
    return selectedTables.isEmpty ? null : selectedTables.first;
  }

  bool get canAdvanceFromSource =>
      sourcePath.trim().isNotEmpty && tables.isNotEmpty;

  bool get canAdvanceFromTarget => targetPath.trim().isNotEmpty;

  bool get canAdvanceFromPreview => selectedTables.isNotEmpty;

  bool get canAdvanceFromTransforms =>
      selectedTables.isNotEmpty &&
      selectedTables.every(
        (table) =>
            table.targetName.trim().isNotEmpty &&
            _hasDistinctNames(
              table.columns.map((column) => column.targetName).toList(),
            ),
      ) &&
      _hasDistinctNames(
        selectedTables.map((table) => table.targetName).toList(),
      );

  SqliteImportSession copyWith({
    SqliteImportWizardStep? step,
    SqliteImportJobPhase? phase,
    String? sourcePath,
    String? targetPath,
    bool? importIntoExistingTarget,
    bool? replaceExistingTarget,
    List<SqliteImportTableDraft>? tables,
    List<String>? warnings,
    Object? focusedTable = _unset,
    Object? progress = _unset,
    Object? summary = _unset,
    Object? error = _unset,
    Object? jobId = _unset,
    Object? loadingPreviewTable = _unset,
  }) {
    return SqliteImportSession(
      step: step ?? this.step,
      phase: phase ?? this.phase,
      sourcePath: sourcePath ?? this.sourcePath,
      targetPath: targetPath ?? this.targetPath,
      importIntoExistingTarget:
          importIntoExistingTarget ?? this.importIntoExistingTarget,
      replaceExistingTarget:
          replaceExistingTarget ?? this.replaceExistingTarget,
      tables: tables ?? this.tables,
      warnings: warnings ?? this.warnings,
      focusedTable: focusedTable == _unset
          ? this.focusedTable
          : focusedTable as String?,
      progress: progress == _unset
          ? this.progress
          : progress as SqliteImportProgress?,
      summary: summary == _unset
          ? this.summary
          : summary as SqliteImportSummary?,
      error: error == _unset ? this.error : error as String?,
      jobId: jobId == _unset ? this.jobId : jobId as String?,
      loadingPreviewTable: loadingPreviewTable == _unset
          ? this.loadingPreviewTable
          : loadingPreviewTable as String?,
    );
  }
}

const Object _unset = Object();

bool _hasDistinctNames(List<String> names) {
  final normalized = names
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty);
  return normalized.length == normalized.toSet().length;
}

String formatImportCellValue(Object? value) {
  return formatCellValue(value);
}
