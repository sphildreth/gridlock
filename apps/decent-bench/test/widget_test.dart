import 'package:decent_bench/app/app.dart';
import 'package:decent_bench/app/startup_launch_options.dart';
import 'package:decent_bench/features/workspace/application/workspace_controller.dart';
import 'package:decent_bench/features/workspace/domain/app_config.dart';
import 'package:decent_bench/features/workspace/domain/workspace_models.dart';
import 'package:decent_bench/features/workspace/domain/workspace_shell_preferences.dart';
import 'package:decent_bench/features/workspace/presentation/shell/results_pane.dart';
import 'package:decent_bench/features/workspace/presentation/shell/status_bar.dart';
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
    expect(find.text('Export path'), findsNothing);
    expect(find.text('Export CSV'), findsNothing);
    expect(tester.getSize(find.byType(StatusBar)).width, 1600);
    expect(
      find.widgetWithText(OutlinedButton, 'Import SQLite...'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'New Query Tab'),
      findsOneWidget,
    );
    expect(find.widgetWithText(OutlinedButton, 'Manage'), findsNothing);

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Snippets'), findsOneWidget);
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

  testWidgets('startup --import opens the matching import wizard', (
    tester,
  ) async {
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
        startupLaunchOptions: const StartupLaunchOptions(
          importSourcePath: '/tmp/source.xlsx',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Excel Import Wizard'), findsOneWidget);
  });

  testWidgets('execution plan tab renders EXPLAIN rows', (tester) async {
    final verticalScrollController = ScrollController();
    final horizontalScrollController = ScrollController();
    final tab = QueryTabState.initial(id: 'query-tab-1', title: 'Query 1')
        .copyWith(
          executionPlan: const QueryExecutionPlanState(
            columns: <String>['query_plan'],
            rows: <Map<String, Object?>>[
              <String, Object?>{
                'query_plan': 'SCAN tasks USING COVERING INDEX idx_tasks_title',
              },
            ],
            isLoading: false,
          ),
        );

    _configureDesktopViewport(tester);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      verticalScrollController.dispose();
      horizontalScrollController.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1200,
              height: 600,
              child: Material(
                child: ResultsPane(
                  activeTab: tab,
                  activeResultsTab: ResultsPaneTab.executionPlan,
                  verticalScrollController: verticalScrollController,
                  horizontalScrollController: horizontalScrollController,
                  interactionState: const ResultsGridInteractionState(),
                  onResultsTabChanged: (_) {},
                  onLoadNextPage: () {},
                  onSelectCell: (_, _) {},
                  onShowCellMenu: (_, _, _) {},
                  onSelectRow: (_) {},
                  onTogglePinnedColumn: (_) {},
                  usePlaceholderContent: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('SCAN tasks'), findsOneWidget);
  });
}
