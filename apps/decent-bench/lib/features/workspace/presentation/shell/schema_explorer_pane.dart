import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../domain/workspace_models.dart';
import 'shell_pane_frame.dart';

class SchemaExplorerPane extends StatelessWidget {
  const SchemaExplorerPane({
    super.key,
    required this.schema,
    required this.databasePath,
    required this.selectedObjectName,
    required this.onSelectObject,
    required this.onRefresh,
    required this.isLoading,
  });

  final SchemaSnapshot schema;
  final String? databasePath;
  final String? selectedObjectName;
  final ValueChanged<String> onSelectObject;
  final VoidCallback onRefresh;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final databaseLabel = databasePath == null
        ? 'sample.decentdb'
        : p.basename(databasePath!);
    return ShellPaneFrame(
      title: 'Schema Explorer',
      subtitle: databaseLabel,
      leadingIcon: Icons.account_tree_outlined,
      actions: <Widget>[
        IconButton(
          tooltip: 'Refresh schema',
          onPressed: isLoading ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 18),
        ),
      ],
      padding: EdgeInsets.zero,
      child: isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(8),
              children: <Widget>[
                _TreeRoot(label: databaseLabel),
                const SizedBox(height: 8),
                _TreeSection(
                  title: 'Tables',
                  icon: Icons.table_chart_outlined,
                  children: schema.tables.isEmpty
                      ? _sampleTables
                      : schema.tables.map(_objectBranch).toList(),
                ),
                const SizedBox(height: 8),
                _TreeSection(
                  title: 'Views',
                  icon: Icons.visibility_outlined,
                  children: schema.views.isEmpty
                      ? _sampleViews
                      : schema.views.map(_objectBranch).toList(),
                ),
                const SizedBox(height: 8),
                _TreeSection(
                  title: 'Indexes',
                  icon: Icons.filter_alt_outlined,
                  children: schema.indexes.isEmpty
                      ? _sampleIndexes
                      : schema.indexes
                            .map(
                              (index) => _TreeLeaf(
                                icon: Icons.label_outline,
                                label:
                                    '${index.name} (${index.columns.join(", ")})',
                                selected: false,
                                onTap: null,
                              ),
                            )
                            .toList(),
                ),
              ],
            ),
    );
  }

  Widget _objectBranch(SchemaObjectSummary object) {
    return _TreeBranch(
      icon: object.kind == SchemaObjectKind.table
          ? Icons.table_rows_outlined
          : Icons.view_sidebar_outlined,
      label: object.name,
      selected: selectedObjectName == object.name,
      onTap: () => onSelectObject(object.name),
      children: <Widget>[
        for (final column in object.columns)
          _TreeLeaf(
            icon: Icons.subdirectory_arrow_right,
            label: '${column.name}  ${column.type}',
            selected: false,
            onTap: () => onSelectObject(object.name),
          ),
      ],
    );
  }
}

const List<Widget> _sampleTables = <Widget>[
  _TreeBranch(
    icon: Icons.table_rows_outlined,
    label: 'customers',
    children: <Widget>[
      _TreeLeaf(icon: Icons.subdirectory_arrow_right, label: 'id  INTEGER'),
      _TreeLeaf(icon: Icons.subdirectory_arrow_right, label: 'name  TEXT'),
      _TreeLeaf(icon: Icons.subdirectory_arrow_right, label: 'region  TEXT'),
    ],
  ),
  _TreeBranch(
    icon: Icons.table_rows_outlined,
    label: 'orders',
    children: <Widget>[
      _TreeLeaf(icon: Icons.subdirectory_arrow_right, label: 'id  INTEGER'),
      _TreeLeaf(
        icon: Icons.subdirectory_arrow_right,
        label: 'customer_id  INTEGER',
      ),
      _TreeLeaf(icon: Icons.subdirectory_arrow_right, label: 'total  DECIMAL'),
    ],
  ),
];

const List<Widget> _sampleViews = <Widget>[
  _TreeBranch(
    icon: Icons.view_sidebar_outlined,
    label: 'active_orders',
    children: <Widget>[
      _TreeLeaf(icon: Icons.subdirectory_arrow_right, label: 'id  ANY'),
      _TreeLeaf(icon: Icons.subdirectory_arrow_right, label: 'status  ANY'),
    ],
  ),
];

const List<Widget> _sampleIndexes = <Widget>[
  _TreeLeaf(icon: Icons.label_outline, label: 'idx_orders_customer'),
  _TreeLeaf(icon: Icons.label_outline, label: 'idx_customers_region'),
];

class _TreeRoot extends StatelessWidget {
  const _TreeRoot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.storage_outlined, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _TreeSection extends StatelessWidget {
  const _TreeSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 16),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _TreeBranch extends StatelessWidget {
  const _TreeBranch({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
    this.children = const <Widget>[],
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      color: selected ? theme.colorScheme.secondaryContainer : null,
      child: ExpansionTile(
        dense: true,
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.only(left: 12, bottom: 4),
        collapsedShape: const RoundedRectangleBorder(),
        shape: const RoundedRectangleBorder(),
        leading: Icon(icon, size: 16),
        title: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        onExpansionChanged: (_) => onTap?.call(),
        children: children,
      ),
    );
  }
}

class _TreeLeaf extends StatelessWidget {
  const _TreeLeaf({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return child;
    }
    return InkWell(onTap: onTap, child: child);
  }
}
