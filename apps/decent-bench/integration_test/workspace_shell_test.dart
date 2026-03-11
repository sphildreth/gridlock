import 'dart:io';

import 'package:decent_bench/app/app.dart';
import 'package:decent_bench/app/logging/app_logger.dart';
import 'package:decent_bench/app/startup_launch_options.dart';
import 'package:archive/archive.dart';
import 'package:decent_bench/features/workspace/application/workspace_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the desktop shell', (tester) async {
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
      DecentBenchApp(
        controller: controller,
        autoInitialize: false,
        logger: const NoOpAppLogger(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Schema Explorer'), findsOneWidget);
    expect(find.text('SQL Editor'), findsOneWidget);
    expect(find.text('Results Window'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Format'), findsOneWidget);
  });

  testWidgets('opens a workspace and runs a query inside the shell', (
    tester,
  ) async {
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    final tempDir = await Directory.systemTemp.createTemp('decent-bench-it-');
    final dbPath = p.join(tempDir.path, 'workspace.ddb');

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
    await controller.openDatabase(dbPath, createIfMissing: true);
    controller.updateActiveSql('SELECT id, title FROM tasks ORDER BY id');

    await tester.pumpWidget(
      DecentBenchApp(
        controller: controller,
        autoInitialize: false,
        logger: const NoOpAppLogger(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('tasks'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Run'));
    await tester.pumpAndSettle();

    expect(find.text('Ship phase 1'), findsOneWidget);
    expect(find.textContaining('Workspace: workspace.ddb'), findsOneWidget);
  });

  testWidgets('launches the generic CSV import wizard from startup options', (
    tester,
  ) async {
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    final tempDir = await Directory.systemTemp.createTemp('decent-bench-it-');
    final csvPath = p.join(tempDir.path, 'customers.csv');
    await File(csvPath).writeAsString('id,name\n1,Ada\n2,Lin\n');

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
      DecentBenchApp(
        controller: controller,
        autoInitialize: false,
        logger: const NoOpAppLogger(),
        startupLaunchOptions: StartupLaunchOptions(importSourcePath: csvPath),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CSV Import Wizard'), findsOneWidget);
    expect(find.textContaining('Tables: 1'), findsOneWidget);
  });

  testWidgets('launches archive chooser for ZIP imports from startup options', (
    tester,
  ) async {
    final controller = WorkspaceController(
      gateway: FakeWorkspaceGateway(),
      configStore: InMemoryConfigStore(),
      workspaceStateStore: InMemoryWorkspaceStateStore(),
    );
    final tempDir = await Directory.systemTemp.createTemp('decent-bench-it-');
    final zipPath = p.join(tempDir.path, 'bundle.zip');
    final archive = Archive()
      ..addFile(
        ArchiveFile('customers.csv', 14, 'id,name\n1,Ada\n'.codeUnits),
      );
    await File(zipPath).writeAsBytes(ZipEncoder().encode(archive)!, flush: true);

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
      DecentBenchApp(
        controller: controller,
        autoInitialize: false,
        logger: const NoOpAppLogger(),
        startupLaunchOptions: StartupLaunchOptions(importSourcePath: zipPath),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ZIP Wrapper Contents'), findsOneWidget);
    expect(find.textContaining('customers.csv'), findsOneWidget);
  });
}
