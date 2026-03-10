import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/workspace_models.dart';
import '../../domain/workspace_shell_preferences.dart';
import 'shell_pane_frame.dart';

class ResultsGridCellSelection {
  const ResultsGridCellSelection({
    required this.rowIndex,
    required this.columnName,
  });

  final int rowIndex;
  final String columnName;
}

class ResultsGridInteractionState {
  const ResultsGridInteractionState({
    this.selectedRows = const <int>{},
    this.selectedCell,
    this.pinnedColumns = const <String>{},
  });

  final Set<int> selectedRows;
  final ResultsGridCellSelection? selectedCell;
  final Set<String> pinnedColumns;

  ResultsGridInteractionState copyWith({
    Set<int>? selectedRows,
    Object? selectedCell = _unset,
    Set<String>? pinnedColumns,
  }) {
    return ResultsGridInteractionState(
      selectedRows: selectedRows ?? this.selectedRows,
      selectedCell: selectedCell == _unset
          ? this.selectedCell
          : selectedCell as ResultsGridCellSelection?,
      pinnedColumns: pinnedColumns ?? this.pinnedColumns,
    );
  }

  static const Object _unset = Object();
}

List<String> resolveResultsColumns(QueryTabState tab) {
  if (tab.resultColumns.isNotEmpty) {
    return tab.resultColumns;
  }
  return const <String>['id', 'name', 'region', 'total'];
}

List<Map<String, Object?>> resolveResultsRows(QueryTabState tab) {
  if (tab.resultRows.isNotEmpty) {
    return tab.resultRows;
  }
  return const <Map<String, Object?>>[
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
  ];
}

class ResultsPane extends StatelessWidget {
  const ResultsPane({
    super.key,
    required this.activeTab,
    required this.activeResultsTab,
    required this.verticalScrollController,
    required this.horizontalScrollController,
    required this.interactionState,
    required this.onResultsTabChanged,
    required this.onLoadNextPage,
    required this.onSelectCell,
    required this.onSelectRow,
    required this.onTogglePinnedColumn,
  });

  final QueryTabState activeTab;
  final ResultsPaneTab activeResultsTab;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final ResultsGridInteractionState interactionState;
  final ValueChanged<ResultsPaneTab> onResultsTabChanged;
  final VoidCallback onLoadNextPage;
  final void Function(int rowIndex, String columnName) onSelectCell;
  final ValueChanged<int> onSelectRow;
  final ValueChanged<String> onTogglePinnedColumn;

  @override
  Widget build(BuildContext context) {
    return ShellPaneFrame(
      title: 'Results Window',
      subtitle: _subtitle(),
      leadingIcon: Icons.table_view_outlined,
      toolbar: _ResultsToolbar(
        activeTab: activeTab,
        pinnedColumnCount: interactionState.pinnedColumns.length,
        selectedRowCount: interactionState.selectedRows.length,
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
                interactionState: interactionState,
                verticalScrollController: verticalScrollController,
                horizontalScrollController: horizontalScrollController,
                onLoadNextPage: onLoadNextPage,
                onSelectCell: onSelectCell,
                onSelectRow: onSelectRow,
                onTogglePinnedColumn: onTogglePinnedColumn,
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
    required this.activeTab,
    required this.pinnedColumnCount,
    required this.selectedRowCount,
  });

  final QueryTabState activeTab;
  final int pinnedColumnCount;
  final int selectedRowCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        _InfoBadge(
          icon: Icons.push_pin_outlined,
          label: 'Pinned $pinnedColumnCount',
        ),
        _InfoBadge(
          icon: Icons.select_all_outlined,
          label: 'Rows $selectedRowCount',
        ),
        _InfoBadge(
          icon: Icons.chat_bubble_outline,
          label: 'Messages ${activeTab.messageHistory.length}',
        ),
        _InfoBadge(
          icon: activeTab.hasMoreRows
              ? Icons.unfold_more_outlined
              : Icons.check_circle_outline,
          label: activeTab.hasMoreRows ? 'More rows available' : 'Page loaded',
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

class _ResultsGrid extends StatefulWidget {
  const _ResultsGrid({
    required this.tab,
    required this.interactionState,
    required this.verticalScrollController,
    required this.horizontalScrollController,
    required this.onLoadNextPage,
    required this.onSelectCell,
    required this.onSelectRow,
    required this.onTogglePinnedColumn,
  });

  final QueryTabState tab;
  final ResultsGridInteractionState interactionState;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final VoidCallback onLoadNextPage;
  final void Function(int rowIndex, String columnName) onSelectCell;
  final ValueChanged<int> onSelectRow;
  final ValueChanged<String> onTogglePinnedColumn;

  @override
  State<_ResultsGrid> createState() => _ResultsGridState();
}

class _ResultsGridState extends State<_ResultsGrid> {
  static const double _rowHeight = 36;
  static const double _rowHeaderWidth = 56;
  static const double _columnWidth = 180;

  final ScrollController _pinnedVerticalController = ScrollController();
  bool _syncingVertical = false;

  @override
  void initState() {
    super.initState();
    widget.verticalScrollController.addListener(_syncFromScrollable);
    _pinnedVerticalController.addListener(_syncFromPinned);
  }

  @override
  void didUpdateWidget(covariant _ResultsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verticalScrollController != widget.verticalScrollController) {
      oldWidget.verticalScrollController.removeListener(_syncFromScrollable);
      widget.verticalScrollController.addListener(_syncFromScrollable);
    }
  }

  @override
  void dispose() {
    widget.verticalScrollController.removeListener(_syncFromScrollable);
    _pinnedVerticalController
      ..removeListener(_syncFromPinned)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final columns = resolveResultsColumns(widget.tab);
    final rows = resolveResultsRows(widget.tab);
    final pinnedColumns = <String>[
      for (final column in columns)
        if (widget.interactionState.pinnedColumns.contains(column)) column,
    ];
    final remainingColumns = <String>[
      for (final column in columns)
        if (!widget.interactionState.pinnedColumns.contains(column)) column,
    ];
    final pinnedWidth =
        _rowHeaderWidth + (pinnedColumns.length * _columnWidth).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollableWidth = math.max(
          constraints.maxWidth - pinnedWidth,
          220,
        );
        final unpinnedContentWidth = math.max(
          scrollableWidth,
          remainingColumns.length * _columnWidth,
        );

        return Column(
          children: <Widget>[
            Expanded(
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: pinnedWidth,
                    child: Column(
                      children: <Widget>[
                        SizedBox(
                          height: _rowHeight,
                          child: Row(
                            children: <Widget>[
                              _RowHeaderCell(
                                label: '#',
                                isHeader: true,
                                width: _rowHeaderWidth,
                              ),
                              for (final column in pinnedColumns)
                                _GridCell(
                                  text: column,
                                  isHeader: true,
                                  width: _columnWidth,
                                  pinned: true,
                                  onPinToggle: () =>
                                      widget.onTogglePinnedColumn(column),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: _pinnedVerticalController,
                            itemExtent: _rowHeight,
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final rowSelected = widget
                                  .interactionState
                                  .selectedRows
                                  .contains(index);
                              return Row(
                                children: <Widget>[
                                  _RowHeaderCell(
                                    label: '${index + 1}',
                                    width: _rowHeaderWidth,
                                    selected: rowSelected,
                                    onTap: () => widget.onSelectRow(index),
                                  ),
                                  for (final column in pinnedColumns)
                                    _GridCell(
                                      text: formatCellValue(row[column]),
                                      width: _columnWidth,
                                      pinned: true,
                                      selected: _isCellSelected(index, column),
                                      rowSelected: rowSelected,
                                      onTap: () =>
                                          widget.onSelectCell(index, column),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: widget.horizontalScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: widget.horizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: unpinnedContentWidth.toDouble(),
                          child: Column(
                            children: <Widget>[
                              SizedBox(
                                height: _rowHeight,
                                child: Row(
                                  children: <Widget>[
                                    for (final column in remainingColumns)
                                      _GridCell(
                                        text: column,
                                        isHeader: true,
                                        width: _columnWidth,
                                        pinned: false,
                                        onPinToggle: () =>
                                            widget.onTogglePinnedColumn(column),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  controller: widget.verticalScrollController,
                                  itemExtent: _rowHeight,
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) {
                                    final row = rows[index];
                                    final rowSelected = widget
                                        .interactionState
                                        .selectedRows
                                        .contains(index);
                                    return Row(
                                      children: <Widget>[
                                        for (final column in remainingColumns)
                                          _GridCell(
                                            text: formatCellValue(row[column]),
                                            width: _columnWidth,
                                            selected: _isCellSelected(
                                              index,
                                              column,
                                            ),
                                            rowSelected: rowSelected,
                                            onTap: () => widget.onSelectCell(
                                              index,
                                              column,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.tab.hasMoreRows)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: widget.onLoadNextPage,
                    icon: const Icon(Icons.expand_more),
                    label: Text(
                      widget.tab.phase == QueryPhase.fetching
                          ? 'Loading...'
                          : 'Load next page',
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  bool _isCellSelected(int rowIndex, String columnName) {
    final cell = widget.interactionState.selectedCell;
    return cell != null &&
        cell.rowIndex == rowIndex &&
        cell.columnName == columnName;
  }

  void _syncFromScrollable() {
    if (_syncingVertical ||
        !widget.verticalScrollController.hasClients ||
        !_pinnedVerticalController.hasClients) {
      return;
    }
    _syncingVertical = true;
    _pinnedVerticalController.jumpTo(
      widget.verticalScrollController.offset.clamp(
        0,
        _pinnedVerticalController.position.maxScrollExtent,
      ),
    );
    _syncingVertical = false;
  }

  void _syncFromPinned() {
    if (_syncingVertical ||
        !_pinnedVerticalController.hasClients ||
        !widget.verticalScrollController.hasClients) {
      return;
    }
    _syncingVertical = true;
    widget.verticalScrollController.jumpTo(
      _pinnedVerticalController.offset.clamp(
        0,
        widget.verticalScrollController.position.maxScrollExtent,
      ),
    );
    _syncingVertical = false;
  }
}

class _GridCell extends StatelessWidget {
  const _GridCell({
    required this.text,
    required this.width,
    this.isHeader = false,
    this.selected = false,
    this.rowSelected = false,
    this.pinned = false,
    this.onTap,
    this.onPinToggle,
  });

  final String text;
  final double width;
  final bool isHeader;
  final bool selected;
  final bool rowSelected;
  final bool pinned;
  final VoidCallback? onTap;
  final VoidCallback? onPinToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = isHeader
        ? theme.colorScheme.surfaceContainerHighest
        : selected
        ? theme.colorScheme.secondaryContainer
        : rowSelected
        ? theme.colorScheme.surfaceContainerLow
        : theme.colorScheme.surface;

    final child = Container(
      width: width,
      padding: EdgeInsets.symmetric(
        horizontal: isHeader ? 8 : 10,
        vertical: isHeader ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: isHeader
          ? Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: pinned ? 'Unpin column' : 'Pin column',
                  onPressed: onPinToggle,
                  icon: Icon(
                    pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 14,
                  ),
                ),
              ],
            )
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
    );

    if (isHeader || onTap == null) {
      return child;
    }
    return InkWell(onTap: onTap, child: child);
  }
}

class _RowHeaderCell extends StatelessWidget {
  const _RowHeaderCell({
    required this.label,
    required this.width,
    this.isHeader = false,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final double width;
  final bool isHeader;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isHeader
            ? theme.colorScheme.surfaceContainerHighest
            : selected
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      alignment: Alignment.centerRight,
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontWeight: isHeader || selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
    if (isHeader || onTap == null) {
      return child;
    }
    return InkWell(onTap: onTap, child: child);
  }
}

class _MessagesPanel extends StatelessWidget {
  const _MessagesPanel({required this.tab});

  final QueryTabState tab;

  @override
  Widget build(BuildContext context) {
    final messages = tab.messageHistory.isNotEmpty
        ? tab.messageHistory.reversed.toList()
        : <QueryMessageEntry>[
            QueryMessageEntry(
              level: QueryMessageLevel.info,
              message:
                  'Ready. Execute a query to capture elapsed time, row counts, and warnings.',
              timestamp: DateTime.now(),
            ),
          ];
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final entry = messages[index];
        return Container(
          padding: const EdgeInsets.all(10),
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _MessageLevelBadge(level: entry.level),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _formatTimestamp(entry.timestamp),
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(entry.message),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final local = timestamp.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    final second = local.second.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hour:$minute:$second';
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
          'Execution plan visualizer is not implemented yet.\n'
          'The pane remains docked so message history, grid interactions, and result workflows can be used without changing the layout.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
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

class _MessageLevelBadge extends StatelessWidget {
  const _MessageLevelBadge({required this.level});

  final QueryMessageLevel level;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (level) {
      QueryMessageLevel.info => ('INFO', Theme.of(context).colorScheme.primary),
      QueryMessageLevel.warning => ('WARN', const Color(0xFFB26A00)),
      QueryMessageLevel.error => ('ERROR', Theme.of(context).colorScheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: color)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
