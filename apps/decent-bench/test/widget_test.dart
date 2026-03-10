import 'dart:io';

import 'package:decent_bench/app/app.dart';
import 'package:decent_bench/features/workspace/application/workspace_controller.dart';
import 'package:decent_bench/features/workspace/domain/app_config.dart';
import 'package:decent_bench/features/workspace/domain/workspace_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void _configureDesktopViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
}

void main() {
  testWidgets('renders the desktop shell with classic panes', (tester) async {
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );

    _configureDesktopViewport(tester);
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

    expect(find.text('File'), findsOneWidget);
    expect(find.text('Import'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
    expect(find.text('Schema Explorer'), findsOneWidget);
    expect(find.text('Properties / Details'), findsOneWidget);
    expect(find.text('SQL Editor'), findsOneWidget);
    expect(find.text('Results Window'), findsOneWidget);
    expect(find.textContaining('Workspace:'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Import SQLite...'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'New Query Tab'),
      findsOneWidget,
    );
  });

  testWidgets('loads shortcut labels from TOML-backed config into the menu', (
    tester,
  ) async {
    final config = AppConfig.defaults().copyWith(
      shortcutBindings: <String, String>{
        ...AppConfig.defaultShortcutBindings(),
        'file_exit': 'Ctrl+Shift+Q',
      },
    );
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(config),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );

    _configureDesktopViewport(tester);
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

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('Exit'), findsOneWidget);
    expect(find.text('Ctrl+Shift+Q'), findsOneWidget);
  });

  testWidgets('File Exit requests an application shutdown', (tester) async {
    final lifecycle = FakeAppLifecycleService();
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );

    _configureDesktopViewport(tester);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      controller.dispose();
    });
    await controller.initialize();
    await tester.pumpWidget(
      DecentBenchApp(
        controller: controller,
        autoInitialize: false,
        appLifecycleService: lifecycle,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exit'));
    await tester.pumpAndSettle();

    expect(lifecycle.requestedExit, isTrue);
  });

  testWidgets('toolbar import entry opens the SQLite wizard', (tester) async {
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );

    _configureDesktopViewport(tester);
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'Import SQLite...'));
    await tester.pumpAndSettle();

    expect(find.text('SQLite Import Wizard'), findsOneWidget);
  });

  testWidgets(
    'Run is enabled again after the first query page finishes loading',
    (tester) async {
      final dbPath =
          '${Directory.systemTemp.path}/workbench-${DateTime.now().microsecondsSinceEpoch}.ddb';
      final controller = WorkspaceController(
        gateway: FakeWorkspaceGateway(),
        configStore: InMemoryConfigStore(),
        workspaceStateStore: InMemoryWorkspaceStateStore(),
      );

      _configureDesktopViewport(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        controller.dispose();
      });
      await controller.initialize();
      await controller.openDatabase(dbPath, createIfMissing: true);
      controller.updateActiveSql('SELECT id, title FROM tasks ORDER BY id');

      await tester.pumpWidget(
        DecentBenchApp(controller: controller, autoInitialize: false),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Run'));
      await tester.pumpAndSettle();

      final runButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Run'),
      );
      expect(controller.activeTab.phase, QueryPhase.completed);
      expect(controller.activeTab.hasMoreRows, isTrue);
      expect(runButton.onPressed, isNotNull);
    },
  );
}
