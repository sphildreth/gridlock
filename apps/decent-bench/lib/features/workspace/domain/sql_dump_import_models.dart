import 'workspace_models.dart';

enum SqlDumpImportWizardStep {
  source,
  target,
  preview,
  transforms,
  execute,
  summary,
}

enum SqlDumpImportJobPhase {
  idle,
  inspecting,
  ready,
  running,
  cancelling,
  completed,
  failed,
  cancelled,
}

enum SqlDumpImportUpdateKind { progress, completed, failed, cancelled }

const List<String> sqlDumpEncodingOptions = <String>['auto', 'utf8', 'latin1'];

String sqlDumpEncodingLabel(String value) {
  return switch (value) {
    'auto' => 'Auto-detect',
    'utf8' => 'UTF-8',
    'latin1' => 'Latin-1',
    _ => value,
  };
}

class SqlDumpImportSkippedStatement {
  const SqlDumpImportSkippedStatement({
    required this.ordinal,
    required this.kind,
    required this.reason,
    required this.snippet,
  });

  final int ordinal;
  final String kind;
  final String reason;
  final String snippet;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'ordinal': ordinal,
      'kind': kind,
      'reason': reason,
      'snippet': snippet,
    };
  }

  factory SqlDumpImportSkippedStatement.fromMap(Map<String, Object?> map) {
    return SqlDumpImportSkippedStatement(
      ordinal: map['ordinal']! as int,
      kind: map['kind']! as String,
      reason: map['reason']! as String,
      snippet: map['snippet']! as String,
    );
  }
}

class SqlDumpImportColumnDraft {
  const SqlDumpImportColumnDraft({
    required this.sourceIndex,
    required this.sourceName,
    required this.targetName,
    required this.declaredType,
    required this.inferredTargetType,
    required this.targetType,
    required this.notNull,
    required this.primaryKey,
    required this.unique,
  });

  final int sourceIndex;
  final String sourceName;
  final String targetName;
  final String declaredType;
  final String inferredTargetType;
  final String targetType;
  final bool notNull;
  final bool primaryKey;
  final bool unique;

  SqlDumpImportColumnDraft copyWith({
    int? sourceIndex,
    String? sourceName,
    String? targetName,
    String? declaredType,
    String? inferredTargetType,
    String? targetType,
    bool? notNull,
    bool? primaryKey,
    bool? unique,
  }) {
    return SqlDumpImportColumnDraft(
      sourceIndex: sourceIndex ?? this.sourceIndex,
      sourceName: sourceName ?? this.sourceName,
      targetName: targetName ?? this.targetName,
      declaredType: declaredType ?? this.declaredType,
      inferredTargetType: inferredTargetType ?? this.inferredTargetType,
      targetType: targetType ?? this.targetType,
      notNull: notNull ?? this.notNull,
      primaryKey: primaryKey ?? this.primaryKey,
      unique: unique ?? this.unique,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourceIndex': sourceIndex,
      'sourceName': sourceName,
      'targetName': targetName,
      'declaredType': declaredType,
      'inferredTargetType': inferredTargetType,
      'targetType': targetType,
      'notNull': notNull,
      'primaryKey': primaryKey,
      'unique': unique,
    };
  }

  factory SqlDumpImportColumnDraft.fromMap(Map<String, Object?> map) {
    return SqlDumpImportColumnDraft(
      sourceIndex: map['sourceIndex']! as int,
      sourceName: map['sourceName']! as String,
      targetName: map['targetName']! as String,
      declaredType: map['declaredType']! as String,
      inferredTargetType: map['inferredTargetType']! as String,
      targetType: map['targetType']! as String,
      notNull: map['notNull']! as bool,
      primaryKey: map['primaryKey']! as bool,
      unique: map['unique']! as bool,
    );
  }
}

class SqlDumpImportTableDraft {
  const SqlDumpImportTableDraft({
    required this.sourceName,
    required this.targetName,
    required this.selected,
    required this.rowCount,
    required this.columns,
    required this.previewRows,
  });

  final String sourceName;
  final String targetName;
  final bool selected;
  final int rowCount;
  final List<SqlDumpImportColumnDraft> columns;
  final List<Map<String, Object?>> previewRows;

  SqlDumpImportTableDraft copyWith({
    String? sourceName,
    String? targetName,
    bool? selected,
    int? rowCount,
    List<SqlDumpImportColumnDraft>? columns,
    List<Map<String, Object?>>? previewRows,
  }) {
    return SqlDumpImportTableDraft(
      sourceName: sourceName ?? this.sourceName,
      targetName: targetName ?? this.targetName,
      selected: selected ?? this.selected,
      rowCount: rowCount ?? this.rowCount,
      columns: columns ?? this.columns,
      previewRows: previewRows ?? this.previewRows,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourceName': sourceName,
      'targetName': targetName,
      'selected': selected,
      'rowCount': rowCount,
      'columns': <Map<String, Object?>>[
        for (final column in columns) column.toMap(),
      ],
      'previewRows': previewRows,
    };
  }

  factory SqlDumpImportTableDraft.fromMap(Map<String, Object?> map) {
    return SqlDumpImportTableDraft(
      sourceName: map['sourceName']! as String,
      targetName: map['targetName']! as String,
      selected: map['selected']! as bool,
      rowCount: map['rowCount']! as int,
      columns: ((map['columns'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (column) => SqlDumpImportColumnDraft.fromMap(
              column.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      previewRows: ((map['previewRows'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map((row) => row.map((key, value) => MapEntry(key as String, value)))
          .toList(),
    );
  }
}

class SqlDumpImportInspection {
  const SqlDumpImportInspection({
    required this.sourcePath,
    required this.requestedEncoding,
    required this.resolvedEncoding,
    required this.tables,
    required this.warnings,
    required this.skippedStatements,
    required this.totalStatements,
  });

  final String sourcePath;
  final String requestedEncoding;
  final String resolvedEncoding;
  final List<SqlDumpImportTableDraft> tables;
  final List<String> warnings;
  final List<SqlDumpImportSkippedStatement> skippedStatements;
  final int totalStatements;

  int get skippedStatementCount => skippedStatements.length;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourcePath': sourcePath,
      'requestedEncoding': requestedEncoding,
      'resolvedEncoding': resolvedEncoding,
      'tables': <Map<String, Object?>>[
        for (final table in tables) table.toMap(),
      ],
      'warnings': warnings,
      'skippedStatements': <Map<String, Object?>>[
        for (final statement in skippedStatements) statement.toMap(),
      ],
      'totalStatements': totalStatements,
    };
  }

  factory SqlDumpImportInspection.fromMap(Map<String, Object?> map) {
    return SqlDumpImportInspection(
      sourcePath: map['sourcePath']! as String,
      requestedEncoding: map['requestedEncoding']! as String,
      resolvedEncoding: map['resolvedEncoding']! as String,
      tables: ((map['tables'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (table) => SqlDumpImportTableDraft.fromMap(
              table.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      warnings: ((map['warnings'] as List?) ?? const <Object?>[])
          .cast<String>(),
      skippedStatements:
          ((map['skippedStatements'] as List?) ?? const <Object?>[])
              .cast<Map<Object?, Object?>>()
              .map(
                (statement) => SqlDumpImportSkippedStatement.fromMap(
                  statement.map((key, value) => MapEntry(key as String, value)),
                ),
              )
              .toList(),
      totalStatements: map['totalStatements']! as int,
    );
  }
}

class SqlDumpImportRequest {
  const SqlDumpImportRequest({
    required this.jobId,
    required this.sourcePath,
    required this.targetPath,
    required this.importIntoExistingTarget,
    required this.replaceExistingTarget,
    required this.encoding,
    required this.tables,
  });

  final String jobId;
  final String sourcePath;
  final String targetPath;
  final bool importIntoExistingTarget;
  final bool replaceExistingTarget;
  final String encoding;
  final List<SqlDumpImportTableDraft> tables;

  List<SqlDumpImportTableDraft> get selectedTables =>
      tables.where((table) => table.selected).toList();

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'importIntoExistingTarget': importIntoExistingTarget,
      'replaceExistingTarget': replaceExistingTarget,
      'encoding': encoding,
      'tables': <Map<String, Object?>>[
        for (final table in tables) table.toMap(),
      ],
    };
  }

  factory SqlDumpImportRequest.fromMap(Map<String, Object?> map) {
    return SqlDumpImportRequest(
      jobId: map['jobId']! as String,
      sourcePath: map['sourcePath']! as String,
      targetPath: map['targetPath']! as String,
      importIntoExistingTarget: map['importIntoExistingTarget']! as bool,
      replaceExistingTarget: map['replaceExistingTarget']! as bool,
      encoding: map['encoding']! as String,
      tables: ((map['tables'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (table) => SqlDumpImportTableDraft.fromMap(
              table.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
    );
  }
}

class SqlDumpImportProgress {
  const SqlDumpImportProgress({
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

  factory SqlDumpImportProgress.fromMap(Map<String, Object?> map) {
    return SqlDumpImportProgress(
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

class SqlDumpImportSummary {
  const SqlDumpImportSummary({
    required this.jobId,
    required this.sourcePath,
    required this.targetPath,
    required this.importedTables,
    required this.rowsCopiedByTable,
    required this.skippedStatementCount,
    required this.warnings,
    required this.skippedStatements,
    required this.statusMessage,
    required this.rolledBack,
  });

  final String jobId;
  final String sourcePath;
  final String targetPath;
  final List<String> importedTables;
  final Map<String, int> rowsCopiedByTable;
  final int skippedStatementCount;
  final List<String> warnings;
  final List<SqlDumpImportSkippedStatement> skippedStatements;
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
      'skippedStatementCount': skippedStatementCount,
      'warnings': warnings,
      'skippedStatements': <Map<String, Object?>>[
        for (final statement in skippedStatements) statement.toMap(),
      ],
      'statusMessage': statusMessage,
      'rolledBack': rolledBack,
    };
  }

  factory SqlDumpImportSummary.fromMap(Map<String, Object?> map) {
    return SqlDumpImportSummary(
      jobId: map['jobId']! as String,
      sourcePath: map['sourcePath']! as String,
      targetPath: map['targetPath']! as String,
      importedTables: ((map['importedTables'] as List?) ?? const <Object?>[])
          .cast<String>(),
      rowsCopiedByTable:
          ((map['rowsCopiedByTable'] as Map?) ?? const <Object?, Object?>{})
              .map((key, value) => MapEntry(key as String, value as int)),
      skippedStatementCount: map['skippedStatementCount']! as int,
      warnings: ((map['warnings'] as List?) ?? const <Object?>[])
          .cast<String>(),
      skippedStatements:
          ((map['skippedStatements'] as List?) ?? const <Object?>[])
              .cast<Map<Object?, Object?>>()
              .map(
                (statement) => SqlDumpImportSkippedStatement.fromMap(
                  statement.map((key, value) => MapEntry(key as String, value)),
                ),
              )
              .toList(),
      statusMessage: map['statusMessage']! as String,
      rolledBack: map['rolledBack']! as bool,
    );
  }
}

class SqlDumpImportUpdate {
  const SqlDumpImportUpdate({
    required this.kind,
    required this.jobId,
    this.progress,
    this.summary,
    this.message,
  });

  final SqlDumpImportUpdateKind kind;
  final String jobId;
  final SqlDumpImportProgress? progress;
  final SqlDumpImportSummary? summary;
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

  factory SqlDumpImportUpdate.fromMap(Map<String, Object?> map) {
    return SqlDumpImportUpdate(
      kind: SqlDumpImportUpdateKind.values.byName(map['kind']! as String),
      jobId: map['jobId']! as String,
      progress: map['progress'] is Map<Object?, Object?>
          ? SqlDumpImportProgress.fromMap(
              (map['progress']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key as String, value),
              ),
            )
          : null,
      summary: map['summary'] is Map<Object?, Object?>
          ? SqlDumpImportSummary.fromMap(
              (map['summary']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key as String, value),
              ),
            )
          : null,
      message: map['message'] as String?,
    );
  }
}

class SqlDumpImportSession {
  const SqlDumpImportSession({
    required this.step,
    required this.phase,
    required this.sourcePath,
    required this.targetPath,
    required this.importIntoExistingTarget,
    required this.replaceExistingTarget,
    required this.encoding,
    required this.resolvedEncoding,
    required this.tables,
    required this.warnings,
    required this.skippedStatements,
    required this.totalStatements,
    this.focusedTable,
    this.progress,
    this.summary,
    this.error,
    this.jobId,
  });

  final SqlDumpImportWizardStep step;
  final SqlDumpImportJobPhase phase;
  final String sourcePath;
  final String targetPath;
  final bool importIntoExistingTarget;
  final bool replaceExistingTarget;
  final String encoding;
  final String resolvedEncoding;
  final List<SqlDumpImportTableDraft> tables;
  final List<String> warnings;
  final List<SqlDumpImportSkippedStatement> skippedStatements;
  final int totalStatements;
  final String? focusedTable;
  final SqlDumpImportProgress? progress;
  final SqlDumpImportSummary? summary;
  final String? error;
  final String? jobId;

  factory SqlDumpImportSession.initial({String sourcePath = ''}) {
    return SqlDumpImportSession(
      step: SqlDumpImportWizardStep.source,
      phase: SqlDumpImportJobPhase.idle,
      sourcePath: sourcePath,
      targetPath: '',
      importIntoExistingTarget: false,
      replaceExistingTarget: false,
      encoding: 'auto',
      resolvedEncoding: 'utf8',
      tables: const <SqlDumpImportTableDraft>[],
      warnings: const <String>[],
      skippedStatements: const <SqlDumpImportSkippedStatement>[],
      totalStatements: 0,
    );
  }

  List<SqlDumpImportTableDraft> get selectedTables =>
      tables.where((table) => table.selected).toList();

  int get skippedStatementCount => skippedStatements.length;

  SqlDumpImportTableDraft? get focusedTableDraft {
    if (focusedTable == null) {
      return tables.isEmpty ? null : tables.first;
    }
    for (final table in tables) {
      if (table.sourceName == focusedTable) {
        return table;
      }
    }
    return tables.isEmpty ? null : tables.first;
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

  SqlDumpImportSession copyWith({
    SqlDumpImportWizardStep? step,
    SqlDumpImportJobPhase? phase,
    String? sourcePath,
    String? targetPath,
    bool? importIntoExistingTarget,
    bool? replaceExistingTarget,
    String? encoding,
    String? resolvedEncoding,
    List<SqlDumpImportTableDraft>? tables,
    List<String>? warnings,
    List<SqlDumpImportSkippedStatement>? skippedStatements,
    int? totalStatements,
    Object? focusedTable = _unset,
    Object? progress = _unset,
    Object? summary = _unset,
    Object? error = _unset,
    Object? jobId = _unset,
  }) {
    return SqlDumpImportSession(
      step: step ?? this.step,
      phase: phase ?? this.phase,
      sourcePath: sourcePath ?? this.sourcePath,
      targetPath: targetPath ?? this.targetPath,
      importIntoExistingTarget:
          importIntoExistingTarget ?? this.importIntoExistingTarget,
      replaceExistingTarget:
          replaceExistingTarget ?? this.replaceExistingTarget,
      encoding: encoding ?? this.encoding,
      resolvedEncoding: resolvedEncoding ?? this.resolvedEncoding,
      tables: tables ?? this.tables,
      warnings: warnings ?? this.warnings,
      skippedStatements: skippedStatements ?? this.skippedStatements,
      totalStatements: totalStatements ?? this.totalStatements,
      focusedTable: focusedTable == _unset
          ? this.focusedTable
          : focusedTable as String?,
      progress: progress == _unset
          ? this.progress
          : progress as SqlDumpImportProgress?,
      summary: summary == _unset
          ? this.summary
          : summary as SqlDumpImportSummary?,
      error: error == _unset ? this.error : error as String?,
      jobId: jobId == _unset ? this.jobId : jobId as String?,
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

String formatSqlDumpImportCellValue(Object? value) {
  return formatCellValue(value);
}
