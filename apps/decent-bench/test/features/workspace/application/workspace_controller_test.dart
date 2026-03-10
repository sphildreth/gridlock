import 'dart:io';

import 'package:decent_bench/features/workspace/application/workspace_controller.dart';
import 'package:decent_bench/features/workspace/domain/app_config.dart';
import 'package:decent_bench/features/workspace/domain/excel_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sql_dump_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sqlite_import_models.dart';
import 'package:decent_bench/features/workspace/domain/workspace_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

void main() {
  test('initialize loads config and native library path', () async {
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );

    await controller.initialize();

    expect(controller.nativeLibraryPath, '/tmp/libc_api.so');
    expect(controller.workspaceMessage, 'Ready.');
    expect(controller.tabs, hasLength(1));
  });

  test(
    'initialize reopens the most recent workspace when it still exists',
    () async {
      final dbPath =
          '${Directory.systemTemp.path}/workbench-${DateTime.now().microsecondsSinceEpoch}.ddb';
      final file = File(dbPath);
      await file.parent.create(recursive: true);
      await file.writeAsString('');

      addTearDown(() async {
        if (await file.exists()) {
          await file.delete();
        }
      });

      final config = AppConfig.defaults().copyWith(
        recentFiles: <String>[dbPath],
      );
      final controller = WorkspaceController(
        gateway: FakeWorkspaceGateway(),
        configStore: InMemoryConfigStore(config),
        workspaceStateStore: InMemoryWorkspaceStateStore(),
      );

      await controller.initialize();

      expect(controller.databasePath, dbPath);
      expect(controller.engineVersion, '1.6.1');
      expect(controller.schema.tables.single.name, 'tasks');
      expect(controller.workspaceError, isNull);
    },
  );

  test(
    'initialize falls back to the sample shell when the last workspace is missing',
    () async {
      final missingPath =
          '${Directory.systemTemp.path}/missing-${DateTime.now().microsecondsSinceEpoch}.ddb';
      final config = AppConfig.defaults().copyWith(
        recentFiles: <String>[missingPath],
      );
      final controller = WorkspaceController(
        gateway: FakeWorkspaceGateway(),
        configStore: InMemoryConfigStore(config),
        workspaceStateStore: InMemoryWorkspaceStateStore(),
      );

      await controller.initialize();

      expect(controller.databasePath, isNull);
      expect(controller.workspaceError, isNull);
      expect(controller.workspaceMessage, 'Ready.');
      expect(controller.schema.tables, isEmpty);
    },
  );

  test('openDatabase refreshes schema and stores recent files', () async {
    final dbPath =
        '${Directory.systemTemp.path}/workbench-${DateTime.now().microsecondsSinceEpoch}.ddb';
    final store = InMemoryConfigStore();
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: store,
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    await controller.initialize();

    await controller.openDatabase(dbPath, createIfMissing: true);

    expect(controller.databasePath, dbPath);
    expect(controller.engineVersion, '1.6.1');
    expect(controller.schema.tables.single.name, 'tasks');
    expect(controller.schema.views.single.name, 'active_tasks');
    expect((await store.load()).recentFiles, contains(dbPath));
  });

  test('applyAppConfig persists and reloads TOML-backed preferences', () async {
    final store = InMemoryConfigStore();
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: store,
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    await controller.initialize();

    final updatedConfig = controller.config.copyWith(
      defaultPageSize: 250,
      csvDelimiter: ';',
      csvIncludeHeaders: false,
      editorSettings: const EditorSettings(
        autocompleteEnabled: false,
        autocompleteMaxSuggestions: 18,
        formatUppercaseKeywords: false,
        indentSpaces: 4,
      ),
      shortcutBindings: <String, String>{
        ...controller.config.shortcutBindings,
        'tools_run_query': 'Ctrl+Shift+Enter',
      },
      snippets: const <SqlSnippet>[
        SqlSnippet(
          id: 'custom',
          name: 'Custom',
          trigger: 'custom',
          description: 'Custom snippet',
          body: 'SELECT * FROM custom_table;',
        ),
      ],
    );

    final saved = await controller.applyAppConfig(updatedConfig);

    expect(saved, isTrue);
    expect((await store.load()).defaultPageSize, 250);
    expect((await store.load()).csvDelimiter, ';');

    controller.config = AppConfig.defaults();
    await controller.reloadConfig();

    expect(controller.config.defaultPageSize, 250);
    expect(controller.config.csvIncludeHeaders, isFalse);
    expect(
      controller.config.shortcutBindings['tools_run_query'],
      'Ctrl+Shift+Enter',
    );
    expect(controller.config.snippets.single.trigger, 'custom');
  });

  test('tabs own independent query state and results', () async {
    final dbPath =
        '${Directory.systemTemp.path}/workbench-${DateTime.now().microsecondsSinceEpoch}.ddb';
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    await controller.initialize();
    await controller.openDatabase(dbPath, createIfMissing: true);

    controller.updateActiveSql('SELECT id, title FROM tasks ORDER BY id');
    await controller.runActiveTab();
    expect(controller.activeTab.resultRows.single['title'], 'Ship phase 1');
    expect(controller.activeTab.phase, QueryPhase.completed);
    expect(controller.canRunActiveTab, isTrue);
    expect(controller.canCancelActiveTab, isFalse);

    controller.createTab();
    controller.updateActiveSql('SELECT id, name FROM projects ORDER BY id');
    await controller.runActiveTab();
    expect(controller.activeTab.resultRows.single['name'], 'Phase 3');
    expect(controller.activeTab.phase, QueryPhase.completed);
    expect(controller.canRunActiveTab, isTrue);
    expect(controller.canCancelActiveTab, isFalse);

    final secondTabId = controller.activeTabId;
    controller.previousTab();

    expect(controller.activeTab.sql, 'SELECT id, title FROM tasks ORDER BY id');
    expect(controller.activeTab.resultRows.single['title'], 'Ship phase 1');
    expect(controller.tabs, hasLength(2));

    controller.selectTab(secondTabId);
    await controller.fetchNextPage();
    expect(controller.activeTab.phase, QueryPhase.completed);
    expect(controller.activeTab.resultRows.last['name'], 'Keep testing');

    await controller.cancelTabQuery(controller.tabs.first.id);
    controller.selectTab(controller.tabs.first.id);
    expect(controller.activeTab.phase, QueryPhase.completed);
    expect(controller.activeTab.isResultPartial, isFalse);
    expect(controller.activeTab.hasMoreRows, isTrue);
  });

  test('runTab captures execution plan rows from EXPLAIN output', () async {
    final dbPath =
        '${Directory.systemTemp.path}/workbench-${DateTime.now().microsecondsSinceEpoch}.ddb';
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    await controller.initialize();
    await controller.openDatabase(dbPath, createIfMissing: true);

    controller.updateActiveSql('SELECT id, title FROM tasks ORDER BY id');
    await controller.runActiveTab();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.activeTab.executionPlan.isLoading, isFalse);
    expect(controller.activeTab.executionPlan.columns, <String>['query_plan']);
    expect(
      controller.activeTab.executionPlan.rows.single['query_plan'],
      contains('SCAN tasks'),
    );
  });

  test('reopening the same database restores persisted tab drafts', () async {
    final dbPath =
        '${Directory.systemTemp.path}/workbench-${DateTime.now().microsecondsSinceEpoch}.ddb';
    final configStore = InMemoryConfigStore();
    final workspaceStateStore = InMemoryWorkspaceStateStore();

    final firstController = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: configStore,
      workspaceStateStore: workspaceStateStore,
    );
    await firstController.initialize();
    await firstController.openDatabase(dbPath, createIfMissing: true);
    firstController.updateActiveSql('SELECT * FROM tasks WHERE id = \$1');
    firstController.updateActiveParameterJson('[1]');
    firstController.createTab();
    firstController.updateActiveSql('SELECT * FROM projects ORDER BY id');
    firstController.updateActiveExportPath('/tmp/projects.csv');
    await Future<void>.delayed(const Duration(milliseconds: 450));

    final secondController = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: configStore,
      workspaceStateStore: workspaceStateStore,
    );
    await secondController.initialize();
    await secondController.openDatabase(dbPath, createIfMissing: false);

    expect(secondController.tabs, hasLength(2));
    expect(
      secondController.activeTab.sql,
      'SELECT * FROM projects ORDER BY id',
    );
    expect(secondController.activeTab.exportPath, '/tmp/projects.csv');
    secondController.previousTab();
    expect(secondController.activeTab.parameterJson, '[1]');
  });

  test(
    'reopening the same database restores per-tab query and message history',
    () async {
      final dbPath =
          '${Directory.systemTemp.path}/workbench-${DateTime.now().microsecondsSinceEpoch}.ddb';
      final configStore = InMemoryConfigStore();
      final workspaceStateStore = InMemoryWorkspaceStateStore();

      final firstController = WorkspaceController(
        gateway: FakeWorkspaceGateway(),
        configStore: configStore,
        workspaceStateStore: workspaceStateStore,
      );
      await firstController.initialize();
      await firstController.openDatabase(dbPath, createIfMissing: true);
      firstController.updateActiveSql(
        'SELECT id, title FROM tasks ORDER BY id',
      );
      await firstController.runActiveTab();
      await firstController.fetchNextPage();
      await Future<void>.delayed(const Duration(milliseconds: 450));

      final secondController = WorkspaceController(
        gateway: FakeWorkspaceGateway(),
        configStore: configStore,
        workspaceStateStore: workspaceStateStore,
      );
      await secondController.initialize();
      await secondController.openDatabase(dbPath, createIfMissing: false);

      expect(secondController.activeTab.queryHistory, hasLength(1));
      expect(
        secondController.activeTab.queryHistory.single.outcome,
        QueryHistoryOutcome.completed,
      );
      expect(secondController.activeTab.messageHistory, isNotEmpty);
    },
  );

  test(
    'excel import inspection loads sheets, previews, and import summary',
    () async {
      final gateway = FakeWorkspaceGateway();
      final controller = WorkspaceController(
        gateway: gateway,
        configStore: InMemoryConfigStore(),
        workspaceStateStore: InMemoryWorkspaceStateStore(),
      );
      await controller.initialize();

      controller.beginExcelImport();
      await controller.loadExcelImportSource('/tmp/phase5-source.xlsx');

      final session = controller.excelImportSession;
      expect(session, isNotNull);
      expect(session!.phase, ExcelImportJobPhase.ready);
      expect(
        session.sheets.map((sheet) => sheet.sourceName),
        contains('people'),
      );
      expect(session.focusedSheetDraft?.previewRows.first['name'], 'Ada');

      controller.setExcelImportStep(ExcelImportWizardStep.transforms);
      controller.renameExcelImportSheet('people', 'imported_people');
      controller.renameExcelImportColumn('people', 1, 'display_name');
      await controller.runExcelImport();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(gateway.lastExcelImportRequest, isNotNull);
      expect(
        gateway.lastExcelImportRequest!.selectedSheets.first.targetName,
        'imported_people',
      );
      expect(
        controller.excelImportSession?.phase,
        ExcelImportJobPhase.completed,
      );
      expect(
        controller.excelImportSession?.summary?.importedTables,
        contains('imported_people'),
      );
    },
  );

  test('excel import cancellation updates session state', () async {
    final gateway = FakeWorkspaceGateway()..holdExcelImportOpen = true;
    final controller = WorkspaceController(
      gateway: gateway,
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    await controller.initialize();
    controller.beginExcelImport();
    await controller.loadExcelImportSource('/tmp/phase5-cancel.xlsx');

    await controller.runExcelImport();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.excelImportSession?.phase, ExcelImportJobPhase.running);

    final jobId = controller.excelImportSession?.jobId;
    await controller.cancelExcelImport();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(gateway.lastCancelledImportJobId, jobId);
    expect(controller.excelImportSession?.phase, ExcelImportJobPhase.cancelled);
    expect(controller.excelImportSession?.summary?.rolledBack, isTrue);
  });

  test(
    'sql dump import inspection loads parsed tables, warnings, and import summary',
    () async {
      final gateway = FakeWorkspaceGateway();
      final controller = WorkspaceController(
        gateway: gateway,
        configStore: InMemoryConfigStore(),
        workspaceStateStore: InMemoryWorkspaceStateStore(),
      );
      await controller.initialize();

      controller.beginSqlDumpImport();
      await controller.loadSqlDumpImportSource('/tmp/phase6-source.sql');

      final session = controller.sqlDumpImportSession;
      expect(session, isNotNull);
      expect(session!.phase, SqlDumpImportJobPhase.ready);
      expect(
        session.tables.map((table) => table.sourceName),
        contains('people'),
      );
      expect(session.warnings, isNotEmpty);
      expect(session.skippedStatementCount, greaterThan(0));
      expect(session.focusedTableDraft?.previewRows.first['name'], 'Ada');

      controller.setSqlDumpImportStep(SqlDumpImportWizardStep.transforms);
      controller.renameSqlDumpImportTable('people', 'imported_people');
      controller.renameSqlDumpImportColumn('people', 1, 'display_name');
      await controller.runSqlDumpImport();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(gateway.lastSqlDumpImportRequest, isNotNull);
      expect(
        gateway.lastSqlDumpImportRequest!.selectedTables.first.targetName,
        'imported_people',
      );
      expect(
        gateway
            .lastSqlDumpImportRequest!
            .selectedTables
            .first
            .columns[1]
            .targetName,
        'display_name',
      );
      expect(
        controller.sqlDumpImportSession?.phase,
        SqlDumpImportJobPhase.completed,
      );
      expect(
        controller.sqlDumpImportSession?.summary?.importedTables,
        contains('imported_people'),
      );
    },
  );

  test('sql dump import cancellation updates session state', () async {
    final gateway = FakeWorkspaceGateway()..holdSqlDumpImportOpen = true;
    final controller = WorkspaceController(
      gateway: gateway,
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    await controller.initialize();
    controller.beginSqlDumpImport();
    await controller.loadSqlDumpImportSource('/tmp/phase6-cancel.sql');

    await controller.runSqlDumpImport();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      controller.sqlDumpImportSession?.phase,
      SqlDumpImportJobPhase.running,
    );

    final jobId = controller.sqlDumpImportSession?.jobId;
    await controller.cancelSqlDumpImport();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(gateway.lastCancelledImportJobId, jobId);
    expect(
      controller.sqlDumpImportSession?.phase,
      SqlDumpImportJobPhase.cancelled,
    );
    expect(controller.sqlDumpImportSession?.summary?.rolledBack, isTrue);
  });

  test(
    'sqlite import inspection loads tables, previews, and import summary',
    () async {
      final gateway = FakeWorkspaceGateway();
      final controller = WorkspaceController(
        gateway: gateway,
        configStore: InMemoryConfigStore(),
        workspaceStateStore: InMemoryWorkspaceStateStore(),
      );
      await controller.initialize();

      controller.beginSqliteImport();
      await controller.loadSqliteImportSource('/tmp/phase4-source.sqlite');

      final session = controller.sqliteImportSession;
      expect(session, isNotNull);
      expect(session!.phase, SqliteImportJobPhase.ready);
      expect(
        session.tables.map((table) => table.sourceName),
        contains('users'),
      );
      expect(session.focusedTableDraft?.previewLoaded, isTrue);
      expect(
        session.focusedTableDraft?.previewRows.first['name'],
        anyOf('Ada', isNull),
      );

      controller.setSqliteImportStep(SqliteImportWizardStep.transforms);
      controller.renameSqliteImportTable('users', 'imported_users');
      controller.renameSqliteImportColumn('users', 'name', 'display_name');
      await controller.runSqliteImport();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(gateway.lastSqliteImportRequest, isNotNull);
      expect(
        gateway.lastSqliteImportRequest!.selectedTables.first.targetName,
        'imported_users',
      );
      expect(
        controller.sqliteImportSession?.phase,
        SqliteImportJobPhase.completed,
      );
      expect(
        controller.sqliteImportSession?.summary?.importedTables,
        contains('imported_users'),
      );
    },
  );

  test('sqlite import cancellation updates session state', () async {
    final gateway = FakeWorkspaceGateway()..holdImportOpen = true;
    final controller = WorkspaceController(
      gateway: gateway,
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    await controller.initialize();
    controller.beginSqliteImport();
    await controller.loadSqliteImportSource('/tmp/phase4-cancel.sqlite');

    await controller.runSqliteImport();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.sqliteImportSession?.phase, SqliteImportJobPhase.running);

    final jobId = controller.sqliteImportSession?.jobId;
    await controller.cancelSqliteImport();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(gateway.lastCancelledImportJobId, jobId);
    expect(
      controller.sqliteImportSession?.phase,
      SqliteImportJobPhase.cancelled,
    );
    expect(controller.sqliteImportSession?.summary?.rolledBack, isTrue);
  });
}
