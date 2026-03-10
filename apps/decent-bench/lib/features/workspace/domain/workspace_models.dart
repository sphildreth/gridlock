import 'dart:convert';
import 'dart:typed_data';

enum QueryPhase {
  idle,
  opening,
  running,
  fetching,
  cancelling,
  completed,
  cancelled,
  failed,
}

enum QueryErrorStage { validation, opening, paging, cancellation, export }

enum QueryMessageLevel { info, warning, error }

enum QueryHistoryOutcome { completed, failed, cancelled }

enum SchemaObjectKind { table, view }

class BridgeFailure implements Exception {
  final String message;
  final String? code;

  const BridgeFailure(this.message, {this.code});

  @override
  String toString() => code == null ? message : '$code: $message';
}

class QueryErrorDetails {
  const QueryErrorDetails({
    required this.stage,
    required this.message,
    this.code,
  });

  final QueryErrorStage stage;
  final String message;
  final String? code;

  factory QueryErrorDetails.fromError(
    Object error, {
    required QueryErrorStage stage,
  }) {
    if (error is QueryErrorDetails) {
      return error;
    }
    if (error is BridgeFailure) {
      return QueryErrorDetails(
        stage: stage,
        message: error.message,
        code: error.code,
      );
    }
    return QueryErrorDetails(stage: stage, message: error.toString());
  }

  String get stageLabel {
    switch (stage) {
      case QueryErrorStage.validation:
        return 'Validation';
      case QueryErrorStage.opening:
        return 'Open';
      case QueryErrorStage.paging:
        return 'Paging';
      case QueryErrorStage.cancellation:
        return 'Cancellation';
      case QueryErrorStage.export:
        return 'Export';
    }
  }

  String toClipboardText({String? sql}) {
    final buffer = StringBuffer()
      ..writeln('Stage: $stageLabel')
      ..writeln('Message: $message');
    if (code != null) {
      buffer.writeln('Code: $code');
    }
    if (sql != null && sql.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('SQL:')
        ..writeln(sql.trim());
    }
    return buffer.toString().trimRight();
  }
}

class DatabaseSession {
  const DatabaseSession({required this.path, required this.engineVersion});

  final String path;
  final String engineVersion;

  factory DatabaseSession.fromMap(Map<String, Object?> map) {
    return DatabaseSession(
      path: map['path']! as String,
      engineVersion: map['engineVersion']! as String,
    );
  }
}

class SchemaColumn {
  const SchemaColumn({
    required this.name,
    required this.type,
    required this.notNull,
    required this.unique,
    required this.primaryKey,
    required this.refTable,
    required this.refColumn,
    required this.refOnDelete,
    required this.refOnUpdate,
  });

  final String name;
  final String type;
  final bool notNull;
  final bool unique;
  final bool primaryKey;
  final String? refTable;
  final String? refColumn;
  final String? refOnDelete;
  final String? refOnUpdate;

  factory SchemaColumn.fromMap(Map<String, Object?> map) {
    return SchemaColumn(
      name: map['name']! as String,
      type: map['type']! as String,
      notNull: map['notNull']! as bool,
      unique: map['unique']! as bool,
      primaryKey: map['primaryKey']! as bool,
      refTable: map['refTable'] as String?,
      refColumn: map['refColumn'] as String?,
      refOnDelete: map['refOnDelete'] as String?,
      refOnUpdate: map['refOnUpdate'] as String?,
    );
  }

  bool get hasForeignKey => refTable != null && refColumn != null;

  List<String> get constraintSummaries {
    return <String>[
      if (primaryKey) 'PRIMARY KEY',
      if (unique) 'UNIQUE',
      if (notNull) 'NOT NULL',
      if (hasForeignKey)
        'REFERENCES $refTable($refColumn)'
            '${refOnDelete != null ? ' ON DELETE $refOnDelete' : ''}'
            '${refOnUpdate != null ? ' ON UPDATE $refOnUpdate' : ''}',
    ];
  }

  String get descriptor {
    final flags = constraintSummaries;
    return flags.isEmpty ? type : '$type | ${flags.join(" | ")}';
  }
}

class SchemaObjectSummary {
  const SchemaObjectSummary({
    required this.name,
    required this.kind,
    required this.columns,
    this.ddl,
  });

  final String name;
  final SchemaObjectKind kind;
  final String? ddl;
  final List<SchemaColumn> columns;

  factory SchemaObjectSummary.fromMap(Map<String, Object?> map) {
    return SchemaObjectSummary(
      name: map['name']! as String,
      kind: (map['kind'] as String) == 'view'
          ? SchemaObjectKind.view
          : SchemaObjectKind.table,
      ddl: map['ddl'] as String?,
      columns: ((map['columns'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (column) => SchemaColumn.fromMap(
              column.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
    );
  }

  List<String> get exposedConstraintSummaries {
    return <String>[
      for (final column in columns)
        for (final constraint in column.constraintSummaries)
          '${column.name}: $constraint',
    ];
  }
}

class IndexSummary {
  const IndexSummary({
    required this.name,
    required this.table,
    required this.columns,
    required this.unique,
    required this.kind,
  });

  final String name;
  final String table;
  final List<String> columns;
  final bool unique;
  final String kind;

  factory IndexSummary.fromMap(Map<String, Object?> map) {
    return IndexSummary(
      name: map['name']! as String,
      table: map['table']! as String,
      columns: ((map['columns'] as List?) ?? const <Object?>[]).cast<String>(),
      unique: map['unique']! as bool,
      kind: map['kind']! as String,
    );
  }
}

class SchemaSnapshot {
  const SchemaSnapshot({
    required this.objects,
    required this.indexes,
    required this.loadedAt,
  });

  final List<SchemaObjectSummary> objects;
  final List<IndexSummary> indexes;
  final DateTime loadedAt;

  factory SchemaSnapshot.empty() {
    return SchemaSnapshot(
      objects: const <SchemaObjectSummary>[],
      indexes: const <IndexSummary>[],
      loadedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  factory SchemaSnapshot.fromMap(Map<String, Object?> map) {
    return SchemaSnapshot(
      objects: ((map['objects'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (item) => SchemaObjectSummary.fromMap(
              item.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      indexes: ((map['indexes'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (item) => IndexSummary.fromMap(
              item.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      loadedAt: DateTime.parse(map['loadedAt']! as String),
    );
  }

  List<SchemaObjectSummary> get tables =>
      objects.where((item) => item.kind == SchemaObjectKind.table).toList();

  List<SchemaObjectSummary> get views =>
      objects.where((item) => item.kind == SchemaObjectKind.view).toList();

  SchemaObjectSummary? objectNamed(String name) {
    for (final object in objects) {
      if (object.name == name) {
        return object;
      }
    }
    return null;
  }

  List<IndexSummary> indexesForObject(String objectName) {
    return indexes.where((index) => index.table == objectName).toList();
  }
}

class QueryResultPage {
  const QueryResultPage({
    required this.cursorId,
    required this.columns,
    required this.rows,
    required this.done,
    required this.rowsAffected,
    required this.elapsed,
  });

  final String? cursorId;
  final List<String> columns;
  final List<Map<String, Object?>> rows;
  final bool done;
  final int? rowsAffected;
  final Duration elapsed;

  factory QueryResultPage.fromMap(Map<String, Object?> map) {
    return QueryResultPage(
      cursorId: map['cursorId'] as String?,
      columns: ((map['columns'] as List?) ?? const <Object?>[]).cast<String>(),
      rows: ((map['rows'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (row) => row.map(
              (key, value) => MapEntry(key as String, _decodeCell(value)),
            ),
          )
          .toList(),
      done: map['done']! as bool,
      rowsAffected: map['rowsAffected'] as int?,
      elapsed: Duration(microseconds: map['elapsedMicros']! as int),
    );
  }

  static Object? _decodeCell(Object? value) {
    if (value is Map && value['kind'] == 'decimal') {
      final unscaled = value['unscaled'] as int;
      final scale = value['scale'] as int;
      return formatDecimalValue(unscaled, scale);
    }
    if (value is Map && value['kind'] == 'blob') {
      return base64Decode(value['base64']! as String);
    }
    if (value is Map && value['kind'] == 'datetime') {
      return DateTime.parse(value['iso8601']! as String);
    }
    return value;
  }
}

class CsvExportResult {
  const CsvExportResult({required this.rowCount, required this.path});

  final int rowCount;
  final String path;

  factory CsvExportResult.fromMap(Map<String, Object?> map) {
    return CsvExportResult(
      rowCount: map['rowCount']! as int,
      path: map['path']! as String,
    );
  }
}

class QueryMessageEntry {
  const QueryMessageEntry({
    required this.level,
    required this.message,
    required this.timestamp,
  });

  final QueryMessageLevel level;
  final String message;
  final DateTime timestamp;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'level': level.name,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory QueryMessageEntry.fromJson(Map<String, Object?> map) {
    return QueryMessageEntry(
      level: switch (map['level'] as String? ?? 'info') {
        'warning' => QueryMessageLevel.warning,
        'error' => QueryMessageLevel.error,
        _ => QueryMessageLevel.info,
      },
      message: map['message'] as String? ?? '',
      timestamp: DateTime.parse(
        map['timestamp'] as String? ??
            DateTime.fromMillisecondsSinceEpoch(0).toIso8601String(),
      ),
    );
  }
}

class QueryHistoryEntry {
  const QueryHistoryEntry({
    required this.sql,
    required this.parameterJson,
    required this.ranAt,
    required this.outcome,
    required this.elapsed,
    required this.rowsLoaded,
    required this.rowsAffected,
    this.errorMessage,
  });

  final String sql;
  final String parameterJson;
  final DateTime ranAt;
  final QueryHistoryOutcome outcome;
  final Duration elapsed;
  final int? rowsLoaded;
  final int? rowsAffected;
  final String? errorMessage;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sql': sql,
      'parameterJson': parameterJson,
      'ranAt': ranAt.toIso8601String(),
      'outcome': outcome.name,
      'elapsedMs': elapsed.inMilliseconds,
      'rowsLoaded': rowsLoaded,
      'rowsAffected': rowsAffected,
      'errorMessage': errorMessage,
    };
  }

  factory QueryHistoryEntry.fromJson(Map<String, Object?> map) {
    return QueryHistoryEntry(
      sql: map['sql']! as String,
      parameterJson: map['parameterJson'] as String? ?? '',
      ranAt: DateTime.parse(map['ranAt']! as String),
      outcome: switch (map['outcome'] as String? ?? 'completed') {
        'failed' => QueryHistoryOutcome.failed,
        'cancelled' => QueryHistoryOutcome.cancelled,
        _ => QueryHistoryOutcome.completed,
      },
      elapsed: Duration(milliseconds: map['elapsedMs'] as int? ?? 0),
      rowsLoaded: map['rowsLoaded'] as int?,
      rowsAffected: map['rowsAffected'] as int?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}

class QueryTabState {
  const QueryTabState({
    required this.id,
    required this.title,
    required this.sql,
    required this.parameterJson,
    required this.exportPath,
    required this.phase,
    required this.resultColumns,
    required this.resultRows,
    required this.cursorId,
    required this.error,
    required this.statusMessage,
    required this.lastSql,
    required this.lastParameterJson,
    required this.lastParams,
    required this.lastRunStartedAt,
    required this.rowsAffected,
    required this.elapsed,
    required this.hasMoreRows,
    required this.isExporting,
    required this.isResultPartial,
    required this.executionGeneration,
    required this.messageHistory,
    required this.queryHistory,
  });

  static const Object _unset = Object();

  final String id;
  final String title;
  final String sql;
  final String parameterJson;
  final String exportPath;
  final QueryPhase phase;
  final List<String> resultColumns;
  final List<Map<String, Object?>> resultRows;
  final String? cursorId;
  final QueryErrorDetails? error;
  final String? statusMessage;
  final String? lastSql;
  final String? lastParameterJson;
  final List<Object?> lastParams;
  final DateTime? lastRunStartedAt;
  final int? rowsAffected;
  final Duration? elapsed;
  final bool hasMoreRows;
  final bool isExporting;
  final bool isResultPartial;
  final int executionGeneration;
  final List<QueryMessageEntry> messageHistory;
  final List<QueryHistoryEntry> queryHistory;

  factory QueryTabState.initial({
    required String id,
    required String title,
    String sql = 'SELECT 1 AS ready;',
    String parameterJson = '',
    String exportPath = '',
  }) {
    return QueryTabState(
      id: id,
      title: title,
      sql: sql,
      parameterJson: parameterJson,
      exportPath: exportPath,
      phase: QueryPhase.idle,
      resultColumns: const <String>[],
      resultRows: const <Map<String, Object?>>[],
      cursorId: null,
      error: null,
      statusMessage: null,
      lastSql: null,
      lastParameterJson: null,
      lastParams: const <Object?>[],
      lastRunStartedAt: null,
      rowsAffected: null,
      elapsed: null,
      hasMoreRows: false,
      isExporting: false,
      isResultPartial: false,
      executionGeneration: 0,
      messageHistory: const <QueryMessageEntry>[],
      queryHistory: const <QueryHistoryEntry>[],
    );
  }

  bool get canCancel =>
      phase == QueryPhase.opening ||
      phase == QueryPhase.running ||
      phase == QueryPhase.fetching ||
      phase == QueryPhase.cancelling;

  bool get canExport =>
      lastSql != null && resultColumns.isNotEmpty && !isExporting;

  bool get hasResultData => resultColumns.isNotEmpty || rowsAffected != null;

  QueryTabState copyWith({
    String? id,
    String? title,
    String? sql,
    String? parameterJson,
    String? exportPath,
    QueryPhase? phase,
    List<String>? resultColumns,
    List<Map<String, Object?>>? resultRows,
    Object? cursorId = _unset,
    Object? error = _unset,
    Object? statusMessage = _unset,
    Object? lastSql = _unset,
    Object? lastParameterJson = _unset,
    List<Object?>? lastParams,
    Object? lastRunStartedAt = _unset,
    Object? rowsAffected = _unset,
    Object? elapsed = _unset,
    bool? hasMoreRows,
    bool? isExporting,
    bool? isResultPartial,
    int? executionGeneration,
    List<QueryMessageEntry>? messageHistory,
    List<QueryHistoryEntry>? queryHistory,
  }) {
    return QueryTabState(
      id: id ?? this.id,
      title: title ?? this.title,
      sql: sql ?? this.sql,
      parameterJson: parameterJson ?? this.parameterJson,
      exportPath: exportPath ?? this.exportPath,
      phase: phase ?? this.phase,
      resultColumns: resultColumns ?? this.resultColumns,
      resultRows: resultRows ?? this.resultRows,
      cursorId: cursorId == _unset ? this.cursorId : cursorId as String?,
      error: error == _unset ? this.error : error as QueryErrorDetails?,
      statusMessage: statusMessage == _unset
          ? this.statusMessage
          : statusMessage as String?,
      lastSql: lastSql == _unset ? this.lastSql : lastSql as String?,
      lastParameterJson: lastParameterJson == _unset
          ? this.lastParameterJson
          : lastParameterJson as String?,
      lastParams: lastParams ?? this.lastParams,
      lastRunStartedAt: lastRunStartedAt == _unset
          ? this.lastRunStartedAt
          : lastRunStartedAt as DateTime?,
      rowsAffected: rowsAffected == _unset
          ? this.rowsAffected
          : rowsAffected as int?,
      elapsed: elapsed == _unset ? this.elapsed : elapsed as Duration?,
      hasMoreRows: hasMoreRows ?? this.hasMoreRows,
      isExporting: isExporting ?? this.isExporting,
      isResultPartial: isResultPartial ?? this.isResultPartial,
      executionGeneration: executionGeneration ?? this.executionGeneration,
      messageHistory: messageHistory ?? this.messageHistory,
      queryHistory: queryHistory ?? this.queryHistory,
    );
  }
}

String formatCellValue(Object? value) {
  if (value == null) {
    return 'NULL';
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is Uint8List) {
    return base64Encode(value);
  }
  return '$value';
}

String formatDecimalValue(int unscaled, int scale) {
  if (scale == 0) {
    return '$unscaled';
  }

  final negative = unscaled < 0;
  final digits = unscaled.abs().toString().padLeft(scale + 1, '0');
  final split = digits.length - scale;
  final whole = digits.substring(0, split);
  final fraction = digits.substring(split);
  return '${negative ? "-" : ""}$whole.$fraction';
}
