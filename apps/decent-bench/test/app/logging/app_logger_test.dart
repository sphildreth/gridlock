import 'package:decent_bench/app/logging/app_logger.dart';
import 'package:decent_bench/features/workspace/domain/app_config.dart';
import 'package:decent_bench/features/workspace/domain/excel_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sql_dump_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sqlite_import_models.dart';
import 'package:decent_bench/features/workspace/domain/workspace_models.dart';
import 'package:decent_bench/features/workspace/infrastructure/decentdb_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('logger initializes the log database schema', () async {
    final gateway = _FakeLogGateway();
    final logger = DecentBenchLogger(
      gatewayFactory: () => gateway,
      logDatabasePath: '/tmp/decent-bench-log-test.ddb',
    );
    addTearDown(logger.dispose);

    await logger.initialize();

    expect(gateway.openedPath, '/tmp/decent-bench-log-test.ddb');
    expect(
      gateway.executedSql.any(
        (sql) => sql.contains('CREATE TABLE IF NOT EXISTS app_logs'),
      ),
      isTrue,
    );
    expect(
      gateway.executedSql.any(
        (sql) =>
            sql.contains('CREATE INDEX IF NOT EXISTS idx_app_logs_logged_at'),
      ),
      isTrue,
    );
    expect(gateway.inserts, hasLength(1));
    expect(gateway.inserts.single.params[3], 'logging');
    expect(gateway.inserts.single.params[4], 'initialize');
  });

  test('logger respects the configured verbosity threshold', () async {
    final gateway = _FakeLogGateway();
    final logger = DecentBenchLogger(
      gatewayFactory: () => gateway,
      logDatabasePath: '/tmp/decent-bench-log-test.ddb',
    );
    addTearDown(logger.dispose);

    await logger.initialize(minimumLevel: LogVerbosity.warning);
    logger.info(category: 'workspace', operation: 'init', message: 'skip me');
    logger.error(category: 'workspace', operation: 'init', message: 'keep me');
    await logger.dispose();

    final inserted = gateway.inserts;
    expect(inserted, hasLength(2));
    expect(inserted.last.params[2], 'Errors');
    expect(inserted.last.params[5], 'keep me');
  });

  test('logger writes structured query timing records', () async {
    final gateway = _FakeLogGateway();
    final logger = DecentBenchLogger(
      gatewayFactory: () => gateway,
      logDatabasePath: '/tmp/decent-bench-log-test.ddb',
    );
    addTearDown(logger.dispose);

    await logger.initialize(minimumLevel: LogVerbosity.information);
    logger.logQueryTiming(
      databasePath: '/tmp/workbench.ddb',
      sql: 'SELECT * FROM tasks',
      rowCount: 42,
      elapsedNanos: 987654321,
      rowsAffected: 0,
      details: const <String, Object?>{'tab_id': 'query-tab-1'},
    );
    await logger.dispose();

    expect(gateway.inserts, hasLength(2));
    final inserted = gateway.inserts.last;
    expect(inserted.params[6], '/tmp/workbench.ddb');
    expect(inserted.params[7], 'SELECT * FROM tasks');
    expect(inserted.params[8], 42);
    expect(inserted.params[9], 0);
    expect(inserted.params[10], 987654321);
    expect((inserted.params[11] as String), contains('"tab_id":"query-tab-1"'));
  });
}

class _FakeLogGateway implements WorkspaceDatabaseGateway {
  final List<String> executedSql = <String>[];
  final List<_ExecutedInsert> inserts = <_ExecutedInsert>[];
  String? openedPath;

  @override
  String? get resolvedLibraryPath => '/tmp/libc_api.so';

  @override
  Future<void> cancelImport(String jobId) async {}

  @override
  Future<void> cancelQuery(String cursorId) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<CsvExportResult> exportCsv({
    required String sql,
    required List<Object?> params,
    required int pageSize,
    required String path,
    required String delimiter,
    required bool includeHeaders,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<QueryResultPage> fetchNextPage({
    required String cursorId,
    required int pageSize,
  }) async {
    throw UnimplementedError();
  }

  @override
  Stream<ExcelImportUpdate> importExcel({required ExcelImportRequest request}) {
    throw UnimplementedError();
  }

  @override
  Stream<SqlDumpImportUpdate> importSqlDump({
    required SqlDumpImportRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<SqliteImportUpdate> importSqlite({
    required SqliteImportRequest request,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> initialize() async => resolvedLibraryPath!;

  @override
  Future<ExcelImportInspection> inspectExcelSource({
    required String sourcePath,
    required bool headerRow,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SqlDumpImportInspection> inspectSqlDumpSource({
    required String sourcePath,
    required String encoding,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SqliteImportInspection> inspectSqliteSource({
    required String sourcePath,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<SchemaSnapshot> loadSchema() async {
    throw UnimplementedError();
  }

  @override
  Future<SqliteImportPreview> loadSqlitePreview({
    required String sourcePath,
    required String tableName,
    int limit = 8,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<DatabaseSession> openDatabase(String path) async {
    openedPath = path;
    return DatabaseSession(path: path, engineVersion: '1.6.1');
  }

  @override
  Future<QueryResultPage> runQuery({
    required String sql,
    required List<Object?> params,
    required int pageSize,
  }) async {
    executedSql.add(sql);
    if (sql.contains('INSERT INTO app_logs')) {
      inserts.add(
        _ExecutedInsert(sql: sql, params: List<Object?>.from(params)),
      );
    }
    return const QueryResultPage(
      cursorId: null,
      columns: <String>[],
      rows: <Map<String, Object?>>[],
      done: true,
      rowsAffected: 1,
      elapsed: Duration(milliseconds: 1),
    );
  }
}

class _ExecutedInsert {
  const _ExecutedInsert({required this.sql, required this.params});

  final String sql;
  final List<Object?> params;
}
