import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme_system/decent_bench_theme_extension.dart';
import '../../domain/app_config.dart';
import '../../domain/sql_autocomplete.dart';
import '../../domain/workspace_models.dart';
import 'shell_pane_frame.dart';
import 'sql_code_editor.dart';

class SqlEditorPane extends StatelessWidget {
  const SqlEditorPane({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.sqlController,
    required this.paramsController,
    required this.editorScrollController,
    required this.focusNode,
    required this.paramsFocusNode,
    required this.undoController,
    required this.paramsUndoController,
    required this.autocompleteResult,
    required this.snippets,
    required this.zoomFactor,
    required this.indentSpaces,
    required this.showLineNumbers,
    required this.showFindBar,
    required this.findController,
    required this.findFocusNode,
    required this.findStatusLabel,
    required this.onSqlChanged,
    required this.onParamsChanged,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
    required this.onRunQuery,
    required this.onStopQuery,
    required this.onFormatSql,
    required this.onInsertSnippet,
    required this.onApplyAutocomplete,
    required this.selectedAutocompleteIndex,
    required this.onAutocompleteNext,
    required this.onAutocompletePrevious,
    required this.onAcceptAutocomplete,
    required this.canRun,
    required this.canStop,
    required this.onFindChanged,
    required this.onFindNext,
    required this.onFindPrevious,
    required this.onCloseFind,
    required this.runLabel,
    required this.formatLabel,
    required this.onRunBuffer,
    this.editorContextLabel,
    this.errorLocationLabel,
    this.errorMessage,
    this.showRunBufferButton = false,
  });

  final List<QueryTabState> tabs;
  final QueryTabState activeTab;
  final TextEditingController sqlController;
  final TextEditingController paramsController;
  final ScrollController editorScrollController;
  final FocusNode focusNode;
  final FocusNode paramsFocusNode;
  final UndoHistoryController undoController;
  final UndoHistoryController paramsUndoController;
  final AutocompleteResult autocompleteResult;
  final List<SqlSnippet> snippets;
  final double zoomFactor;
  final int indentSpaces;
  final bool showLineNumbers;
  final bool showFindBar;
  final TextEditingController findController;
  final FocusNode findFocusNode;
  final String findStatusLabel;
  final ValueChanged<String> onSqlChanged;
  final ValueChanged<String> onParamsChanged;
  final ValueChanged<String> onSelectTab;
  final Future<void> Function(String tabId) onCloseTab;
  final VoidCallback onNewTab;
  final VoidCallback onRunQuery;
  final VoidCallback onStopQuery;
  final VoidCallback onFormatSql;
  final VoidCallback onRunBuffer;
  final ValueChanged<SqlSnippet> onInsertSnippet;
  final ValueChanged<AutocompleteSuggestion> onApplyAutocomplete;
  final int selectedAutocompleteIndex;
  final VoidCallback onAutocompleteNext;
  final VoidCallback onAutocompletePrevious;
  final VoidCallback onAcceptAutocomplete;
  final bool canRun;
  final bool canStop;
  final ValueChanged<String> onFindChanged;
  final VoidCallback onFindNext;
  final VoidCallback onFindPrevious;
  final VoidCallback onCloseFind;
  final String runLabel;
  final String formatLabel;
  final String? editorContextLabel;
  final String? errorLocationLabel;
  final String? errorMessage;
  final bool showRunBufferButton;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    final effectiveTabs = tabs.length >= 2
        ? tabs
        : <QueryTabState>[
            ...tabs,
            QueryTabState.initial(
              id: 'mock-tab',
              title: 'Scratch.sql',
              sql: 'SELECT * FROM customers LIMIT 100;',
            ),
          ];
    return ShellPaneFrame(
      title: 'SQL Editor',
      subtitle: activeTab.title,
      leadingIcon: Icons.code,
      toolbar: _EditorToolbar(
        canRun: canRun,
        canStop: canStop,
        snippets: snippets,
        onRunQuery: onRunQuery,
        onStopQuery: onStopQuery,
        onFormatSql: onFormatSql,
        onNewTab: onNewTab,
        onInsertSnippet: onInsertSnippet,
        runLabel: runLabel,
        formatLabel: formatLabel,
        onRunBuffer: onRunBuffer,
        showRunBufferButton: showRunBufferButton,
      ),
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          _TabStrip(
            tabs: effectiveTabs,
            activeTabId: activeTab.id,
            onSelectTab: onSelectTab,
            onCloseTab: onCloseTab,
          ),
          if (showFindBar)
            _FindBar(
              controller: findController,
              focusNode: findFocusNode,
              statusLabel: findStatusLabel,
              onChanged: onFindChanged,
              onFindNext: onFindNext,
              onFindPrevious: onFindPrevious,
              onClose: onCloseFind,
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: tokens.colors.panelBg,
              border: Border(bottom: BorderSide(color: tokens.colors.border)),
            ),
            child: TextField(
              focusNode: paramsFocusNode,
              controller: paramsController,
              undoController: paramsUndoController,
              onChanged: onParamsChanged,
              style: TextStyle(
                fontSize: tokens.fonts.uiSize * zoomFactor,
                color: tokens.dialog.inputText,
              ),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Parameters (JSON array)',
                hintText: '[1, "alice", true]',
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final themeTokens = context.decentBenchTheme;
                final editorStyle = TextStyle(
                  fontSize: themeTokens.fonts.editorSize * zoomFactor,
                  fontFamily: themeTokens.fonts.editorFamily,
                  height: themeTokens.fonts.lineHeight,
                  color: themeTokens.editor.text,
                );
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: themeTokens.editor.background,
                    border: Border(
                      bottom: BorderSide(color: themeTokens.colors.border),
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (showLineNumbers)
                            _LineNumberGutter(
                              lineCount: _lineCount(sqlController.text),
                              controller: editorScrollController,
                              zoomFactor: zoomFactor,
                              errorLineNumber: activeTab.error?.location?.line,
                              errorMessage: errorMessage,
                            ),
                          Expanded(
                            child: Shortcuts(
                              shortcuts: autocompleteResult.isEmpty
                                  ? const <ShortcutActivator, Intent>{}
                                  : const <ShortcutActivator, Intent>{
                                      SingleActivator(LogicalKeyboardKey.tab):
                                          _AcceptAutocompleteIntent(),
                                      SingleActivator(
                                        LogicalKeyboardKey.arrowDown,
                                      ): _NextAutocompleteIntent(),
                                      SingleActivator(
                                        LogicalKeyboardKey.arrowUp,
                                      ): _PreviousAutocompleteIntent(),
                                    },
                              child: Actions(
                                actions: <Type, Action<Intent>>{
                                  _AcceptAutocompleteIntent:
                                      CallbackAction<_AcceptAutocompleteIntent>(
                                        onInvoke: (_) {
                                          onAcceptAutocomplete();
                                          return null;
                                        },
                                      ),
                                  _NextAutocompleteIntent:
                                      CallbackAction<_NextAutocompleteIntent>(
                                        onInvoke: (_) {
                                          onAutocompleteNext();
                                          return null;
                                        },
                                      ),
                                  _PreviousAutocompleteIntent:
                                      CallbackAction<
                                        _PreviousAutocompleteIntent
                                      >(
                                        onInvoke: (_) {
                                          onAutocompletePrevious();
                                          return null;
                                        },
                                      ),
                                },
                                child: SqlCodeEditor(
                                  controller: sqlController,
                                  focusNode: focusNode,
                                  scrollController: editorScrollController,
                                  undoController: undoController,
                                  onChanged: onSqlChanged,
                                  zoomFactor: zoomFactor,
                                  indentSpaces: indentSpaces,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!autocompleteResult.isEmpty)
                        _AutocompletePopup(
                          result: autocompleteResult,
                          selectedIndex: selectedAutocompleteIndex,
                          editorTextStyle: editorStyle,
                          editorText: sqlController.text,
                          selection: sqlController.selection,
                          showLineNumbers: showLineNumbers,
                          editorScrollOffset: editorScrollController.hasClients
                              ? editorScrollController.offset
                              : 0,
                          maxWidth: constraints.maxWidth,
                          maxHeight: constraints.maxHeight,
                          onApply: onApplyAutocomplete,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: <Widget>[
                _StateChip(label: 'State ${activeTab.phase.name}'),
                const SizedBox(width: 8),
                if (activeTab.elapsed != null)
                  _StateChip(
                    label: 'Elapsed ${activeTab.elapsed!.inMilliseconds} ms',
                  ),
                const SizedBox(width: 8),
                if (editorContextLabel != null) ...<Widget>[
                  _StateChip(label: editorContextLabel!),
                  const SizedBox(width: 8),
                ],
                if (errorLocationLabel != null) ...<Widget>[
                  _StateChip(
                    label: 'Error $errorLocationLabel',
                    backgroundColor: tokens.colors.error.withValues(
                      alpha: 0.16,
                    ),
                    textColor: tokens.colors.error,
                  ),
                  const SizedBox(width: 8),
                ],
                _StateChip(label: 'Zoom ${(zoomFactor * 100).round()}%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _lineCount(String text) {
    if (text.isEmpty) {
      return 1;
    }
    return '\n'.allMatches(text).length + 1;
  }
}

class _FindBar extends StatelessWidget {
  const _FindBar({
    required this.controller,
    required this.focusNode,
    required this.statusLabel,
    required this.onChanged,
    required this.onFindNext,
    required this.onFindPrevious,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String statusLabel;
  final ValueChanged<String> onChanged;
  final VoidCallback onFindNext;
  final VoidCallback onFindPrevious;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: tokens.editor.currentLineBackground,
        border: Border(bottom: BorderSide(color: tokens.colors.border)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.search_outlined,
            size: tokens.metrics.iconSize + 2,
            color: tokens.editor.tabInactiveText,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 240,
            child: TextField(
              focusNode: focusNode,
              controller: controller,
              onChanged: onChanged,
              onSubmitted: (_) => onFindNext(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Find in editor',
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onFindPrevious,
            icon: const Icon(Icons.keyboard_arrow_up, size: 16),
            label: const Text('Prev'),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: onFindNext,
            icon: const Icon(Icons.keyboard_arrow_down, size: 16),
            label: const Text('Next'),
          ),
          const SizedBox(width: 12),
          Text(
            statusLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: tokens.fonts.editorFamily,
              color: tokens.editor.tabInactiveText,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Close find',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({
    required this.canRun,
    required this.canStop,
    required this.snippets,
    required this.onRunQuery,
    required this.onStopQuery,
    required this.onFormatSql,
    required this.onNewTab,
    required this.onInsertSnippet,
    required this.runLabel,
    required this.formatLabel,
    required this.onRunBuffer,
    required this.showRunBufferButton,
  });

  final bool canRun;
  final bool canStop;
  final List<SqlSnippet> snippets;
  final VoidCallback onRunQuery;
  final VoidCallback onStopQuery;
  final VoidCallback onFormatSql;
  final VoidCallback onNewTab;
  final ValueChanged<SqlSnippet> onInsertSnippet;
  final String runLabel;
  final String formatLabel;
  final VoidCallback onRunBuffer;
  final bool showRunBufferButton;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          onPressed: canRun ? onRunQuery : null,
          icon: Icon(Icons.play_arrow_rounded, size: tokens.metrics.iconSize),
          label: Text(runLabel),
        ),
        if (showRunBufferButton)
          OutlinedButton.icon(
            onPressed: canRun ? onRunBuffer : null,
            icon: Icon(Icons.subject_outlined, size: tokens.metrics.iconSize),
            label: const Text('Run Buffer'),
          ),
        OutlinedButton.icon(
          onPressed: canStop ? onStopQuery : null,
          icon: Icon(Icons.stop_rounded, size: tokens.metrics.iconSize),
          label: const Text('Stop'),
        ),
        OutlinedButton.icon(
          onPressed: onFormatSql,
          icon: Icon(
            Icons.auto_fix_high_rounded,
            size: tokens.metrics.iconSize,
          ),
          label: Text(formatLabel),
        ),
        OutlinedButton.icon(
          onPressed: onNewTab,
          icon: Icon(Icons.add_box_outlined, size: tokens.metrics.iconSize),
          label: const Text('New Tab'),
        ),
        PopupMenuButton<SqlSnippet>(
          tooltip: 'Insert snippet',
          onSelected: onInsertSnippet,
          itemBuilder: (context) {
            return <PopupMenuEntry<SqlSnippet>>[
              for (final snippet in snippets)
                PopupMenuItem<SqlSnippet>(
                  value: snippet,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(snippet.name),
                      Text(
                        snippet.trigger,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
            ];
          },
          child: IgnorePointer(
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: Icon(
                Icons.snippet_folder_outlined,
                size: tokens.metrics.iconSize,
              ),
              label: const Text('Snippets'),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.activeTabId,
    required this.onSelectTab,
    required this.onCloseTab,
  });

  final List<QueryTabState> tabs;
  final String activeTabId;
  final ValueChanged<String> onSelectTab;
  final Future<void> Function(String tabId) onCloseTab;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: tokens.editor.tabInactiveBackground,
        border: Border(bottom: BorderSide(color: tokens.colors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isActive = tab.id == activeTabId;
          final isMock = tab.id == 'mock-tab';
          return InkWell(
            onTap: isMock ? null : () => onSelectTab(tab.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: isActive
                    ? tokens.editor.tabActiveBackground
                    : tokens.editor.tabInactiveBackground,
                border: Border.all(color: tokens.colors.border),
                borderRadius: BorderRadius.circular(
                  tokens.metrics.borderRadius,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    tab.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isActive
                          ? tokens.editor.tabActiveText
                          : tokens.editor.tabInactiveText,
                    ),
                  ),
                  if (!isMock) ...<Widget>[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onCloseTab(tab.id),
                      child: Icon(
                        Icons.close,
                        size: tokens.metrics.iconSize - 2,
                        color: isActive
                            ? tokens.editor.tabActiveText
                            : tokens.editor.tabInactiveText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemCount: tabs.length,
      ),
    );
  }
}

class _LineNumberGutter extends StatelessWidget {
  const _LineNumberGutter({
    required this.lineCount,
    required this.controller,
    required this.zoomFactor,
    this.errorLineNumber,
    this.errorMessage,
  });

  final int lineCount;
  final ScrollController controller;
  final double zoomFactor;
  final int? errorLineNumber;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    final lineHeight =
        (tokens.fonts.editorSize * zoomFactor) * tokens.fonts.lineHeight;
    return Container(
      key: const ValueKey<String>('sql_editor.gutter'),
      width: kSqlEditorGutterWidth,
      color: tokens.editor.gutterBackground,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final offset = controller.hasClients ? controller.offset : 0.0;
            return Transform.translate(
              offset: Offset(0, -offset),
              child: Padding(
                padding: EdgeInsets.only(top: kSqlEditorContentPadding.top),
                child: Column(
                  children: <Widget>[
                    for (var index = 0; index < lineCount; index++)
                      Builder(
                        builder: (context) {
                          final isErrorLine = errorLineNumber == index + 1;
                          final row = Container(
                            height: lineHeight,
                            color: isErrorLine
                                ? tokens.colors.error.withValues(alpha: 0.14)
                                : null,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                if (isErrorLine)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.error_outline,
                                      size: 12,
                                      color: tokens.colors.error,
                                    ),
                                  ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Text(
                                    '${index + 1}',
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontSize:
                                          tokens.fonts.editorSize * zoomFactor -
                                          1,
                                      fontFamily: tokens.fonts.editorFamily,
                                      height: 1,
                                      color: isErrorLine
                                          ? tokens.colors.error
                                          : tokens.editor.gutterText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (!isErrorLine) {
                            return row;
                          }
                          return Tooltip(
                            message: errorMessage ?? 'Query error',
                            child: row,
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AutocompletePopup extends StatelessWidget {
  const _AutocompletePopup({
    required this.result,
    required this.selectedIndex,
    required this.editorTextStyle,
    required this.editorText,
    required this.selection,
    required this.showLineNumbers,
    required this.editorScrollOffset,
    required this.maxWidth,
    required this.maxHeight,
    required this.onApply,
  });

  final AutocompleteResult result;
  final int selectedIndex;
  final TextStyle editorTextStyle;
  final String editorText;
  final TextSelection selection;
  final bool showLineNumbers;
  final double editorScrollOffset;
  final double maxWidth;
  final double maxHeight;
  final ValueChanged<AutocompleteSuggestion> onApply;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    final popupWidth = maxWidth < 380 ? maxWidth - 16 : 360.0;
    final popupHeight = (result.suggestions.length.clamp(1, 6) * 40) + 34.0;
    final position = _popupOffset(
      popupWidth: popupWidth,
      popupHeight: popupHeight,
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        elevation: 6,
        color: tokens.editor.background,
        child: Container(
          width: popupWidth,
          constraints: BoxConstraints(maxHeight: popupHeight),
          decoration: BoxDecoration(
            color: tokens.editor.background,
            border: Border.all(color: tokens.colors.borderStrong),
            borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                color: tokens.editor.tabInactiveBackground,
                child: Text(
                  'Suggestions · Tab to accept',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.editor.tabInactiveText,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: result.suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = result.suggestions[index];
                    final selected = index == selectedIndex;
                    return InkWell(
                      onTap: () => onApply(suggestion),
                      child: Container(
                        color: selected
                            ? tokens.colors.selection
                            : tokens.editor.background,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              _iconForKind(suggestion.kind),
                              size: tokens.metrics.iconSize,
                              color: tokens.colors.accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    suggestion.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: tokens.editor.text,
                                        ),
                                  ),
                                  Text(
                                    suggestion.detail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: tokens.colors.textMuted,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Offset _popupOffset({
    required double popupWidth,
    required double popupHeight,
  }) {
    final clampedOffset = selection.isValid && selection.baseOffset >= 0
        ? selection.baseOffset.clamp(0, editorText.length).toInt()
        : editorText.length;
    final beforeCursor = editorText.substring(0, clampedOffset);
    final lastLineBreak = beforeCursor.lastIndexOf('\n');
    final lineIndex = '\n'.allMatches(beforeCursor).length;
    final columnIndex = beforeCursor.length - (lastLineBreak + 1);
    final lineHeight =
        (editorTextStyle.fontSize ?? 13) * (editorTextStyle.height ?? 1.4);
    final textPainter = TextPainter(
      text: TextSpan(text: 'M', style: editorTextStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final charWidth = textPainter.width;

    final rawLeft =
        (showLineNumbers ? kSqlEditorGutterWidth : 0) +
        kSqlEditorContentPadding.left +
        (columnIndex * charWidth);
    final rawTop =
        kSqlEditorContentPadding.top +
        (lineIndex * lineHeight) -
        editorScrollOffset +
        lineHeight;
    final clampedLeft = rawLeft
        .clamp(8.0, maxWidth - popupWidth - 8.0)
        .toDouble();
    final preferredTop = rawTop
        .clamp(8.0, maxHeight - popupHeight - 8.0)
        .toDouble();
    final fallbackTop = (rawTop - popupHeight - lineHeight)
        .clamp(8.0, maxHeight - popupHeight - 8.0)
        .toDouble();
    final finalTop = preferredTop > maxHeight - popupHeight - 8.0
        ? fallbackTop
        : preferredTop;
    return Offset(clampedLeft, finalTop);
  }
}

IconData _iconForKind(AutocompleteSuggestionKind kind) {
  return switch (kind) {
    AutocompleteSuggestionKind.object => Icons.table_rows_outlined,
    AutocompleteSuggestionKind.column => Icons.view_column_outlined,
    AutocompleteSuggestionKind.function => Icons.functions_outlined,
    AutocompleteSuggestionKind.keyword => Icons.key_outlined,
    AutocompleteSuggestionKind.snippet => Icons.code_outlined,
  };
}

class _AcceptAutocompleteIntent extends Intent {
  const _AcceptAutocompleteIntent();
}

class _NextAutocompleteIntent extends Intent {
  const _NextAutocompleteIntent();
}

class _PreviousAutocompleteIntent extends Intent {
  const _PreviousAutocompleteIntent();
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, this.backgroundColor, this.textColor});

  final String label;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? tokens.editor.tabInactiveBackground,
        border: Border.all(color: tokens.colors.border),
        borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: textColor ?? tokens.editor.tabInactiveText,
        ),
      ),
    );
  }
}
