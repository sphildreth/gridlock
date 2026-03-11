import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../application/workspace_controller.dart';
import '../domain/import_target_types.dart';
import '../domain/sqlite_import_models.dart';
import '../domain/workspace_file_entry.dart';

class SqliteImportDialog extends StatefulWidget {
  const SqliteImportDialog({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<SqliteImportDialog> createState() => _SqliteImportDialogState();
}

class _SqliteImportDialogState extends State<SqliteImportDialog> {
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
        final session = widget.controller.sqliteImportSession;
        if (session == null) {
          return const SizedBox.shrink();
        }
        _syncControllers(session);

        return AlertDialog(
          title: const Text('SQLite Import Wizard'),
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
                    session.step != SqliteImportWizardStep.summary) ...<Widget>[
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

  Widget _buildStepHeader(SqliteImportSession session) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final step in SqliteImportWizardStep.values)
          ChoiceChip(
            label: Text(_stepLabel(step)),
            selected: session.step == step,
            onSelected: (selected) {
              if (!selected) {
                return;
              }
              widget.controller.setSqliteImportStep(step);
            },
          ),
        Chip(label: Text('Phase: ${session.phase.name}')),
      ],
    );
  }

  Widget _buildStepBody(SqliteImportSession session) {
    return switch (session.step) {
      SqliteImportWizardStep.source => _buildSourceStep(session),
      SqliteImportWizardStep.target => _buildTargetStep(session),
      SqliteImportWizardStep.preview => _buildPreviewStep(session),
      SqliteImportWizardStep.transforms => _buildTransformsStep(session),
      SqliteImportWizardStep.execute => _buildExecuteStep(session),
      SqliteImportWizardStep.summary => _buildSummaryStep(session),
    };
  }

  Widget _buildSourceStep(SqliteImportSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Select a SQLite source file. The wizard will inspect tables, row counts, indexes, and foreign keys before import.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _sourcePathController,
                decoration: const InputDecoration(
                  labelText: 'SQLite source path',
                  hintText: '/tmp/source.sqlite',
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
              onPressed: session.phase == SqliteImportJobPhase.inspecting
                  ? null
                  : () => widget.controller.loadSqliteImportSource(
                      _sourcePathController.text,
                    ),
              child: Text(
                session.phase == SqliteImportJobPhase.inspecting
                    ? 'Inspecting...'
                    : 'Inspect Source',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: session.tables.isEmpty
              ? const _DialogEmptyState(
                  title: 'No SQLite schema loaded yet',
                  message:
                      'Choose a SQLite file to inspect tables, preview rows, and configure the target DecentDB import.',
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
                          '${table.rowCount} rows | ${table.columns.length} columns'
                          '${table.strict ? ' | STRICT' : ''}'
                          '${table.withoutRowId ? ' | WITHOUT ROWID' : ''}',
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

  Widget _buildTargetStep(SqliteImportSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Choose where the imported SQLite tables should land. Create a new DecentDB file or import into an existing one.',
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
            widget.controller.updateSqliteImportIntoExistingTarget(
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
                onChanged: widget.controller.updateSqliteImportTargetPath,
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
                .updateSqliteImportReplaceExistingTarget(value ?? false),
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

  Widget _buildPreviewStep(SqliteImportSession session) {
    return _TableSplitView(
      tableList: _buildTableList(session),
      detail: _buildPreviewDetail(session),
    );
  }

  Widget _buildTransformsStep(SqliteImportSession session) {
    final focused = session.focusedTableDraft;
    return _TableSplitView(
      tableList: _buildTableList(session),
      detail: focused == null
          ? const _DialogEmptyState(
              title: 'No table selected',
              message:
                  'Choose at least one SQLite table to configure names and target types.',
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
                    onChanged: (value) => widget.controller
                        .renameSqliteImportTable(focused.sourceName, value),
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
                          widget.controller.renameSqliteImportColumn(
                            focused.sourceName,
                            column.sourceName,
                            value,
                          ),
                      onTypeChanged: (value) =>
                          widget.controller.overrideSqliteImportColumnType(
                            focused.sourceName,
                            column.sourceName,
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

  Widget _buildExecuteStep(SqliteImportSession session) {
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
          'Run the SQLite import in a background isolate. The target DecentDB import is transactional for this phase, so cancel or failure will roll back the job.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _SummaryGrid(
          rows: <(String, String)>[
            ('Source', p.basename(session.sourcePath)),
            ('Target', p.basename(session.targetPath)),
            ('Tables', '${session.selectedTables.length}'),
            ('Rows selected', '$totalRows'),
          ],
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(value: progressValue.clamp(0, 1)),
        const SizedBox(height: 12),
        Text(progress?.message ?? 'Ready to start the SQLite import.'),
        if (progress != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            '${progress.currentTableRowsCopied}/${progress.currentTableRowCount} rows copied for ${progress.currentTable}',
          ),
          Text(
            '${progress.completedTables}/${progress.totalTables} tables completed',
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryStep(SqliteImportSession session) {
    final summary = session.summary;
    if (summary == null) {
      return _DialogEmptyState(
        title: session.phase == SqliteImportJobPhase.failed
            ? 'Import failed'
            : 'Import summary unavailable',
        message: session.error ?? 'The import did not produce a summary.',
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DialogBanner(
            color: session.phase == SqliteImportJobPhase.completed
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.tertiaryContainer,
            icon: session.phase == SqliteImportJobPhase.completed
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded,
            text: summary.statusMessage,
          ),
          const SizedBox(height: 16),
          _SummaryGrid(
            rows: <(String, String)>[
              ('Source', summary.sourcePath),
              ('Target', summary.targetPath),
              ('Imported tables', '${summary.importedTables.length}'),
              ('Rows copied', '${summary.totalRowsCopied}'),
              ('Indexes created', '${summary.indexesCreated.length}'),
              ('Rolled back', summary.rolledBack ? 'Yes' : 'No'),
            ],
          ),
          if (summary.warnings.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text('Warnings', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final warning in summary.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(warning),
              ),
          ],
          if (summary.skippedItems.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Skipped items',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final item in summary.skippedItems)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${item.tableName == null ? item.name : '${item.tableName}.${item.name}'}: ${item.reason}',
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildTableList(SqliteImportSession session) {
    if (session.tables.isEmpty) {
      return const _DialogEmptyState(
        title: 'No tables loaded',
        message: 'Inspect a SQLite source file first.',
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: session.tables.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final table = session.tables[index];
          final isFocused = table.sourceName == session.focusedTable;
          return Material(
            color: isFocused
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () =>
                  widget.controller.focusSqliteImportTable(table.sourceName),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: <Widget>[
                    Checkbox(
                      value: table.selected,
                      onChanged: (value) =>
                          widget.controller.toggleSqliteImportTableSelection(
                            table.sourceName,
                            value ?? false,
                          ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(table.sourceName),
                          const SizedBox(height: 2),
                          Text(
                            '${table.rowCount} rows | ${table.columns.length} cols',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewDetail(SqliteImportSession session) {
    final focused = session.focusedTableDraft;
    if (focused == null) {
      return const _DialogEmptyState(
        title: 'No table selected',
        message: 'Choose a SQLite table to preview sample rows.',
      );
    }

    if (session.loadingPreviewTable == focused.sourceName &&
        !focused.previewLoaded) {
      return const Center(child: CircularProgressIndicator());
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
              if (focused.strict) const Chip(label: Text('STRICT')),
              if (focused.withoutRowId)
                const Chip(label: Text('WITHOUT ROWID')),
              if (focused.hasCompositePrimaryKey)
                const Chip(label: Text('Composite PK')),
            ],
          ),
          const SizedBox(height: 14),
          Text('Columns', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final column in focused.columns)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${column.sourceName} | ${column.declaredType.isEmpty ? 'untyped' : column.declaredType} -> ${column.targetType}'
                '${column.primaryKey ? ' | PK' : ''}'
                '${column.unique ? ' | UNIQUE' : ''}'
                '${column.notNull ? ' | NOT NULL' : ''}',
              ),
            ),
          const SizedBox(height: 14),
          Text('Sample rows', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (focused.previewError != null)
            Text(focused.previewError!)
          else if (focused.previewRows.isEmpty)
            const Text('No sample rows available.')
          else
            _PreviewTable(table: focused),
        ],
      ),
    );
  }

  List<Widget> _buildActions(
    BuildContext context,
    SqliteImportSession session,
  ) {
    final actions = <Widget>[
      TextButton(
        onPressed: () {
          widget.controller.closeSqliteImportSession();
          Navigator.of(context).pop();
        },
        child: const Text('Close'),
      ),
    ];

    switch (session.step) {
      case SqliteImportWizardStep.source:
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromSource
                ? () => widget.controller.setSqliteImportStep(
                    SqliteImportWizardStep.target,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case SqliteImportWizardStep.target:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setSqliteImportStep(
              SqliteImportWizardStep.source,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromTarget
                ? () => widget.controller.setSqliteImportStep(
                    SqliteImportWizardStep.preview,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case SqliteImportWizardStep.preview:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setSqliteImportStep(
              SqliteImportWizardStep.target,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromPreview
                ? () => widget.controller.setSqliteImportStep(
                    SqliteImportWizardStep.transforms,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case SqliteImportWizardStep.transforms:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setSqliteImportStep(
              SqliteImportWizardStep.preview,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: widget.controller.runSqliteImport,
            child: const Text('Start Import'),
          ),
        );
        break;
      case SqliteImportWizardStep.execute:
        actions.add(
          FilledButton.tonal(
            onPressed:
                session.phase == SqliteImportJobPhase.running ||
                    session.phase == SqliteImportJobPhase.cancelling
                ? widget.controller.cancelSqliteImport
                : null,
            child: Text(
              session.phase == SqliteImportJobPhase.cancelling
                  ? 'Cancelling...'
                  : 'Cancel Import',
            ),
          ),
        );
        break;
      case SqliteImportWizardStep.summary:
        if (session.summary?.firstImportedTable != null &&
            session.phase == SqliteImportJobPhase.completed) {
          actions.add(
            TextButton(
              onPressed: () async {
                await widget.controller.openImportedDatabaseFromSummary();
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
                await widget.controller.runQueryForImportedTable();
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
      label: 'sqlite',
      extensions: <String>['db', 'sqlite', 'sqlite3'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) {
      return;
    }
    _sourcePathController.text = file.path;
    await widget.controller.loadSqliteImportSource(file.path);
  }

  Future<void> _browseTarget(SqliteImportSession session) async {
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
      widget.controller.updateSqliteImportTargetPath(file.path);
      return;
    }

    final suggestedTargetPath = session.targetPath.trim().isEmpty
        ? suggestNewDecentDbTargetPath(session.sourcePath)
        : session.targetPath.trim();
    final result = await getSaveLocation(
      initialDirectory: p.dirname(suggestedTargetPath),
      suggestedName: p.basename(suggestedTargetPath),
    );
    if (result == null) {
      return;
    }
    _targetPathController.text = result.path;
    widget.controller.updateSqliteImportTargetPath(result.path);
  }

  void _syncControllers(SqliteImportSession session) {
    if (_sourcePathController.text != session.sourcePath) {
      _sourcePathController.text = session.sourcePath;
    }
    if (_targetPathController.text != session.targetPath) {
      _targetPathController.text = session.targetPath;
    }
  }

  String _stepLabel(SqliteImportWizardStep step) {
    return switch (step) {
      SqliteImportWizardStep.source => 'Source',
      SqliteImportWizardStep.target => 'Target',
      SqliteImportWizardStep.preview => 'Preview',
      SqliteImportWizardStep.transforms => 'Transforms',
      SqliteImportWizardStep.execute => 'Execute',
      SqliteImportWizardStep.summary => 'Summary',
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
            SizedBox(width: 280, child: tableList),
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
  final SqliteImportColumnDraft column;
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
              'Declared: ${column.declaredType.isEmpty ? 'untyped' : column.declaredType}'
              ' | Suggested: ${column.inferredTargetType}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>(
                      'rename-$tableName-${column.sourceName}',
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

  final SqliteImportTableDraft table;

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
                          Text(formatImportCellValue(row[column.sourceName])),
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 140,
                      child: Text(
                        row.$1,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    Expanded(child: Text(row.$2)),
                  ],
                ),
              ),
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
            const SizedBox(width: 10),
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
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
