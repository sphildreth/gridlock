import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../app/theme_system/decent_bench_theme_extension.dart';
import '../../domain/workspace_models.dart';
import 'shell_pane_frame.dart';

class SchemaExplorerPane extends StatefulWidget {
  const SchemaExplorerPane({
    super.key,
    required this.schema,
    required this.databasePath,
    required this.selectedNodeId,
    required this.onSelectNode,
    required this.onShowNodeMenu,
    required this.onRefresh,
    required this.isLoading,
  });

  final SchemaSnapshot schema;
  final String? databasePath;
  final String? selectedNodeId;
  final ValueChanged<String> onSelectNode;
  final void Function(String nodeId, Offset globalPosition) onShowNodeMenu;
  final VoidCallback onRefresh;
  final bool isLoading;

  @override
  State<SchemaExplorerPane> createState() => _SchemaExplorerPaneState();
}

class _SchemaExplorerPaneState extends State<SchemaExplorerPane> {
  final Set<String> _expandedNodes = <String>{
    'section:tables',
    'section:views',
    'folder:sample.customers:columns',
    'folder:sample.orders:columns',
  };

  @override
  Widget build(BuildContext context) {
    final showSampleSchema = widget.databasePath == null;
    final databaseLabel = widget.databasePath == null
        ? 'sample.decentdb'
        : p.basename(widget.databasePath!);
    final schema = widget.schema;

    return ShellPaneFrame(
      title: 'Schema Explorer',
      subtitle: databaseLabel,
      leadingIcon: Icons.account_tree_outlined,
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh schema',
          onPressed: widget.isLoading ? null : widget.onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 18),
        ),
      ],
      padding: EdgeInsets.zero,
      child: widget.isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : DecoratedBox(
              decoration: BoxDecoration(
                color: context.decentBenchTheme.sidebar.background,
              ),
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: <Widget>[
                  _RootNode(
                    label: databaseLabel,
                    selected: widget.selectedNodeId == 'database',
                    onTap: () => widget.onSelectNode('database'),
                  ),
                  const SizedBox(height: 8),
                  _SectionBranch(
                    nodeId: 'section:tables',
                    title: 'Tables',
                    count: showSampleSchema && schema.tables.isEmpty
                        ? _sampleTables.length
                        : schema.tables.length,
                    icon: Icons.table_chart_outlined,
                    selected: widget.selectedNodeId == 'section:tables',
                    expanded: _expandedNodes.contains('section:tables'),
                    onSelected: widget.onSelectNode,
                    onShowContextMenu: widget.onShowNodeMenu,
                    onExpansionChanged: _setExpanded,
                    children: showSampleSchema && schema.tables.isEmpty
                        ? _buildSampleTableNodes()
                        : <Widget>[
                            for (final object in schema.tables)
                              _ObjectBranch(
                                nodeId: 'table:${object.name}',
                                label: object.name,
                                icon: Icons.table_rows_outlined,
                                selectedNodeId: widget.selectedNodeId,
                                expandedNodes: _expandedNodes,
                                onSelectNode: widget.onSelectNode,
                                onShowContextMenu: widget.onShowNodeMenu,
                                onExpansionChanged: _setExpanded,
                                children: _buildObjectChildren(
                                  object: object,
                                  relatedIndexes: schema.indexesForObject(
                                    object.name,
                                  ),
                                  relatedTriggers: schema.triggersForObject(
                                    object.name,
                                  ),
                                ),
                              ),
                          ],
                  ),
                  const SizedBox(height: 8),
                  _SectionBranch(
                    nodeId: 'section:views',
                    title: 'Views',
                    count: showSampleSchema && schema.views.isEmpty
                        ? _sampleViews.length
                        : schema.views.length,
                    icon: Icons.visibility_outlined,
                    selected: widget.selectedNodeId == 'section:views',
                    expanded: _expandedNodes.contains('section:views'),
                    onSelected: widget.onSelectNode,
                    onShowContextMenu: widget.onShowNodeMenu,
                    onExpansionChanged: _setExpanded,
                    children: showSampleSchema && schema.views.isEmpty
                        ? _buildSampleViewNodes()
                        : <Widget>[
                            for (final object in schema.views)
                              _ObjectBranch(
                                nodeId: 'view:${object.name}',
                                label: object.name,
                                icon: Icons.view_sidebar_outlined,
                                selectedNodeId: widget.selectedNodeId,
                                expandedNodes: _expandedNodes,
                                onSelectNode: widget.onSelectNode,
                                onShowContextMenu: widget.onShowNodeMenu,
                                onExpansionChanged: _setExpanded,
                                children: _buildObjectChildren(
                                  object: object,
                                  relatedIndexes: schema.indexesForObject(
                                    object.name,
                                  ),
                                  relatedTriggers: schema.triggersForObject(
                                    object.name,
                                  ),
                                  includeConstraints: false,
                                ),
                              ),
                          ],
                  ),
                  const SizedBox(height: 8),
                  _SectionBranch(
                    nodeId: 'section:indexes',
                    title: 'Indexes',
                    count: showSampleSchema && schema.indexes.isEmpty
                        ? _sampleIndexLabels.length
                        : schema.indexes.length,
                    icon: Icons.filter_alt_outlined,
                    selected: widget.selectedNodeId == 'section:indexes',
                    expanded: _expandedNodes.contains('section:indexes'),
                    onSelected: widget.onSelectNode,
                    onShowContextMenu: widget.onShowNodeMenu,
                    onExpansionChanged: _setExpanded,
                    children: showSampleSchema && schema.indexes.isEmpty
                        ? <Widget>[
                            for (final label in _sampleIndexLabels)
                              _LeafNode(
                                nodeId: 'index:sample:$label',
                                icon: Icons.label_outline,
                                label: label,
                                selected:
                                    widget.selectedNodeId ==
                                    'index:sample:$label',
                                onTap: widget.onSelectNode,
                              ),
                          ]
                        : <Widget>[
                            for (final index in schema.indexes)
                              _LeafNode(
                                nodeId: 'index:${index.name}',
                                icon: Icons.label_outline,
                                label:
                                    '${index.name} (${index.columns.join(", ")})',
                                selected:
                                    widget.selectedNodeId ==
                                    'index:${index.name}',
                                onTap: widget.onSelectNode,
                              ),
                          ],
                  ),
                ],
              ),
            ),
    );
  }

  List<Widget> _buildObjectChildren({
    required SchemaObjectSummary object,
    required List<IndexSummary> relatedIndexes,
    required List<TriggerSummary> relatedTriggers,
    bool includeConstraints = true,
    bool includeTriggers = true,
  }) {
    final widgets = <Widget>[
      _FolderBranch(
        nodeId: 'folder:${object.name}:columns',
        label: 'Columns',
        count: object.columns.length,
        icon: Icons.view_column_outlined,
        selectedNodeId: widget.selectedNodeId,
        expandedNodes: _expandedNodes,
        onSelectNode: widget.onSelectNode,
        onShowContextMenu: widget.onShowNodeMenu,
        onExpansionChanged: _setExpanded,
        children: <Widget>[
          for (final column in object.columns)
            _LeafNode(
              nodeId: 'column:${object.name}:${column.name}',
              icon: Icons.subdirectory_arrow_right,
              label: '${column.name}  ${column.type}',
              selected:
                  widget.selectedNodeId ==
                  'column:${object.name}:${column.name}',
              onTap: widget.onSelectNode,
            ),
        ],
      ),
      _FolderBranch(
        nodeId: 'folder:${object.name}:indexes',
        label: 'Indexes',
        count: relatedIndexes.length,
        icon: Icons.filter_alt_outlined,
        selectedNodeId: widget.selectedNodeId,
        expandedNodes: _expandedNodes,
        onSelectNode: widget.onSelectNode,
        onShowContextMenu: widget.onShowNodeMenu,
        onExpansionChanged: _setExpanded,
        children: relatedIndexes.isEmpty
            ? <Widget>[
                _LeafNode(
                  nodeId: 'folder:${object.name}:indexes:empty',
                  icon: Icons.horizontal_rule,
                  label: 'No indexes',
                  selected: false,
                  enabled: false,
                  onTap: widget.onSelectNode,
                ),
              ]
            : <Widget>[
                for (final index in relatedIndexes)
                  _LeafNode(
                    nodeId: 'index:${index.name}',
                    icon: Icons.label_outline,
                    label: '${index.name} (${index.columns.join(", ")})',
                    selected: widget.selectedNodeId == 'index:${index.name}',
                    onTap: widget.onSelectNode,
                  ),
              ],
      ),
    ];

    if (includeConstraints) {
      widgets.add(
        _FolderBranch(
          nodeId: 'folder:${object.name}:constraints',
          label: 'Constraints',
          count: object.exposedConstraintSummaries.length,
          icon: Icons.rule_folder_outlined,
          selectedNodeId: widget.selectedNodeId,
          expandedNodes: _expandedNodes,
          onSelectNode: widget.onSelectNode,
          onShowContextMenu: widget.onShowNodeMenu,
          onExpansionChanged: _setExpanded,
          children: _buildConstraintNodes(object),
        ),
      );
    }

    if (includeTriggers) {
      widgets.add(
        _FolderBranch(
          nodeId: 'folder:${object.name}:triggers',
          label: 'Triggers',
          count: relatedTriggers.length,
          icon: Icons.bolt_outlined,
          selectedNodeId: widget.selectedNodeId,
          expandedNodes: _expandedNodes,
          onSelectNode: widget.onSelectNode,
          onShowContextMenu: widget.onShowNodeMenu,
          onExpansionChanged: _setExpanded,
          children: relatedTriggers.isEmpty
              ? <Widget>[
                  _LeafNode(
                    nodeId: 'trigger:${object.name}:none',
                    icon: Icons.horizontal_rule,
                    label: 'No triggers',
                    selected: false,
                    enabled: false,
                    onTap: widget.onSelectNode,
                  ),
                ]
              : <Widget>[
                  for (final trigger in relatedTriggers)
                    _LeafNode(
                      nodeId: 'trigger:${object.name}:${trigger.name}',
                      icon: Icons.bolt_outlined,
                      label:
                          '${trigger.name} (${trigger.timing.toUpperCase()} ${trigger.events.join(", ")})',
                      selected:
                          widget.selectedNodeId ==
                          'trigger:${object.name}:${trigger.name}',
                      onTap: widget.onSelectNode,
                    ),
                ],
        ),
      );
    }

    return widgets;
  }

  List<Widget> _buildConstraintNodes(SchemaObjectSummary object) {
    final nodes = <Widget>[];
    for (final column in object.columns) {
      for (var i = 0; i < column.constraintSummaries.length; i++) {
        nodes.add(
          _LeafNode(
            nodeId: 'constraint:${object.name}:${column.name}:$i',
            icon: Icons.rule_outlined,
            label: '${column.name}: ${column.constraintSummaries[i]}',
            selected:
                widget.selectedNodeId ==
                'constraint:${object.name}:${column.name}:$i',
            onTap: widget.onSelectNode,
          ),
        );
      }
    }
    for (var i = 0; i < object.checks.length; i++) {
      final check = object.checks[i];
      nodes.add(
        _LeafNode(
          nodeId: 'constraint:${object.name}:check:$i',
          icon: Icons.rule_outlined,
          label: check.summary,
          selected:
              widget.selectedNodeId == 'constraint:${object.name}:check:$i',
          onTap: widget.onSelectNode,
        ),
      );
    }
    if (nodes.isNotEmpty) {
      return nodes;
    }
    return <Widget>[
      _LeafNode(
        nodeId: 'constraint:${object.name}:none',
        icon: Icons.horizontal_rule,
        label: 'No explicit constraints',
        selected: false,
        enabled: false,
        onTap: widget.onSelectNode,
      ),
    ];
  }

  List<Widget> _buildSampleTableNodes() {
    return <Widget>[
      _ObjectBranch(
        nodeId: 'table:sample.customers',
        label: 'customers',
        icon: Icons.table_rows_outlined,
        selectedNodeId: widget.selectedNodeId,
        expandedNodes: _expandedNodes,
        onSelectNode: widget.onSelectNode,
        onShowContextMenu: widget.onShowNodeMenu,
        onExpansionChanged: _setExpanded,
        children: <Widget>[
          _FolderBranch(
            nodeId: 'folder:sample.customers:columns',
            label: 'Columns',
            count: 3,
            icon: Icons.view_column_outlined,
            selectedNodeId: widget.selectedNodeId,
            expandedNodes: _expandedNodes,
            onSelectNode: widget.onSelectNode,
            onShowContextMenu: widget.onShowNodeMenu,
            onExpansionChanged: _setExpanded,
            children: const <Widget>[
              _LeafNode(
                nodeId: 'column:sample.customers:id',
                icon: Icons.subdirectory_arrow_right,
                label: 'id  INTEGER',
              ),
              _LeafNode(
                nodeId: 'column:sample.customers:name',
                icon: Icons.subdirectory_arrow_right,
                label: 'name  TEXT',
              ),
              _LeafNode(
                nodeId: 'column:sample.customers:region',
                icon: Icons.subdirectory_arrow_right,
                label: 'region  TEXT',
              ),
            ],
          ),
        ],
      ),
      _ObjectBranch(
        nodeId: 'table:sample.orders',
        label: 'orders',
        icon: Icons.table_rows_outlined,
        selectedNodeId: widget.selectedNodeId,
        expandedNodes: _expandedNodes,
        onSelectNode: widget.onSelectNode,
        onShowContextMenu: widget.onShowNodeMenu,
        onExpansionChanged: _setExpanded,
        children: <Widget>[
          _FolderBranch(
            nodeId: 'folder:sample.orders:columns',
            label: 'Columns',
            count: 3,
            icon: Icons.view_column_outlined,
            selectedNodeId: widget.selectedNodeId,
            expandedNodes: _expandedNodes,
            onSelectNode: widget.onSelectNode,
            onShowContextMenu: widget.onShowNodeMenu,
            onExpansionChanged: _setExpanded,
            children: const <Widget>[
              _LeafNode(
                nodeId: 'column:sample.orders:id',
                icon: Icons.subdirectory_arrow_right,
                label: 'id  INTEGER',
              ),
              _LeafNode(
                nodeId: 'column:sample.orders:customer_id',
                icon: Icons.subdirectory_arrow_right,
                label: 'customer_id  INTEGER',
              ),
              _LeafNode(
                nodeId: 'column:sample.orders:total',
                icon: Icons.subdirectory_arrow_right,
                label: 'total  DECIMAL',
              ),
            ],
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildSampleViewNodes() {
    return <Widget>[
      _ObjectBranch(
        nodeId: 'view:sample.active_orders',
        label: 'active_orders',
        icon: Icons.view_sidebar_outlined,
        selectedNodeId: widget.selectedNodeId,
        expandedNodes: _expandedNodes,
        onSelectNode: widget.onSelectNode,
        onShowContextMenu: widget.onShowNodeMenu,
        onExpansionChanged: _setExpanded,
        children: <Widget>[
          _FolderBranch(
            nodeId: 'folder:sample.active_orders:columns',
            label: 'Columns',
            count: 2,
            icon: Icons.view_column_outlined,
            selectedNodeId: widget.selectedNodeId,
            expandedNodes: _expandedNodes,
            onSelectNode: widget.onSelectNode,
            onShowContextMenu: widget.onShowNodeMenu,
            onExpansionChanged: _setExpanded,
            children: const <Widget>[
              _LeafNode(
                nodeId: 'column:sample.active_orders:id',
                icon: Icons.subdirectory_arrow_right,
                label: 'id  ANY',
              ),
              _LeafNode(
                nodeId: 'column:sample.active_orders:status',
                icon: Icons.subdirectory_arrow_right,
                label: 'status  ANY',
              ),
            ],
          ),
        ],
      ),
    ];
  }

  void _setExpanded(String nodeId, bool expanded) {
    setState(() {
      if (expanded) {
        _expandedNodes.add(nodeId);
      } else {
        _expandedNodes.remove(nodeId);
      }
    });
  }
}

const List<String> _sampleTables = <String>['customers', 'orders'];
const List<String> _sampleViews = <String>['active_orders'];
const List<String> _sampleIndexLabels = <String>[
  'idx_orders_customer',
  'idx_customers_region',
];

class _RootNode extends StatelessWidget {
  const _RootNode({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.decentBenchTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: selected ? tokens.sidebar.itemSelectedBackground : null,
        child: Row(
          children: <Widget>[
            Icon(
              Icons.storage_outlined,
              size: tokens.metrics.iconSize + 2,
              color: tokens.sidebar.itemText,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected
                    ? tokens.sidebar.itemSelectedText
                    : tokens.sidebar.itemText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionBranch extends StatelessWidget {
  const _SectionBranch({
    required this.nodeId,
    required this.title,
    required this.count,
    required this.icon,
    required this.selected,
    required this.expanded,
    required this.onSelected,
    required this.onShowContextMenu,
    required this.onExpansionChanged,
    required this.children,
  });

  final String nodeId;
  final String title;
  final int count;
  final IconData icon;
  final bool selected;
  final bool expanded;
  final ValueChanged<String> onSelected;
  final void Function(String nodeId, Offset globalPosition) onShowContextMenu;
  final void Function(String nodeId, bool expanded) onExpansionChanged;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.decentBenchTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.colors.border),
        color: tokens.sidebar.headerBackground,
      ),
      child: Column(
        children: <Widget>[
          _BranchHeader(
            key: PageStorageKey<String>(nodeId),
            nodeId: nodeId,
            selected: selected,
            expanded: expanded,
            icon: icon,
            label: title,
            count: count,
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: tokens.sidebar.headerText,
            ),
            iconColor: tokens.sidebar.headerText,
            onSelect: onSelected,
            onShowContextMenu: onShowContextMenu,
            onExpansionChanged: onExpansionChanged,
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 10, right: 6, bottom: 6),
              child: Column(children: children),
            ),
        ],
      ),
    );
  }
}

class _BranchHeader extends StatefulWidget {
  const _BranchHeader({
    super.key,
    required this.nodeId,
    required this.label,
    required this.icon,
    required this.selected,
    required this.expanded,
    this.count,
    required this.textStyle,
    required this.iconColor,
    required this.onSelect,
    required this.onShowContextMenu,
    required this.onExpansionChanged,
  });

  static const double _toggleHitWidth = 32;
  static const Duration _doubleClickWindow = Duration(milliseconds: 300);
  static const double _doubleClickSlop = 24;

  final String nodeId;
  final String label;
  final IconData icon;
  final bool selected;
  final bool expanded;
  final int? count;
  final TextStyle? textStyle;
  final Color iconColor;
  final ValueChanged<String> onSelect;
  final void Function(String nodeId, Offset globalPosition) onShowContextMenu;
  final void Function(String nodeId, bool expanded) onExpansionChanged;

  @override
  State<_BranchHeader> createState() => _BranchHeaderState();
}

class _BranchHeaderState extends State<_BranchHeader> {
  DateTime? _lastPrimaryTapAt;
  Offset? _lastPrimaryTapPosition;

  void _clearTapState() {
    _lastPrimaryTapAt = null;
    _lastPrimaryTapPosition = null;
  }

  void _handlePrimaryTap(TapUpDetails details, double maxWidth) {
    final tappedToggle =
        details.localPosition.dx >= maxWidth - _BranchHeader._toggleHitWidth;
    if (tappedToggle) {
      _clearTapState();
      widget.onExpansionChanged(widget.nodeId, !widget.expanded);
      return;
    }

    widget.onSelect(widget.nodeId);

    final now = DateTime.now();
    final lastTapAt = _lastPrimaryTapAt;
    final lastTapPosition = _lastPrimaryTapPosition;
    final isDoubleClick =
        lastTapAt != null &&
        now.difference(lastTapAt) <= _BranchHeader._doubleClickWindow &&
        lastTapPosition != null &&
        (details.localPosition - lastTapPosition).distance <=
            _BranchHeader._doubleClickSlop;
    if (isDoubleClick) {
      _clearTapState();
      widget.onExpansionChanged(widget.nodeId, !widget.expanded);
      return;
    }

    _lastPrimaryTapAt = now;
    _lastPrimaryTapPosition = details.localPosition;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) => _handlePrimaryTap(details, constraints.maxWidth),
        onSecondaryTapDown: (details) =>
            widget.onShowContextMenu(widget.nodeId, details.globalPosition),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(
                widget.icon,
                size: tokens.metrics.iconSize,
                color: widget.iconColor,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(widget.label, style: widget.textStyle)),
              if (widget.count != null)
                _CountBadge(
                  key: ValueKey<String>('schema.count.${widget.nodeId}'),
                  count: widget.count!,
                ),
              const SizedBox(width: 4),
              SizedBox(
                width: _BranchHeader._toggleHitWidth,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 160),
                    turns: widget.expanded ? 0.25 : 0,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: tokens.metrics.iconSize + 4,
                      color: widget.iconColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ObjectBranch extends StatelessWidget {
  const _ObjectBranch({
    required this.nodeId,
    required this.label,
    required this.icon,
    required this.selectedNodeId,
    required this.expandedNodes,
    required this.onSelectNode,
    required this.onShowContextMenu,
    required this.onExpansionChanged,
    required this.children,
  });

  final String nodeId;
  final String label;
  final IconData icon;
  final String? selectedNodeId;
  final Set<String> expandedNodes;
  final ValueChanged<String> onSelectNode;
  final void Function(String nodeId, Offset globalPosition) onShowContextMenu;
  final void Function(String nodeId, bool expanded) onExpansionChanged;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _BranchNode(
      nodeId: nodeId,
      label: label,
      icon: icon,
      selectedNodeId: selectedNodeId,
      expandedNodes: expandedNodes,
      onSelectNode: onSelectNode,
      onShowContextMenu: onShowContextMenu,
      onExpansionChanged: onExpansionChanged,
      children: children,
    );
  }
}

class _BranchNode extends StatelessWidget {
  const _BranchNode({
    required this.nodeId,
    required this.label,
    required this.icon,
    this.count,
    required this.selectedNodeId,
    required this.expandedNodes,
    required this.onSelectNode,
    required this.onShowContextMenu,
    required this.onExpansionChanged,
    required this.children,
    this.inset = 0,
  });

  final String nodeId;
  final String label;
  final IconData icon;
  final int? count;
  final String? selectedNodeId;
  final Set<String> expandedNodes;
  final ValueChanged<String> onSelectNode;
  final void Function(String nodeId, Offset globalPosition) onShowContextMenu;
  final void Function(String nodeId, bool expanded) onExpansionChanged;
  final List<Widget> children;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final selected = selectedNodeId == nodeId;
    final expanded = expandedNodes.contains(nodeId);
    final theme = Theme.of(context);
    final tokens = context.decentBenchTheme;
    return Container(
      key: ValueKey<String>('schema.branch.$nodeId.$expanded'),
      margin: EdgeInsets.only(left: inset, bottom: 4),
      color: selected ? tokens.sidebar.itemSelectedBackground : null,
      child: Column(
        children: <Widget>[
          _BranchHeader(
            key: PageStorageKey<String>(nodeId),
            nodeId: nodeId,
            label: label,
            icon: icon,
            selected: selected,
            expanded: expanded,
            count: count,
            textStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? tokens.sidebar.itemSelectedText
                  : tokens.sidebar.itemText,
            ),
            iconColor: selected
                ? tokens.sidebar.itemSelectedText
                : tokens.sidebar.itemText,
            onSelect: onSelectNode,
            onShowContextMenu: onShowContextMenu,
            onExpansionChanged: onExpansionChanged,
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Column(children: children),
            ),
        ],
      ),
    );
  }
}

class _FolderBranch extends StatelessWidget {
  const _FolderBranch({
    required this.nodeId,
    required this.label,
    required this.icon,
    this.count,
    required this.selectedNodeId,
    required this.expandedNodes,
    required this.onSelectNode,
    required this.onShowContextMenu,
    required this.onExpansionChanged,
    required this.children,
  });

  final String nodeId;
  final String label;
  final IconData icon;
  final int? count;
  final String? selectedNodeId;
  final Set<String> expandedNodes;
  final ValueChanged<String> onSelectNode;
  final void Function(String nodeId, Offset globalPosition) onShowContextMenu;
  final void Function(String nodeId, bool expanded) onExpansionChanged;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _BranchNode(
      nodeId: nodeId,
      label: label,
      icon: icon,
      count: count,
      selectedNodeId: selectedNodeId,
      expandedNodes: expandedNodes,
      onSelectNode: onSelectNode,
      onShowContextMenu: onShowContextMenu,
      onExpansionChanged: onExpansionChanged,
      inset: 10,
      children: children,
    );
  }
}

class _LeafNode extends StatelessWidget {
  const _LeafNode({
    required this.nodeId,
    required this.icon,
    required this.label,
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  final String nodeId;
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<String>? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.decentBenchTheme;
    final child = Container(
      color: selected ? tokens.sidebar.itemSelectedBackground : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: enabled
                ? (selected
                      ? tokens.sidebar.itemSelectedText
                      : tokens.sidebar.itemText)
                : tokens.colors.textDisabled,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: tokens.fonts.editorFamily,
                color: enabled
                    ? (selected
                          ? tokens.sidebar.itemSelectedText
                          : tokens.sidebar.itemText)
                    : tokens.colors.textDisabled,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
    if (!enabled || onTap == null) {
      return child;
    }
    return InkWell(onTap: () => onTap!(nodeId), child: child);
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.sidebar.background,
        border: Border.all(color: tokens.sidebar.treeLine),
        borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontFamily: tokens.fonts.editorFamily,
          color: tokens.sidebar.itemText,
        ),
      ),
    );
  }
}
