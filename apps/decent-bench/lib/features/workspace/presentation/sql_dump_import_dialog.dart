import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../application/workspace_controller.dart';
import '../domain/import_target_types.dart';
import '../domain/sql_dump_import_models.dart';

class SqlDumpImportDialog extends StatefulWidget {
  const SqlDumpImportDialog({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<SqlDumpImportDialog> createState() => _SqlDumpImportDialogState();
}

class _SqlDumpImportDialogState extends State<SqlDumpImportDialog> {
  late final TextEditingController _sourcePathController =
      TextEditingController();
  late final TextEditingController _targetPathController =
      TextEditingController();

  @override
  void dispose() {
    _targetPathController.dispose();
    _sourcePathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final session = widget.controller.sqlDumpImportSession;
        if (session == null) {
          return const SizedBox.shrink();
        }
        _syncControllers(session);

        return AlertDialog(
          title: const Text('SQL Dump Import Wizard'),
          content: SizedBox(
            width: 1080,
            height: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _buildStepHeader(session),
                const SizedBox(height: 16),
                if (session.error != null) ...<Widget>[
                  _DialogBanner(
                    color: Theme.of(context).colorScheme.errorContainer,
                    icon: Icons.error_outline_rounded,
                    text: session.error!,
                  ),
                  const SizedBox(height: 12),
                ],
                if (session.warnings.isNotEmpty &&
                    session.step != SqlDumpImportWizardStep.summary) ...<Widget>[
                  _DialogBanner(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    icon: Icons.warning_amber_rounded,
                    text: session.warnings.join('\n'),
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(child: _buildStepBody(session)),
              ],
            ),
          ),
          actions: _buildActions(context, session),
        );
      },
    );
  }

  Widget _buildStepHeader(SqlDumpImportSession session) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final step in SqlDumpImportWizardStep.values)
          ChoiceChip(
            label: Text(_stepLabel(step)),
            selected: session.step == step,
            onSelected: (selected) {
              if (!selected) {
                return;
              }
              widget.controller.setSqlDumpImportStep(step);
            },
          ),
        Chip(label: Text('Phase: ${session.phase.name}')),
      ],
    );
  }

  Widget _buildStepBody(SqlDumpImportSession session) {
    return switch (session.step) {
      SqlDumpImportWizardStep.source => _buildSourceStep(session),
      SqlDumpImportWizardStep.target => _buildTargetStep(session),
      SqlDumpImportWizardStep.preview => _buildPreviewStep(session),
      SqlDumpImportWizardStep.transforms => _buildTransformsStep(session),
      SqlDumpImportWizardStep.execute => _buildExecuteStep(session),
      SqlDumpImportWizardStep.summary => _buildSummaryStep(session),
    };
  }

  Widget _buildSourceStep(SqlDumpImportSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Select a MariaDB/MySQL-style `.sql` dump, choose the decoding strategy, and inspect the supported CREATE TABLE and INSERT statements before import.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _sourcePathController,
                decoration: const InputDecoration(
                  labelText: 'SQL dump source path',
                  hintText: '/tmp/source.sql',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: _browseSourceFile,
              child: const Text('Browse'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: session.phase == SqlDumpImportJobPhase.inspecting
                  ? null
                  : () => widget.controller.loadSqlDumpImportSource(
                      _sourcePathController.text,
                    ),
              child: Text(
                session.phase == SqlDumpImportJobPhase.inspecting
                    ? 'Inspecting...'
                    : 'Inspect Dump',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: session.encoding,
                items: <DropdownMenuItem<String>>[
                  for (final option in sqlDumpEncodingOptions)
                    DropdownMenuItem<String>(
                      value: option,
                      child: Text(sqlDumpEncodingLabel(option)),
                    ),
                ],
                onChanged: session.phase == SqlDumpImportJobPhase.inspecting
                    ? null
                    : (value) {
                        if (value != null) {
                          widget.controller.updateSqlDumpImportEncoding(value);
                        }
                      },
                decoration: const InputDecoration(
                  labelText: 'Decode dump as',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Resolved encoding',
                ),
                child: Text(sqlDumpEncodingLabel(session.resolvedEncoding)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SummaryGrid(
          rows: <(String, String)>[
            ('Parsed tables', '${session.tables.length}'),
            ('Total statements', '${session.totalStatements}'),
            ('Skipped statements', '${session.skippedStatementCount}'),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: session.tables.isEmpty
              ? const _DialogEmptyState(
                  title: 'No supported dump content loaded yet',
                  message:
                      'Choose a `.sql` dump to parse supported CREATE TABLE and INSERT statements, infer target types, and preview sample rows.',
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: session.tables.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final table = session.tables[index];
                      return ListTile(
                        title: Text(table.sourceName),
                        subtitle: Text(
                          '${table.rowCount} rows | ${table.columns.length} columns',
                        ),
                        trailing: Icon(
                          table.selected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTargetStep(SqlDumpImportSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Choose where the parsed dump tables should land. Create a new DecentDB file or import into an existing one.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(
              value: false,
              label: Text('Create New'),
              icon: Icon(Icons.add_circle_outline_rounded),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Use Existing'),
              icon: Icon(Icons.folder_open_rounded),
            ),
          ],
          selected: <bool>{session.importIntoExistingTarget},
          onSelectionChanged: (selection) {
            widget.controller.updateSqlDumpImportIntoExistingTarget(
              selection.first,
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _targetPathController,
                onChanged: widget.controller.updateSqlDumpImportTargetPath,
                decoration: const InputDecoration(
                  labelText: 'DecentDB target path',
                  hintText: '/tmp/import.ddb',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: () => _browseTarget(session),
              child: Text(
                session.importIntoExistingTarget ? 'Choose' : 'Save As',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!session.importIntoExistingTarget)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: session.replaceExistingTarget,
            onChanged: (value) => widget.controller
                .updateSqlDumpImportReplaceExistingTarget(value ?? false),
            title: const Text('Replace target file if it already exists'),
          ),
        const SizedBox(height: 20),
        _SummaryGrid(
          rows: <(String, String)>[
            ('Source', p.basename(session.sourcePath)),
            ('Selected tables', '${session.selectedTables.length}'),
            (
              'Rows selected',
              '${session.selectedTables.fold<int>(0, (sum, table) => sum + table.rowCount)}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewStep(SqlDumpImportSession session) {
    return _TableSplitView(
      tableList: _buildTableList(session),
      detail: _buildPreviewDetail(session),
    );
  }

  Widget _buildTransformsStep(SqlDumpImportSession session) {
    final focused = session.focusedTableDraft;
    return _TableSplitView(
      tableList: _buildTableList(session),
      detail: focused == null
          ? const _DialogEmptyState(
              title: 'No parsed table selected',
              message:
                  'Choose at least one parsed table to configure names and target types.',
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Target table',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey<String>('table-${focused.sourceName}'),
                    initialValue: focused.targetName,
                    onChanged: (value) =>
                        widget.controller.renameSqlDumpImportTable(
                          focused.sourceName,
                          value,
                        ),
                    decoration: const InputDecoration(
                      labelText: 'Target table name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Columns',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final column in focused.columns) ...<Widget>[
                    _ColumnTransformRow(
                      tableName: focused.sourceName,
                      column: column,
                      onRename: (value) =>
                          widget.controller.renameSqlDumpImportColumn(
                            focused.sourceName,
                            column.sourceIndex,
                            value,
                          ),
                      onTypeChanged: (value) =>
                          widget.controller.overrideSqlDumpImportColumnType(
                            focused.sourceName,
                            column.sourceIndex,
                            value,
                          ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildExecuteStep(SqlDumpImportSession session) {
    final progress = session.progress;
    final totalRows = session.selectedTables.fold<int>(
      0,
      (sum, table) => sum + table.rowCount,
    );
    final denominator = math.max(1, totalRows);
    final progressValue = progress == null
        ? 0.0
        : progress.totalRowsCopied / denominator;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Run the SQL dump import in a background isolate. The target DecentDB import is transactional for this phase, and unsupported statements remain warnings rather than fatal errors where possible.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _SummaryGrid(
          rows: <(String, String)>[
            ('Source', p.basename(session.sourcePath)),
            ('Target', p.basename(session.targetPath)),
            ('Tables', '${session.selectedTables.length}'),
            ('Rows selected', '$totalRows'),
            ('Skipped statements', '${session.skippedStatementCount}'),
          ],
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(value: progressValue.clamp(0.0, 1.0)),
        const SizedBox(height: 12),
        Text(progress?.message ?? 'Waiting to start...'),
        if (progress != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Table ${progress.completedTables + 1} of ${progress.totalTables}: '
            '${progress.currentTableRowsCopied}/${progress.currentTableRowCount} rows',
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryStep(SqlDumpImportSession session) {
    final summary = session.summary;
    if (summary == null) {
      return const _DialogEmptyState(
        title: 'No summary available',
        message: 'Run a SQL dump import to populate the summary view.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            summary.statusMessage,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _SummaryGrid(
            rows: <(String, String)>[
              ('Source', p.basename(summary.sourcePath)),
              ('Target', p.basename(summary.targetPath)),
              ('Imported tables', '${summary.importedTables.length}'),
              ('Rows copied', '${summary.totalRowsCopied}'),
              ('Skipped statements', '${summary.skippedStatementCount}'),
              ('Rolled back', summary.rolledBack ? 'Yes' : 'No'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Imported tables', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (summary.importedTables.isEmpty)
            const Text('No tables were imported.')
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final table in summary.importedTables)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '$table | ${summary.rowsCopiedByTable[table] ?? 0} rows',
                    ),
                  ),
              ],
            ),
          if (summary.skippedStatements.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Skipped statements',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final skipped in summary.skippedStatements.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '#${skipped.ordinal} ${skipped.kind}: ${skipped.reason}\n${skipped.snippet}',
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableList(SqlDumpImportSession session) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: session.tables.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final table = session.tables[index];
          return CheckboxListTile(
            value: table.selected,
            onChanged: table.columns.isEmpty
                ? null
                : (value) => widget.controller.toggleSqlDumpImportTableSelection(
                    table.sourceName,
                    value ?? false,
                  ),
            title: Text(table.sourceName),
            subtitle: Text(
              '${table.rowCount} rows | ${table.columns.length} columns',
            ),
            secondary: IconButton(
              tooltip: 'Focus parsed table details',
              onPressed: () => widget.controller.focusSqlDumpImportTable(
                table.sourceName,
              ),
              icon: Icon(
                session.focusedTable == table.sourceName
                    ? Icons.visibility_rounded
                    : Icons.visibility_outlined,
              ),
            ),
            controlAffinity: ListTileControlAffinity.leading,
          );
        },
      ),
    );
  }

  Widget _buildPreviewDetail(SqlDumpImportSession session) {
    final focused = session.focusedTableDraft;
    if (focused == null) {
      return const _DialogEmptyState(
        title: 'No parsed table selected',
        message: 'Choose a parsed table from the list to inspect sample rows.',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            focused.sourceName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Chip(label: Text('${focused.rowCount} rows')),
              Chip(label: Text('${focused.columns.length} columns')),
              Chip(
                label: Text(
                  'Encoding: ${sqlDumpEncodingLabel(session.resolvedEncoding)}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Columns', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final column in focused.columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${column.sourceName} | ${column.declaredType} -> ${column.targetType}'
                '${column.primaryKey ? ' | PK' : ''}'
                '${column.unique ? ' | UNIQUE' : ''}'
                '${column.notNull ? ' | NOT NULL' : ''}',
              ),
            ),
          const SizedBox(height: 14),
          Text('Sample rows', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (focused.previewRows.isEmpty)
            const Text('No sample rows available.')
          else
            _PreviewTable(table: focused),
          if (session.skippedStatements.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Skipped statements',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final skipped in session.skippedStatements.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '#${skipped.ordinal} ${skipped.kind}: ${skipped.reason}\n${skipped.snippet}',
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    SqlDumpImportSession session,
  ) {
    final actions = <Widget>[
      TextButton(
        onPressed: () {
          widget.controller.closeSqlDumpImportSession();
          Navigator.of(context).pop();
        },
        child: const Text('Close'),
      ),
    ];

    switch (session.step) {
      case SqlDumpImportWizardStep.source:
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromSource
                ? () => widget.controller.setSqlDumpImportStep(
                    SqlDumpImportWizardStep.target,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case SqlDumpImportWizardStep.target:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setSqlDumpImportStep(
              SqlDumpImportWizardStep.source,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromTarget
                ? () => widget.controller.setSqlDumpImportStep(
                    SqlDumpImportWizardStep.preview,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case SqlDumpImportWizardStep.preview:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setSqlDumpImportStep(
              SqlDumpImportWizardStep.target,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromPreview
                ? () => widget.controller.setSqlDumpImportStep(
                    SqlDumpImportWizardStep.transforms,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case SqlDumpImportWizardStep.transforms:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setSqlDumpImportStep(
              SqlDumpImportWizardStep.preview,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: widget.controller.runSqlDumpImport,
            child: const Text('Start Import'),
          ),
        );
        break;
      case SqlDumpImportWizardStep.execute:
        actions.add(
          FilledButton.tonal(
            onPressed:
                session.phase == SqlDumpImportJobPhase.running ||
                    session.phase == SqlDumpImportJobPhase.cancelling
                ? widget.controller.cancelSqlDumpImport
                : null,
            child: Text(
              session.phase == SqlDumpImportJobPhase.cancelling
                  ? 'Cancelling...'
                  : 'Cancel Import',
            ),
          ),
        );
        break;
      case SqlDumpImportWizardStep.summary:
        if (session.summary?.firstImportedTable != null &&
            session.phase == SqlDumpImportJobPhase.completed) {
          actions.add(
            TextButton(
              onPressed: () async {
                await widget.controller.openSqlDumpImportedDatabaseFromSummary();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Open Database'),
            ),
          );
          actions.add(
            FilledButton(
              onPressed: () async {
                await widget.controller.runQueryForSqlDumpImportedTable();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Run a Query'),
            ),
          );
        }
        break;
    }

    return actions;
  }

  Future<void> _browseSourceFile() async {
    const typeGroup = XTypeGroup(
      label: 'sql-dump',
      extensions: <String>['sql'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) {
      return;
    }
    _sourcePathController.text = file.path;
    await widget.controller.loadSqlDumpImportSource(file.path);
  }

  Future<void> _browseTarget(SqlDumpImportSession session) async {
    if (session.importIntoExistingTarget) {
      const typeGroup = XTypeGroup(
        label: 'decentdb',
        extensions: <String>['ddb'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      if (file == null) {
        return;
      }
      _targetPathController.text = file.path;
      widget.controller.updateSqlDumpImportTargetPath(file.path);
      return;
    }

    final result = await getSaveLocation(
      suggestedName: p.basename(
        session.targetPath.trim().isEmpty
            ? '${p.basenameWithoutExtension(session.sourcePath)}.ddb'
            : session.targetPath,
      ),
    );
    if (result == null) {
      return;
    }
    _targetPathController.text = result.path;
    widget.controller.updateSqlDumpImportTargetPath(result.path);
  }

  void _syncControllers(SqlDumpImportSession session) {
    if (_sourcePathController.text != session.sourcePath) {
      _sourcePathController.text = session.sourcePath;
    }
    if (_targetPathController.text != session.targetPath) {
      _targetPathController.text = session.targetPath;
    }
  }

  String _stepLabel(SqlDumpImportWizardStep step) {
    return switch (step) {
      SqlDumpImportWizardStep.source => 'Source',
      SqlDumpImportWizardStep.target => 'Target',
      SqlDumpImportWizardStep.preview => 'Preview',
      SqlDumpImportWizardStep.transforms => 'Transforms',
      SqlDumpImportWizardStep.execute => 'Execute',
      SqlDumpImportWizardStep.summary => 'Summary',
    };
  }
}

class _TableSplitView extends StatelessWidget {
  const _TableSplitView({required this.tableList, required this.detail});

  final Widget tableList;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            children: <Widget>[
              SizedBox(height: 220, child: tableList),
              const SizedBox(height: 12),
              Expanded(child: detail),
            ],
          );
        }
        return Row(
          children: <Widget>[
            SizedBox(width: 300, child: tableList),
            const SizedBox(width: 16),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

class _ColumnTransformRow extends StatelessWidget {
  const _ColumnTransformRow({
    required this.tableName,
    required this.column,
    required this.onRename,
    required this.onTypeChanged,
  });

  final String tableName;
  final SqlDumpImportColumnDraft column;
  final ValueChanged<String> onRename;
  final ValueChanged<String> onTypeChanged;

  @override
  Widget build(BuildContext context) {
    final typeItems = <String>{
      ...decentDbImportTargetTypes,
      column.targetType,
    }.toList()..sort();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('$tableName.${column.sourceName}'),
            const SizedBox(height: 4),
            Text(
              'Declared: ${column.declaredType} | Suggested: ${column.inferredTargetType}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>(
                      'rename-$tableName-${column.sourceIndex}',
                    ),
                    initialValue: column.targetName,
                    onChanged: onRename,
                    decoration: const InputDecoration(
                      labelText: 'Target column name',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: column.targetType,
                    isExpanded: true,
                    items: <DropdownMenuItem<String>>[
                      for (final type in typeItems)
                        DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        onTypeChanged(value);
                      }
                    },
                    decoration: const InputDecoration(labelText: 'Target type'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.table});

  final SqlDumpImportTableDraft table;

  @override
  Widget build(BuildContext context) {
    final columnWidths = table.columns.length * 180.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, columnWidths),
            child: DataTable(
              columns: <DataColumn>[
                for (final column in table.columns)
                  DataColumn(label: Text(column.targetName)),
              ],
              rows: <DataRow>[
                for (final row in table.previewRows)
                  DataRow(
                    cells: <DataCell>[
                      for (final column in table.columns)
                        DataCell(
                          Text(
                            formatSqlDumpImportCellValue(
                              row[column.sourceName],
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            for (var i = 0; i < rows.length; i++) ...<Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 180,
                    child: Text(
                      rows[i].$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: SelectableText(rows[i].$2)),
                ],
              ),
              if (i + 1 < rows.length) const Divider(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

class _DialogBanner extends StatelessWidget {
  const _DialogBanner({
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _DialogEmptyState extends StatelessWidget {
  const _DialogEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.description_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
