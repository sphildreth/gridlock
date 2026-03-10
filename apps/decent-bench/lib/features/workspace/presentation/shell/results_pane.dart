import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/workspace_models.dart';
import '../../domain/workspace_shell_preferences.dart';
import 'shell_pane_frame.dart';

class ResultsPane extends StatelessWidget {
  const ResultsPane({
    super.key,
    required this.activeTab,
    required this.activeResultsTab,
    required this.exportPathController,
    required this.delimiterController,
    required this.verticalScrollController,
    required this.horizontalScrollController,
    required this.csvIncludeHeaders,
    required this.onResultsTabChanged,
    required this.onExportPathChanged,
    required this.onDelimiterSubmitted,
    required this.onHeadersChanged,
    required this.onExportCsv,
    required this.onLoadNextPage,
  });

  final QueryTabState activeTab;
  final ResultsPaneTab activeResultsTab;
  final TextEditingController exportPathController;
  final TextEditingController delimiterController;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final bool csvIncludeHeaders;
  final ValueChanged<ResultsPaneTab> onResultsTabChanged;
  final ValueChanged<String> onExportPathChanged;
  final ValueChanged<String> onDelimiterSubmitted;
  final ValueChanged<bool> onHeadersChanged;
  final VoidCallback onExportCsv;
  final VoidCallback onLoadNextPage;

  @override
  Widget build(BuildContext context) {
    return ShellPaneFrame(
      title: 'Results Window',
      subtitle: _subtitle(),
      leadingIcon: Icons.table_view_outlined,
      toolbar: _ResultsToolbar(
        exportPathController: exportPathController,
        delimiterController: delimiterController,
        csvIncludeHeaders: csvIncludeHeaders,
        isExporting: activeTab.isExporting,
        onExportPathChanged: onExportPathChanged,
        onDelimiterSubmitted: onDelimiterSubmitted,
        onHeadersChanged: onHeadersChanged,
        onExportCsv: onExportCsv,
      ),
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          _ResultsSubtabs(
            selectedTab: activeResultsTab,
            onSelected: onResultsTabChanged,
          ),
          Expanded(
            child: switch (activeResultsTab) {
              ResultsPaneTab.results => _ResultsGrid(
                tab: activeTab,
                verticalScrollController: verticalScrollController,
                horizontalScrollController: horizontalScrollController,
                onLoadNextPage: onLoadNextPage,
              ),
              ResultsPaneTab.messages => _MessagesPanel(tab: activeTab),
              ResultsPaneTab.executionPlan => const _ExecutionPlanPanel(),
            },
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    if (activeTab.resultColumns.isNotEmpty) {
      return '${activeTab.resultRows.length} rows loaded';
    }
    if (activeTab.rowsAffected != null) {
      return '${activeTab.rowsAffected} rows affected';
    }
    return 'Messages, data, and execution placeholders';
  }
}

class _ResultsToolbar extends StatelessWidget {
  const _ResultsToolbar({
    required this.exportPathController,
    required this.delimiterController,
    required this.csvIncludeHeaders,
    required this.isExporting,
    required this.onExportPathChanged,
    required this.onDelimiterSubmitted,
    required this.onHeadersChanged,
    required this.onExportCsv,
  });

  final TextEditingController exportPathController;
  final TextEditingController delimiterController;
  final bool csvIncludeHeaders;
  final bool isExporting;
  final ValueChanged<String> onExportPathChanged;
  final ValueChanged<String> onDelimiterSubmitted;
  final ValueChanged<bool> onHeadersChanged;
  final VoidCallback onExportCsv;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: exportPathController,
                onChanged: onExportPathChanged,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Export path',
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextField(
                controller: delimiterController,
                onSubmitted: onDelimiterSubmitted,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Delim',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('Headers'),
              selected: csvIncludeHeaders,
              onSelected: onHeadersChanged,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isExporting ? null : onExportCsv,
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text(isExporting ? 'Exporting' : 'Export CSV'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: const <Widget>[
            _FormatBadge(icon: Icons.data_object, label: 'JSON'),
            _FormatBadge(icon: Icons.view_column, label: 'Parquet'),
            _FormatBadge(icon: Icons.table_chart, label: 'Excel'),
          ],
        ),
      ],
    );
  }
}

class _ResultsSubtabs extends StatelessWidget {
  const _ResultsSubtabs({required this.selectedTab, required this.onSelected});

  final ResultsPaneTab selectedTab;
  final ValueChanged<ResultsPaneTab> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          _ResultTabButton(
            label: 'Results',
            selected: selectedTab == ResultsPaneTab.results,
            onTap: () => onSelected(ResultsPaneTab.results),
          ),
          _ResultTabButton(
            label: 'Messages',
            selected: selectedTab == ResultsPaneTab.messages,
            onTap: () => onSelected(ResultsPaneTab.messages),
          ),
          _ResultTabButton(
            label: 'Execution Plan',
            selected: selectedTab == ResultsPaneTab.executionPlan,
            onTap: () => onSelected(ResultsPaneTab.executionPlan),
          ),
        ],
      ),
    );
  }
}

class _ResultTabButton extends StatelessWidget {
  const _ResultTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).colorScheme.surface : null,
          border: Border(
            right: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            bottom: selected
                ? BorderSide.none
                : BorderSide(color: Colors.transparent),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({
    required this.tab,
    required this.verticalScrollController,
    required this.horizontalScrollController,
    required this.onLoadNextPage,
  });

  final QueryTabState tab;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final VoidCallback onLoadNextPage;

  @override
  Widget build(BuildContext context) {
    final columns = tab.resultColumns.isEmpty
        ? const <String>['id', 'name', 'region', 'total']
        : tab.resultColumns;
    final rows = tab.resultRows.isEmpty
        ? const <Map<String, Object?>>[
            <String, Object?>{
              'id': 1,
              'name': 'Northwind Trading',
              'region': 'Midwest',
              'total': 1420.50,
            },
            <String, Object?>{
              'id': 2,
              'name': 'Oceanic Logistics',
              'region': 'West',
              'total': 995.00,
            },
            <String, Object?>{
              'id': 3,
              'name': 'Summit Foods',
              'region': 'South',
              'total': 128.75,
            },
          ]
        : tab.resultRows;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.max(constraints.maxWidth, columns.length * 180);
        return Scrollbar(
          controller: horizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width.toDouble(),
              child: Column(
                children: <Widget>[
                  Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: Row(
                      children: <Widget>[
                        for (final column in columns)
                          _GridCell(text: column, isHeader: true, width: 180),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: verticalScrollController,
                      itemCount: rows.length + (tab.hasMoreRows ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= rows.length) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: onLoadNextPage,
                                icon: const Icon(Icons.expand_more),
                                label: Text(
                                  tab.phase == QueryPhase.fetching
                                      ? 'Loading...'
                                      : 'Load next page',
                                ),
                              ),
                            ),
                          );
                        }
                        final row = rows[index];
                        final zebra = index.isEven;
                        return Container(
                          color: zebra
                              ? Theme.of(context).colorScheme.surface
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLowest,
                          child: Row(
                            children: <Widget>[
                              for (final column in columns)
                                _GridCell(
                                  text: formatCellValue(row[column]),
                                  width: 180,
                                ),
                            ],
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
      },
    );
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.text,
    required this.width,
    this.isHeader = false,
  });

  final String text;
  final double width;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Text(
        text,
        style: isHeader
            ? Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)
            : Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}

class _MessagesPanel extends StatelessWidget {
  const _MessagesPanel({required this.tab});

  final QueryTabState tab;

  @override
  Widget build(BuildContext context) {
    final messages = <String>[
      if (tab.statusMessage != null) tab.statusMessage!,
      if (tab.error != null)
        '${tab.error!.stageLabel}: ${tab.error!.message}'
      else if (tab.statusMessage == null)
        'Ready. Execute a query to capture elapsed time, row counts, and warnings.',
      if (tab.elapsed != null)
        'Last execution: ${tab.elapsed!.inMilliseconds} ms',
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        for (final message in messages)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Text(message),
          ),
      ],
    );
  }
}

class _ExecutionPlanPanel extends StatelessWidget {
  const _ExecutionPlanPanel();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Execution plan visualizer is a placeholder in this shell proof.\n'
          'The pane is intentionally present so menu layout, docking, and status behavior can be evaluated now.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
