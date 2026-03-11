import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_metadata.dart';
import '../../../app/startup_launch_options.dart';
import '../../../app/theme_system/theme_manager.dart';
import '../../import/application/import_manager.dart';
import '../../import/domain/import_models.dart';
import '../../import/presentation/generic_import_dialog.dart';
import '../../import/presentation/import_archive_chooser_dialog.dart';
import '../application/menu_command_registry.dart';
import '../application/workspace_controller.dart';
import '../application/workspace_shell_controller.dart';
import '../domain/app_config.dart';
import '../domain/sql_autocomplete.dart';
import '../domain/sql_execution_target.dart';
import '../domain/sql_editor_selection.dart';
import '../domain/sql_formatter.dart';
import '../domain/workspace_file_entry.dart';
import '../domain/workspace_models.dart';
import '../infrastructure/app_lifecycle_service.dart';
import '../infrastructure/shortcut_config_service.dart';
import 'excel_import_dialog.dart';
import 'export_results_csv_dialog.dart';
import 'preferences_dialog.dart';
import 'shell/app_menu_bar.dart';
import 'shell/command_toolbar.dart';
import 'shell/properties_pane.dart';
import 'shell/results_pane.dart';
import 'shell/schema_explorer_pane.dart';
import 'shell/schema_browser_models.dart';
import 'shell/sql_editor_pane.dart';
import 'shell/sql_highlighting_text_controller.dart';
import 'shell/status_bar.dart';
import 'shell/workspace_layout_shell.dart';
import 'sql_dump_import_dialog.dart';
import 'sqlite_import_dialog.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.controller,
    required this.themeManager,
    this.appLifecycleService = const FlutterAppLifecycleService(),
    this.startupLaunchOptions = const StartupLaunchOptions(),
  });

  final WorkspaceController controller;
  final ThemeManager themeManager;
  final AppLifecycleService appLifecycleService;
  final StartupLaunchOptions startupLaunchOptions;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  static const _decentDbTypeGroup = XTypeGroup(
    label: 'DecentDB',
    extensions: <String>['ddb'],
  );
  static const _csvTypeGroup = XTypeGroup(
    label: 'CSV',
    extensions: <String>['csv'],
  );

  late final SqlHighlightingTextEditingController _sqlController =
      SqlHighlightingTextEditingController()
        ..addListener(_handleSqlEditorStateChanged);
  late final TextEditingController _paramsController = TextEditingController();
  late final TextEditingController _findController = TextEditingController();
  late final FocusNode _sqlFocusNode = FocusNode(debugLabel: 'sql-editor')
    ..addListener(_handleFocusChanged);
  late final FocusNode _paramsFocusNode = FocusNode(debugLabel: 'sql-params')
    ..addListener(_handleFocusChanged);
  late final FocusNode _resultsFocusNode = FocusNode(debugLabel: 'results')
    ..addListener(_handleFocusChanged);
  late final FocusNode _findFocusNode = FocusNode(debugLabel: 'editor-find')
    ..addListener(_handleFocusChanged);
  late final UndoHistoryController _sqlUndoController = UndoHistoryController();
  late final UndoHistoryController _paramsUndoController =
      UndoHistoryController();
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
  final ImportManager _importManager = ImportManager();

  bool _didHydrateShellPreferences = false;
  bool _isDropTargetActive = false;
  bool _genericImportOpen = false;
  bool _showFindBar = false;
  int _findMatchCount = 0;
  int _activeFindMatch = 0;
  String? _selectedSchemaNodeId;
  bool _nativeMenuAvailable = false;
  bool _didCheckNativeMenuAvailability = false;
  bool _didProcessStartupLaunchOptions = false;
  bool _pendingSqlEditorStateRebuild = false;
  bool _pendingControllerSync = false;
  int _autocompleteSelectionIndex = 0;
  String? _pendingSqlText;
  String? _pendingParamsText;
  SqlExecutionTarget _lastSqlExecutionTarget = const SqlExecutionTarget(
    kind: SqlExecutionTargetKind.buffer,
    sql: '',
    startOffset: 0,
    endOffset: 0,
    startLine: 1,
    startColumn: 1,
    lineCount: 0,
  );
  final Map<String, ResultsGridInteractionState> _resultsStateByTabId =
      <String, ResultsGridInteractionState>{};

  @override
  void initState() {
    super.initState();
    unawaited(_checkNativeMenuAvailability());
  }

  @override
  void dispose() {
    unawaited(_shellController.persistNow());
    _shellController.dispose();
    _paramsUndoController.dispose();
    _sqlUndoController.dispose();
    _editorScrollController.dispose();
    _resultsHorizontalController.dispose();
    _resultsVerticalController
      ..removeListener(_onResultsScroll)
      ..dispose();
    _findFocusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _paramsFocusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _sqlFocusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _resultsFocusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _findController.dispose();
    _paramsController.dispose();
    _sqlController.removeListener(_handleSqlEditorStateChanged);
    _sqlController.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSqlEditorStateChanged() {
    final currentTarget = _sqlExecutionTarget();
    final shouldRebuild =
        currentTarget.kind != _lastSqlExecutionTarget.kind ||
        currentTarget.startOffset != _lastSqlExecutionTarget.startOffset ||
        currentTarget.endOffset != _lastSqlExecutionTarget.endOffset ||
        currentTarget.lineCount != _lastSqlExecutionTarget.lineCount;
    _lastSqlExecutionTarget = currentTarget;
    if (!mounted || !shouldRebuild) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(() {});
      return;
    }
    if (_pendingSqlEditorStateRebuild) {
      return;
    }
    _pendingSqlEditorStateRebuild = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingSqlEditorStateRebuild = false;
      if (mounted) {
        setState(() {});
      }
    });
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
        _scheduleStartupLaunchIfReady(controller);
        final activeTab = controller.activeTab;
        _syncControllers(controller, activeTab);

        final selectedSelection = _selectedSchemaSelection(controller);
        final shortcuts = _shortcutConfigService.load(controller.config);
        final registry = _buildMenuCommandRegistry(controller, shortcuts);
        final autocompleteResult = _autocompleteFor(controller);
        final selectedAutocompleteIndex = _selectedAutocompleteIndexFor(
          autocompleteResult,
        );
        final sqlExecutionTarget = _sqlExecutionTarget();
        final sqlSelection = _sqlSelectionInfo();
        final shellPreferences = _shellController.preferences;
        final resultsState = _resultsStateFor(activeTab.id);
        final usePlaceholderContent = _usePlaceholderContent(controller);

        return DropTarget(
          enable: !controller.hasImportSession && !_genericImportOpen,
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
              child: _wrapInMenuHost(
                registry,
                controller.config.recentFiles,
                Scaffold(
                  body: SafeArea(
                    child: Stack(
                      children: <Widget>[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (!_nativeMenuAvailable ||
                                !_didCheckNativeMenuAvailability)
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
                                    selectedNodeId: selectedSelection?.nodeId,
                                    onSelectNode: (nodeId) {
                                      setState(() {
                                        _selectedSchemaNodeId = nodeId;
                                      });
                                    },
                                    onShowNodeMenu: _showSchemaNodeContextMenu,
                                    onRefresh: () {
                                      controller.refreshSchema();
                                    },
                                    isLoading:
                                        controller.isSchemaLoading ||
                                        controller.isOpeningDatabase,
                                  ),
                                  propertiesPane: PropertiesPane(
                                    selection: selectedSelection,
                                  ),
                                  sqlEditor: SqlEditorPane(
                                    tabs: controller.tabs,
                                    activeTab: activeTab,
                                    sqlController: _sqlController,
                                    paramsController: _paramsController,
                                    editorScrollController:
                                        _editorScrollController,
                                    focusNode: _sqlFocusNode,
                                    paramsFocusNode: _paramsFocusNode,
                                    undoController: _sqlUndoController,
                                    paramsUndoController: _paramsUndoController,
                                    autocompleteResult: autocompleteResult,
                                    snippets: controller.config.snippets,
                                    zoomFactor: shellPreferences.editorZoom,
                                    indentSpaces: controller
                                        .config
                                        .editorSettings
                                        .indentSpaces,
                                    showLineNumbers: controller
                                        .config
                                        .editorSettings
                                        .showLineNumbers,
                                    showFindBar: _showFindBar,
                                    findController: _findController,
                                    findFocusNode: _findFocusNode,
                                    findStatusLabel: _findStatusLabel(),
                                    runLabel: sqlExecutionTarget.runLabel,
                                    formatLabel:
                                        sqlSelection.hasRunnableSelection
                                        ? 'Format Selection'
                                        : 'Format',
                                    editorContextLabel:
                                        sqlExecutionTarget.contextLabel,
                                    errorLocationLabel:
                                        activeTab.error?.location?.shortLabel,
                                    errorMessage: activeTab.error?.message,
                                    showRunBufferButton:
                                        !sqlExecutionTarget.isBufferTarget &&
                                        resolveSqlBufferTarget(
                                          _sqlController.value,
                                        ).hasRunnableSql,
                                    onSqlChanged: _handleSqlChanged,
                                    onParamsChanged:
                                        controller.updateActiveParameterJson,
                                    onSelectTab: controller.selectTab,
                                    onCloseTab: controller.closeTab,
                                    onNewTab: () => controller.createTab(),
                                    onRunQuery: _runPrimarySqlTarget,
                                    onRunBuffer: _runEntireSqlBuffer,
                                    onStopQuery: () {
                                      controller.cancelActiveQuery();
                                    },
                                    onFormatSql: _formatActiveSql,
                                    onInsertSnippet: _insertSnippet,
                                    onApplyAutocomplete: (suggestion) =>
                                        _applyAutocompleteSuggestion(
                                          autocompleteResult,
                                          suggestion,
                                        ),
                                    selectedAutocompleteIndex:
                                        selectedAutocompleteIndex,
                                    onAutocompleteNext: () =>
                                        _moveAutocompleteSelection(
                                          autocompleteResult,
                                          1,
                                        ),
                                    onAutocompletePrevious: () =>
                                        _moveAutocompleteSelection(
                                          autocompleteResult,
                                          -1,
                                        ),
                                    onAcceptAutocomplete: () =>
                                        _acceptAutocompleteSuggestion(
                                          autocompleteResult,
                                        ),
                                    canRun: controller.canRunActiveTab,
                                    canStop: controller.canCancelActiveTab,
                                    onFindChanged: _handleFindChanged,
                                    onFindNext: _findNext,
                                    onFindPrevious: _findPrevious,
                                    onCloseFind: _hideFindBar,
                                  ),
                                  resultsPane: Focus(
                                    focusNode: _resultsFocusNode,
                                    child: ResultsPane(
                                      activeTab: activeTab,
                                      activeResultsTab:
                                          shellPreferences.activeResultsTab,
                                      verticalScrollController:
                                          _resultsVerticalController,
                                      horizontalScrollController:
                                          _resultsHorizontalController,
                                      interactionState: resultsState,
                                      onResultsTabChanged:
                                          _shellController.setActiveResultsTab,
                                      onLoadNextPage: () {
                                        controller.fetchNextPage();
                                      },
                                      onSelectCell: _selectResultsCell,
                                      onShowCellMenu: _showResultsCellMenu,
                                      onSelectRow: _selectResultsRow,
                                      onTogglePinnedColumn: _togglePinnedColumn,
                                      usePlaceholderContent:
                                          usePlaceholderContent,
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
                                    'Rows: ${activeTab.resultRows.isNotEmpty ? activeTab.resultRows.length : activeTab.rowsAffected ?? (controller.hasOpenDatabase ? 0 : 250)}',
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

  void _scheduleStartupLaunchIfReady(WorkspaceController controller) {
    if (_didProcessStartupLaunchOptions || controller.isInitializing) {
      return;
    }
    _didProcessStartupLaunchOptions = true;
    if (!widget.startupLaunchOptions.hasPendingAction) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await _handleStartupLaunchOptions(widget.startupLaunchOptions);
    });
  }

  void _syncControllers(
    WorkspaceController controller,
    QueryTabState activeTab,
  ) {
    _pendingSqlText = activeTab.sql;
    _pendingParamsText = activeTab.parameterJson;
    if (_pendingControllerSync) {
      return;
    }
    if (_sqlController.text == activeTab.sql &&
        _paramsController.text == activeTab.parameterJson) {
      return;
    }
    _pendingControllerSync = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingControllerSync = false;
      if (!mounted) {
        return;
      }
      _syncTextController(_sqlController, _pendingSqlText ?? '');
      _syncTextController(_paramsController, _pendingParamsText ?? '');
    });
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

  void _handleSqlChanged(String value) {
    _autocompleteSelectionIndex = 0;
    widget.controller.updateActiveSql(value);
  }

  SchemaSelectionDetails? _selectedSchemaSelection(
    WorkspaceController controller,
  ) {
    final candidate =
        _selectedSchemaNodeId ?? _fallbackSchemaNodeId(controller);
    final resolved = _selectionDetailsForNode(controller, candidate);
    if (resolved != null) {
      _selectedSchemaNodeId = resolved.nodeId;
      return resolved;
    }
    _selectedSchemaNodeId = 'database';
    return _selectionDetailsForNode(controller, 'database');
  }

  String _fallbackSchemaNodeId(WorkspaceController controller) {
    if (controller.schema.tables.isNotEmpty) {
      return 'table:${controller.schema.tables.first.name}';
    }
    if (controller.schema.views.isNotEmpty) {
      return 'view:${controller.schema.views.first.name}';
    }
    if (controller.schema.indexes.isNotEmpty) {
      return 'index:${controller.schema.indexes.first.name}';
    }
    return 'database';
  }

  SchemaSelectionDetails? _selectionDetailsForNode(
    WorkspaceController controller,
    String nodeId,
  ) {
    final allowSampleSchema = controller.databasePath == null;
    if (nodeId == 'database') {
      return SchemaSelectionDetails(
        nodeId: nodeId,
        kind: SchemaSelectionKind.database,
        label: controller.databasePath == null
            ? 'sample.decentdb'
            : p.basename(controller.databasePath!),
        subtitle: 'Database summary',
        summaryRows: <MapEntry<String, String>>[
          MapEntry('Tables', '${controller.schema.tables.length}'),
          MapEntry('Views', '${controller.schema.views.length}'),
          MapEntry('Indexes', '${controller.schema.indexes.length}'),
          MapEntry('Engine', controller.engineVersion ?? 'DecentDB mock shell'),
        ],
        notes: controller.databasePath == null
            ? const <String>[
                'No database is open yet. The shell is showing realistic placeholders so layout and density can be evaluated.',
              ]
            : const <String>[
                'Select a table, view, index, column, or constraint in Schema Explorer to inspect it here.',
              ],
      );
    }

    if (nodeId.startsWith('section:')) {
      final section = nodeId.substring('section:'.length);
      final (label, count) = switch (section) {
        'tables' => ('Tables', controller.schema.tables.length),
        'views' => ('Views', controller.schema.views.length),
        'indexes' => ('Indexes', controller.schema.indexes.length),
        _ => (section, 0),
      };
      return SchemaSelectionDetails(
        nodeId: nodeId,
        kind: SchemaSelectionKind.section,
        label: label,
        subtitle: '$label folder',
        summaryRows: <MapEntry<String, String>>[
          MapEntry('Visible items', '$count'),
          MapEntry('Selection', 'Explorer section'),
        ],
        notes: <String>[
          'Sections are lazily expanded and keep their expansion state while the workspace is open.',
        ],
      );
    }

    if (nodeId.startsWith('table:') || nodeId.startsWith('view:')) {
      final isTable = nodeId.startsWith('table:');
      final objectName = nodeId.substring(isTable ? 6 : 5);
      final object = controller.schema.objectNamed(objectName);
      if (object == null) {
        return allowSampleSchema ? _sampleSelectionDetails(nodeId) : null;
      }
      final indexes = controller.schema.indexesForObject(object.name);
      return SchemaSelectionDetails(
        nodeId: nodeId,
        kind: isTable ? SchemaSelectionKind.table : SchemaSelectionKind.view,
        label: object.name,
        subtitle: '${object.kind.name} metadata',
        objectName: object.name,
        definition: object.ddl,
        summaryRows: <MapEntry<String, String>>[
          MapEntry('Columns', '${object.columns.length}'),
          MapEntry('Indexes', '${indexes.length}'),
          MapEntry(
            'Definition',
            object.ddl == null ? 'Not exposed' : 'Available',
          ),
        ],
        notes: <String>[
          ...object.exposedConstraintSummaries,
          ...controller.schemaNotesForObject(object),
        ],
      );
    }

    if (nodeId.startsWith('index:')) {
      final indexName = nodeId.substring('index:'.length);
      for (final index in controller.schema.indexes) {
        if (index.name == indexName) {
          return SchemaSelectionDetails(
            nodeId: nodeId,
            kind: SchemaSelectionKind.schemaIndex,
            label: index.name,
            subtitle: 'Index metadata',
            objectName: index.table,
            summaryRows: <MapEntry<String, String>>[
              MapEntry('Table', index.table),
              MapEntry('Kind', index.kind),
              MapEntry('Unique', index.unique ? 'Yes' : 'No'),
              MapEntry('Columns', index.columns.join(', ')),
            ],
            notes: const <String>[
              'Index statistics are not exposed by the current DecentDB Dart schema API.',
            ],
          );
        }
      }
      return allowSampleSchema ? _sampleSelectionDetails(nodeId) : null;
    }

    if (nodeId.startsWith('column:')) {
      final parts = nodeId.split(':');
      if (parts.length >= 3) {
        final object = controller.schema.objectNamed(parts[1]);
        if (object == null) {
          return allowSampleSchema ? _sampleSelectionDetails(nodeId) : null;
        }
        for (final column in object.columns) {
          if (column.name == parts[2]) {
            return SchemaSelectionDetails(
              nodeId: nodeId,
              kind: SchemaSelectionKind.column,
              label: column.name,
              subtitle: 'Column metadata',
              objectName: object.name,
              summaryRows: <MapEntry<String, String>>[
                MapEntry('Object', object.name),
                MapEntry('Type', column.type),
                MapEntry('Primary key', column.primaryKey ? 'Yes' : 'No'),
                MapEntry('Nullable', column.notNull ? 'No' : 'Yes'),
                MapEntry('Unique', column.unique ? 'Yes' : 'No'),
              ],
              notes: column.constraintSummaries.isEmpty
                  ? const <String>['No explicit constraints exposed.']
                  : column.constraintSummaries,
            );
          }
        }
      }
      return allowSampleSchema ? _sampleSelectionDetails(nodeId) : null;
    }

    if (nodeId.startsWith('constraint:')) {
      final parts = nodeId.split(':');
      if (parts.length >= 4) {
        final object = controller.schema.objectNamed(parts[1]);
        if (object == null) {
          return allowSampleSchema ? _sampleSelectionDetails(nodeId) : null;
        }
        for (final column in object.columns) {
          if (column.name != parts[2]) {
            continue;
          }
          final constraintIndex = int.tryParse(parts[3]);
          if (constraintIndex != null &&
              constraintIndex >= 0 &&
              constraintIndex < column.constraintSummaries.length) {
            final constraint = column.constraintSummaries[constraintIndex];
            return SchemaSelectionDetails(
              nodeId: nodeId,
              kind: SchemaSelectionKind.constraint,
              label: constraint,
              subtitle: 'Constraint metadata',
              objectName: object.name,
              summaryRows: <MapEntry<String, String>>[
                MapEntry('Object', object.name),
                MapEntry('Column', column.name),
                MapEntry('Constraint', constraint),
              ],
              notes: const <String>[
                'Check and named constraint metadata is currently inferred from column introspection only.',
              ],
            );
          }
        }
      }
      return SchemaSelectionDetails(
        nodeId: nodeId,
        kind: SchemaSelectionKind.constraint,
        label: 'No explicit constraints',
        subtitle: 'Constraint folder',
        summaryRows: const <MapEntry<String, String>>[
          MapEntry('Constraint count', '0'),
        ],
        notes: const <String>[
          'The current object does not expose explicit constraints through the Dart schema API.',
        ],
      );
    }

    if (nodeId.startsWith('trigger:')) {
      final parts = nodeId.split(':');
      return SchemaSelectionDetails(
        nodeId: nodeId,
        kind: SchemaSelectionKind.trigger,
        label: parts.length > 1 ? parts[1] : 'Trigger',
        subtitle: 'Trigger metadata',
        objectName: parts.length > 1 ? parts[1] : null,
        summaryRows: const <MapEntry<String, String>>[
          MapEntry('Exposure', 'Not available'),
        ],
        notes: const <String>[
          'Trigger definitions and bindings are not exposed by the current DecentDB Dart schema API.',
          'The tree keeps trigger folders visible now so the shell layout matches classic database clients even before deeper engine metadata lands.',
        ],
      );
    }

    return allowSampleSchema ? _sampleSelectionDetails(nodeId) : null;
  }

  SchemaSelectionDetails? _sampleSelectionDetails(String nodeId) {
    if (nodeId.startsWith('table:sample.')) {
      final label = nodeId.substring('table:sample.'.length);
      return SchemaSelectionDetails(
        nodeId: nodeId,
        kind: SchemaSelectionKind.table,
        label: label,
        subtitle: 'Sample table metadata',
        objectName: label,
        summaryRows: const <MapEntry<String, String>>[
          MapEntry('Columns', '3'),
          MapEntry('Indexes', '1'),
          MapEntry('Definition', 'Placeholder'),
        ],
        notes: const <String>[
          'Sample metadata is shown until a real DecentDB file is opened.',
        ],
      );
    }
    if (nodeId.startsWith('view:sample.')) {
      final label = nodeId.substring('view:sample.'.length);
      return SchemaSelectionDetails(
        nodeId: nodeId,
        kind: SchemaSelectionKind.view,
        label: label,
        subtitle: 'Sample view metadata',
        objectName: label,
        summaryRows: const <MapEntry<String, String>>[
          MapEntry('Columns', '2'),
          MapEntry('Definition', 'Placeholder'),
        ],
        notes: const <String>[
          'Sample metadata is shown until a real DecentDB file is opened.',
        ],
      );
    }
    if (nodeId.startsWith('index:sample:')) {
      final label = nodeId.substring('index:sample:'.length);
      return SchemaSelectionDetails(
        nodeId: nodeId,
        kind: SchemaSelectionKind.schemaIndex,
        label: label,
        subtitle: 'Sample index metadata',
        summaryRows: const <MapEntry<String, String>>[
          MapEntry('Kind', 'btree'),
          MapEntry('Unique', 'No'),
        ],
        notes: const <String>[
          'Sample metadata is shown until a real DecentDB file is opened.',
        ],
      );
    }
    return null;
  }

  String _editorModeLabel() {
    if (_findFocusNode.hasFocus) {
      return 'Find mode';
    }
    if (_resultsFocusNode.hasFocus) {
      return 'Grid mode';
    }
    if (_paramsFocusNode.hasFocus) {
      return 'Parameter mode';
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

  SqlEditorSelectionInfo _sqlSelectionInfo() {
    return resolveSqlEditorSelectionInfo(_sqlController.value);
  }

  SqlExecutionTarget _sqlExecutionTarget() {
    return resolveSqlExecutionTarget(_sqlController.value);
  }

  int _selectedAutocompleteIndexFor(AutocompleteResult result) {
    if (result.isEmpty) {
      return 0;
    }
    return _autocompleteSelectionIndex
        .clamp(0, result.suggestions.length - 1)
        .toInt();
  }

  void _moveAutocompleteSelection(AutocompleteResult result, int delta) {
    if (result.isEmpty) {
      return;
    }
    final nextIndex =
        (_selectedAutocompleteIndexFor(result) + delta) %
        result.suggestions.length;
    setState(() {
      _autocompleteSelectionIndex = nextIndex < 0
          ? result.suggestions.length - 1
          : nextIndex;
    });
  }

  void _acceptAutocompleteSuggestion(AutocompleteResult result) {
    if (result.isEmpty) {
      return;
    }
    _applyAutocompleteSuggestion(
      result,
      result.suggestions[_selectedAutocompleteIndexFor(result)],
    );
  }

  Future<void> _checkNativeMenuAvailability() async {
    if (kIsWeb ||
        !(Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      if (!mounted) {
        return;
      }
      setState(() {
        _didCheckNativeMenuAvailability = true;
        _nativeMenuAvailable = false;
      });
      return;
    }

    try {
      final supported = await SystemChannels.menu.invokeMethod<bool>(
        'Menu.isPluginAvailable',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _didCheckNativeMenuAvailability = true;
        _nativeMenuAvailable = supported ?? Platform.isMacOS;
      });
    } on MissingPluginException {
      if (!mounted) {
        return;
      }
      setState(() {
        _didCheckNativeMenuAvailability = true;
        _nativeMenuAvailable = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _didCheckNativeMenuAvailability = true;
        _nativeMenuAvailable = false;
      });
    }
  }

  ResultsGridInteractionState _resultsStateFor(String tabId) {
    final current = _resultsStateByTabId.putIfAbsent(
      tabId,
      () => const ResultsGridInteractionState(),
    );
    final tab = widget.controller.tabById(tabId) ?? widget.controller.activeTab;
    final usePlaceholderContent = _usePlaceholderContent(widget.controller);
    final rows = resolveResultsRows(
      tab,
      usePlaceholderContent: usePlaceholderContent,
    );
    final columns = resolveResultsColumns(
      tab,
      usePlaceholderContent: usePlaceholderContent,
    );
    final shouldResetForExecution =
        current.executionGeneration != tab.executionGeneration;
    final normalized = current.copyWith(
      selectedRows: shouldResetForExecution
          ? const <int>{}
          : current.selectedRows
                .where((rowIndex) => rowIndex >= 0 && rowIndex < rows.length)
                .toSet(),
      selectedCell: shouldResetForExecution
          ? null
          : current.selectedCell != null &&
                current.selectedCell!.rowIndex >= 0 &&
                current.selectedCell!.rowIndex < rows.length &&
                columns.contains(current.selectedCell!.columnName)
          ? current.selectedCell
          : null,
      pinnedColumns: current.pinnedColumns.where(columns.contains).toSet(),
      cellOverrides: shouldResetForExecution
          ? const <ResultsGridCellKey, Object?>{}
          : Map<ResultsGridCellKey, Object?>.fromEntries(
              current.cellOverrides.entries.where(
                (entry) =>
                    entry.key.rowIndex >= 0 &&
                    entry.key.rowIndex < rows.length &&
                    columns.contains(entry.key.columnName),
              ),
            ),
      executionGeneration: tab.executionGeneration,
    );
    _resultsStateByTabId[tabId] = normalized;
    return normalized;
  }

  void _selectResultsCell(int rowIndex, String columnName) {
    final tabId = widget.controller.activeTabId;
    final current = _resultsStateFor(tabId);
    setState(() {
      _resultsStateByTabId[tabId] = current.copyWith(
        selectedRows: <int>{rowIndex},
        selectedCell: ResultsGridCellSelection(
          rowIndex: rowIndex,
          columnName: columnName,
        ),
      );
    });
    _resultsFocusNode.requestFocus();
  }

  void _selectResultsRow(int rowIndex) {
    final tabId = widget.controller.activeTabId;
    final current = _resultsStateFor(tabId);
    setState(() {
      _resultsStateByTabId[tabId] = current.copyWith(
        selectedRows: <int>{rowIndex},
        selectedCell: null,
      );
    });
    _resultsFocusNode.requestFocus();
  }

  Future<void> _showResultsCellMenu(
    int rowIndex,
    String columnName,
    Offset globalPosition,
  ) async {
    _selectResultsCell(rowIndex, columnName);
    final clipboardText = (await Clipboard.getData(
      Clipboard.kTextPlain,
    ))?.text?.trim();
    final canPaste = clipboardText != null && clipboardText.isNotEmpty;
    final canSetNull = _isSelectedResultsCellNullable(
      rowIndex: rowIndex,
      columnName: columnName,
    );
    if (!mounted) {
      return;
    }

    final action = await showMenu<_ResultsCellMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: <PopupMenuEntry<_ResultsCellMenuAction>>[
        _popupMenuItem(
          value: _ResultsCellMenuAction.copy,
          icon: Icons.copy_outlined,
          label: 'Copy',
        ),
        _popupMenuItem(
          value: _ResultsCellMenuAction.paste,
          icon: Icons.content_paste_outlined,
          label: 'Paste',
          enabled: canPaste,
        ),
        _popupMenuItem(
          value: _ResultsCellMenuAction.setNull,
          icon: Icons.exposure_zero_outlined,
          label: 'Set To Null',
          enabled: canSetNull,
        ),
      ],
    );
    if (action == null) {
      return;
    }

    switch (action) {
      case _ResultsCellMenuAction.copy:
        await _copyResultsSelection();
        break;
      case _ResultsCellMenuAction.paste:
        if (clipboardText != null && clipboardText.isNotEmpty) {
          _updateSelectedResultsCellValue(
            rowIndex: rowIndex,
            columnName: columnName,
            value: clipboardText,
          );
        }
        break;
      case _ResultsCellMenuAction.setNull:
        _updateSelectedResultsCellValue(
          rowIndex: rowIndex,
          columnName: columnName,
          value: null,
        );
        break;
    }
  }

  void _togglePinnedColumn(String columnName) {
    final tabId = widget.controller.activeTabId;
    final current = _resultsStateFor(tabId);
    final nextPinned = <String>{...current.pinnedColumns};
    if (!nextPinned.add(columnName)) {
      nextPinned.remove(columnName);
    }
    setState(() {
      _resultsStateByTabId[tabId] = current.copyWith(pinnedColumns: nextPinned);
    });
  }

  void _selectAllResultsRows() {
    final tab = widget.controller.activeTab;
    final current = _resultsStateFor(tab.id);
    final rows = resolveResultsRows(tab);
    setState(() {
      _resultsStateByTabId[tab.id] = current.copyWith(
        selectedRows: <int>{for (var i = 0; i < rows.length; i++) i},
        selectedCell: null,
      );
    });
    _resultsFocusNode.requestFocus();
  }

  String _findStatusLabel() {
    if (_findController.text.isEmpty) {
      return 'Type to search';
    }
    if (_findMatchCount == 0) {
      return 'No matches';
    }
    return '$_activeFindMatch of $_findMatchCount';
  }

  void _openFindBar() {
    final selection = _sqlController.selection;
    final selectedText = selection.isValid && !selection.isCollapsed
        ? selection.textInside(_sqlController.text)
        : '';
    setState(() {
      _showFindBar = true;
      if (_findController.text.isEmpty && selectedText.isNotEmpty) {
        _findController.text = selectedText;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _findFocusNode.requestFocus();
      _findController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findController.text.length,
      );
    });
    if (_findController.text.isNotEmpty) {
      _findNext();
    }
  }

  void _hideFindBar() {
    setState(() {
      _showFindBar = false;
      _findMatchCount = 0;
      _activeFindMatch = 0;
    });
    _sqlFocusNode.requestFocus();
  }

  void _handleFindChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _findMatchCount = 0;
        _activeFindMatch = 0;
      });
      return;
    }
    _findNext(resetFromStart: true);
  }

  void _findNext({bool resetFromStart = false}) {
    final matches = _findMatches(_findController.text);
    if (matches.isEmpty) {
      setState(() {
        _findMatchCount = 0;
        _activeFindMatch = 0;
      });
      return;
    }

    final currentStart = resetFromStart || !_sqlController.selection.isValid
        ? -1
        : _sqlController.selection.start;
    var targetIndex = matches.indexWhere((match) => match.start > currentStart);
    if (targetIndex < 0) {
      targetIndex = 0;
    }
    _applyFindMatch(matches, targetIndex);
  }

  void _findPrevious() {
    final matches = _findMatches(_findController.text);
    if (matches.isEmpty) {
      setState(() {
        _findMatchCount = 0;
        _activeFindMatch = 0;
      });
      return;
    }

    final currentStart = _sqlController.selection.isValid
        ? _sqlController.selection.start
        : _sqlController.text.length + 1;
    var targetIndex = -1;
    for (var i = matches.length - 1; i >= 0; i--) {
      if (matches[i].start < currentStart) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) {
      targetIndex = matches.length - 1;
    }
    _applyFindMatch(matches, targetIndex);
  }

  List<_TextMatch> _findMatches(String pattern) {
    final query = pattern.trim().toLowerCase();
    if (query.isEmpty) {
      return const <_TextMatch>[];
    }
    final source = _sqlController.text.toLowerCase();
    final matches = <_TextMatch>[];
    var start = 0;
    while (true) {
      final index = source.indexOf(query, start);
      if (index < 0) {
        break;
      }
      matches.add(_TextMatch(index, index + query.length));
      start = index + math.max(query.length, 1);
    }
    return matches;
  }

  void _applyFindMatch(List<_TextMatch> matches, int index) {
    final match = matches[index];
    _sqlController.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    _sqlFocusNode.requestFocus();
    setState(() {
      _findMatchCount = matches.length;
      _activeFindMatch = index + 1;
    });
  }

  Future<void> _undoFocusedEdit() async {
    _focusedEditableField()?.undoController?.undo();
  }

  Future<void> _redoFocusedEdit() async {
    _focusedEditableField()?.undoController?.redo();
  }

  Future<void> _cutFocusedSelection() async {
    final field = _focusedEditableField();
    if (field == null) {
      return;
    }
    final selection = field.controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: selection.textInside(field.controller.text)),
    );
    final updated =
        selection.textBefore(field.controller.text) +
        selection.textAfter(field.controller.text);
    field.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: selection.start),
    );
    field.onChanged(updated);
  }

  Future<void> _copyFocusedSelection() async {
    if (_resultsFocusNode.hasFocus) {
      await _copyResultsSelection();
      return;
    }
    final field = _focusedEditableField();
    if (field == null) {
      return;
    }
    final selection = field.controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return;
    }
    await Clipboard.setData(
      ClipboardData(text: selection.textInside(field.controller.text)),
    );
  }

  Future<void> _pasteIntoFocusedField() async {
    if (_resultsFocusNode.hasFocus) {
      final pasteText = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      final selectedCell = _resultsStateFor(
        widget.controller.activeTabId,
      ).selectedCell;
      if (pasteText == null || pasteText.isEmpty || selectedCell == null) {
        return;
      }
      _updateSelectedResultsCellValue(
        rowIndex: selectedCell.rowIndex,
        columnName: selectedCell.columnName,
        value: pasteText,
      );
      return;
    }
    final field = _focusedEditableField();
    if (field == null) {
      return;
    }
    final pasteData = await Clipboard.getData(Clipboard.kTextPlain);
    final pasteText = pasteData?.text;
    if (pasteText == null || pasteText.isEmpty) {
      return;
    }
    final selection = field.controller.selection;
    final start = selection.isValid
        ? selection.start
        : field.controller.text.length;
    final end = selection.isValid
        ? selection.end
        : field.controller.text.length;
    final updated =
        field.controller.text.substring(0, start) +
        pasteText +
        field.controller.text.substring(end);
    final offset = start + pasteText.length;
    field.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: offset),
    );
    field.onChanged(updated);
  }

  Future<void> _selectAllFocusedSurface() async {
    if (_resultsFocusNode.hasFocus) {
      _selectAllResultsRows();
      return;
    }
    final field = _focusedEditableField();
    if (field == null) {
      return;
    }
    field.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: field.controller.text.length,
    );
  }

  Future<void> _copyResultsSelection() async {
    final tab = widget.controller.activeTab;
    final usePlaceholderContent = _usePlaceholderContent(widget.controller);
    final columns = resolveResultsColumns(
      tab,
      usePlaceholderContent: usePlaceholderContent,
    );
    final state = _resultsStateFor(tab.id);
    if (state.selectedCell != null && state.selectedCell!.rowIndex >= 0) {
      final cell = state.selectedCell!;
      await Clipboard.setData(
        ClipboardData(
          text: formatCellValue(
            resolveResultsCellValue(
              tab,
              state,
              cell.rowIndex,
              cell.columnName,
              usePlaceholderContent: usePlaceholderContent,
            ),
          ),
        ),
      );
      return;
    }
    if (state.selectedRows.isEmpty) {
      return;
    }
    final buffer = StringBuffer()..writeln(columns.join('\t'));
    final sortedRows = state.selectedRows.toList()..sort();
    for (final rowIndex in sortedRows) {
      buffer.writeln(
        columns
            .map(
              (column) => formatCellValue(
                resolveResultsCellValue(
                  tab,
                  state,
                  rowIndex,
                  column,
                  usePlaceholderContent: usePlaceholderContent,
                ),
              ),
            )
            .join('\t'),
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
  }

  void _updateSelectedResultsCellValue({
    required int rowIndex,
    required String columnName,
    required Object? value,
  }) {
    final tabId = widget.controller.activeTabId;
    final current = _resultsStateFor(tabId);
    final nextOverrides = Map<ResultsGridCellKey, Object?>.from(
      current.cellOverrides,
    )..[ResultsGridCellKey(rowIndex: rowIndex, columnName: columnName)] = value;
    setState(() {
      _resultsStateByTabId[tabId] = current.copyWith(
        selectedRows: <int>{rowIndex},
        selectedCell: ResultsGridCellSelection(
          rowIndex: rowIndex,
          columnName: columnName,
        ),
        cellOverrides: nextOverrides,
      );
    });
    _resultsFocusNode.requestFocus();
  }

  bool _isSelectedResultsCellNullable({
    required int rowIndex,
    required String columnName,
  }) {
    final tab = widget.controller.activeTab;
    final sql = (tab.lastSql ?? tab.sql).trim();
    final objectName = _firstObjectNameInFromClause(sql);
    if (objectName == null) {
      return false;
    }
    final object = widget.controller.schema.objectNamed(objectName);
    if (object == null || rowIndex < 0) {
      return false;
    }
    for (final column in object.columns) {
      if (column.name == columnName) {
        return !column.notNull;
      }
    }
    return false;
  }

  String? _firstObjectNameInFromClause(String sql) {
    final quotedMatch = RegExp(
      r'\bFROM\s+"((?:[^"]|"")+)"',
      caseSensitive: false,
    ).firstMatch(sql);
    if (quotedMatch != null) {
      return quotedMatch.group(1)?.replaceAll('""', '"');
    }
    final bareMatch = RegExp(
      r'\bFROM\s+([A-Za-z_][A-Za-z0-9_]*)',
      caseSensitive: false,
    ).firstMatch(sql);
    return bareMatch?.group(1);
  }

  _EditableFieldBinding? _focusedEditableField() {
    final controller = widget.controller;
    final bindings = <_EditableFieldBinding>[
      _EditableFieldBinding(
        controller: _findController,
        focusNode: _findFocusNode,
        undoController: null,
        onChanged: _handleFindChanged,
      ),
      _EditableFieldBinding(
        controller: _sqlController,
        focusNode: _sqlFocusNode,
        undoController: _sqlUndoController,
        onChanged: controller.updateActiveSql,
      ),
      _EditableFieldBinding(
        controller: _paramsController,
        focusNode: _paramsFocusNode,
        undoController: _paramsUndoController,
        onChanged: controller.updateActiveParameterJson,
      ),
    ];
    for (final binding in bindings) {
      if (binding.focusNode.hasFocus) {
        return binding;
      }
    }
    return null;
  }

  Widget _wrapInMenuHost(
    MenuCommandRegistry registry,
    List<String> recentFiles,
    Widget child,
  ) {
    if (!_nativeMenuAvailable) {
      return child;
    }
    return NativeAppMenuHost(
      registry: registry,
      recentFiles: recentFiles,
      onOpenRecent: _openRecentWorkspace,
      child: child,
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
            'Database duplication is not wired in this prerelease build yet.',
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
          onInvoke: _undoFocusedEdit,
        ),
        command(
          id: 'edit_redo',
          label: 'Redo',
          icon: Icons.redo_outlined,
          onInvoke: _redoFocusedEdit,
        ),
        command(
          id: 'edit_cut',
          label: 'Cut',
          icon: Icons.content_cut_outlined,
          onInvoke: _cutFocusedSelection,
        ),
        command(
          id: 'edit_copy',
          label: 'Copy',
          icon: Icons.copy_outlined,
          onInvoke: _copyFocusedSelection,
        ),
        command(
          id: 'edit_paste',
          label: 'Paste',
          icon: Icons.content_paste_outlined,
          onInvoke: _pasteIntoFocusedField,
        ),
        command(
          id: 'edit_find',
          label: 'Find',
          icon: Icons.search_outlined,
          onInvoke: () async {
            _openFindBar();
          },
        ),
        command(
          id: 'edit_find_next',
          label: 'Find Next',
          icon: Icons.find_replace_outlined,
          onInvoke: () async {
            if (!_showFindBar) {
              _openFindBar();
            } else {
              _findNext();
            }
          },
        ),
        command(
          id: 'edit_select_all',
          label: 'Select All',
          icon: Icons.select_all_outlined,
          onInvoke: _selectAllFocusedSurface,
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
            'External live database imports are represented in the shell but not wired in this prerelease build yet.',
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
          onInvoke: _showCsvExportDialog,
          enabled: controller.activeTab.canExport,
        ),
        command(
          id: 'export_results_json',
          label: 'Export Results as JSON...',
          icon: Icons.data_object_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Export JSON',
            'JSON export is planned but not implemented yet.',
          ),
        ),
        command(
          id: 'export_results_parquet',
          label: 'Export Results as Parquet...',
          icon: Icons.view_column_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Export Parquet',
            'Parquet export is planned but not implemented yet.',
          ),
        ),
        command(
          id: 'export_results_excel',
          label: 'Export Results as Excel...',
          icon: Icons.table_view_outlined,
          onInvoke: () => _showPlaceholderNotice(
            'Export Excel',
            'Excel export is planned but not implemented yet.',
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
            'Schema export is not implemented yet.',
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
          label: _sqlExecutionTarget().runLabel,
          icon: Icons.play_arrow_outlined,
          onInvoke: _runPrimarySqlTarget,
          enabled: controller.canRunActiveTab,
        ),
        command(
          id: 'tools_run_buffer',
          label: 'Run Buffer',
          icon: Icons.subject_outlined,
          onInvoke: _runEntireSqlBuffer,
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
          label: _sqlSelectionInfo().hasRunnableSelection
              ? 'Format Selection'
              : 'Format SQL',
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
          onInvoke: _showQueryHistoryDialog,
        ),
        command(
          id: 'tools_snippets',
          label: 'Manage Snippets',
          icon: Icons.library_books_outlined,
          onInvoke: () => _showPreferencesDialog(
            initialSection: PreferencesDialogSection.snippets,
          ),
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

  Future<void> _showGenericImportDialog({
    required String sourcePath,
    required ImportFormatDefinition format,
  }) async {
    setState(() {
      _genericImportOpen = true;
    });
    final result = await showDialog<GenericImportDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => GenericImportDialog(
        initialSourcePath: sourcePath,
        initialFormat: format,
        logger: widget.controller.logger,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _genericImportOpen = false;
    });
    if (result != null) {
      await widget.controller.openDatabase(
        result.targetPath,
        createIfMissing: false,
      );
    }
  }

  Future<void> _showImportChooser() async {
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'Import sources',
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
            'xlsx',
            'xls',
            'db',
            'sqlite',
            'sqlite3',
            'sql',
            'zip',
            'gz',
          ],
        ),
      ],
    );
    if (file == null) {
      return;
    }
    await _startImportFromPath(file.path);
  }

  Future<void> _handleStartupLaunchOptions(
    StartupLaunchOptions launchOptions,
  ) async {
    final startupNotice = launchOptions.startupNotice?.trim();
    if (startupNotice != null && startupNotice.isNotEmpty) {
      await _showPlaceholderNotice('Command-line import', startupNotice);
      return;
    }

    final importSourcePath = launchOptions.importSourcePath?.trim();
    if (importSourcePath == null || importSourcePath.isEmpty) {
      return;
    }

    await _startImportFromPath(importSourcePath);
  }

  Future<void> _startImportFromPath(String path) async {
    final detection = await _importManager.detectSource(path);
    switch (detection.format.implementationKind) {
      case ImportImplementationKind.directOpen:
        await widget.controller.openDatabase(path, createIfMissing: false);
        break;
      case ImportImplementationKind.legacyWizard:
        switch (detection.format.key) {
          case ImportFormatKey.sqlite:
            await _showSqliteImportDialog(sourcePath: path);
            break;
          case ImportFormatKey.xlsx:
          case ImportFormatKey.xls:
            await _showExcelImportDialog(sourcePath: path);
            break;
          case ImportFormatKey.sqlDump:
            await _showSqlDumpImportDialog(sourcePath: path);
            break;
          default:
            await _showPlaceholderNotice(
              'Import unavailable',
              '${detection.format.label} is detected but still uses a wizard path that is not wired here yet.',
            );
            break;
        }
        break;
      case ImportImplementationKind.genericWizard:
        await _showGenericImportDialog(
          sourcePath: path,
          format: detection.format,
        );
        break;
      case ImportImplementationKind.wrapper:
        await _handleArchiveImport(detection);
        break;
      case ImportImplementationKind.recognizedUnsupported:
        final note = detection.format.note == null
            ? ''
            : '\n\n${detection.format.note}';
        await _showPlaceholderNotice(
          '${detection.format.label} not available yet',
          'Decent Bench recognizes this format as `${detection.format.supportState.name}`, but it is not implemented in this build yet.$note',
        );
        break;
      case ImportImplementationKind.unknown:
        await _showPlaceholderNotice(
          'Unknown file type',
          'Supported import sources currently include `.csv`, `.tsv`, `.txt`, `.json`, `.jsonl`, `.ndjson`, `.xml`, `.html`, `.db`/`.sqlite`/`.sqlite3`, `.xls`/`.xlsx`, `.sql`, `.zip`, and `.gz`.',
        );
        break;
    }
  }

  Future<void> _showCsvExportDialog() async {
    final controller = widget.controller;
    final activeTab = controller.activeTab;
    final result = await showDialog<CsvExportDialogResult>(
      context: context,
      builder: (context) {
        return CsvExportDialog(
          queryTitle: activeTab.title,
          initialPath: activeTab.exportPath.trim().isEmpty
              ? controller.suggestExportPath()
              : activeTab.exportPath.trim(),
          initialDelimiter: controller.config.csvDelimiter,
          initialIncludeHeaders: controller.config.csvIncludeHeaders,
          onBrowse: (currentPath) async {
            final initialName = currentPath.trim().isEmpty
                ? p.basename(controller.suggestExportPath())
                : p.basename(currentPath.trim());
            final location = await getSaveLocation(
              suggestedName: initialName,
              acceptedTypeGroups: const <XTypeGroup>[_csvTypeGroup],
            );
            return location?.path;
          },
        );
      },
    );
    if (result == null) {
      return;
    }

    controller.updateActiveExportPath(result.path);
    await controller.updateCsvDelimiter(result.delimiter);
    await controller.updateCsvIncludeHeaders(result.includeHeaders);
    await controller.exportCurrentQuery();
  }

  Future<void> _handleIncomingFiles(Iterable<String> rawPaths) async {
    final decision = decideWorkspaceIncomingFiles(rawPaths);
    final path = decision.primaryPath;
    if (path == null) {
      await _showPlaceholderNotice(
        'No file detected',
        'Drop a DecentDB or supported import source to continue.',
      );
      return;
    }
    if (decision.hadMultipleFiles) {
      await _showPlaceholderNotice(
        'One file at a time',
        'MVP import currently continues with ${p.basename(path)}.',
      );
    }

    await _startImportFromPath(path);
  }

  Future<void> _handleArchiveImport(ImportDetectionResult detection) async {
    if (!detection.hasArchiveCandidates) {
      await _showPlaceholderNotice(
        detection.format.label,
        'No recognized importable files were found inside `${p.basename(detection.sourcePath)}`.',
      );
      return;
    }
    final candidate = await showDialog<ImportArchiveCandidate>(
      context: context,
      builder: (context) => ImportArchiveChooserDialog(
        archivePath: detection.sourcePath,
        wrapperLabel: detection.format.label,
        candidates: detection.archiveCandidates,
      ),
    );
    if (candidate == null) {
      return;
    }
    final extractedPath = await _importManager.extractArchiveCandidate(
      archivePath: detection.sourcePath,
      wrapperKey: detection.format.key,
      candidate: candidate,
    );
    try {
      await _startImportFromPath(extractedPath);
    } finally {
      final extractedDir = Directory(p.dirname(extractedPath));
      if (await extractedDir.exists()) {
        await extractedDir.delete(recursive: true);
      }
    }
  }

  Future<void> _showSchemaNodeContextMenu(
    String nodeId,
    Offset globalPosition,
  ) async {
    final items = _schemaMenuItemsForNode(nodeId);
    if (items.isEmpty) {
      return;
    }
    setState(() {
      _selectedSchemaNodeId = nodeId;
    });
    final action = await showMenu<_SchemaNodeMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: items,
    );
    if (action == null) {
      return;
    }

    final objectName = _objectNameForSchemaNode(nodeId);
    switch (action) {
      case _SchemaNodeMenuAction.viewData:
        if (objectName != null) {
          await _openObjectDataQuery(objectName);
        }
        break;
      case _SchemaNodeMenuAction.scriptInsert:
        if (objectName != null) {
          _openSqlTemplate(_insertTemplateForTable(objectName));
        }
        break;
      case _SchemaNodeMenuAction.scriptUpdate:
        if (objectName != null) {
          _openSqlTemplate(_updateTemplateForTable(objectName));
        }
        break;
      case _SchemaNodeMenuAction.scriptDelete:
        if (objectName != null) {
          _openSqlTemplate(_deleteTemplateForTable(objectName));
        }
        break;
      case _SchemaNodeMenuAction.renameObject:
        if (objectName != null) {
          _openSqlTemplate(
            'ALTER TABLE ${_quoteIdentifier(objectName)}\n'
            'RENAME TO ${_quoteIdentifier('new_$objectName')};',
          );
        }
        break;
      case _SchemaNodeMenuAction.deleteObject:
        if (objectName != null) {
          _openSqlTemplate('DROP TABLE ${_quoteIdentifier(objectName)};');
        }
        break;
      case _SchemaNodeMenuAction.refresh:
        await widget.controller.refreshSchema();
        break;
      case _SchemaNodeMenuAction.newIndex:
        _openSqlTemplate(_newIndexTemplate());
        break;
      case _SchemaNodeMenuAction.rebuildAllIndexes:
        _openSqlTemplate('REINDEX;');
        break;
      case _SchemaNodeMenuAction.newView:
        _openSqlTemplate(_newViewTemplate());
        break;
    }
  }

  List<PopupMenuEntry<_SchemaNodeMenuAction>> _schemaMenuItemsForNode(
    String nodeId,
  ) {
    if (nodeId.startsWith('table:')) {
      return <PopupMenuEntry<_SchemaNodeMenuAction>>[
        _popupMenuItem(
          value: _SchemaNodeMenuAction.scriptInsert,
          icon: Icons.note_add_outlined,
          label: 'Script Table as INSERT',
        ),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.scriptUpdate,
          icon: Icons.edit_note_outlined,
          label: 'Script Table as UPDATE',
        ),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.scriptDelete,
          icon: Icons.delete_sweep_outlined,
          label: 'Script Table as DELETE',
        ),
        const PopupMenuDivider(),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.viewData,
          icon: Icons.table_view_outlined,
          label: 'View Data',
        ),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.renameObject,
          icon: Icons.drive_file_rename_outline_outlined,
          label: 'Rename',
        ),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.deleteObject,
          icon: Icons.delete_outline,
          label: 'Delete',
        ),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.refresh,
          icon: Icons.refresh_outlined,
          label: 'Refresh',
        ),
      ];
    }
    if (nodeId == 'section:indexes') {
      return <PopupMenuEntry<_SchemaNodeMenuAction>>[
        _popupMenuItem(
          value: _SchemaNodeMenuAction.newIndex,
          icon: Icons.add_circle_outline,
          label: 'New Index',
        ),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.rebuildAllIndexes,
          icon: Icons.build_circle_outlined,
          label: 'Rebuild All',
        ),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.refresh,
          icon: Icons.refresh_outlined,
          label: 'Refresh',
        ),
      ];
    }
    if (nodeId == 'section:views') {
      return <PopupMenuEntry<_SchemaNodeMenuAction>>[
        _popupMenuItem(
          value: _SchemaNodeMenuAction.newView,
          icon: Icons.add_circle_outline,
          label: 'New View',
        ),
        _popupMenuItem(
          value: _SchemaNodeMenuAction.refresh,
          icon: Icons.refresh_outlined,
          label: 'Refresh',
        ),
      ];
    }
    return const <PopupMenuEntry<_SchemaNodeMenuAction>>[];
  }

  String? _objectNameForSchemaNode(String nodeId) {
    if (nodeId.startsWith('table:')) {
      return nodeId.substring('table:'.length);
    }
    if (nodeId.startsWith('view:')) {
      return nodeId.substring('view:'.length);
    }
    return null;
  }

  Future<void> _openObjectDataQuery(String objectName) async {
    _openSqlTemplate(
      'SELECT *\n'
      'FROM ${_quoteIdentifier(objectName)}\n'
      'LIMIT ${widget.controller.config.defaultPageSize};',
    );
    if (widget.controller.hasOpenDatabase) {
      await widget.controller.runActiveTab();
    }
  }

  void _openSqlTemplate(String sql) {
    _autocompleteSelectionIndex = 0;
    widget.controller.createTab(sql: sql);
  }

  String _insertTemplateForTable(String tableName) {
    final object = widget.controller.schema.objectNamed(tableName);
    final columns = object?.columns ?? const <SchemaColumn>[];
    if (columns.isEmpty) {
      return 'INSERT INTO ${_quoteIdentifier(tableName)} ()\nVALUES ();';
    }
    final quotedColumns = columns
        .map((column) => _quoteIdentifier(column.name))
        .join(', ');
    final values = <String>[
      for (var index = 0; index < columns.length; index++) '\$${index + 1}',
    ].join(', ');
    return 'INSERT INTO ${_quoteIdentifier(tableName)} (\n'
        '  $quotedColumns\n'
        ')\n'
        'VALUES (\n'
        '  $values\n'
        ');';
  }

  String _updateTemplateForTable(String tableName) {
    final object = widget.controller.schema.objectNamed(tableName);
    final columns = object?.columns ?? const <SchemaColumn>[];
    final keyColumn =
        _firstOrNull(columns.where((column) => column.primaryKey)) ??
        (columns.isEmpty ? null : columns.first);
    final valueColumns = columns
        .where((column) => column != keyColumn)
        .toList();
    final setters = valueColumns.isEmpty
        ? '  ${_quoteIdentifier('column_name')} = \$1'
        : <String>[
            for (var index = 0; index < valueColumns.length; index++)
              '  ${_quoteIdentifier(valueColumns[index].name)} = \$${index + 1}',
          ].join(',\n');
    final whereValue = valueColumns.length + 1;
    final whereClause = keyColumn == null
        ? 'WHERE ${_quoteIdentifier('key_column')} = \$$whereValue;'
        : 'WHERE ${_quoteIdentifier(keyColumn.name)} = \$$whereValue;';
    return 'UPDATE ${_quoteIdentifier(tableName)}\n'
        'SET\n'
        '$setters\n'
        '$whereClause';
  }

  String _deleteTemplateForTable(String tableName) {
    final object = widget.controller.schema.objectNamed(tableName);
    final keyColumn = object == null
        ? null
        : _firstOrNull(object.columns.where((column) => column.primaryKey)) ??
              (object.columns.isEmpty ? null : object.columns.first);
    final whereClause = keyColumn == null
        ? 'WHERE ${_quoteIdentifier('key_column')} = \$1;'
        : 'WHERE ${_quoteIdentifier(keyColumn.name)} = \$1;';
    return 'DELETE FROM ${_quoteIdentifier(tableName)}\n$whereClause';
  }

  String _newIndexTemplate() {
    final firstTable = _firstOrNull(widget.controller.schema.tables);
    final table = firstTable?.name ?? 'table_name';
    final column = firstTable == null || firstTable.columns.isEmpty
        ? 'column_name'
        : firstTable.columns.first.name;
    return 'CREATE INDEX ${_quoteIdentifier('idx_${table}_$column')}\n'
        'ON ${_quoteIdentifier(table)} (${_quoteIdentifier(column)});';
  }

  String _newViewTemplate() {
    final table =
        _firstOrNull(widget.controller.schema.tables)?.name ?? 'table_name';
    return 'CREATE VIEW ${_quoteIdentifier('new_view')}\n'
        'AS\n'
        'SELECT *\n'
        'FROM ${_quoteIdentifier(table)}\n'
        'LIMIT ${widget.controller.config.defaultPageSize};';
  }

  String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  T? _firstOrNull<T>(Iterable<T> values) {
    final iterator = values.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }

  bool _usePlaceholderContent(WorkspaceController controller) {
    return !controller.hasOpenDatabase;
  }

  void _formatActiveSql() {
    final selection = _sqlSelectionInfo();
    final formatted = _sqlFormatter.format(
      selection.hasRunnableSelection
          ? selection.selectedText
          : _sqlController.text,
      settings: widget.controller.config.editorSettings,
    );
    _sqlController.value = replaceSelectedTextOrAll(
      _sqlController.value,
      replacement: formatted,
      useSelection: selection.hasRunnableSelection,
    );
    widget.controller.updateActiveSql(_sqlController.text);
  }

  Future<void> _runPrimarySqlTarget() async {
    final executionTarget = _sqlExecutionTarget();
    if (!executionTarget.isBufferTarget) {
      await widget.controller.runActiveSql(
        executionTarget.sql,
        bufferStartOffset: executionTarget.startOffset,
        description: switch (executionTarget.kind) {
          SqlExecutionTargetKind.selection => 'selected SQL',
          SqlExecutionTargetKind.statement => 'statement',
          SqlExecutionTargetKind.buffer => 'SQL',
        },
      );
      return;
    }
    await widget.controller.runActiveTab();
  }

  Future<void> _runEntireSqlBuffer() async {
    await widget.controller.runActiveTab();
  }

  void _insertSnippet(SqlSnippet snippet) {
    _autocompleteSelectionIndex = 0;
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
    _autocompleteSelectionIndex = 0;
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

  Future<void> _showQueryHistoryDialog() {
    final entries = widget.controller.queryHistory;
    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Query History'),
          content: SizedBox(
            width: 760,
            child: entries.isEmpty
                ? const Text(
                    'No query executions have been recorded in this workspace yet.',
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          entry.sql.replaceAll('\n', ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                        subtitle: Text(
                          '${entry.ranAt.toLocal()} • ${entry.outcome.name} • ${entry.elapsed.inMilliseconds} ms'
                          '${entry.rowsLoaded != null ? ' • rows ${entry.rowsLoaded}' : ''}'
                          '${entry.rowsAffected != null ? ' • affected ${entry.rowsAffected}' : ''}'
                          '${entry.errorMessage != null ? ' • ${entry.errorMessage}' : ''}',
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: <Widget>[
                            TextButton(
                              onPressed: () {
                                widget.controller.loadHistoryEntryIntoActiveTab(
                                  entry,
                                );
                                Navigator.of(context).pop();
                              },
                              child: const Text('Load'),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.of(context).pop();
                                await widget.controller.rerunHistoryEntry(
                                  entry,
                                );
                              },
                              child: const Text('Run'),
                            ),
                            TextButton(
                              onPressed: () {
                                widget.controller.loadHistoryEntryIntoActiveTab(
                                  entry,
                                  openInNewTab: true,
                                );
                                Navigator.of(context).pop();
                              },
                              child: const Text('New Tab'),
                            ),
                          ],
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
      'Decent Bench emphasizes import, query, and export workflows. Use the menu bar, keyboard shortcuts, and draggable panes to work through the desktop layout.',
    );
  }

  Future<void> _showPreferencesDialog({
    PreferencesDialogSection initialSection = PreferencesDialogSection.general,
  }) {
    return _showPreferencesDialogInternal(initialSection: initialSection);
  }

  Future<void> _showPreferencesDialogInternal({
    PreferencesDialogSection initialSection = PreferencesDialogSection.general,
  }) async {
    await _shellController.persistNow();
    await widget.controller.reloadConfig();
    _shellController.replacePreferences(
      widget.controller.config.shellPreferences,
    );
    if (!mounted) {
      return;
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return PreferencesDialog(
            initialConfig: widget.controller.config,
            configFilePath: widget.controller.configFilePath,
            shortcutConfigService: _shortcutConfigService,
            createSnippetId: widget.controller.createSnippetId,
            availableThemesById: <String, String>{
              for (final theme in widget.themeManager.availableThemes)
                theme.id: theme.name,
            },
            resolvedThemesDirectory:
                widget.themeManager.resolvedThemesDirectory,
            initialSection: initialSection,
            onPreviewTheme: widget.themeManager.switchTheme,
            onSave: (config) async {
              final saved = await widget.controller.applyAppConfig(
                config,
                statusMessage:
                    'Saved preferences to ${widget.controller.configFilePath}.',
              );
              if (saved) {
                _shellController.replacePreferences(
                  widget.controller.config.shellPreferences,
                );
                return null;
              }
              return widget.controller.workspaceError ??
                  'Unable to save application preferences.';
            },
          );
        },
      );
    } finally {
      unawaited(
        widget.themeManager.loadFromConfig(widget.controller.config.appearance),
      );
    }
  }

  Future<void> _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: kDecentBenchDisplayName,
      applicationVersion: kDecentBenchVersion,
      children: const <Widget>[
        Text('Classic desktop SQL workbench for DecentDB.'),
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

  PopupMenuItem<T> _popupMenuItem<T>({
    required T value,
    required IconData icon,
    required String label,
    bool enabled = true,
  }) {
    return PopupMenuItem<T>(
      value: value,
      enabled: enabled,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
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

class _TextMatch {
  const _TextMatch(this.start, this.end);

  final int start;
  final int end;
}

class _EditableFieldBinding {
  const _EditableFieldBinding({
    required this.controller,
    required this.focusNode,
    required this.undoController,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final UndoHistoryController? undoController;
  final ValueChanged<String> onChanged;
}

enum _ResultsCellMenuAction { copy, paste, setNull }

enum _SchemaNodeMenuAction {
  scriptInsert,
  scriptUpdate,
  scriptDelete,
  viewData,
  renameObject,
  deleteObject,
  refresh,
  newIndex,
  rebuildAllIndexes,
  newView,
}
