import 'package:decent_bench/app/app.dart';
import 'package:decent_bench/features/workspace/application/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Finder _fieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField labeled $label',
  );
}

void main() {
  testWidgets('renders the Phase 3 workspace shell and editor tools', (
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

    final manageSnippetsButton = find.widgetWithText(
      OutlinedButton,
      'Manage Snippets',
    );
    await tester.ensureVisible(manageSnippetsButton);
    await tester.tap(manageSnippetsButton);
    await tester.pumpAndSettle();

    expect(find.text('SQL Snippets'), findsOneWidget);
    expect(find.text('Recursive CTE'), findsOneWidget);
  });

  testWidgets('opens the SQLite import wizard and completes an import', (
    tester,
  ) async {
    final gateway = FakeWorkspaceGateway();
    final controller = WorkspaceController(
      gateway: gateway,
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

    final importButton = find.widgetWithText(OutlinedButton, 'Import SQLite');
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pumpAndSettle();

    expect(find.text('SQLite Import Wizard'), findsOneWidget);

    await tester.enterText(
      _fieldWithLabel('SQLite source path'),
      '/tmp/phase4-widget.sqlite',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Inspect Source'));
    await tester.pumpAndSettle();

    expect(find.text('users'), findsWidgets);
    expect(find.text('audit_log'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start Import'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(gateway.lastSqliteImportRequest, isNotNull);
  });

  testWidgets('opens the Excel import wizard and completes an import', (
    tester,
  ) async {
    final gateway = FakeWorkspaceGateway();
    final controller = WorkspaceController(
      gateway: gateway,
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

    final importButton = find.widgetWithText(OutlinedButton, 'Import Excel');
    await tester.ensureVisible(importButton);
    await tester.tap(importButton);
    await tester.pumpAndSettle();

    expect(find.text('Excel Import Wizard'), findsOneWidget);

    await tester.enterText(
      _fieldWithLabel('Excel source path'),
      '/tmp/phase5-widget.xlsx',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Inspect Workbook'));
    await tester.pumpAndSettle();

    expect(find.text('people'), findsWidgets);
    expect(find.text('metrics'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start Import'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(gateway.lastExcelImportRequest, isNotNull);
  });
}
