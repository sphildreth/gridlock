import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_support_paths.dart';
import '../../features/workspace/domain/app_config.dart';
import '../../features/workspace/infrastructure/decentdb_bridge.dart';

abstract class AppLogger {
  const AppLogger();

  String get logDatabasePath;

  Future<void> initialize({LogVerbosity? minimumLevel});

  void updateMinimumLevel(LogVerbosity minimumLevel);

  void log({
    required LogVerbosity level,
    required String category,
    required String message,
    String? operation,
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
    Object? error,
    StackTrace? stackTrace,
  });

  void debug({
    required String category,
    required String message,
    String? operation,
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
  }) {
    log(
      level: LogVerbosity.debug,
      category: category,
      message: message,
      operation: operation,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
    );
  }

  void info({
    required String category,
    required String message,
    String? operation,
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
  }) {
    log(
      level: LogVerbosity.information,
      category: category,
      message: message,
      operation: operation,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
    );
  }

  void warning({
    required String category,
    required String message,
    String? operation,
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      level: LogVerbosity.warning,
      category: category,
      message: message,
      operation: operation,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void error({
    required String category,
    required String message,
    String? operation,
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      level: LogVerbosity.error,
      category: category,
      message: message,
      operation: operation,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void logQueryTiming({
    required String databasePath,
    required String sql,
    required int rowCount,
    required int elapsedNanos,
    String operation = 'query.complete',
    int? rowsAffected,
    Map<String, Object?>? details,
  }) {
    info(
      category: 'query',
      operation: operation,
      message: 'SQL execution timing recorded.',
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
    );
  }

  Future<void> dispose();
}

class NoOpAppLogger extends AppLogger {
  const NoOpAppLogger();

  @override
  String get logDatabasePath => AppSupportPaths.resolveLogDatabasePath();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize({LogVerbosity? minimumLevel}) async {}

  @override
  void log({
    required LogVerbosity level,
    required String category,
    required String message,
    String? operation,
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
    Object? error,
    StackTrace? stackTrace,
  }) {}

  @override
  void updateMinimumLevel(LogVerbosity minimumLevel) {}
}

class DecentBenchLogger extends AppLogger {
  DecentBenchLogger({
    WorkspaceDatabaseGateway Function()? gatewayFactory,
    String? logDatabasePath,
  }) : _gatewayFactory = gatewayFactory ?? DecentDbBridge.new,
       _logDatabasePath =
           logDatabasePath ?? AppSupportPaths.resolveLogDatabasePath();

  final WorkspaceDatabaseGateway Function() _gatewayFactory;
  final String _logDatabasePath;

  WorkspaceDatabaseGateway? _gateway;
  Future<void>? _initialization;
  Future<void> _writeChain = Future<void>.value();
  LogVerbosity _minimumLevel = LogVerbosity.warning;

  @override
  String get logDatabasePath => _logDatabasePath;

  @override
  Future<void> initialize({LogVerbosity? minimumLevel}) async {
    if (minimumLevel != null) {
      _minimumLevel = minimumLevel;
    }
    final existing = _initialization;
    if (existing != null) {
      await existing;
      return;
    }

    final initialization = _initializeInternal();
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  @override
  void updateMinimumLevel(LogVerbosity minimumLevel) {
    _minimumLevel = minimumLevel;
  }

  @override
  void log({
    required LogVerbosity level,
    required String category,
    required String message,
    String? operation,
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.value < _minimumLevel.value) {
      return;
    }

    final mergedDetails = _normalizeDetails(
      details,
      error: error,
      stackTrace: stackTrace,
    );
    final entry = _LogEntry(
      loggedAtUtc: DateTime.now().toUtc(),
      level: level,
      category: category,
      message: message,
      operation: operation,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      detailsJson: mergedDetails == null ? null : jsonEncode(mergedDetails),
    );
    _enqueueWrite(entry);
    if (level.value >= LogVerbosity.warning.value) {
      final operationSuffix = operation == null ? '' : ' [$operation]';
      debugPrint(
        '[${level.label.toUpperCase()}][$category$operationSuffix] $message',
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _writeChain.catchError((_) {});
    final gateway = _gateway;
    _gateway = null;
    _initialization = null;
    if (gateway != null) {
      await gateway.dispose();
    }
  }

  Future<void> _initializeInternal() async {
    final file = File(_logDatabasePath);
    await file.parent.create(recursive: true);
    final gateway = _gatewayFactory();
    await gateway.initialize();
    await gateway.openDatabase(_logDatabasePath);
    await gateway.runQuery(
      sql: '''
CREATE TABLE IF NOT EXISTS app_logs (
  id INTEGER PRIMARY KEY,
  logged_at_utc TEXT NOT NULL,
  level_value INTEGER NOT NULL,
  level_name TEXT NOT NULL,
  category TEXT NOT NULL,
  operation TEXT,
  message TEXT NOT NULL,
  database_path TEXT,
  sql_text TEXT,
  row_count INTEGER,
  rows_affected INTEGER,
  elapsed_nanos INTEGER,
  details_json TEXT
);
''',
      params: const <Object?>[],
      pageSize: 1,
    );
    await gateway.runQuery(
      sql: '''
CREATE INDEX IF NOT EXISTS idx_app_logs_logged_at
ON app_logs(logged_at_utc DESC);
''',
      params: const <Object?>[],
      pageSize: 1,
    );
    _gateway = gateway;
    await _persistEntryWithGateway(
      gateway,
      _LogEntry(
        loggedAtUtc: DateTime.now().toUtc(),
        level: LogVerbosity.information,
        category: 'logging',
        operation: 'initialize',
        message: 'Application logging initialized.',
        detailsJson: jsonEncode(<String, Object?>{
          'log_database_path': _logDatabasePath,
          'minimum_level': _minimumLevel.name,
        }),
      ),
    );
  }

  void _enqueueWrite(_LogEntry entry) {
    _writeChain = _writeChain.then((_) => _writeEntry(entry)).catchError((
      error,
      stackTrace,
    ) {
      stderr.writeln('Failed to persist application log entry: $error');
      if (stackTrace != null) {
        stderr.writeln(stackTrace);
      }
    });
  }

  Future<void> _writeEntry(_LogEntry entry) async {
    try {
      await initialize();
      final gateway = _gateway;
      if (gateway == null) {
        return;
      }
      await _persistEntryWithGateway(gateway, entry);
    } catch (error, stackTrace) {
      stderr.writeln('Failed to write application log entry: $error');
      stderr.writeln(stackTrace);
    }
  }

  Future<void> _persistEntryWithGateway(
    WorkspaceDatabaseGateway gateway,
    _LogEntry entry,
  ) async {
    await gateway.runQuery(
      sql: '''
INSERT INTO app_logs (
  logged_at_utc,
  level_value,
  level_name,
  category,
  operation,
  message,
  database_path,
  sql_text,
  row_count,
  rows_affected,
  elapsed_nanos,
  details_json
) VALUES (
  \$1, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$9, \$10, \$11, \$12
);
''',
      params: <Object?>[
        entry.loggedAtUtc.toIso8601String(),
        entry.level.value,
        entry.level.label,
        entry.category,
        entry.operation,
        entry.message,
        entry.databasePath,
        entry.sql,
        entry.rowCount,
        entry.rowsAffected,
        entry.elapsedNanos,
        entry.detailsJson,
      ],
      pageSize: 1,
    );
  }

  Map<String, Object?>? _normalizeDetails(
    Map<String, Object?>? details, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final normalized = <String, Object?>{};
    if (details != null) {
      for (final entry in details.entries) {
        normalized[entry.key] = _normalizeDetailValue(entry.value);
      }
    }
    if (error != null) {
      normalized['error'] = error.toString();
    }
    if (stackTrace != null) {
      normalized['stack_trace'] = stackTrace.toString();
    }
    return normalized.isEmpty ? null : normalized;
  }

  Object? _normalizeDetailValue(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is List) {
      return value.map<Object?>((item) => _normalizeDetailValue(item)).toList();
    }
    if (value is Map) {
      return value.map<String, Object?>(
        (key, item) => MapEntry(key.toString(), _normalizeDetailValue(item)),
      );
    }
    return value.toString();
  }
}

class _LogEntry {
  const _LogEntry({
    required this.loggedAtUtc,
    required this.level,
    required this.category,
    required this.message,
    this.operation,
    this.databasePath,
    this.sql,
    this.rowCount,
    this.rowsAffected,
    this.elapsedNanos,
    this.detailsJson,
  });

  final DateTime loggedAtUtc;
  final LogVerbosity level;
  final String category;
  final String message;
  final String? operation;
  final String? databasePath;
  final String? sql;
  final int? rowCount;
  final int? rowsAffected;
  final int? elapsedNanos;
  final String? detailsJson;
}
