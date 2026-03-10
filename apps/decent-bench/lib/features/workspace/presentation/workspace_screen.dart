import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/app_metadata.dart';
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
import 'shell/schema_browser_models.dart';
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

  bool _didHydrateShellPreferences = false;
  bool _isDropTargetActive = false;
  bool _showFindBar = false;
  int _findMatchCount = 0;
  int _activeFindMatch = 0;
  String? _selectedSchemaNodeId;
  bool _nativeMenuAvailable = false;
  bool _didCheckNativeMenuAvailability = false;
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

        final selectedSelection = _selectedSchemaSelection(controller);
        final shortcuts = _shortcutConfigService.load(controller.config);
        final registry = _buildMenuCommandRegistry(controller, shortcuts);
        final autocompleteResult = _autocompleteFor(controller);
        final shellPreferences = _shellController.preferences;
        final resultsState = _resultsStateFor(activeTab.id);

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
              child: _wrapInMenuHost(
                registry,
                controller.config.recentFiles,
                Scaffold(
                  body: SafeArea(
                    child: Stack(
                      children: <Widget>[
                        Column(
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
                                    showFindBar: _showFindBar,
                                    findController: _findController,
                                    findFocusNode: _findFocusNode,
                                    findStatusLabel: _findStatusLabel(),
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
                                      exportPathController:
                                          _exportPathController,
                                      delimiterController: _delimiterController,
                                      verticalScrollController:
                                          _resultsVerticalController,
                                      horizontalScrollController:
                                          _resultsHorizontalController,
                                      csvIncludeHeaders:
                                          controller.config.csvIncludeHeaders,
                                      interactionState: resultsState,
                                      onResultsTabChanged:
                                          _shellController.setActiveResultsTab,
                                      onExportPathChanged:
                                          controller.updateActiveExportPath,
                                      onDelimiterSubmitted:
                                          controller.updateCsvDelimiter,
                                      onHeadersChanged: (value) {
                                        controller.updateCsvIncludeHeaders(
                                          value,
                                        );
                                      },
                                      onExportCsv: () {
                                        controller.exportCurrentQuery();
                                      },
                                      onLoadNextPage: () {
                                        controller.fetchNextPage();
                                      },
                                      onSelectCell: _selectResultsCell,
                                      onSelectRow: _selectResultsRow,
                                      onTogglePinnedColumn: _togglePinnedColumn,
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
        return _sampleSelectionDetails(nodeId);
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
      return _sampleSelectionDetails(nodeId);
    }

    if (nodeId.startsWith('column:')) {
      final parts = nodeId.split(':');
      if (parts.length >= 3) {
        final object = controller.schema.objectNamed(parts[1]);
        if (object == null) {
          return _sampleSelectionDetails(nodeId);
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
      return _sampleSelectionDetails(nodeId);
    }

    if (nodeId.startsWith('constraint:')) {
      final parts = nodeId.split(':');
      if (parts.length >= 4) {
        final object = controller.schema.objectNamed(parts[1]);
        if (object == null) {
          return _sampleSelectionDetails(nodeId);
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

    return _sampleSelectionDetails(nodeId);
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
    final rows = resolveResultsRows(tab);
    final columns = resolveResultsColumns(tab);
    final normalized = current.copyWith(
      selectedRows: current.selectedRows
          .where((rowIndex) => rowIndex >= 0 && rowIndex < rows.length)
          .toSet(),
      selectedCell:
          current.selectedCell != null &&
              current.selectedCell!.rowIndex >= 0 &&
              current.selectedCell!.rowIndex < rows.length &&
              columns.contains(current.selectedCell!.columnName)
          ? current.selectedCell
          : null,
      pinnedColumns: current.pinnedColumns.where(columns.contains).toSet(),
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
    final rows = resolveResultsRows(tab);
    final columns = resolveResultsColumns(tab);
    final state = _resultsStateFor(tab.id);
    if (state.selectedCell != null &&
        state.selectedCell!.rowIndex >= 0 &&
        state.selectedCell!.rowIndex < rows.length) {
      final cell = state.selectedCell!;
      await Clipboard.setData(
        ClipboardData(
          text: formatCellValue(rows[cell.rowIndex][cell.columnName]),
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
      if (rowIndex < 0 || rowIndex >= rows.length) {
        continue;
      }
      buffer.writeln(
        columns
            .map((column) => formatCellValue(rows[rowIndex][column]))
            .join('\t'),
      );
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
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
          onInvoke: controller.exportCurrentQuery,
          enabled: true,
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
          onInvoke: _showQueryHistoryDialog,
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
                  'This dialog is intentionally lightweight for now. It shows where shell, editor, and export preferences will converge.',
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
