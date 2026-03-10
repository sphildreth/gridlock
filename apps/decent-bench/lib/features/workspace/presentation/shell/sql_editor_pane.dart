import 'package:flutter/material.dart';

import '../../domain/app_config.dart';
import '../../domain/sql_autocomplete.dart';
import '../../domain/workspace_models.dart';
import 'shell_pane_frame.dart';

class SqlEditorPane extends StatelessWidget {
  const SqlEditorPane({
    super.key,
    required this.tabs,
    required this.activeTab,
    required this.sqlController,
    required this.paramsController,
    required this.editorScrollController,
    required this.focusNode,
    required this.autocompleteResult,
    required this.snippets,
    required this.zoomFactor,
    required this.onSqlChanged,
    required this.onParamsChanged,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onNewTab,
    required this.onRunQuery,
    required this.onStopQuery,
    required this.onFormatSql,
    required this.onInsertSnippet,
    required this.onManageSnippets,
    required this.onApplyAutocomplete,
    required this.canRun,
    required this.canStop,
  });

  final List<QueryTabState> tabs;
  final QueryTabState activeTab;
  final TextEditingController sqlController;
  final TextEditingController paramsController;
  final ScrollController editorScrollController;
  final FocusNode focusNode;
  final AutocompleteResult autocompleteResult;
  final List<SqlSnippet> snippets;
  final double zoomFactor;
  final ValueChanged<String> onSqlChanged;
  final ValueChanged<String> onParamsChanged;
  final ValueChanged<String> onSelectTab;
  final Future<void> Function(String tabId) onCloseTab;
  final VoidCallback onNewTab;
  final VoidCallback onRunQuery;
  final VoidCallback onStopQuery;
  final VoidCallback onFormatSql;
  final ValueChanged<SqlSnippet> onInsertSnippet;
  final VoidCallback onManageSnippets;
  final ValueChanged<AutocompleteSuggestion> onApplyAutocomplete;
  final bool canRun;
  final bool canStop;

  @override
  Widget build(BuildContext context) {
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
        onManageSnippets: onManageSnippets,
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
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: TextField(
              controller: paramsController,
              onChanged: onParamsChanged,
              style: TextStyle(fontSize: 12 * zoomFactor),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Parameters (JSON array)',
                hintText: '[1, "alice", true]',
              ),
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FA),
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  _LineNumberGutter(
                    lineCount: _lineCount(sqlController.text),
                    controller: editorScrollController,
                    zoomFactor: zoomFactor,
                  ),
                  Expanded(
                    child: TextField(
                      focusNode: focusNode,
                      controller: sqlController,
                      scrollController: editorScrollController,
                      onChanged: onSqlChanged,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontSize: 13 * zoomFactor,
                        fontFamily: 'monospace',
                        height: 1.45,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(16),
                        hintText: 'SELECT *\nFROM your_table\nLIMIT 100;',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!autocompleteResult.isEmpty)
            SizedBox(
              height: 144,
              child: _AutocompleteList(
                result: autocompleteResult,
                onApply: onApplyAutocomplete,
              ),
            )
          else
            const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(
              children: <Widget>[
                _StateChip(label: 'State ${activeTab.phase.name}'),
                const SizedBox(width: 8),
                if (activeTab.elapsed != null)
                  _StateChip(
                    label: 'Elapsed ${activeTab.elapsed!.inMilliseconds} ms',
                  ),
                const SizedBox(width: 8),
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
    required this.onManageSnippets,
  });

  final bool canRun;
  final bool canStop;
  final List<SqlSnippet> snippets;
  final VoidCallback onRunQuery;
  final VoidCallback onStopQuery;
  final VoidCallback onFormatSql;
  final VoidCallback onNewTab;
  final ValueChanged<SqlSnippet> onInsertSnippet;
  final VoidCallback onManageSnippets;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.icon(
          onPressed: canRun ? onRunQuery : null,
          icon: const Icon(Icons.play_arrow_rounded, size: 16),
          label: const Text('Run'),
        ),
        OutlinedButton.icon(
          onPressed: canStop ? onStopQuery : null,
          icon: const Icon(Icons.stop_rounded, size: 16),
          label: const Text('Stop'),
        ),
        OutlinedButton.icon(
          onPressed: onFormatSql,
          icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
          label: const Text('Format'),
        ),
        OutlinedButton.icon(
          onPressed: onNewTab,
          icon: const Icon(Icons.add_box_outlined, size: 16),
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
              icon: const Icon(Icons.snippet_folder_outlined, size: 16),
              label: const Text('Snippets'),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onManageSnippets,
          icon: const Icon(Icons.library_books_outlined, size: 16),
          label: const Text('Manage'),
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
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
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
                    ? Theme.of(context).colorScheme.surface
                    : Colors.transparent,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Text(tab.title),
                  if (!isMock) ...<Widget>[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => onCloseTab(tab.id),
                      child: const Icon(Icons.close, size: 14),
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
  });

  final int lineCount;
  final ScrollController controller;
  final double zoomFactor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      color: const Color(0xFFE9EEF5),
      child: ClipRect(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final offset = controller.hasClients ? controller.offset : 0.0;
            return Transform.translate(
              offset: Offset(0, -offset),
              child: Column(
                children: <Widget>[
                  for (var index = 0; index < lineCount; index++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 2, 8, 2),
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12 * zoomFactor,
                          fontFamily: 'monospace',
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AutocompleteList extends StatelessWidget {
  const _AutocompleteList({required this.result, required this.onApply});

  final AutocompleteResult result;
  final ValueChanged<AutocompleteSuggestion> onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              'Autocomplete',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: result.suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = result.suggestions[index];
                return ListTile(
                  dense: true,
                  onTap: () => onApply(suggestion),
                  leading: Icon(_iconForKind(suggestion.kind), size: 16),
                  title: Text(suggestion.label),
                  subtitle: Text(suggestion.detail),
                );
              },
            ),
          ),
        ],
      ),
    );
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
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
