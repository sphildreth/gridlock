import 'dart:io';

import 'package:decent_bench/app/app.dart';
import 'package:decent_bench/features/workspace/application/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../test/support/fakes.dart';

Finder _fieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField labeled $label',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the phase 3 workspace shell and editor tools', (
    tester,
  ) async {
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
    });
    await controller.initialize();

    await tester.pumpWidget(
      DecentBenchApp(controller: controller, autoInitialize: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('Decent Bench'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Schema'), findsOneWidget);
    expect(find.text('SQL Workspace'), findsOneWidget);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('New Tab'), findsOneWidget);
    expect(find.text('Format SQL'), findsOneWidget);
    expect(find.text('Insert Snippet'), findsOneWidget);
    expect(find.text('Manage Snippets'), findsOneWidget);

    await tester.enterText(_fieldWithLabel('SQL'), 'SELECT cou');
    await tester.pumpAndSettle();

    expect(find.text('Autocomplete'), findsOneWidget);
    expect(find.text('COUNT'), findsOneWidget);
  });

  testWidgets('creates a workspace, formats SQL, uses tabs, and exports CSV', (
    tester,
  ) async {
    final gateway = FakeWorkspaceGateway();
    final controller = WorkspaceController(
      gateway: gateway,
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    final tempDir = await Directory.systemTemp.createTemp('decent-bench-it-');
    final dbPath = p.join(tempDir.path, 'phase3.ddb');
    final exportPath = p.join(tempDir.path, 'phase3.csv');

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await controller.initialize();

    await tester.pumpWidget(
      DecentBenchApp(controller: controller, autoInitialize: false),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_fieldWithLabel('Database path'), dbPath);
    final createNewButton = find.widgetWithText(FilledButton, 'Create New');
    await tester.ensureVisible(createNewButton);
    await tester.tap(createNewButton);
    await tester.pumpAndSettle();

    expect(find.text('tasks'), findsWidgets);
    expect(find.text('active_tasks'), findsWidgets);

    await tester.tap(find.text('active_tasks').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('CREATE VIEW active_tasks'), findsOneWidget);

    await tester.enterText(
      _fieldWithLabel('SQL'),
      "select id, title from tasks where title = 'Ship phase 1' and id = 1",
    );
    final formatButton = find.widgetWithText(OutlinedButton, 'Format SQL');
    await tester.ensureVisible(formatButton);
    await tester.tap(formatButton);
    await tester.pumpAndSettle();
    expect(controller.activeTab.sql, contains('SELECT id, title'));
    expect(controller.activeTab.sql, contains('\nFROM tasks'));

    final runSqlButton = find.widgetWithText(FilledButton, 'Run SQL');
    await tester.ensureVisible(runSqlButton);
    await tester.tap(runSqlButton);
    await tester.pumpAndSettle();
    expect(find.text('Ship phase 1'), findsOneWidget);

    final newTabButton = find.widgetWithText(FilledButton, 'New Tab');
    await tester.ensureVisible(newTabButton);
    await tester.tap(newTabButton);
    await tester.pumpAndSettle();
    expect(find.text('Query 2'), findsOneWidget);
    expect(controller.activeTab.title, 'Query 2');

    controller.updateActiveSql('SELECT id, name FROM projects ORDER BY id');
    await tester.pumpAndSettle();
    await tester.ensureVisible(runSqlButton);
    await tester.tap(runSqlButton);
    await tester.pumpAndSettle();
    expect(controller.activeTab.resultRows.single['name'], 'Phase 3');

    await tester.tap(find.text('Query 1'));
    await tester.pumpAndSettle();
    expect(find.text('Ship phase 1'), findsOneWidget);

    await tester.tap(find.text('Load next page'));
    await tester.pumpAndSettle();
    expect(find.text('Keep paging'), findsOneWidget);

    await tester.enterText(_fieldWithLabel('CSV export path'), exportPath);
    final exportButton = find.widgetWithText(FilledButton, 'Export CSV');
    await tester.ensureVisible(exportButton);
    await tester.tap(exportButton);
    await tester.pumpAndSettle();

    expect(gateway.lastExportPath, exportPath);
    expect(find.textContaining('Exported 2 rows to'), findsOneWidget);
  });

  testWidgets('imports SQLite through the wizard and opens a query tab', (
    tester,
  ) async {
    final gateway = FakeWorkspaceGateway();
    final controller = WorkspaceController(
      gateway: gateway,
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    final tempDir = await Directory.systemTemp.createTemp('decent-bench-it-');
    final targetPath = p.join(tempDir.path, 'imported.ddb');

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await controller.initialize();

    await tester.pumpWidget(
      DecentBenchApp(controller: controller, autoInitialize: false),
    );
    await tester.pumpAndSettle();

    final importButton = find.widgetWithText(OutlinedButton, 'Import SQLite');
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pumpAndSettle();

    await tester.enterText(
      _fieldWithLabel('SQLite source path'),
      p.join(tempDir.path, 'phase4-source.sqlite'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Inspect Source'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.enterText(_fieldWithLabel('DecentDB target path'), targetPath);
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start Import'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Run a Query'), findsOneWidget);
    expect(gateway.lastSqliteImportRequest, isNotNull);
    expect(gateway.lastSqliteImportRequest!.targetPath, targetPath);

    await tester.tap(find.widgetWithText(FilledButton, 'Run a Query'));
    await tester.pumpAndSettle();

    expect(controller.databasePath, targetPath);
    expect(controller.activeTab.sql, contains('SELECT *'));
  });

  testWidgets('imports Excel through the wizard and opens a query tab', (
    tester,
  ) async {
    final gateway = FakeWorkspaceGateway();
    final controller = WorkspaceController(
      gateway: gateway,
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    final tempDir = await Directory.systemTemp.createTemp('decent-bench-it-');
    final targetPath = p.join(tempDir.path, 'excel-imported.ddb');

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1000);
    addTearDown(() async {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    await controller.initialize();

    await tester.pumpWidget(
      DecentBenchApp(controller: controller, autoInitialize: false),
    );
    await tester.pumpAndSettle();

    final importButton = find.widgetWithText(OutlinedButton, 'Import Excel');
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pumpAndSettle();

    await tester.enterText(
      _fieldWithLabel('Excel source path'),
      p.join(tempDir.path, 'phase5-source.xlsx'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Inspect Workbook'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.enterText(_fieldWithLabel('DecentDB target path'), targetPath);
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start Import'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Run a Query'), findsOneWidget);
    expect(gateway.lastExcelImportRequest, isNotNull);
    expect(gateway.lastExcelImportRequest!.targetPath, targetPath);

    await tester.tap(find.widgetWithText(FilledButton, 'Run a Query'));
    await tester.pumpAndSettle();

    expect(controller.databasePath, targetPath);
    expect(controller.activeTab.sql, contains('SELECT *'));
  });
}
