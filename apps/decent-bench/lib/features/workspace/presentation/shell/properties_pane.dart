import 'package:flutter/material.dart';

import '../../domain/workspace_models.dart';
import 'shell_pane_frame.dart';

class PropertiesPane extends StatelessWidget {
  const PropertiesPane({
    super.key,
    required this.object,
    required this.relatedIndexes,
    required this.notes,
  });

  final SchemaObjectSummary? object;
  final List<IndexSummary> relatedIndexes;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final resolvedObject = object;
    return ShellPaneFrame(
      title: 'Properties / Details',
      subtitle: resolvedObject == null
          ? 'Inspector'
          : '${resolvedObject.kind.name} metadata',
      leadingIcon: Icons.info_outline,
      padding: EdgeInsets.zero,
      child: resolvedObject == null
          ? _SampleInspector(notes: notes)
          : _ObjectInspector(
              object: resolvedObject,
              relatedIndexes: relatedIndexes,
              notes: notes,
            ),
    );
  }
}

class _ObjectInspector extends StatelessWidget {
  const _ObjectInspector({
    required this.object,
    required this.relatedIndexes,
    required this.notes,
  });

  final SchemaObjectSummary object;
  final List<IndexSummary> relatedIndexes;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _PropertyTable(
          rows: <MapEntry<String, String>>[
            MapEntry('Name', object.name),
            MapEntry('Type', object.kind.name),
            MapEntry('Columns', '${object.columns.length}'),
            MapEntry('Indexes', '${relatedIndexes.length}'),
          ],
        ),
        const SizedBox(height: 12),
        Text('Columns', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final column in object.columns)
          _InspectorRow(
            title: column.name,
            subtitle: column.descriptor,
            icon: Icons.view_column_outlined,
          ),
        const SizedBox(height: 12),
        Text('Indexes', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (relatedIndexes.isEmpty)
          const _MutedNote('No indexes exposed for this object.')
        else
          for (final index in relatedIndexes)
            _InspectorRow(
              title: index.name,
              subtitle:
                  '${index.unique ? 'UNIQUE ' : ''}${index.kind} (${index.columns.join(", ")})',
              icon: Icons.filter_alt_outlined,
            ),
        const SizedBox(height: 12),
        Text('Constraints / Notes', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final note in <String>[
          ...object.exposedConstraintSummaries,
          ...notes,
        ])
          _MutedNote(note),
        if (object.ddl != null) ...<Widget>[
          const SizedBox(height: 12),
          Text('Definition', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            color: theme.colorScheme.surfaceContainerLowest,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              object.ddl!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SampleInspector extends StatelessWidget {
  const _SampleInspector({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        const _PropertyTable(
          rows: <MapEntry<String, String>>[
            MapEntry('Name', 'orders'),
            MapEntry('Type', 'table'),
            MapEntry('Primary key', 'id'),
            MapEntry('Estimated rows', '42,180'),
          ],
        ),
        const SizedBox(height: 12),
        const _InspectorRow(
          title: 'id',
          subtitle: 'INTEGER | PRIMARY KEY | NOT NULL',
          icon: Icons.view_column_outlined,
        ),
        const _InspectorRow(
          title: 'customer_id',
          subtitle: 'INTEGER | REFERENCES customers(id)',
          icon: Icons.view_column_outlined,
        ),
        const _InspectorRow(
          title: 'total',
          subtitle: 'DECIMAL(12,2)',
          icon: Icons.view_column_outlined,
        ),
        const SizedBox(height: 12),
        const _MutedNote('Index: idx_orders_customer (customer_id)'),
        const _MutedNote('Constraint: CHECK(total >= 0)'),
        for (final note in notes) _MutedNote(note),
      ],
    );
  }
}

class _PropertyTable extends StatelessWidget {
  const _PropertyTable({required this.rows});

  final List<MapEntry<String, String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          for (var i = 0; i < rows.length; i++)
            Container(
              color: i.isEven
                  ? theme.colorScheme.surfaceContainerLowest
                  : theme.colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 120,
                    child: Text(
                      rows[i].key,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(child: Text(rows[i].value)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InspectorRow extends StatelessWidget {
  const _InspectorRow({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedNote extends StatelessWidget {
  const _MutedNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
      ),
    );
  }
}
