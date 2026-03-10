import 'dart:async';
import 'dart:io';

import 'package:decent_bench/features/workspace/domain/app_config.dart';
import 'package:decent_bench/features/workspace/domain/excel_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sqlite_import_models.dart';
import 'package:decent_bench/features/workspace/domain/workspace_models.dart';
import 'package:decent_bench/features/workspace/domain/workspace_state.dart';
import 'package:decent_bench/features/workspace/infrastructure/app_config_store.dart';
import 'package:decent_bench/features/workspace/infrastructure/decentdb_bridge.dart';
import 'package:decent_bench/features/workspace/infrastructure/workspace_state_store.dart';

class InMemoryConfigStore implements WorkspaceConfigStore {
  InMemoryConfigStore([AppConfig? config])
    : _config = config ?? AppConfig.defaults();

  AppConfig _config;

  @override
  Future<AppConfig> load() async => _config;

  @override
  Future<void> save(AppConfig config) async {
    _config = config;
  }
}

class InMemoryWorkspaceStateStore implements WorkspaceStateStore {
  final Map<String, PersistedWorkspaceState> _states =
      <String, PersistedWorkspaceState>{};

  @override
  Future<void> clear(String databasePath) async {
    _states.remove(databasePath);
  }

  @override
  Future<PersistedWorkspaceState?> load(String databasePath) async {
    return _states[databasePath];
  }

  @override
  Future<void> save(String databasePath, PersistedWorkspaceState state) async {
    _states[databasePath] = state;
  }
}

class FakeWorkspaceGateway implements WorkspaceDatabaseGateway {
  FakeWorkspaceGateway({
    ExcelImportInspection? excelInspection,
    SqliteImportInspection? sqliteInspection,
    Map<String, SqliteImportPreview>? sqlitePreviews,
  }) : excelInspection =
           excelInspection ?? _defaultExcelInspection('/tmp/source.xlsx'),
       sqliteInspection =
           sqliteInspection ?? _defaultSqliteInspection('/tmp/source.sqlite'),
       sqlitePreviews = sqlitePreviews ?? _defaultSqlitePreviews();

  @override
  String? resolvedLibraryPath = '/tmp/libc_api.so';

  int cancelCount = 0;
  String? lastExportPath;
  ExcelImportInspection excelInspection;
  SqliteImportInspection sqliteInspection;
  Map<String, SqliteImportPreview> sqlitePreviews;
  ExcelImportRequest? lastExcelImportRequest;
  SqliteImportRequest? lastSqliteImportRequest;
  String? lastCancelledImportJobId;
  bool holdImportOpen = false;
  bool failNextImport = false;
  bool holdExcelImportOpen = false;
  bool failNextExcelImport = false;
  StreamController<ExcelImportUpdate>? _excelImportController;
  StreamController<SqliteImportUpdate>? _importController;

  SchemaSnapshot snapshot = SchemaSnapshot(
    objects: <SchemaObjectSummary>[
      SchemaObjectSummary(
        name: 'tasks',
        kind: SchemaObjectKind.table,
        columns: const <SchemaColumn>[
          SchemaColumn(
            name: 'id',
            type: 'INTEGER',
            notNull: true,
            unique: true,
            primaryKey: true,
            refTable: null,
            refColumn: null,
            refOnDelete: null,
            refOnUpdate: null,
          ),
          SchemaColumn(
            name: 'title',
            type: 'TEXT',
            notNull: false,
            unique: false,
            primaryKey: false,
            refTable: null,
            refColumn: null,
            refOnDelete: null,
            refOnUpdate: null,
          ),
        ],
      ),
      SchemaObjectSummary(
        name: 'active_tasks',
        kind: SchemaObjectKind.view,
        ddl: 'CREATE VIEW active_tasks AS SELECT id, title FROM tasks;',
        columns: const <SchemaColumn>[
          SchemaColumn(
            name: 'id',
            type: 'ANY',
            notNull: false,
            unique: false,
            primaryKey: false,
            refTable: null,
            refColumn: null,
            refOnDelete: null,
            refOnUpdate: null,
          ),
          SchemaColumn(
            name: 'title',
            type: 'ANY',
            notNull: false,
            unique: false,
            primaryKey: false,
            refTable: null,
            refColumn: null,
            refOnDelete: null,
            refOnUpdate: null,
          ),
        ],
      ),
    ],
    indexes: const <IndexSummary>[
      IndexSummary(
        name: 'idx_tasks_title',
        table: 'tasks',
        columns: <String>['title'],
        unique: false,
        kind: 'btree',
      ),
    ],
    loadedAt: DateTime(2026, 3, 9),
  );

  @override
  Future<void> cancelQuery(String cursorId) async {
    cancelCount++;
  }

  @override
  Future<void> cancelImport(String jobId) async {
    lastCancelledImportJobId = jobId;
    final excelController = _excelImportController;
    if (excelController != null && !excelController.isClosed) {
      excelController.add(
        ExcelImportUpdate(
          kind: ExcelImportUpdateKind.cancelled,
          jobId: jobId,
          summary: _buildCancelledExcelSummary(jobId),
        ),
      );
      await excelController.close();
      _excelImportController = null;
      return;
    }
    final controller = _importController;
    if (controller == null || controller.isClosed) {
      return;
    }
    controller.add(
      SqliteImportUpdate(
        kind: SqliteImportUpdateKind.cancelled,
        jobId: jobId,
        summary: _buildCancelledSummary(jobId),
      ),
    );
    await controller.close();
    _importController = null;
  }

  @override
  Future<void> dispose() async {
    await _excelImportController?.close();
    _excelImportController = null;
    await _importController?.close();
    _importController = null;
  }

  @override
  Future<CsvExportResult> exportCsv({
    required String sql,
    required List<Object?> params,
    required int pageSize,
    required String path,
    required String delimiter,
    required bool includeHeaders,
  }) async {
    lastExportPath = path;
    return CsvExportResult(rowCount: 2, path: path);
  }

  @override
  Future<QueryResultPage> fetchNextPage({
    required String cursorId,
    required int pageSize,
  }) async {
    return switch (cursorId) {
      'cursor-projects' => QueryResultPage(
        cursorId: null,
        columns: const <String>['id', 'name'],
        rows: const <Map<String, Object?>>[
          <String, Object?>{'id': 11, 'name': 'Keep testing'},
        ],
        done: true,
        rowsAffected: null,
        elapsed: const Duration(milliseconds: 4),
      ),
      _ => QueryResultPage(
        cursorId: null,
        columns: const <String>['id', 'title'],
        rows: const <Map<String, Object?>>[
          <String, Object?>{'id': 2, 'title': 'Keep paging'},
        ],
        done: true,
        rowsAffected: null,
        elapsed: const Duration(milliseconds: 4),
      ),
    };
  }

  @override
  Future<String> initialize() async => resolvedLibraryPath!;

  @override
  Stream<ExcelImportUpdate> importExcel({
    required ExcelImportRequest request,
  }) async* {
    lastExcelImportRequest = request;
    if (holdExcelImportOpen) {
      final controller = StreamController<ExcelImportUpdate>();
      _excelImportController = controller;
      Future<void>.microtask(() {
        if (controller.isClosed) {
          return;
        }
        controller.add(
          ExcelImportUpdate(
            kind: ExcelImportUpdateKind.progress,
            jobId: request.jobId,
            progress: ExcelImportProgress(
              jobId: request.jobId,
              currentSheet: request.selectedSheets.first.targetName,
              completedSheets: 0,
              totalSheets: request.selectedSheets.length,
              currentSheetRowsCopied: 0,
              currentSheetRowCount: request.selectedSheets.first.rowCount,
              totalRowsCopied: 0,
              message: 'Preparing Excel import...',
            ),
          ),
        );
      });
      yield* controller.stream;
      return;
    }

    yield ExcelImportUpdate(
      kind: ExcelImportUpdateKind.progress,
      jobId: request.jobId,
      progress: ExcelImportProgress(
        jobId: request.jobId,
        currentSheet: request.selectedSheets.first.targetName,
        completedSheets: 0,
        totalSheets: request.selectedSheets.length,
        currentSheetRowsCopied: request.selectedSheets.first.rowCount,
        currentSheetRowCount: request.selectedSheets.first.rowCount,
        totalRowsCopied: request.selectedSheets.first.rowCount,
        message: 'Copying ${request.selectedSheets.first.targetName}...',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    if (failNextExcelImport) {
      failNextExcelImport = false;
      yield ExcelImportUpdate(
        kind: ExcelImportUpdateKind.failed,
        jobId: request.jobId,
        message: 'Excel import failed in the fake gateway.',
      );
      return;
    }

    final targetFile = File(request.targetPath);
    await targetFile.parent.create(recursive: true);
    if (!await targetFile.exists()) {
      await targetFile.writeAsString('');
    }

    yield ExcelImportUpdate(
      kind: ExcelImportUpdateKind.completed,
      jobId: request.jobId,
      summary: _buildCompletedExcelSummary(request),
    );
  }

  @override
  Stream<SqliteImportUpdate> importSqlite({
    required SqliteImportRequest request,
  }) async* {
    lastSqliteImportRequest = request;
    if (holdImportOpen) {
      final controller = StreamController<SqliteImportUpdate>();
      _importController = controller;
      Future<void>.microtask(() {
        if (controller.isClosed) {
          return;
        }
        controller.add(
          SqliteImportUpdate(
            kind: SqliteImportUpdateKind.progress,
            jobId: request.jobId,
            progress: SqliteImportProgress(
              jobId: request.jobId,
              currentTable: request.selectedTables.first.targetName,
              completedTables: 0,
              totalTables: request.selectedTables.length,
              currentTableRowsCopied: 0,
              currentTableRowCount: request.selectedTables.first.rowCount,
              totalRowsCopied: 0,
              message: 'Preparing SQLite import...',
            ),
          ),
        );
      });
      yield* controller.stream;
      return;
    }

    yield SqliteImportUpdate(
      kind: SqliteImportUpdateKind.progress,
      jobId: request.jobId,
      progress: SqliteImportProgress(
        jobId: request.jobId,
        currentTable: request.selectedTables.first.targetName,
        completedTables: 0,
        totalTables: request.selectedTables.length,
        currentTableRowsCopied: request.selectedTables.first.rowCount,
        currentTableRowCount: request.selectedTables.first.rowCount,
        totalRowsCopied: request.selectedTables.first.rowCount,
        message: 'Copying ${request.selectedTables.first.targetName}...',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    if (failNextImport) {
      failNextImport = false;
      yield SqliteImportUpdate(
        kind: SqliteImportUpdateKind.failed,
        jobId: request.jobId,
        message: 'SQLite import failed in the fake gateway.',
      );
      return;
    }

    final targetFile = File(request.targetPath);
    await targetFile.parent.create(recursive: true);
    if (!await targetFile.exists()) {
      await targetFile.writeAsString('');
    }

    yield SqliteImportUpdate(
      kind: SqliteImportUpdateKind.completed,
      jobId: request.jobId,
      summary: _buildCompletedSummary(request),
    );
  }

  @override
  Future<ExcelImportInspection> inspectExcelSource({
    required String sourcePath,
    required bool headerRow,
  }) async {
    return ExcelImportInspection(
      sourcePath: sourcePath,
      headerRow: headerRow,
      sheets: excelInspection.sheets,
      warnings: excelInspection.warnings,
    );
  }

  @override
  Future<SqliteImportInspection> inspectSqliteSource({
    required String sourcePath,
  }) async {
    return SqliteImportInspection(
      sourcePath: sourcePath,
      tables: sqliteInspection.tables,
      warnings: sqliteInspection.warnings,
    );
  }

  @override
  Future<SchemaSnapshot> loadSchema() async => snapshot;

  @override
  Future<SqliteImportPreview> loadSqlitePreview({
    required String sourcePath,
    required String tableName,
    int limit = 8,
  }) async {
    return sqlitePreviews[tableName] ??
        SqliteImportPreview(
          tableName: tableName,
          rows: const <Map<String, Object?>>[],
        );
  }

  @override
  Future<DatabaseSession> openDatabase(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      await file.parent.create(recursive: true);
      await file.writeAsString('');
    }
    return DatabaseSession(path: path, engineVersion: '1.6.1');
  }

  @override
  Future<QueryResultPage> runQuery({
    required String sql,
    required List<Object?> params,
    required int pageSize,
  }) async {
    if (sql.toUpperCase().contains('BROKEN')) {
      throw const BridgeFailure('syntax error near BROKEN', code: 'ERR_SQL');
    }
    if (sql.toUpperCase().startsWith('CREATE')) {
      return QueryResultPage(
        cursorId: null,
        columns: const <String>[],
        rows: const <Map<String, Object?>>[],
        done: true,
        rowsAffected: 0,
        elapsed: const Duration(milliseconds: 2),
      );
    }
    if (sql.toLowerCase().contains('projects')) {
      return QueryResultPage(
        cursorId: 'cursor-projects',
        columns: const <String>['id', 'name'],
        rows: const <Map<String, Object?>>[
          <String, Object?>{'id': 10, 'name': 'Phase 3'},
        ],
        done: false,
        rowsAffected: null,
        elapsed: const Duration(milliseconds: 5),
      );
    }
    return QueryResultPage(
      cursorId: 'cursor-1',
      columns: const <String>['id', 'title'],
      rows: const <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'title': 'Ship phase 1'},
      ],
      done: false,
      rowsAffected: null,
      elapsed: const Duration(milliseconds: 5),
    );
  }

  SqliteImportSummary _buildCompletedSummary(SqliteImportRequest request) {
    return SqliteImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: request.selectedTables
          .map((table) => table.targetName)
          .toList(),
      rowsCopiedByTable: <String, int>{
        for (final table in request.selectedTables)
          table.targetName: table.rowCount,
      },
      indexesCreated: <String>[
        for (final table in request.selectedTables)
          for (final index in table.indexes) index.name,
      ],
      skippedItems: <SqliteImportSkippedItem>[
        for (final table in request.selectedTables) ...table.skippedItems,
      ],
      warnings: sqliteInspection.warnings,
      statusMessage:
          'Imported ${request.selectedTables.fold<int>(0, (sum, table) => sum + table.rowCount)} rows from ${request.selectedTables.length} SQLite table${request.selectedTables.length == 1 ? '' : 's'}.',
      rolledBack: false,
    );
  }

  SqliteImportSummary _buildCancelledSummary(String jobId) {
    final request = lastSqliteImportRequest;
    if (request == null) {
      return SqliteImportSummary(
        jobId: jobId,
        sourcePath: sqliteInspection.sourcePath,
        targetPath: '/tmp/import-cancelled.ddb',
        importedTables: const <String>[],
        rowsCopiedByTable: const <String, int>{},
        indexesCreated: const <String>[],
        skippedItems: const <SqliteImportSkippedItem>[],
        warnings: const <String>[],
        statusMessage: 'SQLite import cancelled and rolled back.',
        rolledBack: true,
      );
    }
    return SqliteImportSummary(
      jobId: jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: const <String>[],
      rowsCopiedByTable: const <String, int>{},
      indexesCreated: const <String>[],
      skippedItems: const <SqliteImportSkippedItem>[],
      warnings: sqliteInspection.warnings,
      statusMessage: 'SQLite import cancelled and rolled back.',
      rolledBack: true,
    );
  }

  ExcelImportSummary _buildCompletedExcelSummary(ExcelImportRequest request) {
    return ExcelImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: request.selectedSheets
          .map((sheet) => sheet.targetName)
          .toList(),
      rowsCopiedByTable: <String, int>{
        for (final sheet in request.selectedSheets)
          sheet.targetName: sheet.rowCount,
      },
      warnings: excelInspection.warnings,
      statusMessage:
          'Imported ${request.selectedSheets.fold<int>(0, (sum, sheet) => sum + sheet.rowCount)} rows from ${request.selectedSheets.length} workbook sheet${request.selectedSheets.length == 1 ? '' : 's'}.',
      rolledBack: false,
    );
  }

  ExcelImportSummary _buildCancelledExcelSummary(String jobId) {
    final request = lastExcelImportRequest;
    if (request == null) {
      return ExcelImportSummary(
        jobId: jobId,
        sourcePath: excelInspection.sourcePath,
        targetPath: '/tmp/excel-import-cancelled.ddb',
        importedTables: const <String>[],
        rowsCopiedByTable: const <String, int>{},
        warnings: const <String>[],
        statusMessage: 'Excel import cancelled and rolled back.',
        rolledBack: true,
      );
    }
    return ExcelImportSummary(
      jobId: jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: const <String>[],
      rowsCopiedByTable: const <String, int>{},
      warnings: excelInspection.warnings,
      statusMessage: 'Excel import cancelled and rolled back.',
      rolledBack: true,
    );
  }
}

ExcelImportInspection _defaultExcelInspection(String sourcePath) {
  return ExcelImportInspection(
    sourcePath: sourcePath,
    headerRow: true,
    warnings: const <String>['Workbook formulas are imported as formula text.'],
    sheets: const <ExcelImportSheetDraft>[
      ExcelImportSheetDraft(
        sourceName: 'people',
        targetName: 'people',
        selected: true,
        rowCount: 2,
        columns: <ExcelImportColumnDraft>[
          ExcelImportColumnDraft(
            sourceIndex: 0,
            sourceName: 'id',
            targetName: 'id',
            inferredTargetType: 'INTEGER',
            targetType: 'INTEGER',
            containsNulls: false,
          ),
          ExcelImportColumnDraft(
            sourceIndex: 1,
            sourceName: 'name',
            targetName: 'name',
            inferredTargetType: 'TEXT',
            targetType: 'TEXT',
            containsNulls: false,
          ),
          ExcelImportColumnDraft(
            sourceIndex: 2,
            sourceName: 'active',
            targetName: 'active',
            inferredTargetType: 'BOOLEAN',
            targetType: 'BOOLEAN',
            containsNulls: false,
          ),
        ],
        previewRows: <Map<String, Object?>>[
          <String, Object?>{'id': 1, 'name': 'Ada', 'active': true},
          <String, Object?>{'id': 2, 'name': 'Grace', 'active': false},
        ],
      ),
      ExcelImportSheetDraft(
        sourceName: 'metrics',
        targetName: 'metrics',
        selected: true,
        rowCount: 2,
        columns: <ExcelImportColumnDraft>[
          ExcelImportColumnDraft(
            sourceIndex: 0,
            sourceName: 'quarter',
            targetName: 'quarter',
            inferredTargetType: 'TEXT',
            targetType: 'TEXT',
            containsNulls: false,
          ),
          ExcelImportColumnDraft(
            sourceIndex: 1,
            sourceName: 'revenue',
            targetName: 'revenue',
            inferredTargetType: 'FLOAT64',
            targetType: 'FLOAT64',
            containsNulls: false,
          ),
        ],
        previewRows: <Map<String, Object?>>[
          <String, Object?>{'quarter': 'Q1', 'revenue': 1200.5},
          <String, Object?>{'quarter': 'Q2', 'revenue': 1800.25},
        ],
      ),
    ],
  );
}

SqliteImportInspection _defaultSqliteInspection(String sourcePath) {
  return SqliteImportInspection(
    sourcePath: sourcePath,
    warnings: const <String>[
      'audit_log uses WITHOUT ROWID in SQLite; Decent Bench preserves data and keys but not WITHOUT ROWID storage semantics.',
    ],
    tables: const <SqliteImportTableDraft>[
      SqliteImportTableDraft(
        sourceName: 'users',
        targetName: 'users',
        selected: true,
        rowCount: 2,
        strict: false,
        withoutRowId: false,
        columns: <SqliteImportColumnDraft>[
          SqliteImportColumnDraft(
            sourceName: 'id',
            targetName: 'id',
            declaredType: 'INTEGER',
            inferredTargetType: 'INTEGER',
            targetType: 'INTEGER',
            notNull: true,
            primaryKey: true,
            unique: true,
          ),
          SqliteImportColumnDraft(
            sourceName: 'name',
            targetName: 'name',
            declaredType: 'TEXT',
            inferredTargetType: 'TEXT',
            targetType: 'TEXT',
            notNull: true,
            primaryKey: false,
            unique: false,
          ),
        ],
        foreignKeys: <SqliteImportForeignKey>[],
        indexes: <SqliteImportIndex>[
          SqliteImportIndex(
            name: 'idx_users_name',
            column: 'name',
            unique: false,
          ),
        ],
        skippedItems: <SqliteImportSkippedItem>[],
        previewRows: <Map<String, Object?>>[],
        previewLoaded: false,
      ),
      SqliteImportTableDraft(
        sourceName: 'audit_log',
        targetName: 'audit_log',
        selected: true,
        rowCount: 1,
        strict: false,
        withoutRowId: true,
        columns: <SqliteImportColumnDraft>[
          SqliteImportColumnDraft(
            sourceName: 'entry_id',
            targetName: 'entry_id',
            declaredType: 'INTEGER',
            inferredTargetType: 'INTEGER',
            targetType: 'INTEGER',
            notNull: true,
            primaryKey: true,
            unique: true,
          ),
          SqliteImportColumnDraft(
            sourceName: 'actor_id',
            targetName: 'actor_id',
            declaredType: 'INTEGER',
            inferredTargetType: 'INTEGER',
            targetType: 'INTEGER',
            notNull: true,
            primaryKey: false,
            unique: false,
          ),
          SqliteImportColumnDraft(
            sourceName: 'created_at',
            targetName: 'created_at',
            declaredType: 'TEXT',
            inferredTargetType: 'TEXT',
            targetType: 'TEXT',
            notNull: false,
            primaryKey: false,
            unique: false,
          ),
        ],
        foreignKeys: <SqliteImportForeignKey>[
          SqliteImportForeignKey(
            fromColumn: 'actor_id',
            toTable: 'users',
            toColumn: 'id',
          ),
        ],
        indexes: <SqliteImportIndex>[],
        skippedItems: <SqliteImportSkippedItem>[],
        previewRows: <Map<String, Object?>>[],
        previewLoaded: false,
      ),
    ],
  );
}

Map<String, SqliteImportPreview> _defaultSqlitePreviews() {
  return <String, SqliteImportPreview>{
    'users': const SqliteImportPreview(
      tableName: 'users',
      rows: <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'name': 'Ada'},
        <String, Object?>{'id': 2, 'name': 'Grace'},
      ],
    ),
    'audit_log': const SqliteImportPreview(
      tableName: 'audit_log',
      rows: <Map<String, Object?>>[
        <String, Object?>{
          'entry_id': 1,
          'actor_id': 1,
          'created_at': '2026-03-10T12:00:00Z',
        },
      ],
    ),
  };
}
