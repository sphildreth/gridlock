import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../workspace/domain/import_target_types.dart';
import '../../workspace/domain/workspace_models.dart';
import '../domain/import_models.dart';
import '../infrastructure/import_execution_service.dart';
import '../infrastructure/import_preview_service.dart';

const XTypeGroup _genericImportSourceTypeGroup = XTypeGroup(
  label: 'Import source',
  extensions: <String>[
    'csv',
    'tsv',
    'txt',
    'dat',
    'log',
    'json',
    'jsonl',
    'ndjson',
    'xml',
    'html',
    'htm',
  ],
);

const XTypeGroup _decentDbTargetTypeGroup = XTypeGroup(
  label: 'DecentDB database',
  extensions: <String>['ddb'],
);

class GenericImportDialog extends StatefulWidget {
  const GenericImportDialog({
    super.key,
    required this.initialSourcePath,
    required this.initialFormat,
    this.previewService,
    this.executionService,
  });

  final String initialSourcePath;
  final ImportFormatDefinition initialFormat;
  final ImportPreviewService? previewService;
  final ImportExecutionService? executionService;

  @override
  State<GenericImportDialog> createState() => _GenericImportDialogState();
}

class _GenericImportDialogState extends State<GenericImportDialog> {
  late final ImportPreviewService _previewService =
      widget.previewService ?? ImportPreviewService();
  late final ImportExecutionService _executionService =
      widget.executionService ?? ImportExecutionService();
  late final TextEditingController _sourcePathController =
      TextEditingController(text: widget.initialSourcePath);
  late final TextEditingController _targetPathController =
      TextEditingController();

  GenericImportWizardStep _step = GenericImportWizardStep.source;
  GenericImportJobPhase _phase = GenericImportJobPhase.idle;
  late GenericImportOptions _options;
  GenericImportInspection? _inspection;
  GenericImportProgress? _progress;
  GenericImportSummary? _summary;
  StreamSubscription<GenericImportUpdate>? _importSubscription;
  String? _error;
  List<String> _warnings = <String>[];
  bool _importIntoExistingTarget = false;
  bool _replaceExistingTarget = true;
  String? _focusedTableId;

  @override
  void initState() {
    super.initState();
    _options = _defaultOptionsFor(widget.initialFormat.key);
    unawaited(_inspectSource());
  }

  @override
  void dispose() {
    unawaited(_importSubscription?.cancel());
    _sourcePathController.dispose();
    _targetPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.initialFormat.label} Import Wizard'),
      content: SizedBox(
        width: 1080,
        height: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildStepHeader(),
            const SizedBox(height: 16),
            if (_error != null) ...<Widget>[
              _Banner(
                color: Theme.of(context).colorScheme.errorContainer,
                icon: Icons.error_outline_rounded,
                text: _error!,
              ),
              const SizedBox(height: 12),
            ],
            if (_warnings.isNotEmpty &&
                _step != GenericImportWizardStep.summary) ...<Widget>[
              _Banner(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                icon: Icons.warning_amber_rounded,
                text: _warnings.join('\n'),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(child: _buildStepBody()),
          ],
        ),
      ),
      actions: _buildActions(context),
    );
  }

  Widget _buildStepHeader() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final step in GenericImportWizardStep.values)
          ChoiceChip(
            label: Text(_stepLabel(step)),
            selected: _step == step,
            onSelected: (selected) {
              if (!selected) {
                return;
              }
              setState(() {
                _step = step;
              });
            },
          ),
        Chip(label: Text('Phase: ${_phase.name}')),
      ],
    );
  }

  Widget _buildStepBody() {
    return switch (_step) {
      GenericImportWizardStep.source => _buildSourceStep(),
      GenericImportWizardStep.target => _buildTargetStep(),
      GenericImportWizardStep.preview => _buildPreviewStep(),
      GenericImportWizardStep.transforms => _buildTransformsStep(),
      GenericImportWizardStep.execute => _buildExecuteStep(),
      GenericImportWizardStep.summary => _buildSummaryStep(),
    };
  }

  Widget _buildSourceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Confirm the source file and review the detected import family before loading a preview.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _sourcePathController,
                decoration: const InputDecoration(
                  labelText: 'Source path',
                  hintText: '/tmp/source.csv',
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
              onPressed: _phase == GenericImportJobPhase.inspecting
                  ? null
                  : _inspectSource,
              child: Text(
                _phase == GenericImportJobPhase.inspecting
                    ? 'Inspecting...'
                    : 'Load Preview',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card.outlined(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(widget.initialFormat.label),
            subtitle: Text(widget.initialFormat.description),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _inspection == null
              ? const _EmptyState(
                  title: 'No preview loaded yet',
                  message:
                      'Load the source preview to inspect tables, inferred columns, and row samples.',
                )
              : _buildInspectionOverview(),
        ),
      ],
    );
  }

  Widget _buildInspectionOverview() {
    final inspection = _inspection;
    if (inspection == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (inspection.explanation != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(inspection.explanation!),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            Chip(label: Text('Tables: ${inspection.tables.length}')),
            Chip(
              label: Text(
                'Rows: ${inspection.tables.fold<int>(0, (sum, table) => sum + table.rowCount)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: inspection.tables.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final table = inspection.tables[index];
                return ListTile(
                  title: Text(table.targetName),
                  subtitle: Text(
                    '${table.rowCount} rows • ${table.columns.length} columns${table.description == null ? '' : ' • ${table.description}'}',
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Choose whether to create a new DecentDB file or import into an existing target.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: false, label: Text('Create New')),
            ButtonSegment<bool>(value: true, label: Text('Use Existing')),
          ],
          selected: <bool>{_importIntoExistingTarget},
          onSelectionChanged: (selection) {
            setState(() {
              _importIntoExistingTarget = selection.first;
              _replaceExistingTarget = !_importIntoExistingTarget;
            });
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _targetPathController,
                decoration: InputDecoration(
                  labelText: _importIntoExistingTarget
                      ? 'Existing DecentDB target'
                      : 'New DecentDB target',
                  hintText: '/tmp/workspace.ddb',
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: () => _browseTarget(_importIntoExistingTarget),
              child: const Text('Browse'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Replace existing file when creating a new target'),
          subtitle: const Text(
            'Disable this to require a fresh target path if the file already exists.',
          ),
          value: _replaceExistingTarget,
          onChanged: _importIntoExistingTarget
              ? null
              : (value) {
                  setState(() {
                    _replaceExistingTarget = value;
                  });
                },
        ),
      ],
    );
  }

  Widget _buildPreviewStep() {
    final inspection = _inspection;
    if (inspection == null) {
      return const _EmptyState(
        title: 'Preview unavailable',
        message: 'Load the source first to inspect import options.',
      );
    }
    return Row(
      children: <Widget>[
        SizedBox(width: 320, child: _buildOptionsCard()),
        const SizedBox(width: 16),
        Expanded(child: _buildTablePreviewCard()),
      ],
    );
  }

  Widget _buildOptionsCard() {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: <Widget>[
            Text(
              'Preview Options',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            if (_supportsDelimitedOptions) ...<Widget>[
              DropdownButtonFormField<String>(
                initialValue: _options.delimiter,
                decoration: const InputDecoration(labelText: 'Delimiter'),
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: ',', child: Text('Comma (, )')),
                  DropdownMenuItem(value: '\t', child: Text('Tab (\\t)')),
                  DropdownMenuItem(value: ';', child: Text('Semicolon (;)')),
                  DropdownMenuItem(value: '|', child: Text('Pipe (|)')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _options = _options.copyWith(delimiter: value);
                  });
                },
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _options.headerRow,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _options = _options.copyWith(headerRow: value);
                  });
                },
                title: const Text('Treat the first row as headers'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<DelimitedMalformedRowStrategy>(
                initialValue: _options.malformedRowStrategy,
                decoration: const InputDecoration(labelText: 'Malformed rows'),
                items: DelimitedMalformedRowStrategy.values
                    .map(
                      (
                        strategy,
                      ) => DropdownMenuItem<DelimitedMalformedRowStrategy>(
                        value: strategy,
                        child: Text(
                          strategy ==
                                  DelimitedMalformedRowStrategy.padOrTruncate
                              ? 'Pad / truncate'
                              : 'Skip row',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _options = _options.copyWith(malformedRowStrategy: value);
                  });
                },
              ),
              const SizedBox(height: 12),
            ],
            if (_supportsStructuredOptions) ...<Widget>[
              DropdownButtonFormField<StructuredImportStrategy>(
                initialValue: _options.structuredStrategy,
                decoration: const InputDecoration(
                  labelText: 'Structure strategy',
                ),
                items: const <DropdownMenuItem<StructuredImportStrategy>>[
                  DropdownMenuItem(
                    value: StructuredImportStrategy.flatten,
                    child: Text('Flatten to one table'),
                  ),
                  DropdownMenuItem(
                    value: StructuredImportStrategy.normalize,
                    child: Text('Normalize child tables'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _options = _options.copyWith(structuredStrategy: value);
                  });
                },
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<GenericImportEncoding>(
              initialValue: _options.encoding,
              decoration: const InputDecoration(labelText: 'Encoding'),
              items: GenericImportEncoding.values
                  .map(
                    (encoding) => DropdownMenuItem<GenericImportEncoding>(
                      value: encoding,
                      child: Text(encoding.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _options = _options.copyWith(encoding: value);
                });
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _phase == GenericImportJobPhase.inspecting
                  ? null
                  : _inspectSource,
              child: const Text('Reload Preview'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTablePreviewCard() {
    final inspection = _inspection;
    if (inspection == null || inspection.tables.isEmpty) {
      return const _EmptyState(
        title: 'No tables detected',
        message: 'Adjust the preview options or choose another source file.',
      );
    }
    final focused = _focusedTable(inspection);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: focused.sourceId,
              decoration: const InputDecoration(labelText: 'Preview table'),
              items: inspection.tables
                  .map(
                    (table) => DropdownMenuItem<String>(
                      value: table.sourceId,
                      child: Text(table.targetName),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _focusedTableId = value;
                });
              },
            ),
            const SizedBox(height: 16),
            Text(
              focused.description ?? 'Preview rows',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: focused.previewRows.isEmpty
                  ? const _EmptyState(
                      title: 'No preview rows',
                      message:
                          'The source did not produce any rows for the selected table.',
                    )
                  : _PreviewGrid(rows: focused.previewRows),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransformsStep() {
    final inspection = _inspection;
    if (inspection == null || inspection.tables.isEmpty) {
      return const _EmptyState(
        title: 'Transforms unavailable',
        message: 'Load a source preview first.',
      );
    }
    final focused = _focusedTable(inspection);
    return Row(
      children: <Widget>[
        SizedBox(
          width: 320,
          child: Card.outlined(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: inspection.tables.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final table = inspection.tables[index];
                return CheckboxListTile(
                  value: table.selected,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    _updateTable(table.copyWith(selected: value));
                  },
                  title: Text(table.targetName),
                  subtitle: Text('${table.rowCount} rows'),
                  controlAffinity: ListTileControlAffinity.leading,
                  secondary: IconButton(
                    onPressed: () {
                      setState(() {
                        _focusedTableId = table.sourceId;
                      });
                    },
                    icon: const Icon(Icons.visibility_outlined),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: TextEditingController(text: focused.targetName),
                    onChanged: (value) {
                      _updateTable(focused.copyWith(targetName: value));
                    },
                    decoration: const InputDecoration(
                      labelText: 'Target table name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: focused.columns.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final column = focused.columns[index];
                        return Row(
                          children: <Widget>[
                            Expanded(
                              child: TextField(
                                controller: TextEditingController(
                                  text: column.targetName,
                                ),
                                onChanged: (value) {
                                  final columns = List<ImportColumnDraft>.from(
                                    focused.columns,
                                  );
                                  columns[index] = column.copyWith(
                                    targetName: value,
                                  );
                                  _updateTable(
                                    focused.copyWith(columns: columns),
                                  );
                                },
                                decoration: InputDecoration(
                                  labelText: column.sourceName,
                                  helperText:
                                      'Inferred: ${column.inferredTargetType}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 200,
                              child: DropdownButtonFormField<String>(
                                initialValue: column.targetType,
                                decoration: const InputDecoration(
                                  labelText: 'Target type',
                                ),
                                items: decentDbImportTargetTypes
                                    .map(
                                      (type) => DropdownMenuItem<String>(
                                        value: type,
                                        child: Text(type),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value == null) {
                                    return;
                                  }
                                  final columns = List<ImportColumnDraft>.from(
                                    focused.columns,
                                  );
                                  columns[index] = column.copyWith(
                                    targetType: value,
                                  );
                                  _updateTable(
                                    focused.copyWith(columns: columns),
                                  );
                                },
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
      ],
    );
  }

  Widget _buildExecuteStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Run the import in the background. The target file stays transactional where possible, and cancellation rolls back the current job.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card.outlined(
          child: ListTile(
            title: Text(_progress?.message ?? 'Ready to import'),
            subtitle: Text(
              _progress == null
                  ? 'No active import job.'
                  : '${_progress!.currentTableRowsCopied}/${_progress!.currentTableRowCount} rows in ${_progress!.currentTable}',
            ),
            trailing:
                _phase == GenericImportJobPhase.running ||
                    _phase == GenericImportJobPhase.cancelling
                ? const CircularProgressIndicator()
                : const Icon(Icons.play_circle_outline_rounded),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _inspection == null
              ? const _EmptyState(
                  title: 'Nothing queued',
                  message:
                      'Preview a source and choose a target before running the import.',
                )
              : ListView(
                  children: <Widget>[
                    for (final table in _inspection!.tables.where(
                      (table) => table.selected,
                    ))
                      ListTile(
                        title: Text(table.targetName),
                        subtitle: Text(
                          '${table.rowCount} rows • ${table.columns.length} columns',
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryStep() {
    if (_summary == null) {
      return const _EmptyState(
        title: 'No summary yet',
        message: 'Run the import to populate the summary view.',
      );
    }
    return ListView(
      children: <Widget>[
        ListTile(
          title: const Text('Status'),
          subtitle: Text(_summary!.statusMessage),
        ),
        ListTile(
          title: const Text('Target DecentDB'),
          subtitle: Text(_summary!.targetPath),
        ),
        ListTile(
          title: const Text('Source format'),
          subtitle: Text(_summary!.formatLabel),
        ),
        for (final entry in _summary!.rowsCopiedByTable.entries)
          ListTile(
            title: Text(entry.key),
            subtitle: Text('${entry.value} rows imported'),
          ),
        if (_summary!.warnings.isNotEmpty) ...<Widget>[
          const Divider(height: 32),
          Text('Warnings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final warning in _summary!.warnings)
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: Text(warning),
            ),
        ],
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    final isBusy =
        _phase == GenericImportJobPhase.inspecting ||
        _phase == GenericImportJobPhase.running ||
        _phase == GenericImportJobPhase.cancelling;
    return <Widget>[
      TextButton(
        onPressed: isBusy
            ? null
            : () {
                if (_summary != null) {
                  Navigator.of(context).pop(
                    GenericImportDialogResult(
                      targetPath: _summary!.targetPath,
                      summary: _summary!,
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop();
              },
        child: Text(_summary == null ? 'Close' : 'Done'),
      ),
      if (_step != GenericImportWizardStep.source)
        TextButton(
          onPressed: isBusy
              ? null
              : () {
                  setState(() {
                    _step = GenericImportWizardStep.values[_step.index - 1];
                  });
                },
          child: const Text('Back'),
        ),
      if (_step == GenericImportWizardStep.execute &&
          (_phase == GenericImportJobPhase.running ||
              _phase == GenericImportJobPhase.cancelling))
        FilledButton.tonal(
          onPressed: _phase == GenericImportJobPhase.cancelling
              ? null
              : _cancelImport,
          child: Text(
            _phase == GenericImportJobPhase.cancelling
                ? 'Cancelling...'
                : 'Cancel Import',
          ),
        )
      else
        FilledButton(
          onPressed: isBusy ? null : _handlePrimaryAction,
          child: Text(_primaryActionLabel),
        ),
    ];
  }

  String get _primaryActionLabel {
    return switch (_step) {
      GenericImportWizardStep.source => 'Next',
      GenericImportWizardStep.target => 'Next',
      GenericImportWizardStep.preview => 'Next',
      GenericImportWizardStep.transforms => 'Next',
      GenericImportWizardStep.execute => 'Run Import',
      GenericImportWizardStep.summary => 'Done',
    };
  }

  Future<void> _handlePrimaryAction() async {
    switch (_step) {
      case GenericImportWizardStep.source:
        if (_inspection == null) {
          await _inspectSource();
        }
        if (_inspection != null && mounted) {
          setState(() {
            _step = GenericImportWizardStep.target;
          });
        }
        break;
      case GenericImportWizardStep.target:
        if (_targetPathController.text.trim().isEmpty) {
          setState(() {
            _error = 'Choose a DecentDB target before continuing.';
          });
          return;
        }
        setState(() {
          _step = GenericImportWizardStep.preview;
        });
        break;
      case GenericImportWizardStep.preview:
        setState(() {
          _step = GenericImportWizardStep.transforms;
        });
        break;
      case GenericImportWizardStep.transforms:
        if (_inspection == null ||
            _inspection!.tables.where((table) => table.selected).isEmpty) {
          setState(() {
            _error = 'Select at least one table before running the import.';
          });
          return;
        }
        setState(() {
          _step = GenericImportWizardStep.execute;
        });
        break;
      case GenericImportWizardStep.execute:
        await _runImport();
        break;
      case GenericImportWizardStep.summary:
        if (!mounted || _summary == null) {
          return;
        }
        Navigator.of(context).pop(
          GenericImportDialogResult(
            targetPath: _summary!.targetPath,
            summary: _summary!,
          ),
        );
        break;
    }
  }

  Future<void> _browseSourceFile() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_genericImportSourceTypeGroup],
    );
    if (file == null) {
      return;
    }
    _sourcePathController.text = file.path;
    await _inspectSource();
  }

  Future<void> _browseTarget(bool existing) async {
    if (existing) {
      final file = await openFile(
        acceptedTypeGroups: const <XTypeGroup>[_decentDbTargetTypeGroup],
      );
      if (file != null) {
        _targetPathController.text = file.path;
      }
      return;
    }
    final location = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_decentDbTargetTypeGroup],
      suggestedName: 'workspace.ddb',
    );
    if (location != null) {
      _targetPathController.text = location.path;
    }
  }

  Future<void> _inspectSource() async {
    final sourcePath = _sourcePathController.text.trim();
    if (sourcePath.isEmpty) {
      setState(() {
        _error = 'Choose a source file to continue.';
      });
      return;
    }
    setState(() {
      _phase = GenericImportJobPhase.inspecting;
      _error = null;
      _warnings = <String>[];
    });
    try {
      final inspection = await _previewService.inspect(
        sourcePath: sourcePath,
        format: widget.initialFormat,
        options: _options,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _inspection = inspection;
        _warnings = inspection.warnings;
        _phase = GenericImportJobPhase.ready;
        _focusedTableId = inspection.tables.isEmpty
            ? null
            : inspection.tables.first.sourceId;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = GenericImportJobPhase.failed;
        _error = '$error';
      });
    }
  }

  Future<void> _runImport() async {
    final inspection = _inspection;
    if (inspection == null) {
      setState(() {
        _error = 'Preview the source before running the import.';
      });
      return;
    }
    final request = GenericImportRequest(
      jobId: DateTime.now().microsecondsSinceEpoch.toString(),
      sourcePath: _sourcePathController.text.trim(),
      targetPath: _targetPathController.text.trim(),
      importIntoExistingTarget: _importIntoExistingTarget,
      replaceExistingTarget: _replaceExistingTarget,
      formatKey: widget.initialFormat.key,
      options: _options,
      tables: inspection.tables,
    );
    await _importSubscription?.cancel();
    setState(() {
      _phase = GenericImportJobPhase.running;
      _progress = null;
      _summary = null;
      _error = null;
    });
    _importSubscription = _executionService.execute(request: request).listen((
      update,
    ) {
      if (!mounted) {
        return;
      }
      switch (update.kind) {
        case GenericImportUpdateKind.progress:
          setState(() {
            _phase = GenericImportJobPhase.running;
            _progress = update.progress;
          });
        case GenericImportUpdateKind.completed:
          setState(() {
            _phase = GenericImportJobPhase.completed;
            _summary = update.summary;
            _step = GenericImportWizardStep.summary;
          });
        case GenericImportUpdateKind.cancelled:
          setState(() {
            _phase = GenericImportJobPhase.cancelled;
            _summary = update.summary;
            _step = GenericImportWizardStep.summary;
          });
        case GenericImportUpdateKind.failed:
          setState(() {
            _phase = GenericImportJobPhase.failed;
            _error = update.message ?? 'The import failed.';
          });
      }
    });
  }

  Future<void> _cancelImport() async {
    final progress = _progress;
    final summary = _summary;
    final jobId = progress?.jobId ?? summary?.jobId;
    if (jobId == null) {
      return;
    }
    setState(() {
      _phase = GenericImportJobPhase.cancelling;
    });
    await _executionService.cancel(jobId);
  }

  ImportTableDraft _focusedTable(GenericImportInspection inspection) {
    return inspection.tables.firstWhere(
      (table) => table.sourceId == _focusedTableId,
      orElse: () => inspection.tables.first,
    );
  }

  void _updateTable(ImportTableDraft updated) {
    final inspection = _inspection;
    if (inspection == null) {
      return;
    }
    final tables = inspection.tables
        .map((table) => table.sourceId == updated.sourceId ? updated : table)
        .toList(growable: false);
    setState(() {
      _inspection = GenericImportInspection(
        sourcePath: inspection.sourcePath,
        format: inspection.format,
        options: inspection.options,
        tables: tables,
        warnings: inspection.warnings,
        explanation: inspection.explanation,
      );
    });
  }

  bool get _supportsDelimitedOptions {
    return switch (widget.initialFormat.key) {
      ImportFormatKey.csv ||
      ImportFormatKey.tsv ||
      ImportFormatKey.genericDelimited => true,
      _ => false,
    };
  }

  bool get _supportsStructuredOptions {
    return switch (widget.initialFormat.key) {
      ImportFormatKey.json ||
      ImportFormatKey.ndjson ||
      ImportFormatKey.xml => true,
      _ => false,
    };
  }

  String _stepLabel(GenericImportWizardStep step) {
    return switch (step) {
      GenericImportWizardStep.source => 'Source',
      GenericImportWizardStep.target => 'Target',
      GenericImportWizardStep.preview => 'Preview',
      GenericImportWizardStep.transforms => 'Transforms',
      GenericImportWizardStep.execute => 'Execute',
      GenericImportWizardStep.summary => 'Summary',
    };
  }
}

GenericImportOptions _defaultOptionsFor(ImportFormatKey key) {
  return switch (key) {
    ImportFormatKey.tsv => const GenericImportOptions(delimiter: '\t'),
    _ => const GenericImportOptions(),
  };
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PreviewGrid extends StatelessWidget {
  const _PreviewGrid({required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    final columns = rows.first.keys.toList(growable: false);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: <DataColumn>[
          for (final column in columns) DataColumn(label: Text(column)),
        ],
        rows: <DataRow>[
          for (final row in rows)
            DataRow(
              cells: <DataCell>[
                for (final column in columns)
                  DataCell(Text(formatCellValue(row[column]))),
              ],
            ),
        ],
      ),
    );
  }
}
