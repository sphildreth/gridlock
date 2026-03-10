import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../application/menu_command_registry.dart';
import '../application/workspace_controller.dart';
import '../application/workspace_shell_controller.dart';
import '../domain/app_config.dart';
import '../domain/sql_autocomplete.dart';
import '../domain/sql_formatter.dart';
import '../domain/workspace_file_entry.dart';
import '../domain/workspace_models.dart';
import '../infrastructure/app_lifecycle_service.dart';
import '../infrastructure/shortcut_config_service.dart';
import 'excel_import_dialog.dart';
import 'shell/app_menu_bar.dart';
import 'shell/command_toolbar.dart';
import 'shell/properties_pane.dart';
import 'shell/results_pane.dart';
import 'shell/schema_explorer_pane.dart';
import 'shell/sql_editor_pane.dart';
import 'shell/status_bar.dart';
import 'shell/workspace_layout_shell.dart';
import 'sql_dump_import_dialog.dart';
import 'sqlite_import_dialog.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    this.appLifecycleService = const FlutterAppLifecycleService(),
  });

  final WorkspaceController controller;
  final AppLifecycleService appLifecycleService;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  static const _decentDbTypeGroup = XTypeGroup(
    label: 'DecentDB',
    extensions: <String>['ddb'],
  );

  late final TextEditingController _sqlController = TextEditingController();
  late final TextEditingController _paramsController = TextEditingController();
  late final TextEditingController _exportPathController =
      TextEditingController();
  late final TextEditingController _delimiterController =
      TextEditingController();
  late final FocusNode _sqlFocusNode = FocusNode(debugLabel: 'sql-editor')
    ..addListener(_handleFocusChanged);
  late final FocusNode _resultsFocusNode = FocusNode(debugLabel: 'results')
    ..addListener(_handleFocusChanged);
  late final ScrollController _resultsVerticalController = ScrollController()
    ..addListener(_onResultsScroll);
  late final ScrollController _resultsHorizontalController = ScrollController();
  late final ScrollController _editorScrollController = ScrollController();
  late final WorkspaceShellController _shellController =
      WorkspaceShellController(
        initialPreferences: widget.controller.config.shellPreferences,
        onPersist: (preferences, {statusMessage}) {
          return widget.controller.updateShellPreferences(
            preferences,
            statusMessage: statusMessage,
          );
        },
      );
  final ShortcutConfigService _shortcutConfigService =
      const ShortcutConfigService();
  final SqlAutocompleteEngine _autocompleteEngine =
      const SqlAutocompleteEngine();
  final SqlFormatter _sqlFormatter = const SqlFormatter();

  bool _didHydrateShellPreferences = false;
  bool _isDropTargetActive = false;
  String? _selectedSchemaObjectName;

  @override
  void dispose() {
    unawaited(_shellController.persistNow());
    _shellController.dispose();
    _editorScrollController.dispose();
    _resultsHorizontalController.dispose();
    _resultsVerticalController
      ..removeListener(_onResultsScroll)
      ..dispose();
    _sqlFocusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _resultsFocusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _delimiterController.dispose();
    _exportPathController.dispose();
    _paramsController.dispose();
    _sqlController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onResultsScroll() {
    if (!_resultsVerticalController.hasClients) {
      return;
    }
    final tab = widget.controller.activeTab;
    if (!tab.hasMoreRows || tab.phase == QueryPhase.fetching) {
      return;
    }
    final threshold = _resultsVerticalController.position.maxScrollExtent - 240;
    if (_resultsVerticalController.position.pixels >= threshold) {
      widget.controller.fetchNextPage(tabId: tab.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        _shellController,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        _hydrateShellPreferencesIfReady(controller);
        final activeTab = controller.activeTab;
        _syncControllers(controller, activeTab);

        final selectedObject = _selectedObject(controller);
        final shortcuts = _shortcutConfigService.load(controller.config);
        final registry = _buildMenuCommandRegistry(controller, shortcuts);
        final autocompleteResult = _autocompleteFor(controller);
        final shellPreferences = _shellController.preferences;

        return DropTarget(
          enable: !controller.hasImportSession,
          onDragEntered: (_) => setState(() => _isDropTargetActive = true),
          onDragExited: (_) => setState(() => _isDropTargetActive = false),
          onDragDone: (details) async {
            setState(() => _isDropTargetActive = false);
            await _handleIncomingFiles(details.files.map((file) => file.path));
          },
          child: Shortcuts(
            shortcuts: registry.buildShortcutMap(),
            child: Actions(
              actions: <Type, Action<Intent>>{
                MenuCommandIntent: CallbackAction<MenuCommandIntent>(
                  onInvoke: (intent) => registry.invoke(intent.commandId),
                ),
              },
              child: Scaffold(
                body: SafeArea(
                  child: Stack(
                    children: <Widget>[
                      Column(
                        children: <Widget>[
                          AppMenuBar(
                            registry: registry,
                            recentFiles: controller.config.recentFiles,
                            onOpenRecent: _openRecentWorkspace,
                          ),
                          CommandToolbar(registry: registry),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: WorkspaceLayoutShell(
                                controller: _shellController,
                                schemaExplorer: SchemaExplorerPane(
                                  schema: controller.schema,
                                  databasePath: controller.databasePath,
                                  selectedObjectName: _selectedSchemaObjectName,
                                  onSelectObject: (name) {
                                    setState(() {
                                      _selectedSchemaObjectName = name;
                                    });
                                  },
                                  onRefresh: () {
                                    controller.refreshSchema();
                                  },
                                  isLoading:
                                      controller.isSchemaLoading ||
                                      controller.isOpeningDatabase,
                                ),
                                propertiesPane: PropertiesPane(
                                  object: selectedObject,
                                  relatedIndexes: selectedObject == null
                                      ? const <IndexSummary>[]
                                      : controller.schema.indexesForObject(
                                          selectedObject.name,
                                        ),
                                  notes: selectedObject == null
                                      ? _defaultInspectorNotes(controller)
                                      : controller.schemaNotesForObject(
                                          selectedObject,
                                        ),
                                ),
                                sqlEditor: SqlEditorPane(
                                  tabs: controller.tabs,
                                  activeTab: activeTab,
                                  sqlController: _sqlController,
                                  paramsController: _paramsController,
                                  editorScrollController:
                                      _editorScrollController,
                                  focusNode: _sqlFocusNode,
                                  autocompleteResult: autocompleteResult,
                                  snippets: controller.config.snippets,
                                  zoomFactor: shellPreferences.editorZoom,
                                  onSqlChanged: controller.updateActiveSql,
                                  onParamsChanged:
                                      controller.updateActiveParameterJson,
                                  onSelectTab: controller.selectTab,
                                  onCloseTab: controller.closeTab,
                                  onNewTab: () => controller.createTab(),
                                  onRunQuery: () {
                                    controller.runActiveTab();
                                  },
                                  onStopQuery: () {
                                    controller.cancelActiveQuery();
                                  },
                                  onFormatSql: _formatActiveSql,
                                  onInsertSnippet: _insertSnippet,
                                  onManageSnippets: () {
                                    _showSnippetBrowser();
                                  },
                                  onApplyAutocomplete: (suggestion) =>
                                      _applyAutocompleteSuggestion(
                                        autocompleteResult,
                                        suggestion,
                                      ),
                                  canRun: controller.canRunActiveTab,
                                  canStop: controller.canCancelActiveTab,
                                ),
                                resultsPane: Focus(
                                  focusNode: _resultsFocusNode,
                                  child: ResultsPane(
                                    activeTab: activeTab,
                                    activeResultsTab:
                                        shellPreferences.activeResultsTab,
                                    exportPathController: _exportPathController,
                                    delimiterController: _delimiterController,
                                    verticalScrollController:
                                        _resultsVerticalController,
                                    horizontalScrollController:
                                        _resultsHorizontalController,
                                    csvIncludeHeaders:
                                        controller.config.csvIncludeHeaders,
                                    onResultsTabChanged:
                                        _shellController.setActiveResultsTab,
                                    onExportPathChanged:
                                        controller.updateActiveExportPath,
                                    onDelimiterSubmitted:
                                        controller.updateCsvDelimiter,
                                    onHeadersChanged: (value) {
                                      controller.updateCsvIncludeHeaders(value);
                                    },
                                    onExportCsv: () {
                                      controller.exportCurrentQuery();
                                    },
                                    onLoadNextPage: () {
                                      controller.fetchNextPage();
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (shellPreferences.showStatusBar)
                            StatusBar(
                              statusMessage:
                                  controller.workspaceError ??
                                  controller.workspaceMessage ??
                                  'Ready',
                              workspaceLabel:
                                  'Workspace: ${controller.databasePath == null ? 'sample.decentdb' : p.basename(controller.databasePath!)}',
                              lastExecutionLabel:
                                  'Last execution: ${activeTab.elapsed?.inMilliseconds ?? 142} ms',
                              rowsLabel:
                                  'Rows: ${activeTab.resultRows.isNotEmpty ? activeTab.resultRows.length : activeTab.rowsAffected ?? 250}',
                              editorModeLabel: _editorModeLabel(),
                            ),
                        ],
                      ),
                      if (_isDropTargetActive) const _DropOverlay(),
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

  void _hydrateShellPreferencesIfReady(WorkspaceController controller) {
    if (_didHydrateShellPreferences || controller.isInitializing) {
      return;
    }
    _shellController.replacePreferences(controller.config.shellPreferences);
    _didHydrateShellPreferences = true;
  }

  void _syncControllers(
    WorkspaceController controller,
    QueryTabState activeTab,
  ) {
    _syncTextController(_sqlController, activeTab.sql);
    _syncTextController(_paramsController, activeTab.parameterJson);
    _syncTextController(_exportPathController, activeTab.exportPath);
    _syncTextController(_delimiterController, controller.config.csvDelimiter);
  }

  void _syncTextController(TextEditingController controller, String value) {
    if (controller.text == value) {
      return;
    }
    final offset = math.min(value.length, controller.selection.baseOffset);
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: math.max(offset, 0)),
    );
  }

  SchemaObjectSummary? _selectedObject(WorkspaceController controller) {
    if (_selectedSchemaObjectName != null) {
      final selected = controller.schema.objectNamed(
        _selectedSchemaObjectName!,
      );
      if (selected != null) {
        return selected;
      }
    }
    final fallback = controller.schema.objects.isNotEmpty
        ? controller.schema.objects.first
        : null;
    _selectedSchemaObjectName ??= fallback?.name;
    return fallback;
  }

  List<String> _defaultInspectorNotes(WorkspaceController controller) {
    if (controller.databasePath != null) {
      return const <String>[
        'Select an object in Schema Explorer to inspect columns, indexes, and DDL.',
      ];
    }
    return const <String>[
      'No database is open yet. The shell is showing realistic placeholders so layout and density can be evaluated.',
    ];
  }

  String _editorModeLabel() {
    if (_resultsFocusNode.hasFocus) {
      return 'Grid mode';
    }
    if (_sqlFocusNode.hasFocus) {
      return 'Editor mode';
    }
    return 'Ready mode';
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

  MenuCommandRegistry _buildMenuCommandRegistry(
    WorkspaceController controller,
    Map<String, ShortcutBinding> shortcuts,
  ) {
    MenuCommand command({
      required String id,
      required String label,
      required IconData icon,
      required Future<void> Function() onInvoke,
      bool enabled = true,
      bool checked = false,
    }) {
      return MenuCommand(
        id: id,
        label: label,
        icon: icon,
        enabled: enabled,
        checked: checked,
        shortcut: shortcuts[id],
        onInvoke: onInvoke,
      );
    }

    final prefs = _shellController.preferences;
    return MenuCommandRegistry(
      commands: <MenuCommand>[
        command(
          id: 'file_new',
          label: 'New',
          icon: Icons.note_add_outlined,
          onInvoke: _createNewWorkspace,
        ),
        command(
          id: 'file_open',
          label: 'Open...',
          icon: Icons.folder_open_outlined,
          onInvoke: _openWorkspace,
        ),
        command(
          id: 'file_save',
          label: 'Save',
          icon: Icons.save_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Save',
            'Workspace state already persists automatically. Database save commands will be wired when file lifecycle behavior is defined.',
          ),
        ),
        command(
          id: 'file_save_as',
          label: 'Save As...',
          icon: Icons.save_as_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Save As',
            'Database duplication is not wired in this shell proof yet.',
          ),
        ),
        command(
          id: 'file_close',
          label: 'Close',
          icon: Icons.close_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Close Workspace',
            'Open another workspace or use Exit. Close semantics are still being defined.',
          ),
        ),
        command(
          id: 'file_exit',
          label: 'Exit',
          icon: Icons.power_settings_new_outlined,
          onInvoke: widget.appLifecycleService.requestExit,
        ),
        command(
          id: 'edit_undo',
          label: 'Undo',
          icon: Icons.undo_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Undo',
            'Editor undo/redo remains delegated to the native text field for now.',
          ),
        ),
        command(
          id: 'edit_redo',
          label: 'Redo',
          icon: Icons.redo_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Redo',
            'Editor undo/redo remains delegated to the native text field for now.',
          ),
        ),
        command(
          id: 'edit_cut',
          label: 'Cut',
          icon: Icons.content_cut_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Cut',
            'Text editing context commands will be bound per focused field in a later pass.',
          ),
        ),
        command(
          id: 'edit_copy',
          label: 'Copy',
          icon: Icons.copy_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Copy',
            'Text editing context commands will be bound per focused field in a later pass.',
          ),
        ),
        command(
          id: 'edit_paste',
          label: 'Paste',
          icon: Icons.content_paste_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Paste',
            'Text editing context commands will be bound per focused field in a later pass.',
          ),
        ),
        command(
          id: 'edit_find',
          label: 'Find',
          icon: Icons.search_outlined,
          onInvoke: () async {
            _sqlFocusNode.requestFocus();
            await _showPlaceholderNotice(
              'Find',
              'The editor is focused. Inline find UI is a follow-up command surface.',
            );
          },
        ),
        command(
          id: 'edit_find_next',
          label: 'Find Next',
          icon: Icons.find_replace_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Find Next',
            'Find navigation will be added once inline find state exists.',
          ),
        ),
        command(
          id: 'edit_select_all',
          label: 'Select All',
          icon: Icons.select_all_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Select All',
            'Select-all will follow the focused editor/result surface in a later pass.',
          ),
        ),
        command(
          id: 'import_excel',
          label: 'Import Excel...',
          icon: Icons.table_chart_outlined,
          onInvoke: _showExcelImportDialog,
        ),
        command(
          id: 'import_sqlite',
          label: 'Import SQLite...',
          icon: Icons.storage_outlined,
          onInvoke: _showSqliteImportDialog,
        ),
        command(
          id: 'import_sql_dump',
          label: 'Import SQL Dump...',
          icon: Icons.description_outlined,
          onInvoke: _showSqlDumpImportDialog,
        ),
        command(
          id: 'import_from_database',
          label: 'Import From Database...',
          icon: Icons.cloud_sync_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Import From Database',
            'External live database imports are represented in the shell but not wired in this proof.',
          ),
        ),
        command(
          id: 'import_rerun_last',
          label: 'Re-run Last Import',
          icon: Icons.restart_alt_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Re-run Last Import',
            'Recent import recipes are a follow-up workflow.',
          ),
        ),
        command(
          id: 'import_open_wizard',
          label: 'Open Import Wizard...',
          icon: Icons.file_open_outlined,
          onInvoke: _showImportChooser,
        ),
        command(
          id: 'export_results_csv',
          label: 'Export Results as CSV...',
          icon: Icons.file_download_outlined,
          onInvoke: controller.exportCurrentQuery,
          enabled: true,
        ),
        command(
          id: 'export_results_json',
          label: 'Export Results as JSON...',
          icon: Icons.data_object_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Export JSON',
            'JSON export is represented in the proof menu but not implemented yet.',
          ),
        ),
        command(
          id: 'export_results_parquet',
          label: 'Export Results as Parquet...',
          icon: Icons.view_column_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Export Parquet',
            'Parquet export is represented in the proof menu but not implemented yet.',
          ),
        ),
        command(
          id: 'export_results_excel',
          label: 'Export Results as Excel...',
          icon: Icons.table_view_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Export Excel',
            'Excel export is represented in the proof menu but not implemented yet.',
          ),
        ),
        command(
          id: 'export_table',
          label: 'Export Table...',
          icon: Icons.table_rows_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Export Table',
            'Table-level export workflows will reuse the results/export pipeline.',
          ),
        ),
        command(
          id: 'export_schema',
          label: 'Export Schema...',
          icon: Icons.schema_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Export Schema',
            'Schema export is a shell placeholder in this proof.',
          ),
        ),
        command(
          id: 'export_rerun_last',
          label: 'Re-run Last Export',
          icon: Icons.replay_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Re-run Last Export',
            'Reusable export recipes are a follow-up workflow.',
          ),
        ),
        command(
          id: 'view_reset_layout',
          label: 'Reset Layout',
          icon: Icons.space_dashboard_outlined,
          onInvoke: () async => _shellController.resetLayout(),
        ),
        command(
          id: 'view_toggle_schema',
          label: 'Show/Hide Schema Explorer',
          icon: Icons.account_tree_outlined,
          checked: prefs.showSchemaExplorer,
          onInvoke: () async => _shellController.setSchemaExplorerVisible(
            !prefs.showSchemaExplorer,
          ),
        ),
        command(
          id: 'view_toggle_properties',
          label: 'Show/Hide Properties',
          icon: Icons.info_outline,
          checked: prefs.showPropertiesPane,
          onInvoke: () async => _shellController.setPropertiesPaneVisible(
            !prefs.showPropertiesPane,
          ),
        ),
        command(
          id: 'view_toggle_results',
          label: 'Show/Hide Results',
          icon: Icons.table_view_outlined,
          checked: prefs.showResultsPane,
          onInvoke: () async =>
              _shellController.setResultsPaneVisible(!prefs.showResultsPane),
        ),
        command(
          id: 'view_toggle_status_bar',
          label: 'Show/Hide Status Bar',
          icon: Icons.horizontal_rule_outlined,
          checked: prefs.showStatusBar,
          onInvoke: () async =>
              _shellController.setStatusBarVisible(!prefs.showStatusBar),
        ),
        command(
          id: 'view_zoom_in',
          label: 'Zoom In',
          icon: Icons.zoom_in_outlined,
          onInvoke: () async => _shellController.zoomIn(),
        ),
        command(
          id: 'view_zoom_out',
          label: 'Zoom Out',
          icon: Icons.zoom_out_outlined,
          onInvoke: () async => _shellController.zoomOut(),
        ),
        command(
          id: 'view_zoom_reset',
          label: 'Reset Zoom',
          icon: Icons.center_focus_strong_outlined,
          onInvoke: () async => _shellController.resetZoom(),
        ),
        command(
          id: 'tools_run_query',
          label: 'Run Query',
          icon: Icons.play_arrow_outlined,
          onInvoke: controller.runActiveTab,
          enabled: controller.canRunActiveTab,
        ),
        command(
          id: 'tools_stop_query',
          label: 'Stop Query',
          icon: Icons.stop_circle_outlined,
          onInvoke: controller.cancelActiveQuery,
          enabled: controller.canCancelActiveTab,
        ),
        command(
          id: 'tools_format_sql',
          label: 'Format SQL',
          icon: Icons.auto_fix_high_outlined,
          onInvoke: () async => _formatActiveSql(),
        ),
        command(
          id: 'tools_new_query_tab',
          label: 'New Query Tab',
          icon: Icons.add_box_outlined,
          onInvoke: () async => controller.createTab(),
        ),
        command(
          id: 'tools_query_history',
          label: 'Query History',
          icon: Icons.history_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Query History',
            'History persistence is not wired in this shell proof yet.',
          ),
        ),
        command(
          id: 'tools_snippets',
          label: 'Snippets',
          icon: Icons.snippet_folder_outlined,
          onInvoke: _showSnippetBrowser,
        ),
        command(
          id: 'tools_manage_connections',
          label: 'Manage Connections',
          icon: Icons.settings_ethernet_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Manage Connections',
            'Live connection management is a placeholder in this DecentDB-first shell.',
          ),
        ),
        command(
          id: 'tools_options',
          label: 'Options / Preferences',
          icon: Icons.tune_outlined,
          onInvoke: _showPreferencesDialog,
        ),
        command(
          id: 'help_docs',
          label: 'Documentation',
          icon: Icons.menu_book_outlined,
          onInvoke: _showDocumentationDialog,
        ),
        command(
          id: 'help_keyboard_shortcuts',
          label: 'Keyboard Shortcuts',
          icon: Icons.keyboard_outlined,
          onInvoke: () => _showShortcutDialog(shortcuts),
        ),
        command(
          id: 'help_about',
          label: 'About Decent Bench',
          icon: Icons.info_outline,
          onInvoke: _showAboutDialog,
        ),
      ],
    );
  }

  Future<void> _createNewWorkspace() async {
    final result = await getSaveLocation(
      suggestedName: 'workspace.ddb',
      acceptedTypeGroups: const <XTypeGroup>[_decentDbTypeGroup],
    );
    if (result == null) {
      return;
    }
    await widget.controller.openDatabase(result.path, createIfMissing: true);
  }

  Future<void> _openWorkspace() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_decentDbTypeGroup],
    );
    if (file == null) {
      return;
    }
    await widget.controller.openDatabase(file.path, createIfMissing: false);
  }

  Future<void> _openRecentWorkspace(String path) async {
    await widget.controller.openDatabase(path, createIfMissing: false);
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

  Future<void> _showSqlDumpImportDialog({String sourcePath = ''}) async {
    final controller = widget.controller;
    if (!controller.hasSqlDumpImportSession || sourcePath.trim().isNotEmpty) {
      controller.beginSqlDumpImport(sourcePath: sourcePath);
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SqlDumpImportDialog(controller: controller),
    );
    if (!mounted) {
      return;
    }
    controller.closeSqlDumpImportSession();
  }

  Future<void> _showImportChooser() {
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Open Import Wizard'),
          content: const Text(
            'Choose the source type to launch a wizard with realistic desktop flow.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showExcelImportDialog();
              },
              child: const Text('Excel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showSqliteImportDialog();
              },
              child: const Text('SQLite'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showSqlDumpImportDialog();
              },
              child: const Text('SQL Dump'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleIncomingFiles(Iterable<String> rawPaths) async {
    final decision = decideWorkspaceIncomingFiles(rawPaths);
    final path = decision.primaryPath;
    if (path == null) {
      await _showPlaceholderNotice(
        'No file detected',
        'Drop a DecentDB, SQLite, Excel, or SQL dump file to continue.',
      );
      return;
    }
    if (decision.hadMultipleFiles) {
      await _showPlaceholderNotice(
        'One file at a time',
        'MVP import currently continues with ${p.basename(path)}.',
      );
    }

    switch (decision.kind) {
      case WorkspaceIncomingFileKind.decentDb:
        await widget.controller.openDatabase(path, createIfMissing: false);
        break;
      case WorkspaceIncomingFileKind.sqlite:
        await _showSqliteImportDialog(sourcePath: path);
        break;
      case WorkspaceIncomingFileKind.excel:
        await _showExcelImportDialog(sourcePath: path);
        break;
      case WorkspaceIncomingFileKind.sqlDump:
        await _showSqlDumpImportDialog(sourcePath: path);
        break;
      case WorkspaceIncomingFileKind.unknown:
        await _showPlaceholderNotice(
          'Unknown file type',
          'Supported files are `.ddb`, `.db`/`.sqlite`/`.sqlite3`, `.xls`/`.xlsx`, and `.sql`.',
        );
        break;
    }
  }

  void _formatActiveSql() {
    final formatted = _sqlFormatter.format(
      _sqlController.text,
      settings: widget.controller.config.editorSettings,
    );
    _sqlController.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    widget.controller.updateActiveSql(formatted);
  }

  void _insertSnippet(SqlSnippet snippet) {
    final text = _sqlController.text;
    final selection = _sqlController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final replacement = snippet.body;
    final updated =
        text.substring(0, start) + replacement + text.substring(end);
    final offset = start + replacement.length;
    _sqlController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: offset),
    );
    widget.controller.updateActiveSql(updated);
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
  }

  Future<void> _showSnippetBrowser() {
    final snippets = widget.controller.config.snippets;
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('SQL Snippets'),
          content: SizedBox(
            width: 620,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: snippets.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final snippet = snippets[index];
                return ListTile(
                  title: Text(snippet.name),
                  subtitle: Text(snippet.description),
                  trailing: Text(snippet.trigger),
                  onTap: () {
                    Navigator.of(context).pop();
                    _insertSnippet(snippet);
                  },
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showShortcutDialog(Map<String, ShortcutBinding> shortcuts) {
    final sorted = shortcuts.values.toList()
      ..sort((left, right) => left.commandId.compareTo(right.commandId));
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Keyboard Shortcuts'),
          content: SizedBox(
            width: 520,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final shortcut = sorted[index];
                return ListTile(
                  dense: true,
                  title: Text(shortcut.commandId.replaceAll('_', ' ')),
                  trailing: Text(
                    shortcut.displayLabel,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(fontFamily: 'monospace'),
                  ),
                );
              },
            ),
          ),
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

  Future<void> _showDocumentationDialog() {
    return _showPlaceholderNotice(
      'Documentation',
      'This shell proof emphasizes import, query, and export workflows. Use the menu bar, keyboard shortcuts, and draggable panes to evaluate desktop behavior.',
    );
  }

  Future<void> _showPreferencesDialog() {
    final config = widget.controller.config;
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Options / Preferences'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Default page size: ${config.defaultPageSize}'),
                const SizedBox(height: 8),
                Text('CSV delimiter: ${config.csvDelimiter}'),
                const SizedBox(height: 8),
                Text(
                  'Autocomplete suggestions: ${config.editorSettings.autocompleteMaxSuggestions}',
                ),
                const SizedBox(height: 8),
                Text(
                  'Editor zoom: ${(_shellController.preferences.editorZoom * 100).round()}%',
                ),
                const SizedBox(height: 12),
                const Text(
                  'This dialog is intentionally lightweight in the proof. It shows where shell, editor, and export preferences will converge.',
                ),
              ],
            ),
          ),
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

  Future<void> _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Decent Bench',
      applicationVersion: '0.1.0 shell proof',
      children: const <Widget>[
        Text(
          'Classic desktop shell prototype for a DecentDB-first SQL workbench.',
        ),
      ],
    );
    return Future<void>.value();
  }

  Future<void> _showPlaceholderNotice(String title, String message) {
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
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.18),
      child: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.primary),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.file_download_outlined,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Drop file to open or import',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'DecentDB files open directly. SQLite, Excel, and SQL dumps launch the matching import wizard.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
