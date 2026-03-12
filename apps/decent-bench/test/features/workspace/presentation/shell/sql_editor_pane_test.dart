import 'package:decent_bench/app/theme.dart';
import 'package:decent_bench/app/theme_system/theme_presets.dart';
import 'package:decent_bench/features/workspace/domain/app_config.dart';
import 'package:decent_bench/features/workspace/domain/sql_autocomplete.dart';
import 'package:decent_bench/features/workspace/domain/workspace_models.dart';
import 'package:decent_bench/features/workspace/presentation/shell/sql_editor_pane.dart';
import 'package:decent_bench/features/workspace/presentation/shell/sql_highlighting_text_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('escape dismisses open autocomplete suggestions', (tester) async {
    final sqlController = SqlHighlightingTextEditingController(text: 'SEL');
    final paramsController = TextEditingController();
    final findController = TextEditingController();
    final editorScrollController = ScrollController();
    final focusNode = FocusNode();
    final paramsFocusNode = FocusNode();
    final findFocusNode = FocusNode();
    final undoController = UndoHistoryController();
    final paramsUndoController = UndoHistoryController();
    var autocompleteResult = const AutocompleteResult(
      replaceStart: 0,
      replaceEnd: 3,
      suggestions: <AutocompleteSuggestion>[
        AutocompleteSuggestion(
          label: 'SELECT',
          insertText: 'SELECT',
          detail: 'keyword',
          kind: AutocompleteSuggestionKind.keyword,
        ),
      ],
    );

    addTearDown(() {
      paramsUndoController.dispose();
      undoController.dispose();
      findFocusNode.dispose();
      paramsFocusNode.dispose();
      focusNode.dispose();
      editorScrollController.dispose();
      findController.dispose();
      paramsController.dispose();
      sqlController.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildDecentBenchTheme(buildEmergencyTheme()),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: 900,
                height: 600,
                child: SqlEditorPane(
                  tabs: <QueryTabState>[
                    QueryTabState.initial(id: 'query-1', title: 'Query 1'),
                  ],
                  activeTab: QueryTabState.initial(
                    id: 'query-1',
                    title: 'Query 1',
                    sql: 'SEL',
                  ),
                  sqlController: sqlController,
                  paramsController: paramsController,
                  editorScrollController: editorScrollController,
                  focusNode: focusNode,
                  paramsFocusNode: paramsFocusNode,
                  undoController: undoController,
                  paramsUndoController: paramsUndoController,
                  autocompleteResult: autocompleteResult,
                  snippets: const <SqlSnippet>[],
                  zoomFactor: 1,
                  indentSpaces: 2,
                  showLineNumbers: true,
                  showFindBar: false,
                  findController: findController,
                  findFocusNode: findFocusNode,
                  findStatusLabel: '0/0',
                  onSqlChanged: (_) {},
                  onParamsChanged: (_) {},
                  onSelectTab: (_) {},
                  onCloseTab: (_) async {},
                  onNewTab: () {},
                  onRunQuery: () {},
                  onRunBuffer: () {},
                  onStopQuery: () {},
                  onFormatSql: () {},
                  onInsertSnippet: (_) {},
                  onApplyAutocomplete: (_) {},
                  selectedAutocompleteIndex: 0,
                  onAutocompleteNext: () {},
                  onAutocompletePrevious: () {},
                  onAcceptAutocomplete: () {},
                  onDismissAutocomplete: () {
                    setState(() {
                      autocompleteResult = const AutocompleteResult(
                        replaceStart: 0,
                        replaceEnd: 0,
                        suggestions: <AutocompleteSuggestion>[],
                      );
                    });
                  },
                  canRun: true,
                  canStop: false,
                  onFindChanged: (_) {},
                  onFindNext: () {},
                  onFindPrevious: () {},
                  onCloseFind: () {},
                  runLabel: 'Run',
                  formatLabel: 'Format',
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sql_editor.autocomplete_popup')),
      findsOneWidget,
    );

    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('sql_editor.autocomplete_popup')),
      findsNothing,
    );
  });
}
