import 'package:decent_bench/features/workspace/application/workspace_shell_controller.dart';
import 'package:decent_bench/features/workspace/domain/workspace_shell_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splitter changes persist after a debounce', () async {
    WorkspaceShellPreferences? persisted;
    final controller = WorkspaceShellController(
      initialPreferences: WorkspaceShellPreferences.defaults(),
      onPersist: (preferences, {statusMessage}) async {
        persisted = preferences;
      },
    );
    addTearDown(controller.dispose);

    controller.setLeftColumnFraction(0.4);
    expect(persisted, isNull);

    await Future<void>.delayed(const Duration(milliseconds: 220));

    expect(persisted, isNotNull);
    expect(persisted!.leftColumnFraction, closeTo(0.4, 0.001));
  });

  test('reset layout restores defaults immediately', () async {
    WorkspaceShellPreferences? persisted;
    String? message;
    final controller = WorkspaceShellController(
      initialPreferences: const WorkspaceShellPreferences(
        leftColumnFraction: 0.4,
        leftTopFraction: 0.5,
        rightTopFraction: 0.5,
        showSchemaExplorer: false,
        showPropertiesPane: true,
        showResultsPane: false,
        showStatusBar: true,
        editorZoom: 1.2,
        activeResultsTab: ResultsPaneTab.messages,
      ),
      onPersist: (preferences, {statusMessage}) async {
        persisted = preferences;
        message = statusMessage;
      },
    );
    addTearDown(controller.dispose);

    controller.resetLayout();
    await Future<void>.delayed(Duration.zero);

    expect(persisted, isNotNull);
    expect(
      persisted!.leftColumnFraction,
      WorkspaceShellPreferences.defaults().leftColumnFraction,
    );
    expect(persisted!.showSchemaExplorer, isTrue);
    expect(message, 'Workspace layout reset.');
  });
}
