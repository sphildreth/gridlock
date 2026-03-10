import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../shared/widgets/panel_card.dart';
import '../application/workspace_controller.dart';
import '../domain/app_config.dart';
import '../domain/sql_autocomplete.dart';
import '../domain/sql_formatter.dart';
import '../domain/workspace_file_entry.dart';
import '../domain/workspace_models.dart';
import 'excel_import_dialog.dart';
import 'sqlite_import_dialog.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.controller});

  final WorkspaceController controller;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  late final TextEditingController _dbPathController = TextEditingController();
  late final TextEditingController _schemaFilterController =
      TextEditingController();
  late final TextEditingController _sqlController = TextEditingController();
  late final TextEditingController _paramsController = TextEditingController();
  late final TextEditingController _pageSizeController =
      TextEditingController();
  late final TextEditingController _delimiterController =
      TextEditingController();
  late final TextEditingController _exportPathController =
      TextEditingController();
  late final ScrollController _resultsScrollController = ScrollController()
    ..addListener(_onResultsScroll);
  late final ScrollController _resultsHorizontalController = ScrollController();
  late final FocusNode _sqlFocusNode = FocusNode(debugLabel: 'sql-editor');
  late final FocusNode _resultsFocusNode = FocusNode(debugLabel: 'results');
  final SqlAutocompleteEngine _autocompleteEngine =
      const SqlAutocompleteEngine();
  final SqlFormatter _sqlFormatter = const SqlFormatter();

  String? _selectedSchemaObjectName;
  String? _syncedTabId;
  bool _isDropTargetActive = false;

  @override
  void dispose() {
    _resultsHorizontalController.dispose();
    _resultsScrollController
      ..removeListener(_onResultsScroll)
      ..dispose();
    _resultsFocusNode.dispose();
    _sqlFocusNode.dispose();
    _exportPathController.dispose();
    _delimiterController.dispose();
    _pageSizeController.dispose();
    _paramsController.dispose();
    _sqlController.dispose();
    _schemaFilterController.dispose();
    _dbPathController.dispose();
    super.dispose();
  }

  void _onResultsScroll() {
    final controller = widget.controller;
    final tab = controller.tabById(controller.activeTabId);
    if (tab == null ||
        !_resultsScrollController.hasClients ||
        !tab.hasMoreRows ||
        tab.phase == QueryPhase.fetching) {
      return;
    }
    final threshold = _resultsScrollController.position.maxScrollExtent - 320;
    if (_resultsScrollController.position.pixels >= threshold) {
      controller.fetchNextPage(tabId: tab.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        _syncFormFields(controller);
        final filteredObjects = controller.filterSchemaObjects(
          _schemaFilterController.text,
        );
        final selectedObject = _selectedObjectFor(filteredObjects);
        final autocompleteResult = _autocompleteFor(controller);

        return DropTarget(
          enable: !controller.hasImportSession,
          onDragEntered: (_) {
            setState(() {
              _isDropTargetActive = true;
            });
          },
          onDragExited: (_) {
            setState(() {
              _isDropTargetActive = false;
            });
          },
          onDragDone: (details) async {
            setState(() {
              _isDropTargetActive = false;
            });
            await _handleIncomingFiles(details.files.map((file) => file.path));
          },
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _RunQueryIntent(),
              SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _RunQueryIntent(),
              SingleActivator(LogicalKeyboardKey.keyT, control: true):
                  _NewTabIntent(),
              SingleActivator(LogicalKeyboardKey.keyT, meta: true):
                  _NewTabIntent(),
              SingleActivator(LogicalKeyboardKey.tab, control: true):
                  _NextTabIntent(),
              SingleActivator(LogicalKeyboardKey.tab, meta: true):
                  _NextTabIntent(),
              SingleActivator(
                LogicalKeyboardKey.tab,
                control: true,
                shift: true,
              ): _PreviousTabIntent(),
              SingleActivator(LogicalKeyboardKey.tab, meta: true, shift: true):
                  _PreviousTabIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _RunQueryIntent: CallbackAction<_RunQueryIntent>(
                  onInvoke: (_) => controller.runActiveTab(),
                ),
                _NewTabIntent: CallbackAction<_NewTabIntent>(
                  onInvoke: (_) => controller.createTab(),
                ),
                _NextTabIntent: CallbackAction<_NextTabIntent>(
                  onInvoke: (_) => controller.nextTab(),
                ),
                _PreviousTabIntent: CallbackAction<_PreviousTabIntent>(
                  onInvoke: (_) => controller.previousTab(),
                ),
              },
              child: Scaffold(
                body: SafeArea(
                  child: Stack(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: <Widget>[
                            _Header(controller: controller),
                            const SizedBox(height: 20),
                            Expanded(
                              child: _WorkspaceBody(
                                sidebar: Column(
                                  children: <Widget>[
                                    Expanded(child: _buildConnectionPane()),
                                    const SizedBox(height: 16),
                                    Expanded(
                                      flex: 2,
                                      child: _buildSchemaPane(
                                        controller: controller,
                                        filteredObjects: filteredObjects,
                                        selectedObject: selectedObject,
                                      ),
                                    ),
                                  ],
                                ),
                                workbench: Column(
                                  children: <Widget>[
                                    Expanded(
                                      flex: 4,
                                      child: _buildSqlPane(
                                        controller.activeTab,
                                        autocompleteResult,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Expanded(
                                      flex: 5,
                                      child: _buildResultsPane(
                                        controller.activeTab,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isDropTargetActive)
                        const Positioned.fill(child: _DropOverlay()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSqliteImportDialog({String sourcePath = ''}) async {
    final controller = widget.controller;
    if (!controller.hasSqliteImportSession || sourcePath.trim().isNotEmpty) {
      controller.beginSqliteImport(sourcePath: sourcePath);
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SqliteImportDialog(controller: controller),
    );
    if (!mounted) {
      return;
    }
    controller.closeSqliteImportSession();
  }

  Future<void> _showExcelImportDialog({String sourcePath = ''}) async {
    final controller = widget.controller;
    if (!controller.hasExcelImportSession || sourcePath.trim().isNotEmpty) {
      controller.beginExcelImport(sourcePath: sourcePath);
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ExcelImportDialog(controller: controller),
    );
    if (!mounted) {
      return;
    }
    controller.closeExcelImportSession();
  }

  Future<void> _handleIncomingFiles(Iterable<String> rawPaths) async {
    final decision = decideWorkspaceIncomingFiles(rawPaths);
    final path = decision.primaryPath;
    if (path == null) {
      await _showIncomingFileNotice(
        title: 'No file detected',
        message: 'Drop a local DecentDB, SQLite, or Excel file to continue.',
      );
      return;
    }

    if (decision.hadMultipleFiles && mounted) {
      await _showIncomingFileNotice(
        title: 'One file at a time',
        message:
            'MVP supports importing one file at a time. Continuing with ${p.basename(path)}.',
      );
    }

    switch (decision.kind) {
      case WorkspaceIncomingFileKind.decentDb:
        _dbPathController.text = path;
        await widget.controller.openDatabase(path, createIfMissing: false);
        break;
      case WorkspaceIncomingFileKind.sqlite:
        await _showSqliteImportDialog(sourcePath: path);
        break;
      case WorkspaceIncomingFileKind.excel:
        await _showExcelImportDialog(sourcePath: path);
        break;
      case WorkspaceIncomingFileKind.sqlDump:
        await _showIncomingFileNotice(
          title: 'Import type not implemented yet',
          message:
              '${p.basename(path)} was recognized, but SQL dump import remains scheduled for a later phase.',
        );
        break;
      case WorkspaceIncomingFileKind.unknown:
        await _showIncomingFileNotice(
          title: 'Unknown file type',
          message:
              'Supported files are DecentDB `.ddb`, SQLite `.db`/`.sqlite`/`.sqlite3`, Excel `.xls`/`.xlsx`, and `.sql` dumps.',
        );
        break;
    }
  }

  Future<void> _showIncomingFileNotice({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildConnectionPane() {
    final controller = widget.controller;
    return PanelCard(
      title: 'Workspace',
      subtitle: controller.databasePath == null
          ? 'Open a DecentDB file, create a new one, or import a dropped SQLite or Excel source.'
          : controller.databasePath ?? '',
      actions: <Widget>[
        IconButton(
          tooltip: 'Reload schema',
          onPressed:
              controller.hasOpenDatabase &&
                  !controller.isSchemaLoading &&
                  !controller.isOpeningDatabase
              ? controller.refreshSchema
              : null,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _dbPathController,
              decoration: const InputDecoration(
                labelText: 'Database path',
                hintText: '/tmp/workbench.ddb',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: controller.isOpeningDatabase
                        ? null
                        : () => controller.openDatabase(
                            _dbPathController.text,
                            createIfMissing: false,
                          ),
                    child: const Text('Open Existing'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: controller.isOpeningDatabase
                        ? null
                        : () => controller.openDatabase(
                            _dbPathController.text,
                            createIfMissing: true,
                          ),
                    child: const Text('Create New'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.isOpeningDatabase
                    ? null
                    : () => _showSqliteImportDialog(),
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Import SQLite'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.isOpeningDatabase
                    ? null
                    : () => _showExcelImportDialog(),
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('Import Excel'),
              ),
            ),
            const SizedBox(height: 16),
            if (controller.workspaceError != null) ...<Widget>[
              _InlineBanner(
                color: Theme.of(context).colorScheme.errorContainer,
                icon: Icons.error_outline_rounded,
                text: controller.workspaceError!,
              ),
              const SizedBox(height: 12),
            ] else if (controller.workspaceMessage != null) ...<Widget>[
              _InlineBanner(
                color: Theme.of(context).colorScheme.secondaryContainer,
                icon: Icons.info_outline_rounded,
                text: controller.workspaceMessage!,
              ),
              const SizedBox(height: 12),
            ],
            Text('Recent files', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (controller.config.recentFiles.isEmpty)
              const _CompactEmptyState(
                title: 'No recent files yet',
                message: 'The most recent DecentDB paths will appear here.',
              )
            else
              Column(
                children: <Widget>[
                  for (final item in controller.config.recentFiles) ...<Widget>[
                    OutlinedButton(
                      onPressed: controller.isOpeningDatabase
                          ? null
                          : () {
                              _dbPathController.text = item;
                              controller.openDatabase(
                                item,
                                createIfMissing: false,
                              );
                            },
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.all(14),
                      ),
                      child: Text(
                        item,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchemaPane({
    required WorkspaceController controller,
    required List<SchemaObjectSummary> filteredObjects,
    required SchemaObjectSummary? selectedObject,
  }) {
    return PanelCard(
      title: 'Schema',
      subtitle: controller.hasOpenDatabase
          ? '${controller.schema.tables.length} tables, ${controller.schema.views.length} views, ${controller.schema.indexes.length} indexes'
          : 'Schema details appear after opening a database.',
      child: controller.isSchemaLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                TextField(
                  controller: _schemaFilterController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Filter schema',
                    hintText: 'tables, columns, indexes, constraints',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: controller.schema.objects.isEmpty
                      ? const _EmptyState(
                          title: 'No schema loaded',
                          message:
                              'Create a table or open an existing database to inspect objects and indexes.',
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final splitVertical = constraints.maxWidth < 420;
                            if (splitVertical) {
                              return Column(
                                children: <Widget>[
                                  Expanded(
                                    child: _buildSchemaObjectList(
                                      filteredObjects,
                                      selectedObject,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Expanded(
                                    child: _buildSchemaDetails(
                                      controller,
                                      selectedObject,
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              children: <Widget>[
                                SizedBox(
                                  width: 200,
                                  child: _buildSchemaObjectList(
                                    filteredObjects,
                                    selectedObject,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildSchemaDetails(
                                    controller,
                                    selectedObject,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSchemaObjectList(
    List<SchemaObjectSummary> filteredObjects,
    SchemaObjectSummary? selectedObject,
  ) {
    if (filteredObjects.isEmpty) {
      return const _CompactEmptyState(
        title: 'Nothing matched',
        message: 'Try a broader schema filter.',
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListView.separated(
        itemCount: filteredObjects.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        itemBuilder: (context, index) {
          final object = filteredObjects[index];
          final isSelected = object.name == selectedObject?.name;
          return Material(
            color: isSelected
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                setState(() {
                  _selectedSchemaObjectName = object.name;
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Icon(
                      object.kind == SchemaObjectKind.table
                          ? Icons.table_chart_rounded
                          : Icons.visibility_rounded,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            object.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${object.columns.length} columns',
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

  Widget _buildSchemaDetails(
    WorkspaceController controller,
    SchemaObjectSummary? object,
  ) {
    if (object == null) {
      return const _CompactEmptyState(
        title: 'Select an object',
        message: 'Choose a table or view to inspect details.',
      );
    }

    final relatedIndexes = controller.schema.indexesForObject(object.name);
    final notes = controller.schemaNotesForObject(object);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(object.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text(object.kind.name)),
                Chip(label: Text('${object.columns.length} columns')),
                Chip(label: Text('${relatedIndexes.length} indexes')),
              ],
            ),
            const SizedBox(height: 14),
            Text('Columns', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final column in object.columns) ...<Widget>[
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(column.name),
                subtitle: Text(column.descriptor),
              ),
              const Divider(height: 1),
            ],
            const SizedBox(height: 14),
            Text('Constraints', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (object.exposedConstraintSummaries.isEmpty)
              const Text('No exposed column-level constraints for this object.')
            else
              for (final constraint in object.exposedConstraintSummaries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(constraint),
                ),
            const SizedBox(height: 14),
            Text('Indexes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (relatedIndexes.isEmpty)
              const Text('No indexes associated with this object.')
            else
              for (final index in relatedIndexes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${index.name}: ${index.kind}'
                    '${index.unique ? ' | UNIQUE' : ''}'
                    ' | (${index.columns.join(", ")})',
                  ),
                ),
            if (object.ddl != null) ...<Widget>[
              const SizedBox(height: 14),
              Text('Definition', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    object.ddl!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Adapter Notes',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(note, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSqlPane(
    QueryTabState activeTab,
    AutocompleteResult autocompleteResult,
  ) {
    final controller = widget.controller;
    return PanelCard(
      title: 'SQL Workspace',
      subtitle:
          'Phase 3 adds schema-aware autocomplete, user-editable snippets, deterministic formatting, and persisted editor settings on top of the tabbed query workspace.',
      actions: <Widget>[
        FilledButton.icon(
          onPressed: controller.canRunActiveTab
              ? controller.runActiveTab
              : null,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Run SQL'),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: controller.canCancelActiveTab
              ? controller.cancelActiveQuery
              : null,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('Stop'),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final editorHeight = math.max(180.0, constraints.maxHeight * 0.42);
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: <Widget>[
                  _buildTabStrip(controller, activeTab),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: _formatActiveSql,
                          icon: const Icon(Icons.auto_fix_high_rounded),
                          label: const Text('Format SQL'),
                        ),
                        PopupMenuButton<SqlSnippet>(
                          onSelected: _insertSnippet,
                          itemBuilder: (context) {
                            return <PopupMenuEntry<SqlSnippet>>[
                              for (final snippet in controller.config.snippets)
                                PopupMenuItem<SqlSnippet>(
                                  value: snippet,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(snippet.name),
                                      Text(
                                        snippet.trigger,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                            ];
                          },
                          child: IgnorePointer(
                            child: OutlinedButton.icon(
                              onPressed: () {},
                              icon: const Icon(Icons.code_rounded),
                              label: const Text('Insert Snippet'),
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _showSnippetManager,
                          icon: const Icon(Icons.library_books_rounded),
                          label: const Text('Manage Snippets'),
                        ),
                        IconButton(
                          tooltip: 'Editor settings',
                          onPressed: _showEditorSettingsDialog,
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _paramsController,
                          onChanged: controller.updateActiveParameterJson,
                          decoration: const InputDecoration(
                            labelText: 'Parameters (JSON array)',
                            hintText: '[1, "alice", true]',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _pageSizeController,
                          decoration: const InputDecoration(
                            labelText: 'Page size',
                          ),
                          keyboardType: TextInputType.number,
                          onSubmitted: controller.updateDefaultPageSize,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: editorHeight,
                    child: Focus(
                      focusNode: _sqlFocusNode,
                      onKeyEvent: _handleEditorKeyEvent,
                      child: TextField(
                        controller: _sqlController,
                        onChanged: controller.updateActiveSql,
                        expands: true,
                        maxLines: null,
                        minLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.35,
                        ),
                        decoration: const InputDecoration(
                          alignLabelWithHint: true,
                          labelText: 'SQL',
                          hintText: 'SELECT 1 AS ready;',
                        ),
                      ),
                    ),
                  ),
                  if (!autocompleteResult.isEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    _buildAutocompletePanel(autocompleteResult),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        Chip(label: Text('State: ${activeTab.phase.name}')),
                        if (activeTab.elapsed != null)
                          Chip(
                            label: Text(
                              'Elapsed: ${activeTab.elapsed!.inMilliseconds} ms',
                            ),
                          ),
                        if (activeTab.rowsAffected != null)
                          Chip(
                            label: Text(
                              'Rows affected: ${activeTab.rowsAffected}',
                            ),
                          ),
                        Chip(
                          label: Text(
                            'Default page size: ${controller.config.defaultPageSize}',
                          ),
                        ),
                        if (activeTab.isResultPartial)
                          const Chip(label: Text('Partial results retained')),
                      ],
                    ),
                  ),
                  if (activeTab.statusMessage != null &&
                      activeTab.error == null) ...<Widget>[
                    const SizedBox(height: 12),
                    _InlineBanner(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      icon: activeTab.phase == QueryPhase.cancelled
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline_rounded,
                      text: activeTab.statusMessage!,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabStrip(
    WorkspaceController controller,
    QueryTabState activeTab,
  ) {
    return Row(
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final tab in controller.tabs) ...<Widget>[
                  _QueryTabChip(
                    tab: tab,
                    isActive: tab.id == activeTab.id,
                    onTap: () => controller.selectTab(tab.id),
                    onClose: () => controller.closeTab(tab.id),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: controller.createTab,
          icon: const Icon(Icons.add_rounded),
          label: const Text('New Tab'),
        ),
      ],
    );
  }

  Widget _buildResultsPane(QueryTabState activeTab) {
    final controller = widget.controller;
    return PanelCard(
      title: 'Results',
      subtitle: activeTab.resultColumns.isEmpty
          ? 'Each query tab owns its own results, error state, and export controls.'
          : '${activeTab.resultRows.length} rows loaded'
                '${activeTab.hasMoreRows ? ' | more rows available' : ''}'
                '${activeTab.isResultPartial ? ' | partial result' : ''}',
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _exportPathController,
                  onChanged: controller.updateActiveExportPath,
                  decoration: const InputDecoration(
                    labelText: 'CSV export path',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _delimiterController,
                  decoration: const InputDecoration(labelText: 'Delimiter'),
                  onSubmitted: controller.updateCsvDelimiter,
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Headers'),
                selected: controller.config.csvIncludeHeaders,
                onSelected: controller.updateCsvIncludeHeaders,
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: activeTab.isExporting
                    ? null
                    : controller.exportCurrentQuery,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  activeTab.isExporting ? 'Exporting...' : 'Export CSV',
                ),
              ),
            ],
          ),
          if (activeTab.error != null) ...<Widget>[
            const SizedBox(height: 12),
            _ErrorPanel(
              error: activeTab.error!,
              onCopyDetails: () => _copyActiveErrorDetails(activeTab),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Focus(
              focusNode: _resultsFocusNode,
              onKeyEvent: _handleResultsKeyEvent,
              child: activeTab.resultColumns.isEmpty
                  ? _buildResultSummary(activeTab)
                  : _buildResultsTable(activeTab),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSummary(QueryTabState tab) {
    if (tab.rowsAffected != null) {
      return Center(
        child: Text(
          'Statement finished with ${tab.rowsAffected} affected rows.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
    }

    final title = switch (tab.phase) {
      QueryPhase.cancelled => 'Query cancelled',
      QueryPhase.failed => 'Query failed',
      QueryPhase.opening ||
      QueryPhase.running ||
      QueryPhase.fetching => 'Running query',
      _ => 'No result set yet',
    };
    final message = switch (tab.phase) {
      QueryPhase.cancelled =>
        'Run the tab again or adjust the SQL. Partial rows remain visible only when at least one page arrived before cancellation.',
      QueryPhase.failed =>
        'Inspect the error details above or copy them for debugging.',
      QueryPhase.opening ||
      QueryPhase.running ||
      QueryPhase.fetching => 'The first page has not completed yet.',
      _ =>
        'Run a SELECT, EXPLAIN, CTE, or other row-producing statement to page through results.',
    };

    return _EmptyState(title: title, message: message);
  }

  Widget _buildResultsTable(QueryTabState tab) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math
            .max(constraints.maxWidth, tab.resultColumns.length * 220)
            .toDouble();

        return Scrollbar(
          controller: _resultsHorizontalController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _resultsHorizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: <Widget>[
                        for (final column in tab.resultColumns)
                          _ResultCell(
                            width: 220,
                            value: column,
                            isHeader: true,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Scrollbar(
                      controller: _resultsScrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _resultsScrollController,
                        itemCount:
                            tab.resultRows.length + (tab.hasMoreRows ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= tab.resultRows.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: tab.phase == QueryPhase.fetching
                                    ? const CircularProgressIndicator()
                                    : OutlinedButton.icon(
                                        onPressed: () => widget.controller
                                            .fetchNextPage(tabId: tab.id),
                                        icon: const Icon(
                                          Icons.expand_more_rounded,
                                        ),
                                        label: const Text('Load next page'),
                                      ),
                              ),
                            );
                          }

                          final row = tab.resultRows[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: <Widget>[
                                  for (final column in tab.resultColumns)
                                    _ResultCell(
                                      width: 220,
                                      value: formatCellValue(row[column]),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  AutocompleteResult _autocompleteFor(WorkspaceController controller) {
    final selection = _sqlController.selection;
    final offset = selection.isValid && selection.baseOffset >= 0
        ? selection.baseOffset
        : _sqlController.text.length;
    return _autocompleteEngine.suggest(
      sql: _sqlController.text,
      cursorOffset: offset,
      schema: controller.schema,
      config: controller.config,
    );
  }

  Widget _buildAutocompletePanel(AutocompleteResult autocompleteResult) {
    return SizedBox(
      height: 148,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                'Autocomplete',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: autocompleteResult.suggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = autocompleteResult.suggestions[index];
                  return ListTile(
                    dense: true,
                    onTap: () => _applyAutocompleteSuggestion(
                      autocompleteResult,
                      suggestion,
                    ),
                    leading: Icon(_suggestionIcon(suggestion.kind)),
                    title: Text(suggestion.label),
                    subtitle: Text(suggestion.detail),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _suggestionIcon(AutocompleteSuggestionKind kind) {
    return switch (kind) {
      AutocompleteSuggestionKind.object => Icons.table_rows_rounded,
      AutocompleteSuggestionKind.column => Icons.view_column_rounded,
      AutocompleteSuggestionKind.function => Icons.functions_rounded,
      AutocompleteSuggestionKind.keyword => Icons.key_rounded,
      AutocompleteSuggestionKind.snippet => Icons.code_rounded,
    };
  }

  void _applyAutocompleteSuggestion(
    AutocompleteResult result,
    AutocompleteSuggestion suggestion,
  ) {
    final current = _sqlController.text;
    final updated =
        current.substring(0, result.replaceStart) +
        suggestion.insertText +
        current.substring(result.replaceEnd);
    final offset = result.replaceStart + suggestion.insertText.length;
    _sqlController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: offset),
    );
    widget.controller.updateActiveSql(updated);
    _sqlFocusNode.requestFocus();
  }

  void _insertSnippet(SqlSnippet snippet) {
    _insertTextAtSelection(snippet.body);
  }

  void _insertTextAtSelection(String text) {
    final selection = _sqlController.selection;
    final start = selection.isValid && selection.start >= 0
        ? math.min(selection.start, selection.end)
        : _sqlController.text.length;
    final end = selection.isValid && selection.end >= 0
        ? math.max(selection.start, selection.end)
        : _sqlController.text.length;
    final updated = _sqlController.text.replaceRange(start, end, text);
    final offset = start + text.length;
    _sqlController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: offset),
    );
    widget.controller.updateActiveSql(updated);
    _sqlFocusNode.requestFocus();
  }

  void _formatActiveSql() {
    final source = _sqlController.text;
    if (source.trim().isEmpty) {
      return;
    }

    final selection = _sqlController.selection;
    final useSelection = selection.isValid && !selection.isCollapsed;
    final start = useSelection ? selection.start : 0;
    final end = useSelection ? selection.end : source.length;
    final formatted = _sqlFormatter.format(
      source.substring(start, end),
      settings: widget.controller.config.editorSettings,
    );
    final updated = source.replaceRange(start, end, formatted);
    _sqlController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: start + formatted.length),
    );
    widget.controller.updateActiveSql(updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          useSelection ? 'Formatted selected SQL.' : 'Formatted SQL document.',
        ),
      ),
    );
  }

  Future<void> _showSnippetManager() async {
    final controller = widget.controller;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final snippets = controller.config.snippets;
            return AlertDialog(
              title: const Text('SQL Snippets'),
              content: SizedBox(
                width: 720,
                height: 420,
                child: snippets.isEmpty
                    ? const _CompactEmptyState(
                        title: 'No snippets',
                        message: 'Add one to start inserting reusable SQL.',
                      )
                    : ListView.separated(
                        itemCount: snippets.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final snippet = snippets[index];
                          return ListTile(
                            title: Text(snippet.name),
                            subtitle: Text(
                              '${snippet.trigger} | ${snippet.description.isEmpty ? "No description" : snippet.description}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              children: <Widget>[
                                IconButton(
                                  tooltip: 'Insert',
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _insertSnippet(snippet);
                                  },
                                  icon: const Icon(Icons.north_west_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Edit',
                                  onPressed: () async {
                                    final edited =
                                        await _showSnippetEditorDialog(
                                          initial: snippet,
                                        );
                                    if (edited == null) {
                                      return;
                                    }
                                    await controller.saveSnippet(edited);
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(Icons.edit_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    await controller.deleteSnippet(snippet.id);
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () async {
                    final created = await _showSnippetEditorDialog();
                    if (created == null) {
                      return;
                    }
                    await controller.saveSnippet(created);
                    setDialogState(() {});
                  },
                  child: const Text('Add Snippet'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<SqlSnippet?> _showSnippetEditorDialog({SqlSnippet? initial}) async {
    final nameController = TextEditingController(text: initial?.name ?? '');
    final triggerController = TextEditingController(
      text: initial?.trigger ?? '',
    );
    final descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
    final bodyController = TextEditingController(text: initial?.body ?? '');
    String? validationMessage;

    final result = await showDialog<SqlSnippet>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(initial == null ? 'New Snippet' : 'Edit Snippet'),
              content: SizedBox(
                width: 640,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: triggerController,
                      decoration: const InputDecoration(labelText: 'Trigger'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      minLines: 6,
                      maxLines: 12,
                      decoration: const InputDecoration(
                        alignLabelWithHint: true,
                        labelText: 'SQL Body',
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                    ),
                    if (validationMessage != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty ||
                        triggerController.text.trim().isEmpty ||
                        bodyController.text.trim().isEmpty) {
                      setDialogState(() {
                        validationMessage =
                            'Name, trigger, and SQL body are required.';
                      });
                      return;
                    }
                    Navigator.of(context).pop(
                      SqlSnippet(
                        id: initial?.id ?? widget.controller.createSnippetId(),
                        name: nameController.text.trim(),
                        trigger: triggerController.text.trim(),
                        description: descriptionController.text.trim(),
                        body: bodyController.text,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    triggerController.dispose();
    descriptionController.dispose();
    bodyController.dispose();
    return result;
  }

  Future<void> _showEditorSettingsDialog() async {
    final controller = widget.controller;
    final suggestionLimitController = TextEditingController(
      text: controller.config.editorSettings.autocompleteMaxSuggestions
          .toString(),
    );
    final indentController = TextEditingController(
      text: controller.config.editorSettings.indentSpaces.toString(),
    );
    var autocompleteEnabled =
        controller.config.editorSettings.autocompleteEnabled;
    var uppercaseKeywords =
        controller.config.editorSettings.formatUppercaseKeywords;

    await showDialog<void>(
      context: context,
      builder: (context) {
        final navigator = Navigator.of(context);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Editor Settings'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: autocompleteEnabled,
                      onChanged: (value) {
                        setDialogState(() {
                          autocompleteEnabled = value;
                        });
                      },
                      title: const Text('Enable autocomplete'),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: uppercaseKeywords,
                      onChanged: (value) {
                        setDialogState(() {
                          uppercaseKeywords = value;
                        });
                      },
                      title: const Text('Uppercase SQL keywords on format'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: suggestionLimitController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max autocomplete suggestions',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: indentController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Formatter indent spaces',
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    await controller.updateAutocompleteEnabled(
                      autocompleteEnabled,
                    );
                    await controller.updateFormatterUppercaseKeywords(
                      uppercaseKeywords,
                    );
                    await controller.updateAutocompleteMaxSuggestions(
                      suggestionLimitController.text,
                    );
                    await controller.updateEditorIndentSpaces(
                      indentController.text,
                    );
                    if (mounted) {
                      navigator.pop();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    suggestionLimitController.dispose();
    indentController.dispose();
  }

  Future<void> _copyActiveErrorDetails(QueryTabState tab) async {
    final details = widget.controller.errorDetailsForTab(tab.id);
    if (details == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: details));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied error details to the clipboard.')),
    );
  }

  KeyEventResult _handleEditorKeyEvent(FocusNode node, KeyEvent event) {
    if (_isPlainTabKey(event)) {
      _resultsFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleResultsKeyEvent(FocusNode node, KeyEvent event) {
    if (_isPlainTabKey(event)) {
      _sqlFocusNode.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool _isPlainTabKey(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    return event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.tab &&
        !keyboard.isControlPressed &&
        !keyboard.isMetaPressed &&
        !keyboard.isAltPressed;
  }

  SchemaObjectSummary? _selectedObjectFor(
    List<SchemaObjectSummary> filteredObjects,
  ) {
    if (filteredObjects.isEmpty) {
      return null;
    }
    for (final object in filteredObjects) {
      if (object.name == _selectedSchemaObjectName) {
        return object;
      }
    }
    return filteredObjects.first;
  }

  void _syncFormFields(WorkspaceController controller) {
    if (controller.databasePath != null &&
        _dbPathController.text != controller.databasePath) {
      _dbPathController.text = controller.databasePath!;
    }

    final pageSize = controller.config.defaultPageSize.toString();
    if (_pageSizeController.text != pageSize) {
      _pageSizeController.text = pageSize;
    }
    if (_delimiterController.text != controller.config.csvDelimiter) {
      _delimiterController.text = controller.config.csvDelimiter;
    }

    final activeTab = controller.activeTab;
    final tabChanged = _syncedTabId != activeTab.id;
    if (tabChanged || _sqlController.text != activeTab.sql) {
      _sqlController.value = TextEditingValue(
        text: activeTab.sql,
        selection: TextSelection.collapsed(offset: activeTab.sql.length),
      );
    }
    if (tabChanged || _paramsController.text != activeTab.parameterJson) {
      _paramsController.value = TextEditingValue(
        text: activeTab.parameterJson,
        selection: TextSelection.collapsed(
          offset: activeTab.parameterJson.length,
        ),
      );
    }
    if (tabChanged || _exportPathController.text != activeTab.exportPath) {
      final exportPath = activeTab.exportPath.isEmpty
          ? controller.suggestExportPath(activeTab.id)
          : activeTab.exportPath;
      _exportPathController.value = TextEditingValue(
        text: exportPath,
        selection: TextSelection.collapsed(offset: exportPath.length),
      );
    }
    _syncedTabId = activeTab.id;
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({required this.sidebar, required this.workbench});

  final Widget sidebar;
  final Widget workbench;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 1180) {
          return Column(
            children: <Widget>[
              SizedBox(
                height: math.min(
                  440,
                  math.max(300, constraints.maxHeight * 0.42),
                ),
                child: sidebar,
              ),
              const SizedBox(height: 16),
              Expanded(child: workbench),
            ],
          );
        }
        return Row(
          children: <Widget>[
            SizedBox(width: 360, child: sidebar),
            const SizedBox(width: 16),
            Expanded(child: workbench),
          ],
        );
      },
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.file_download_outlined,
                      size: 44,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Drop a DecentDB or SQLite file',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '`.ddb` files open immediately. `.db`, `.sqlite`, and `.sqlite3` files launch the SQLite import wizard.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final WorkspaceController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFF7E2D6), Color(0xFFE6F1EE)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Decent Bench',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Phase 4 workspace: open or create DecentDB files, drag in a SQLite source for guided import, restore query tabs, author SQL with autocomplete and snippets, and iterate through paged results.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _HeaderFact(
                    label: 'Native library',
                    value: controller.nativeLibraryPath ?? 'Resolving...',
                  ),
                  const SizedBox(height: 8),
                  _HeaderFact(
                    label: 'Engine',
                    value: controller.engineVersion ?? 'No database open',
                  ),
                  const SizedBox(height: 8),
                  _HeaderFact(
                    label: 'Tabs',
                    value:
                        '${controller.tabs.length} total | ${controller.hasRunningTabs ? 'activity in progress' : 'idle'}',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderFact extends StatelessWidget {
  const _HeaderFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineBanner extends StatelessWidget {
  const _InlineBanner({
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
          children: <Widget>[
            Icon(icon),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onCopyDetails});

  final QueryErrorDetails error;
  final VoidCallback onCopyDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${error.stageLabel} error',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    error.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  if (error.code != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      'Code: ${error.code}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onCopyDetails,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.onErrorContainer,
                side: BorderSide(color: theme.colorScheme.onErrorContainer),
              ),
            ),
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
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(320, constraints.maxWidth),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactEmptyState extends StatelessWidget {
  const _CompactEmptyState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _QueryTabChip extends StatelessWidget {
  const _QueryTabChip({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  final QueryTabState tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: isActive ? colors.primaryContainer : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _phaseColor(colors, tab.phase),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(tab.title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Text(
                tab.phase.name,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close_rounded, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _phaseColor(ColorScheme colors, QueryPhase phase) {
    return switch (phase) {
      QueryPhase.opening ||
      QueryPhase.running ||
      QueryPhase.fetching ||
      QueryPhase.cancelling => colors.tertiary,
      QueryPhase.completed => colors.primary,
      QueryPhase.cancelled => colors.error,
      QueryPhase.failed => colors.error,
      QueryPhase.idle => colors.outline,
    };
  }
}

class _ResultCell extends StatelessWidget {
  const _ResultCell({
    required this.width,
    required this.value,
    this.isHeader = false,
  });

  final double width;
  final String value;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          value,
          maxLines: isHeader ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style:
              (isHeader
                      ? theme.textTheme.labelLarge
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(fontFamily: 'monospace'),
        ),
      ),
    );
  }
}

class _RunQueryIntent extends Intent {
  const _RunQueryIntent();
}

class _NewTabIntent extends Intent {
  const _NewTabIntent();
}

class _NextTabIntent extends Intent {
  const _NextTabIntent();
}

class _PreviousTabIntent extends Intent {
  const _PreviousTabIntent();
}
