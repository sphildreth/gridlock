import 'package:flutter/material.dart';

import 'schema_browser_models.dart';
import 'shell_pane_frame.dart';

class PropertiesPane extends StatelessWidget {
  const PropertiesPane({super.key, required this.selection});

  final SchemaSelectionDetails? selection;

  @override
  Widget build(BuildContext context) {
    final resolvedSelection = selection;
    return ShellPaneFrame(
      title: 'Properties / Details',
      subtitle: resolvedSelection?.subtitle ?? 'Inspector',
      leadingIcon: Icons.info_outline,
      padding: EdgeInsets.zero,
      child: resolvedSelection == null
          ? const _SampleInspector()
          : _SelectionInspector(selection: resolvedSelection),
    );
  }
}

class _SelectionInspector extends StatelessWidget {
  const _SelectionInspector({required this.selection});

  final SchemaSelectionDetails selection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _PropertyTable(
          rows: <MapEntry<String, String>>[
            MapEntry('Label', selection.label),
            MapEntry('Kind', selection.kind.name),
            if (selection.objectName != null)
              MapEntry('Object', selection.objectName!),
            ...selection.summaryRows,
          ],
        ),
        if (selection.notes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text('Metadata / Notes', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final note in selection.notes) _MutedNote(note),
        ],
        if (selection.definition != null &&
            selection.definition!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text('Definition', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            color: theme.colorScheme.surfaceContainerLowest,
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              selection.definition!,
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
  const _SampleInspector();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const <Widget>[
        _PropertyTable(
          rows: <MapEntry<String, String>>[
            MapEntry('Label', 'sample.decentdb'),
            MapEntry('Kind', 'database'),
            MapEntry('Tables', '2'),
            MapEntry('Indexes', '2'),
          ],
        ),
        SizedBox(height: 12),
        _MutedNote(
          'Select a database object, column, constraint, or index in Schema Explorer to inspect it here.',
        ),
        _MutedNote(
          'The inspector is designed to work for folders and metadata nodes, not only table objects.',
        ),
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
                    width: 140,
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

class _MutedNote extends StatelessWidget {
  const _MutedNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Text(text),
    );
  }
}
