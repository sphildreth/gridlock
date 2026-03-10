import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../application/workspace_controller.dart';
import '../domain/excel_import_models.dart';
import '../domain/import_target_types.dart';

class ExcelImportDialog extends StatefulWidget {
  const ExcelImportDialog({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<ExcelImportDialog> createState() => _ExcelImportDialogState();
}

class _ExcelImportDialogState extends State<ExcelImportDialog> {
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
        final session = widget.controller.excelImportSession;
        if (session == null) {
          return const SizedBox.shrink();
        }
        _syncControllers(session);

        return AlertDialog(
          title: const Text('Excel Import Wizard'),
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
                    session.step != ExcelImportWizardStep.summary) ...<Widget>[
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

  Widget _buildStepHeader(ExcelImportSession session) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final step in ExcelImportWizardStep.values)
          ChoiceChip(
            label: Text(_stepLabel(step)),
            selected: session.step == step,
            onSelected: (selected) {
              if (!selected) {
                return;
              }
              widget.controller.setExcelImportStep(step);
            },
          ),
        Chip(label: Text('Phase: ${session.phase.name}')),
      ],
    );
  }

  Widget _buildStepBody(ExcelImportSession session) {
    return switch (session.step) {
      ExcelImportWizardStep.source => _buildSourceStep(session),
      ExcelImportWizardStep.target => _buildTargetStep(session),
      ExcelImportWizardStep.preview => _buildPreviewStep(session),
      ExcelImportWizardStep.transforms => _buildTransformsStep(session),
      ExcelImportWizardStep.execute => _buildExecuteStep(session),
      ExcelImportWizardStep.summary => _buildSummaryStep(session),
    };
  }

  Widget _buildSourceStep(ExcelImportSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Select an Excel workbook, choose whether the first non-empty row contains headers, and inspect available worksheets before import.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _sourcePathController,
                decoration: const InputDecoration(
                  labelText: 'Excel source path',
                  hintText: '/tmp/source.xlsx',
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
              onPressed: session.phase == ExcelImportJobPhase.inspecting
                  ? null
                  : () => widget.controller.loadExcelImportSource(
                      _sourcePathController.text,
                    ),
              child: Text(
                session.phase == ExcelImportJobPhase.inspecting
                    ? 'Inspecting...'
                    : 'Inspect Workbook',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: session.headerRow,
          onChanged: session.phase == ExcelImportJobPhase.inspecting
              ? null
              : (value) {
                  if (value != null) {
                    widget.controller.updateExcelImportHeaderRow(value);
                  }
                },
          title: const Text('Treat the first non-empty row as column headers'),
          subtitle: const Text(
            'Turn this off to import generic column names like `column_1`.',
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: session.sheets.isEmpty
              ? const _DialogEmptyState(
                  title: 'No workbook loaded yet',
                  message:
                      'Choose an `.xlsx` file to inspect worksheets, infer column types, and preview sample rows.',
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: session.sheets.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final sheet = session.sheets[index];
                      return ListTile(
                        title: Text(sheet.sourceName),
                        subtitle: Text(
                          '${sheet.rowCount} rows | ${sheet.columns.length} columns',
                        ),
                        trailing: Icon(
                          sheet.selected
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

  Widget _buildTargetStep(ExcelImportSession session) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Choose where the imported workbook sheets should land. Create a new DecentDB file or import into an existing one.',
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
            widget.controller.updateExcelImportIntoExistingTarget(
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
                onChanged: widget.controller.updateExcelImportTargetPath,
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
                .updateExcelImportReplaceExistingTarget(value ?? false),
            title: const Text('Replace target file if it already exists'),
          ),
        const SizedBox(height: 20),
        _SummaryGrid(
          rows: <(String, String)>[
            ('Source', p.basename(session.sourcePath)),
            ('Selected sheets', '${session.selectedSheets.length}'),
            (
              'Rows selected',
              '${session.selectedSheets.fold<int>(0, (sum, sheet) => sum + sheet.rowCount)}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewStep(ExcelImportSession session) {
    return _SheetSplitView(
      sheetList: _buildSheetList(session),
      detail: _buildPreviewDetail(session),
    );
  }

  Widget _buildTransformsStep(ExcelImportSession session) {
    final focused = session.focusedSheetDraft;
    return _SheetSplitView(
      sheetList: _buildSheetList(session),
      detail: focused == null
          ? const _DialogEmptyState(
              title: 'No worksheet selected',
              message:
                  'Choose at least one worksheet to configure table names and target column types.',
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
                    key: ValueKey<String>('sheet-${focused.sourceName}'),
                    initialValue: focused.targetName,
                    onChanged: (value) => widget.controller
                        .renameExcelImportSheet(focused.sourceName, value),
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
                      sheetName: focused.sourceName,
                      column: column,
                      onRename: (value) =>
                          widget.controller.renameExcelImportColumn(
                            focused.sourceName,
                            column.sourceIndex,
                            value,
                          ),
                      onTypeChanged: (value) =>
                          widget.controller.overrideExcelImportColumnType(
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

  Widget _buildExecuteStep(ExcelImportSession session) {
    final progress = session.progress;
    final totalRows = session.selectedSheets.fold<int>(
      0,
      (sum, sheet) => sum + sheet.rowCount,
    );
    final denominator = math.max(1, totalRows);
    final progressValue = progress == null
        ? 0.0
        : progress.totalRowsCopied / denominator;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Run the Excel import in a background isolate. The target DecentDB import is transactional for this phase, so cancel or failure will roll back the job.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        _SummaryGrid(
          rows: <(String, String)>[
            ('Source', p.basename(session.sourcePath)),
            ('Target', p.basename(session.targetPath)),
            ('Sheets', '${session.selectedSheets.length}'),
            ('Rows selected', '$totalRows'),
          ],
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(value: progressValue.clamp(0.0, 1.0)),
        const SizedBox(height: 12),
        Text(progress?.message ?? 'Waiting to start...'),
        if (progress != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Sheet ${progress.completedSheets + 1} of ${progress.totalSheets}: '
            '${progress.currentSheetRowsCopied}/${progress.currentSheetRowCount} rows',
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryStep(ExcelImportSession session) {
    final summary = session.summary;
    if (summary == null) {
      return const _DialogEmptyState(
        title: 'No summary available',
        message: 'Run an Excel import to populate the summary view.',
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
              ('Rolled back', summary.rolledBack ? 'Yes' : 'No'),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Imported tables',
            style: Theme.of(context).textTheme.titleSmall,
          ),
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
          if (summary.warnings.isNotEmpty ||
              session.warnings.isNotEmpty ||
              session.error != null) ...<Widget>[
            const SizedBox(height: 16),
            Text('Warnings', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final warning in <String>[
              ...session.warnings,
              ...summary.warnings,
              if (session.error != null) session.error!,
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(warning),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSheetList(ExcelImportSession session) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: session.sheets.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final sheet = session.sheets[index];
          return CheckboxListTile(
            value: sheet.selected,
            onChanged: sheet.columns.isEmpty
                ? null
                : (value) => widget.controller.toggleExcelImportSheetSelection(
                    sheet.sourceName,
                    value ?? false,
                  ),
            title: Text(sheet.sourceName),
            subtitle: Text(
              '${sheet.rowCount} rows | ${sheet.columns.length} columns',
            ),
            secondary: IconButton(
              tooltip: 'Focus worksheet details',
              onPressed: () =>
                  widget.controller.focusExcelImportSheet(sheet.sourceName),
              icon: Icon(
                session.focusedSheet == sheet.sourceName
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

  Widget _buildPreviewDetail(ExcelImportSession session) {
    final focused = session.focusedSheetDraft;
    if (focused == null) {
      return const _DialogEmptyState(
        title: 'No worksheet selected',
        message: 'Choose a worksheet from the list to inspect sample rows.',
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
                label: Text(session.headerRow ? 'Headers On' : 'Headers Off'),
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
                '${column.sourceName} -> ${column.targetType}'
                '${column.containsNulls ? ' | nullable' : ''}',
              ),
            ),
          const SizedBox(height: 14),
          Text('Sample rows', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (focused.previewRows.isEmpty)
            const Text('No sample rows available.')
          else
            _PreviewTable(sheet: focused),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context, ExcelImportSession session) {
    final actions = <Widget>[
      TextButton(
        onPressed: () {
          widget.controller.closeExcelImportSession();
          Navigator.of(context).pop();
        },
        child: const Text('Close'),
      ),
    ];

    switch (session.step) {
      case ExcelImportWizardStep.source:
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromSource
                ? () => widget.controller.setExcelImportStep(
                    ExcelImportWizardStep.target,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case ExcelImportWizardStep.target:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setExcelImportStep(
              ExcelImportWizardStep.source,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromTarget
                ? () => widget.controller.setExcelImportStep(
                    ExcelImportWizardStep.preview,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case ExcelImportWizardStep.preview:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setExcelImportStep(
              ExcelImportWizardStep.target,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: session.canAdvanceFromPreview
                ? () => widget.controller.setExcelImportStep(
                    ExcelImportWizardStep.transforms,
                  )
                : null,
            child: const Text('Next'),
          ),
        );
        break;
      case ExcelImportWizardStep.transforms:
        actions.add(
          TextButton(
            onPressed: () => widget.controller.setExcelImportStep(
              ExcelImportWizardStep.preview,
            ),
            child: const Text('Back'),
          ),
        );
        actions.add(
          FilledButton(
            onPressed: widget.controller.runExcelImport,
            child: const Text('Start Import'),
          ),
        );
        break;
      case ExcelImportWizardStep.execute:
        actions.add(
          FilledButton.tonal(
            onPressed:
                session.phase == ExcelImportJobPhase.running ||
                    session.phase == ExcelImportJobPhase.cancelling
                ? widget.controller.cancelExcelImport
                : null,
            child: Text(
              session.phase == ExcelImportJobPhase.cancelling
                  ? 'Cancelling...'
                  : 'Cancel Import',
            ),
          ),
        );
        break;
      case ExcelImportWizardStep.summary:
        if (session.summary?.firstImportedTable != null &&
            session.phase == ExcelImportJobPhase.completed) {
          actions.add(
            TextButton(
              onPressed: () async {
                await widget.controller.openExcelImportedDatabaseFromSummary();
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
                await widget.controller.runQueryForExcelImportedTable();
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
      label: 'excel',
      extensions: <String>['xlsx', 'xls'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) {
      return;
    }
    _sourcePathController.text = file.path;
    await widget.controller.loadExcelImportSource(file.path);
  }

  Future<void> _browseTarget(ExcelImportSession session) async {
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
      widget.controller.updateExcelImportTargetPath(file.path);
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
    widget.controller.updateExcelImportTargetPath(result.path);
  }

  void _syncControllers(ExcelImportSession session) {
    if (_sourcePathController.text != session.sourcePath) {
      _sourcePathController.text = session.sourcePath;
    }
    if (_targetPathController.text != session.targetPath) {
      _targetPathController.text = session.targetPath;
    }
  }

  String _stepLabel(ExcelImportWizardStep step) {
    return switch (step) {
      ExcelImportWizardStep.source => 'Source',
      ExcelImportWizardStep.target => 'Target',
      ExcelImportWizardStep.preview => 'Preview',
      ExcelImportWizardStep.transforms => 'Transforms',
      ExcelImportWizardStep.execute => 'Execute',
      ExcelImportWizardStep.summary => 'Summary',
    };
  }
}

class _SheetSplitView extends StatelessWidget {
  const _SheetSplitView({required this.sheetList, required this.detail});

  final Widget sheetList;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            children: <Widget>[
              SizedBox(height: 220, child: sheetList),
              const SizedBox(height: 12),
              Expanded(child: detail),
            ],
          );
        }
        return Row(
          children: <Widget>[
            SizedBox(width: 300, child: sheetList),
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
    required this.sheetName,
    required this.column,
    required this.onRename,
    required this.onTypeChanged,
  });

  final String sheetName;
  final ExcelImportColumnDraft column;
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
            Text('$sheetName.${column.sourceName}'),
            const SizedBox(height: 4),
            Text(
              'Suggested: ${column.inferredTargetType}'
              '${column.containsNulls ? ' | nullable' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: ValueKey<String>(
                      'rename-$sheetName-${column.sourceIndex}',
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
  const _PreviewTable({required this.sheet});

  final ExcelImportSheetDraft sheet;

  @override
  Widget build(BuildContext context) {
    final columnWidths = sheet.columns.length * 180.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(constraints.maxWidth, columnWidths),
            child: DataTable(
              columns: <DataColumn>[
                for (final column in sheet.columns)
                  DataColumn(label: Text(column.targetName)),
              ],
              rows: <DataRow>[
                for (final row in sheet.previewRows)
                  DataRow(
                    cells: <DataCell>[
                      for (final column in sheet.columns)
                        DataCell(
                          Text(
                            formatExcelImportCellValue(row[column.sourceName]),
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
              Icons.table_chart_outlined,
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
