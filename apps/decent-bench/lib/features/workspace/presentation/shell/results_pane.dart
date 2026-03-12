import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../../../app/theme_system/decent_bench_theme_extension.dart';
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

  ResultsGridCellKey get key =>
      ResultsGridCellKey(rowIndex: rowIndex, columnName: columnName);
}

class ResultsGridCellKey {
  const ResultsGridCellKey({required this.rowIndex, required this.columnName});

  final int rowIndex;
  final String columnName;

  @override
  bool operator ==(Object other) {
    return other is ResultsGridCellKey &&
        other.rowIndex == rowIndex &&
        other.columnName == columnName;
  }

  @override
  int get hashCode => Object.hash(rowIndex, columnName);
}

class ResultsGridInteractionState {
  const ResultsGridInteractionState({
    this.selectedRows = const <int>{},
    this.selectedCell,
    this.pinnedColumns = const <String>{},
    this.cellOverrides = const <ResultsGridCellKey, Object?>{},
    this.executionGeneration = 0,
  });

  final Set<int> selectedRows;
  final ResultsGridCellSelection? selectedCell;
  final Set<String> pinnedColumns;
  final Map<ResultsGridCellKey, Object?> cellOverrides;
  final int executionGeneration;

  ResultsGridInteractionState copyWith({
    Set<int>? selectedRows,
    Object? selectedCell = _unset,
    Set<String>? pinnedColumns,
    Map<ResultsGridCellKey, Object?>? cellOverrides,
    int? executionGeneration,
  }) {
    return ResultsGridInteractionState(
      selectedRows: selectedRows ?? this.selectedRows,
      selectedCell: selectedCell == _unset
          ? this.selectedCell
          : selectedCell as ResultsGridCellSelection?,
      pinnedColumns: pinnedColumns ?? this.pinnedColumns,
      cellOverrides: cellOverrides ?? this.cellOverrides,
      executionGeneration: executionGeneration ?? this.executionGeneration,
    );
  }

  static const Object _unset = Object();
}

List<String> resolveResultsColumns(
  QueryTabState tab, {
  bool usePlaceholderContent = true,
}) {
  if (tab.resultColumns.isNotEmpty) {
    return tab.resultColumns;
  }
  if (!usePlaceholderContent) {
    return const <String>[];
  }
  return const <String>['id', 'name', 'region', 'total'];
}

List<Map<String, Object?>> resolveResultsRows(
  QueryTabState tab, {
  bool usePlaceholderContent = true,
}) {
  if (tab.resultRows.isNotEmpty) {
    return tab.resultRows;
  }
  if (!usePlaceholderContent) {
    return const <Map<String, Object?>>[];
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

Object? resolveResultsCellValue(
  QueryTabState tab,
  ResultsGridInteractionState state,
  int rowIndex,
  String columnName, {
  bool usePlaceholderContent = true,
}) {
  final key = ResultsGridCellKey(rowIndex: rowIndex, columnName: columnName);
  if (state.cellOverrides.containsKey(key)) {
    return state.cellOverrides[key];
  }
  final rows = resolveResultsRows(
    tab,
    usePlaceholderContent: usePlaceholderContent,
  );
  if (rowIndex < 0 || rowIndex >= rows.length) {
    return null;
  }
  return rows[rowIndex][columnName];
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
    required this.onShowCellMenu,
    required this.onSelectRow,
    required this.onTogglePinnedColumn,
    required this.usePlaceholderContent,
  });

  final QueryTabState activeTab;
  final ResultsPaneTab activeResultsTab;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final ResultsGridInteractionState interactionState;
  final ValueChanged<ResultsPaneTab> onResultsTabChanged;
  final VoidCallback onLoadNextPage;
  final void Function(int rowIndex, String columnName) onSelectCell;
  final void Function(int rowIndex, String columnName, Offset globalPosition)
  onShowCellMenu;
  final ValueChanged<int> onSelectRow;
  final ValueChanged<String> onTogglePinnedColumn;
  final bool usePlaceholderContent;

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
                onShowCellMenu: onShowCellMenu,
                onSelectRow: onSelectRow,
                onTogglePinnedColumn: onTogglePinnedColumn,
                usePlaceholderContent: usePlaceholderContent,
              ),
              ResultsPaneTab.messages => _MessagesPanel(tab: activeTab),
              ResultsPaneTab.executionPlan => _ExecutionPlanPanel(
                tab: activeTab,
              ),
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
    return 'Messages, data, and EXPLAIN output';
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
    final tokens = context.decentBenchTheme;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: tokens.resultsGrid.headerBackground,
        border: Border(bottom: BorderSide(color: tokens.resultsGrid.gridLine)),
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
    final tokens = context.decentBenchTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? tokens.resultsGrid.background
              : tokens.resultsGrid.headerBackground,
          border: Border(
            right: BorderSide(color: tokens.resultsGrid.gridLine),
            bottom: selected
                ? BorderSide.none
                : BorderSide(color: Colors.transparent),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: selected
                ? tokens.resultsGrid.cellText
                : tokens.resultsGrid.headerText,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
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
    required this.onShowCellMenu,
    required this.onSelectRow,
    required this.onTogglePinnedColumn,
    required this.usePlaceholderContent,
  });

  final QueryTabState tab;
  final ResultsGridInteractionState interactionState;
  final ScrollController verticalScrollController;
  final ScrollController horizontalScrollController;
  final VoidCallback onLoadNextPage;
  final void Function(int rowIndex, String columnName) onSelectCell;
  final void Function(int rowIndex, String columnName, Offset globalPosition)
  onShowCellMenu;
  final ValueChanged<int> onSelectRow;
  final ValueChanged<String> onTogglePinnedColumn;
  final bool usePlaceholderContent;

  @override
  State<_ResultsGrid> createState() => _ResultsGridState();
}

class _ResultsGridState extends State<_ResultsGrid> {
  static const double _rowHeight = 36;
  static const double _rowHeaderWidth = 56;
  static const double _columnWidth = 180;
  static const double _minColumnWidth = 96;

  final ScrollController _pinnedVerticalController = ScrollController();
  final Map<String, double> _columnWidths = <String, double>{};
  bool _syncingVertical = false;

  @override
  void initState() {
    super.initState();
    widget.verticalScrollController.addListener(_syncFromScrollable);
    _pinnedVerticalController.addListener(_syncFromPinned);
    _pruneColumnWidths();
  }

  @override
  void didUpdateWidget(covariant _ResultsGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.verticalScrollController != widget.verticalScrollController) {
      oldWidget.verticalScrollController.removeListener(_syncFromScrollable);
      widget.verticalScrollController.addListener(_syncFromScrollable);
    }
    if (oldWidget.interactionState.executionGeneration !=
        widget.interactionState.executionGeneration) {
      _columnWidths.clear();
    }
    _pruneColumnWidths();
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
    final columns = resolveResultsColumns(
      widget.tab,
      usePlaceholderContent: widget.usePlaceholderContent,
    );
    final rows = resolveResultsRows(
      widget.tab,
      usePlaceholderContent: widget.usePlaceholderContent,
    );
    final pinnedColumns = <String>[
      for (final column in columns)
        if (widget.interactionState.pinnedColumns.contains(column)) column,
    ];
    final remainingColumns = <String>[
      for (final column in columns)
        if (!widget.interactionState.pinnedColumns.contains(column)) column,
    ];
    final pinnedWidth =
        _rowHeaderWidth +
        pinnedColumns.fold<double>(0, (sum, column) => sum + _widthFor(column));

    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollableWidth = math.max(
          constraints.maxWidth - pinnedWidth,
          220,
        );
        final unpinnedContentWidth = math.max(
          scrollableWidth,
          remainingColumns.fold<double>(
            0,
            (sum, column) => sum + _widthFor(column),
          ),
        );

        if (columns.isEmpty && rows.isEmpty) {
          return _ResultsEmptyState(
            tab: widget.tab,
            usePlaceholderContent: widget.usePlaceholderContent,
          );
        }

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
                                  key: ValueKey<String>(
                                    'results.header.$column',
                                  ),
                                  text: column,
                                  isHeader: true,
                                  width: _widthFor(column),
                                  pinned: true,
                                  onPinToggle: () =>
                                      widget.onTogglePinnedColumn(column),
                                  onResize: (delta) =>
                                      _resizeColumn(column, delta),
                                  resizeHandleKey: ValueKey<String>(
                                    'results.resize.$column',
                                  ),
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
                                      text: formatCellValue(
                                        resolveResultsCellValue(
                                          widget.tab,
                                          widget.interactionState,
                                          index,
                                          column,
                                          usePlaceholderContent:
                                              widget.usePlaceholderContent,
                                        ),
                                      ),
                                      width: _widthFor(column),
                                      pinned: true,
                                      selected: _isCellSelected(index, column),
                                      rowSelected: rowSelected,
                                      edited: _isCellEdited(index, column),
                                      onTap: () =>
                                          widget.onSelectCell(index, column),
                                      onSecondaryTapDown: (position) =>
                                          widget.onShowCellMenu(
                                            index,
                                            column,
                                            position,
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
                                        key: ValueKey<String>(
                                          'results.header.$column',
                                        ),
                                        text: column,
                                        isHeader: true,
                                        width: _widthFor(column),
                                        pinned: false,
                                        onPinToggle: () =>
                                            widget.onTogglePinnedColumn(column),
                                        onResize: (delta) =>
                                            _resizeColumn(column, delta),
                                        resizeHandleKey: ValueKey<String>(
                                          'results.resize.$column',
                                        ),
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
                                    final rowSelected = widget
                                        .interactionState
                                        .selectedRows
                                        .contains(index);
                                    return Row(
                                      children: <Widget>[
                                        for (final column in remainingColumns)
                                          _GridCell(
                                            text: formatCellValue(
                                              resolveResultsCellValue(
                                                widget.tab,
                                                widget.interactionState,
                                                index,
                                                column,
                                                usePlaceholderContent: widget
                                                    .usePlaceholderContent,
                                              ),
                                            ),
                                            width: _widthFor(column),
                                            selected: _isCellSelected(
                                              index,
                                              column,
                                            ),
                                            rowSelected: rowSelected,
                                            edited: _isCellEdited(
                                              index,
                                              column,
                                            ),
                                            onTap: () => widget.onSelectCell(
                                              index,
                                              column,
                                            ),
                                            onSecondaryTapDown: (position) =>
                                                widget.onShowCellMenu(
                                                  index,
                                                  column,
                                                  position,
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

  bool _isCellEdited(int rowIndex, String columnName) {
    return widget.interactionState.cellOverrides.containsKey(
      ResultsGridCellKey(rowIndex: rowIndex, columnName: columnName),
    );
  }

  double _widthFor(String columnName) =>
      _columnWidths[columnName] ?? _columnWidth;

  void _resizeColumn(String columnName, double delta) {
    setState(() {
      _columnWidths[columnName] = math.max(
        _minColumnWidth,
        _widthFor(columnName) + delta,
      );
    });
  }

  void _pruneColumnWidths() {
    final columns = resolveResultsColumns(
      widget.tab,
      usePlaceholderContent: widget.usePlaceholderContent,
    ).toSet();
    _columnWidths.removeWhere((column, _) => !columns.contains(column));
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
    super.key,
    required this.text,
    required this.width,
    this.isHeader = false,
    this.selected = false,
    this.rowSelected = false,
    this.edited = false,
    this.pinned = false,
    this.onTap,
    this.onSecondaryTapDown,
    this.onPinToggle,
    this.onResize,
    this.resizeHandleKey,
  });

  final String text;
  final double width;
  final bool isHeader;
  final bool selected;
  final bool rowSelected;
  final bool edited;
  final bool pinned;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onSecondaryTapDown;
  final VoidCallback? onPinToggle;
  final ValueChanged<double>? onResize;
  final Key? resizeHandleKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.decentBenchTheme;
    final background = isHeader
        ? tokens.resultsGrid.headerBackground
        : selected
        ? tokens.resultsGrid.rowSelectedBackground
        : edited
        ? tokens.colors.warning.withValues(alpha: 0.18)
        : rowSelected
        ? tokens.resultsGrid.rowAltBackground
        : tokens.resultsGrid.rowBackground;

    final child = Container(
      width: width,
      padding: EdgeInsets.symmetric(
        horizontal: isHeader ? 8 : 10,
        vertical: isHeader ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: background,
        border: Border(
          right: BorderSide(color: tokens.resultsGrid.gridLine),
          bottom: BorderSide(color: tokens.resultsGrid.gridLine),
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
                      color: tokens.resultsGrid.headerText,
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
                    color: tokens.colors.accent,
                  ),
                ),
                if (onResize != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeColumn,
                    child: GestureDetector(
                      key: resizeHandleKey,
                      behavior: HitTestBehavior.translucent,
                      dragStartBehavior: DragStartBehavior.down,
                      onHorizontalDragUpdate: (details) =>
                          onResize!(details.delta.dx),
                      child: Container(
                        width: 12,
                        alignment: Alignment.center,
                        child: Container(
                          width: 2,
                          height: 18,
                          decoration: BoxDecoration(
                            color: tokens.resultsGrid.gridLine,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: tokens.fonts.editorFamily,
                color: selected || rowSelected
                    ? tokens.resultsGrid.rowSelectedText
                    : text == 'NULL'
                    ? tokens.resultsGrid.nullText
                    : tokens.resultsGrid.cellText,
              ),
            ),
    );

    if (isHeader || onTap == null) {
      return child;
    }
    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: onSecondaryTapDown == null
          ? null
          : (details) => onSecondaryTapDown!(details.globalPosition),
      child: child,
    );
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
    final tokens = context.decentBenchTheme;
    final child = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isHeader
            ? tokens.resultsGrid.headerBackground
            : selected
            ? tokens.resultsGrid.rowSelectedBackground
            : tokens.resultsGrid.rowAltBackground,
        border: Border(
          right: BorderSide(color: tokens.resultsGrid.gridLine),
          bottom: BorderSide(color: tokens.resultsGrid.gridLine),
        ),
      ),
      alignment: Alignment.centerRight,
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: tokens.fonts.editorFamily,
          color: isHeader
              ? tokens.resultsGrid.headerText
              : selected
              ? tokens.resultsGrid.rowSelectedText
              : tokens.resultsGrid.cellText,
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

class _ResultsEmptyState extends StatelessWidget {
  const _ResultsEmptyState({
    required this.tab,
    required this.usePlaceholderContent,
  });

  final QueryTabState tab;
  final bool usePlaceholderContent;

  @override
  Widget build(BuildContext context) {
    final label = usePlaceholderContent
        ? 'Run a query to replace the demo dataset.'
        : tab.rowsAffected != null
        ? 'Statement completed without a result grid.'
        : tab.lastSql != null
        ? 'Query returned no rows.'
        : 'Run a query to populate the results grid.';
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = math.min(24.0, constraints.maxWidth / 10);
        final verticalPadding = math.min(24.0, constraints.maxHeight / 6);
        final minWidth = math.max(
          0.0,
          constraints.maxWidth - (horizontalPadding * 2),
        );
        final minHeight = math.max(
          0.0,
          constraints.maxHeight - (verticalPadding * 2),
        );

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minWidth,
              minHeight: minHeight,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.table_rows_outlined, size: 28),
                  const SizedBox(height: 10),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (tab.statusMessage != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      tab.statusMessage!,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessagesPanel extends StatelessWidget {
  const _MessagesPanel({required this.tab});

  final QueryTabState tab;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
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
          color: tokens.colors.panelAltBg,
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontFamily: tokens.fonts.editorFamily,
                        color: tokens.colors.textMuted,
                      ),
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
  const _ExecutionPlanPanel({required this.tab});

  final QueryTabState tab;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    final plan = tab.executionPlan;
    if (plan.isLoading && !plan.hasData) {
      return const _ExecutionPlanEmptyState(
        icon: Icons.account_tree_outlined,
        label: 'Collecting EXPLAIN output...',
      );
    }
    if (!plan.hasData && plan.errorMessage == null) {
      return const _ExecutionPlanEmptyState(
        icon: Icons.account_tree_outlined,
        label:
            'Run a query to populate the execution plan with EXPLAIN results.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (plan.isLoading) const LinearProgressIndicator(minHeight: 2),
        if (plan.errorMessage != null)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            color: tokens.colors.error.withValues(alpha: 0.14),
            child: Text(
              plan.errorMessage!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.colors.error),
            ),
          ),
        Expanded(
          child: !plan.hasData
              ? const _ExecutionPlanEmptyState(
                  icon: Icons.report_gmailerrorred_outlined,
                  label: 'No EXPLAIN rows were captured for this statement.',
                )
              : plan.columns.length == 1 &&
                    plan.columns.first.toLowerCase() == 'query_plan'
              ? ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: plan.rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final row = plan.rows[index];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: tokens.colors.panelAltBg,
                        border: Border.all(color: tokens.resultsGrid.gridLine),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            width: 34,
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.right,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontFamily: tokens.fonts.editorFamily,
                                    color: tokens.colors.textMuted,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              formatCellValue(row[plan.columns.first]),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontFamily: tokens.fonts.editorFamily,
                                    color: tokens.resultsGrid.cellText,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowHeight: 36,
                    dataRowMinHeight: 32,
                    dataRowMaxHeight: 56,
                    columns: <DataColumn>[
                      for (final column in plan.columns)
                        DataColumn(
                          label: Text(
                            column,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontFamily: tokens.fonts.editorFamily,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.resultsGrid.headerText,
                                ),
                          ),
                        ),
                    ],
                    rows: <DataRow>[
                      for (final row in plan.rows)
                        DataRow(
                          cells: <DataCell>[
                            for (final column in plan.columns)
                              DataCell(
                                Text(
                                  formatCellValue(row[column]),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontFamily: tokens.fonts.editorFamily,
                                        color: tokens.resultsGrid.cellText,
                                      ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _ExecutionPlanEmptyState extends StatelessWidget {
  const _ExecutionPlanEmptyState({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 24),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
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
    final tokens = context.decentBenchTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.colors.panelAltBg,
        border: Border.all(color: tokens.colors.border),
        borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: tokens.colors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.colors.textMuted),
          ),
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
    final tokens = context.decentBenchTheme;
    final (label, color) = switch (level) {
      QueryMessageLevel.info => ('INFO', tokens.colors.info),
      QueryMessageLevel.warning => ('WARN', tokens.statusBar.warning),
      QueryMessageLevel.error => ('ERROR', tokens.statusBar.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: color)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontFamily: tokens.fonts.editorFamily,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
