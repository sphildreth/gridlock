import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../domain/workspace_models.dart';
import 'shell_pane_frame.dart';

class SchemaExplorerPane extends StatefulWidget {
  const SchemaExplorerPane({
    super.key,
    required this.schema,
    required this.databasePath,
    required this.selectedNodeId,
    required this.onSelectNode,
    required this.onRefresh,
    required this.isLoading,
  });

  final SchemaSnapshot schema;
  final String? databasePath;
  final String? selectedNodeId;
  final ValueChanged<String> onSelectNode;
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
          : ListView(
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
                  count: schema.tables.isEmpty
                      ? _sampleTables.length
                      : schema.tables.length,
                  icon: Icons.table_chart_outlined,
                  selected: widget.selectedNodeId == 'section:tables',
                  expanded: _expandedNodes.contains('section:tables'),
                  onSelected: widget.onSelectNode,
                  onExpansionChanged: _setExpanded,
                  children: schema.tables.isEmpty
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
                              onExpansionChanged: _setExpanded,
                              children: _buildObjectChildren(
                                object: object,
                                relatedIndexes: schema.indexesForObject(
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
                  count: schema.views.isEmpty
                      ? _sampleViews.length
                      : schema.views.length,
                  icon: Icons.visibility_outlined,
                  selected: widget.selectedNodeId == 'section:views',
                  expanded: _expandedNodes.contains('section:views'),
                  onSelected: widget.onSelectNode,
                  onExpansionChanged: _setExpanded,
                  children: schema.views.isEmpty
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
                              onExpansionChanged: _setExpanded,
                              children: _buildObjectChildren(
                                object: object,
                                relatedIndexes: schema.indexesForObject(
                                  object.name,
                                ),
                                includeConstraints: false,
                                includeTriggers: false,
                              ),
                            ),
                        ],
                ),
                const SizedBox(height: 8),
                _SectionBranch(
                  nodeId: 'section:indexes',
                  title: 'Indexes',
                  count: schema.indexes.isEmpty
                      ? _sampleIndexLabels.length
                      : schema.indexes.length,
                  icon: Icons.filter_alt_outlined,
                  selected: widget.selectedNodeId == 'section:indexes',
                  expanded: _expandedNodes.contains('section:indexes'),
                  onSelected: widget.onSelectNode,
                  onExpansionChanged: _setExpanded,
                  children: schema.indexes.isEmpty
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
    );
  }

  List<Widget> _buildObjectChildren({
    required SchemaObjectSummary object,
    required List<IndexSummary> relatedIndexes,
    bool includeConstraints = true,
    bool includeTriggers = true,
  }) {
    final widgets = <Widget>[
      _FolderBranch(
        nodeId: 'folder:${object.name}:columns',
        label: 'Columns',
        icon: Icons.view_column_outlined,
        selectedNodeId: widget.selectedNodeId,
        expandedNodes: _expandedNodes,
        onSelectNode: widget.onSelectNode,
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
        icon: Icons.filter_alt_outlined,
        selectedNodeId: widget.selectedNodeId,
        expandedNodes: _expandedNodes,
        onSelectNode: widget.onSelectNode,
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
          icon: Icons.rule_folder_outlined,
          selectedNodeId: widget.selectedNodeId,
          expandedNodes: _expandedNodes,
          onSelectNode: widget.onSelectNode,
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
          icon: Icons.bolt_outlined,
          selectedNodeId: widget.selectedNodeId,
          expandedNodes: _expandedNodes,
          onSelectNode: widget.onSelectNode,
          onExpansionChanged: _setExpanded,
          children: <Widget>[
            _LeafNode(
              nodeId: 'trigger:${object.name}:not-exposed',
              icon: Icons.info_outline,
              label: 'Not exposed by current DecentDB Dart schema API',
              selected:
                  widget.selectedNodeId == 'trigger:${object.name}:not-exposed',
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
        onExpansionChanged: _setExpanded,
        children: <Widget>[
          _FolderBranch(
            nodeId: 'folder:sample.customers:columns',
            label: 'Columns',
            icon: Icons.view_column_outlined,
            selectedNodeId: widget.selectedNodeId,
            expandedNodes: _expandedNodes,
            onSelectNode: widget.onSelectNode,
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
        onExpansionChanged: _setExpanded,
        children: <Widget>[
          _FolderBranch(
            nodeId: 'folder:sample.orders:columns',
            label: 'Columns',
            icon: Icons.view_column_outlined,
            selectedNodeId: widget.selectedNodeId,
            expandedNodes: _expandedNodes,
            onSelectNode: widget.onSelectNode,
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
        onExpansionChanged: _setExpanded,
        children: <Widget>[
          _FolderBranch(
            nodeId: 'folder:sample.active_orders:columns',
            label: 'Columns',
            icon: Icons.view_column_outlined,
            selectedNodeId: widget.selectedNodeId,
            expandedNodes: _expandedNodes,
            onSelectNode: widget.onSelectNode,
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
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: selected ? theme.colorScheme.secondaryContainer : null,
        child: Row(
          children: <Widget>[
            const Icon(Icons.storage_outlined, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
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
  final void Function(String nodeId, bool expanded) onExpansionChanged;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surfaceContainerLowest,
      ),
      child: ExpansionTile(
        key: PageStorageKey<String>(nodeId),
        initiallyExpanded: expanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.only(left: 10, right: 6, bottom: 6),
        leading: Icon(icon, size: 16),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelected(nodeId),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              _CountBadge(count: count),
            ],
          ),
        ),
        onExpansionChanged: (value) => onExpansionChanged(nodeId, value),
        children: children,
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
    required this.onExpansionChanged,
    required this.children,
  });

  final String nodeId;
  final String label;
  final IconData icon;
  final String? selectedNodeId;
  final Set<String> expandedNodes;
  final ValueChanged<String> onSelectNode;
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
      onExpansionChanged: onExpansionChanged,
      children: children,
    );
  }
}

class _FolderBranch extends StatelessWidget {
  const _FolderBranch({
    required this.nodeId,
    required this.label,
    required this.icon,
    required this.selectedNodeId,
    required this.expandedNodes,
    required this.onSelectNode,
    required this.onExpansionChanged,
    required this.children,
  });

  final String nodeId;
  final String label;
  final IconData icon;
  final String? selectedNodeId;
  final Set<String> expandedNodes;
  final ValueChanged<String> onSelectNode;
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
      onExpansionChanged: onExpansionChanged,
      inset: 10,
      children: children,
    );
  }
}

class _BranchNode extends StatelessWidget {
  const _BranchNode({
    required this.nodeId,
    required this.label,
    required this.icon,
    required this.selectedNodeId,
    required this.expandedNodes,
    required this.onSelectNode,
    required this.onExpansionChanged,
    required this.children,
    this.inset = 0,
  });

  final String nodeId;
  final String label;
  final IconData icon;
  final String? selectedNodeId;
  final Set<String> expandedNodes;
  final ValueChanged<String> onSelectNode;
  final void Function(String nodeId, bool expanded) onExpansionChanged;
  final List<Widget> children;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final selected = selectedNodeId == nodeId;
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(left: inset, bottom: 4),
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: ExpansionTile(
        key: PageStorageKey<String>(nodeId),
        initiallyExpanded: expandedNodes.contains(nodeId),
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.only(left: 12, bottom: 4),
        collapsedShape: const RoundedRectangleBorder(),
        shape: const RoundedRectangleBorder(),
        leading: Icon(icon, size: 16),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelectNode(nodeId),
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        onExpansionChanged: (value) => onExpansionChanged(nodeId, value),
        children: children,
      ),
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
    final child = Container(
      color: selected ? theme.colorScheme.secondaryContainer : null,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: enabled ? null : theme.disabledColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: enabled ? null : theme.disabledColor,
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
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        '$count',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
      ),
    );
  }
}
