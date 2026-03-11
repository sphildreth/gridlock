import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../app/logging/app_logger.dart';
import '../../../app/logging/import_log_details.dart';
import '../domain/app_config.dart';
import '../domain/excel_import_models.dart';
import '../domain/sql_dump_import_models.dart';
import '../domain/sqlite_import_models.dart';
import '../domain/workspace_models.dart';
import '../domain/workspace_shell_preferences.dart';
import '../domain/workspace_state.dart';
import '../infrastructure/app_config_store.dart';
import '../infrastructure/decentdb_bridge.dart';
import '../infrastructure/layout_persistence_service.dart';
import '../infrastructure/workspace_state_store.dart';

class WorkspaceController extends ChangeNotifier {
  static const int _maxQueryHistoryEntries = 40;
  static const int _maxMessageHistoryEntries = 80;

  WorkspaceController({
    WorkspaceDatabaseGateway? gateway,
    WorkspaceConfigStore? configStore,
    WorkspaceStateStore? workspaceStateStore,
    LayoutPersistenceService? layoutPersistenceService,
    AppLogger? logger,
  }) : _logger = logger ?? const NoOpAppLogger(),
       _gateway = gateway ?? DecentDbBridge(),
       _configStore = configStore ?? AppConfigStore(logger: logger),
       _workspaceStateStore = workspaceStateStore ?? FileWorkspaceStateStore(),
       _layoutPersistenceService =
           layoutPersistenceService ?? const LayoutPersistenceService() {
    _resetTabs(notify: false, resetCounters: true);
  }

  final AppLogger _logger;
  final WorkspaceDatabaseGateway _gateway;
  final WorkspaceConfigStore _configStore;
  final WorkspaceStateStore _workspaceStateStore;
  final LayoutPersistenceService _layoutPersistenceService;

  AppConfig config = AppConfig.defaults();
  SchemaSnapshot schema = SchemaSnapshot.empty();
  List<QueryTabState> tabs = const <QueryTabState>[];
  ExcelImportSession? excelImportSession;
  SqlDumpImportSession? sqlDumpImportSession;
  SqliteImportSession? sqliteImportSession;

  String? databasePath;
  String? engineVersion;
  String? nativeLibraryPath;
  String? workspaceError;
  String? workspaceMessage;
  bool isInitializing = true;
  bool isSchemaLoading = false;
  bool isOpeningDatabase = false;

  int _nextTabIdCounter = 1;
  int _nextTabTitleCounter = 1;
  String? _activeTabId;
  Timer? _workspaceSaveDebounce;
  StreamSubscription<ExcelImportUpdate>? _excelImportSubscription;
  StreamSubscription<SqlDumpImportUpdate>? _sqlDumpImportSubscription;
  StreamSubscription<SqliteImportUpdate>? _sqliteImportSubscription;
  bool _disposed = false;

  bool get hasOpenDatabase => databasePath != null;
  bool get hasExcelImportSession => excelImportSession != null;
  bool get hasSqlDumpImportSession => sqlDumpImportSession != null;
  bool get hasSqliteImportSession => sqliteImportSession != null;
  bool get hasImportSession =>
      hasExcelImportSession ||
      hasSqlDumpImportSession ||
      hasSqliteImportSession;

  String get activeTabId => _activeTabId ?? tabs.first.id;

  QueryTabState get activeTab =>
      tabs.firstWhere((tab) => tab.id == activeTabId);

  List<QueryHistoryEntry> get queryHistory {
    final entries = <QueryHistoryEntry>[
      for (final tab in tabs) ...tab.queryHistory,
    ];
    entries.sort((left, right) => right.ranAt.compareTo(left.ranAt));
    return entries;
  }

  bool get hasRunningTabs => tabs.any(
    (tab) =>
        tab.canCancel ||
        tab.isExporting ||
        tab.phase == QueryPhase.running ||
        tab.phase == QueryPhase.fetching,
  );

  String get configFilePath => _configStore.describeLocation();

  bool get canRunActiveTab => canRunTab(activeTabId);

  bool get canCancelActiveTab => tabById(activeTabId)?.canCancel ?? false;

  AppLogger get logger => _logger;

  void _logDebug(
    String operation,
    String message, {
    String category = 'workspace',
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
  }) {
    _logger.debug(
      category: category,
      operation: operation,
      message: message,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
    );
  }

  void _logInfo(
    String operation,
    String message, {
    String category = 'workspace',
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
  }) {
    _logger.info(
      category: category,
      operation: operation,
      message: message,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
    );
  }

  void _logWarning(
    String operation,
    String message, {
    String category = 'workspace',
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.warning(
      category: category,
      operation: operation,
      message: message,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _logError(
    String operation,
    String message, {
    String category = 'workspace',
    String? databasePath,
    String? sql,
    int? rowCount,
    int? rowsAffected,
    int? elapsedNanos,
    Map<String, Object?>? details,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.error(
      category: category,
      operation: operation,
      message: message,
      databasePath: databasePath,
      sql: sql,
      rowCount: rowCount,
      rowsAffected: rowsAffected,
      elapsedNanos: elapsedNanos,
      details: details,
      error: error,
      stackTrace: stackTrace,
    );
  }

  int _durationToNanos(Duration duration) => duration.inMicroseconds * 1000;

  QueryTabState? tabById(String tabId) {
    for (final tab in tabs) {
      if (tab.id == tabId) {
        return tab;
      }
    }
    return null;
  }

  bool canRunTab(String tabId) {
    final tab = tabById(tabId);
    if (tab == null || !hasOpenDatabase || tab.isExporting) {
      return false;
    }
    return switch (tab.phase) {
      QueryPhase.idle ||
      QueryPhase.completed ||
      QueryPhase.cancelled ||
      QueryPhase.failed => true,
      QueryPhase.opening ||
      QueryPhase.running ||
      QueryPhase.fetching ||
      QueryPhase.cancelling => false,
    };
  }

  Future<void> initialize() async {
    if (!isInitializing) {
      return;
    }

    final stopwatch = Stopwatch()..start();
    await _logger.initialize(minimumLevel: config.logging.verbosity);
    _logInfo('initialize', 'Starting workspace controller initialization.');
    try {
      config = await _configStore.load();
      _logger.updateMinimumLevel(config.logging.verbosity);
      nativeLibraryPath = await _gateway.initialize();
      workspaceMessage = 'Ready.';
      workspaceError = null;
      await _reopenMostRecentWorkspaceIfAvailable();
      _logInfo(
        'initialize',
        'Workspace controller initialized.',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        details: <String, Object?>{
          'native_library_path': nativeLibraryPath,
          'recent_file_count': config.recentFiles.length,
          'theme_id': config.appearance.activeTheme,
          'verbosity': config.logging.verbosity.name,
        },
      );
    } catch (error) {
      workspaceError = error.toString();
      workspaceMessage = null;
      _logError(
        'initialize',
        'Workspace controller initialization failed.',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
      );
    } finally {
      isInitializing = false;
      _safeNotify();
    }
  }

  Future<void> openDatabase(
    String rawPath, {
    required bool createIfMissing,
    bool restoreStartupQuery = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    final normalized = rawPath.trim();
    if (normalized.isEmpty) {
      _setWorkspaceError('Enter a DecentDB file path first.');
      return;
    }

    final file = File(normalized);
    try {
      if (createIfMissing) {
        if (await file.exists()) {
          _setWorkspaceError(
            'Refusing to create over an existing file: $normalized',
          );
          return;
        }
        await file.parent.create(recursive: true);
      } else if (!await file.exists()) {
        _setWorkspaceError('Database file does not exist: $normalized');
        return;
      }
    } on FileSystemException catch (error) {
      _setWorkspaceError(error.message);
      return;
    }

    _workspaceSaveDebounce?.cancel();
    await _cancelAllOpenCursors();

    isOpeningDatabase = true;
    isSchemaLoading = true;
    schema = SchemaSnapshot.empty();
    workspaceError = null;
    workspaceMessage = createIfMissing
        ? 'Creating database...'
        : 'Opening database...';
    _safeNotify();
    _logInfo(
      'open_database',
      createIfMissing ? 'Creating database.' : 'Opening database.',
      databasePath: normalized,
      details: <String, Object?>{
        'create_if_missing': createIfMissing,
        'restore_startup_query': restoreStartupQuery,
      },
    );

    try {
      final session = await _gateway.openDatabase(normalized);
      databasePath = session.path;
      engineVersion = session.engineVersion;
      config = config.pushRecentFile(session.path);
      await _configStore.save(config);
      final restoredState = await _workspaceStateStore.load(session.path);
      _restoreTabs(restoredState, notify: false);
      await refreshSchema(showLoadingState: false);
      if (restoreStartupQuery) {
        await _restoreStartupQueryState();
      }
      await _persistWorkspaceStateNow();
      workspaceMessage =
          'Opened ${p.basename(session.path)}'
          ' on DecentDB ${session.engineVersion}'
          ' with ${tabs.length} query tab${tabs.length == 1 ? '' : 's'}.';
      _logInfo(
        'open_database',
        'Opened database successfully.',
        databasePath: session.path,
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        details: <String, Object?>{
          'engine_version': session.engineVersion,
          'tab_count': tabs.length,
          'schema_tables': schema.tables.length,
          'schema_views': schema.views.length,
        },
      );
    } catch (error) {
      databasePath = null;
      engineVersion = null;
      schema = SchemaSnapshot.empty();
      _setWorkspaceError(error.toString());
      _resetTabs(notify: false, resetCounters: true);
      _logError(
        'open_database',
        'Opening database failed.',
        databasePath: normalized,
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
      );
    } finally {
      isOpeningDatabase = false;
      isSchemaLoading = false;
      _safeNotify();
    }
  }

  Future<void> refreshSchema({bool showLoadingState = true}) async {
    if (!hasOpenDatabase) {
      return;
    }

    final stopwatch = Stopwatch()..start();

    if (showLoadingState) {
      isSchemaLoading = true;
      workspaceError = null;
      workspaceMessage = 'Refreshing schema...';
      _safeNotify();
    }

    try {
      schema = await _gateway.loadSchema();
      workspaceMessage =
          'Loaded ${schema.tables.length} tables and ${schema.views.length} views.';
      workspaceError = null;
      _logInfo(
        'refresh_schema',
        'Loaded schema snapshot.',
        databasePath: databasePath,
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        details: <String, Object?>{
          'table_count': schema.tables.length,
          'view_count': schema.views.length,
          'index_count': schema.indexes.length,
        },
      );
    } catch (error) {
      _setWorkspaceError(error.toString());
      _logError(
        'refresh_schema',
        'Schema refresh failed.',
        databasePath: databasePath,
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
      );
    } finally {
      isSchemaLoading = false;
      _safeNotify();
    }
  }

  void updateActiveSql(String value) {
    _mutateActiveTab((tab) => tab.copyWith(sql: value), persist: true);
  }

  void updateActiveParameterJson(String value) {
    _mutateActiveTab(
      (tab) => tab.copyWith(parameterJson: value),
      persist: true,
    );
  }

  Future<void> _reopenMostRecentWorkspaceIfAvailable() async {
    final lastOpenedPath = config.recentFiles.isEmpty
        ? null
        : config.recentFiles.first.trim();
    if (lastOpenedPath == null || lastOpenedPath.isEmpty) {
      return;
    }

    final file = File(lastOpenedPath);
    try {
      if (!await file.exists()) {
        return;
      }
    } on FileSystemException {
      return;
    }

    await openDatabase(
      lastOpenedPath,
      createIfMissing: false,
      restoreStartupQuery: true,
    );
  }

  void updateActiveExportPath(String value) {
    _mutateActiveTab((tab) => tab.copyWith(exportPath: value), persist: true);
  }

  void selectTab(String tabId) {
    if (tabById(tabId) == null || activeTabId == tabId) {
      return;
    }
    _activeTabId = tabId;
    _scheduleWorkspaceStateSave();
    _safeNotify();
  }

  void nextTab() {
    if (tabs.length < 2) {
      return;
    }
    final currentIndex = tabs.indexWhere((tab) => tab.id == activeTabId);
    final nextIndex = currentIndex < 0 ? 0 : (currentIndex + 1) % tabs.length;
    selectTab(tabs[nextIndex].id);
  }

  void previousTab() {
    if (tabs.length < 2) {
      return;
    }
    final currentIndex = tabs.indexWhere((tab) => tab.id == activeTabId);
    final nextIndex = currentIndex <= 0 ? tabs.length - 1 : currentIndex - 1;
    selectTab(tabs[nextIndex].id);
  }

  void loadHistoryEntryIntoActiveTab(
    QueryHistoryEntry entry, {
    bool openInNewTab = false,
  }) {
    loadHistoryEntryIntoTab(activeTabId, entry, openInNewTab: openInNewTab);
  }

  void loadHistoryEntryIntoTab(
    String tabId,
    QueryHistoryEntry entry, {
    bool openInNewTab = false,
  }) {
    if (openInNewTab) {
      createTab(sql: entry.sql);
      tabId = activeTabId;
    }
    _mutateTab(
      tabId,
      (tab) => tab.copyWith(sql: entry.sql, parameterJson: entry.parameterJson),
      persist: true,
    );
  }

  Future<void> rerunHistoryEntry(
    QueryHistoryEntry entry, {
    bool openInNewTab = false,
  }) async {
    loadHistoryEntryIntoActiveTab(entry, openInNewTab: openInNewTab);
    await runActiveTab();
  }

  void createTab({String? sql}) {
    final title = _newTabTitle();
    final tab = QueryTabState.initial(
      id: _newTabId(),
      title: title,
      sql: sql ?? 'SELECT 1 AS ready;',
      exportPath: _suggestExportPathForTitle(title),
    );
    tabs = <QueryTabState>[...tabs, tab];
    _activeTabId = tab.id;
    _scheduleWorkspaceStateSave();
    _safeNotify();
  }

  Future<void> closeTab(String tabId) async {
    final closing = tabById(tabId);
    if (closing == null) {
      return;
    }

    final closingIndex = tabs.indexWhere((tab) => tab.id == tabId);

    if (closing.cursorId != null) {
      try {
        await _gateway.cancelQuery(closing.cursorId!);
      } catch (_) {
        // Best-effort cleanup.
      }
    }

    final remaining = tabs.where((tab) => tab.id != tabId).toList();
    if (remaining.isEmpty) {
      _resetTabs(notify: false);
    } else {
      tabs = remaining;
      if (_activeTabId == tabId) {
        final nextIndex = closingIndex.clamp(0, remaining.length - 1);
        _activeTabId = remaining[nextIndex].id;
      }
    }

    _scheduleWorkspaceStateSave();
    _safeNotify();
  }

  Future<void> runActiveTab() => runTab(activeTabId);

  Future<void> runActiveSql(
    String sql, {
    int bufferStartOffset = 0,
    String description = 'selected SQL',
  }) => runTab(
    activeTabId,
    sqlOverride: sql,
    sqlBufferStartOffset: bufferStartOffset,
    sqlOverrideDescription: description,
  );

  Future<void> runTab(
    String tabId, {
    String? sqlOverride,
    int sqlBufferStartOffset = 0,
    String sqlOverrideDescription = 'selected SQL',
  }) async {
    final stopwatch = Stopwatch()..start();
    final tab = tabById(tabId);
    if (tab == null || !canRunTab(tabId)) {
      return;
    }
    if (!hasOpenDatabase) {
      _setTabError(
        tabId,
        QueryErrorDetails(
          stage: QueryErrorStage.validation,
          message: 'Open or create a DecentDB file before running SQL.',
        ),
      );
      return;
    }

    final effectiveSourceSql = sqlOverride ?? tab.sql;
    final trimmedSql = effectiveSourceSql.trim();
    final isAlternateSql = sqlOverride != null;
    final effectiveBufferStartOffset = isAlternateSql
        ? sqlBufferStartOffset
        : effectiveSourceSql.length - effectiveSourceSql.trimLeft().length;
    if (trimmedSql.isEmpty) {
      _setTabError(
        tabId,
        QueryErrorDetails(
          stage: QueryErrorStage.validation,
          message: 'Enter SQL before pressing Run.',
        ),
      );
      return;
    }

    final params = _parseParameters(tabId, tab.parameterJson);
    if (params == null) {
      return;
    }

    final startedAt = DateTime.now();
    final generation = tab.executionGeneration + 1;
    final previousCursor = tab.cursorId;
    _mutateTab(
      tabId,
      (current) => current.copyWith(
        phase: QueryPhase.opening,
        resultColumns: const <String>[],
        resultRows: const <Map<String, Object?>>[],
        cursorId: null,
        error: null,
        statusMessage: isAlternateSql
            ? 'Executing $sqlOverrideDescription...'
            : 'Executing SQL...',
        lastSql: trimmedSql,
        lastParameterJson: tab.parameterJson,
        lastParams: params,
        lastRunStartedAt: startedAt,
        rowsAffected: null,
        elapsed: null,
        hasMoreRows: false,
        isResultPartial: false,
        executionGeneration: generation,
        executionPlan: const QueryExecutionPlanState.loading(),
        messageHistory: _appendMessage(
          current.messageHistory,
          QueryMessageLevel.info,
          isAlternateSql
              ? 'Executing $sqlOverrideDescription...'
              : 'Executing SQL...',
          timestamp: startedAt,
        ),
      ),
      notify: false,
    );
    _safeNotify();
    _logInfo(
      'run_query',
      isAlternateSql
          ? 'Executing $sqlOverrideDescription.'
          : 'Executing SQL buffer.',
      category: 'query',
      databasePath: databasePath,
      sql: trimmedSql,
      details: <String, Object?>{
        'tab_id': tabId,
        'execution_target': isAlternateSql ? sqlOverrideDescription : 'buffer',
        'parameter_count': params.length,
      },
    );

    if (previousCursor != null) {
      unawaited(_gateway.cancelQuery(previousCursor));
    }

    try {
      final page = await _gateway.runQuery(
        sql: trimmedSql,
        params: params,
        pageSize: config.defaultPageSize,
      );
      if (!_isCurrentGeneration(tabId, generation)) {
        if (page.cursorId != null) {
          unawaited(_gateway.cancelQuery(page.cursorId!));
        }
        return;
      }

      _mutateTab(tabId, (current) {
        final statusMessage = page.rowsAffected != null
            ? 'Statement completed with ${page.rowsAffected} affected rows.'
            : 'Loaded ${page.rows.length} rows from the first page.';
        final explainsCurrentSql = _isExplainSql(trimmedSql);
        final shouldLoadExecutionPlan = _shouldLoadExecutionPlan(
          sql: trimmedSql,
          page: page,
        );
        final updated = _applyFirstPage(
          current,
          page,
          statusMessage: statusMessage,
        );
        final withPlan = explainsCurrentSql
            ? updated.copyWith(
                executionPlan: QueryExecutionPlanState(
                  columns: page.columns,
                  rows: page.rows,
                  isLoading: !page.done,
                ),
              )
            : shouldLoadExecutionPlan
            ? updated
            : updated.copyWith(
                executionPlan: const QueryExecutionPlanState.idle().copyWith(
                  errorMessage:
                      'Execution plan is only available for statements that return rows.',
                ),
              );
        final withMessage = withPlan.copyWith(
          messageHistory: _appendMessage(
            withPlan.messageHistory,
            QueryMessageLevel.info,
            statusMessage,
          ),
        );
        if (!page.done) {
          _logger.logQueryTiming(
            databasePath: databasePath ?? '',
            sql: trimmedSql,
            rowCount: page.rows.length,
            rowsAffected: page.rowsAffected,
            elapsedNanos: _durationToNanos(page.elapsed),
            operation: 'query.first_page',
            details: <String, Object?>{'tab_id': tabId, 'has_more_rows': true},
          );
          return withMessage;
        }
        _logger.logQueryTiming(
          databasePath: databasePath ?? '',
          sql: trimmedSql,
          rowCount: withMessage.resultRows.length,
          rowsAffected: withMessage.rowsAffected,
          elapsedNanos: _durationToNanos(withMessage.elapsed ?? page.elapsed),
          details: <String, Object?>{'tab_id': tabId, 'has_more_rows': false},
        );
        return withMessage.copyWith(
          queryHistory: _appendQueryHistory(
            withMessage.queryHistory,
            _buildQueryHistoryEntry(
              withMessage,
              outcome: QueryHistoryOutcome.completed,
              rowsLoaded: withMessage.resultRows.length,
              rowsAffected: withMessage.rowsAffected,
              elapsed: withMessage.elapsed,
            ),
          ),
        );
      }, notify: false);
      if (_shouldLoadExecutionPlan(sql: trimmedSql, page: page)) {
        unawaited(
          _loadExecutionPlanForTab(
            tabId,
            generation: generation,
            sql: trimmedSql,
            params: params,
          ),
        );
      }
    } catch (error) {
      if (_isCurrentGeneration(tabId, generation)) {
        _mutateTab(tabId, (current) {
          final failure = QueryErrorDetails.fromError(
            error,
            stage: QueryErrorStage.opening,
            executedSql: trimmedSql,
            bufferText: tab.sql,
            bufferStartOffset: effectiveBufferStartOffset,
          );
          final updated = current.copyWith(
            phase: QueryPhase.failed,
            error: failure,
            statusMessage: null,
            cursorId: null,
            hasMoreRows: false,
            executionPlan: current.executionPlan.copyWith(
              isLoading: false,
              errorMessage:
                  'Execution plan unavailable because the query did not complete.',
            ),
            messageHistory: _appendMessage(
              current.messageHistory,
              QueryMessageLevel.error,
              '${failure.stageLabel}: ${failure.message}',
            ),
          );
          return updated.copyWith(
            queryHistory: _appendQueryHistory(
              updated.queryHistory,
              _buildQueryHistoryEntry(
                updated,
                outcome: QueryHistoryOutcome.failed,
                errorMessage: failure.message,
                rowsLoaded: updated.resultRows.length,
                rowsAffected: updated.rowsAffected,
                elapsed: updated.elapsed,
              ),
            ),
          );
        }, notify: false);
        _logError(
          'run_query',
          'Query execution failed.',
          category: 'query',
          databasePath: databasePath,
          sql: trimmedSql,
          elapsedNanos: _durationToNanos(stopwatch.elapsed),
          error: error,
          details: <String, Object?>{
            'tab_id': tabId,
            'execution_target': isAlternateSql
                ? sqlOverrideDescription
                : 'buffer',
          },
        );
      }
    } finally {
      _safeNotify();
    }
  }

  Future<void> fetchNextPage({String? tabId}) async {
    final resolvedTabId = tabId ?? activeTabId;
    final tab = tabById(resolvedTabId);
    if (tab == null ||
        tab.cursorId == null ||
        tab.phase == QueryPhase.fetching ||
        !tab.hasMoreRows) {
      return;
    }

    final generation = tab.executionGeneration;
    _mutateTab(
      resolvedTabId,
      (current) => current.copyWith(
        phase: QueryPhase.fetching,
        error: null,
        statusMessage: 'Loading the next page...',
      ),
      notify: false,
    );
    _safeNotify();
    final stopwatch = Stopwatch()..start();
    _logDebug(
      'fetch_page',
      'Fetching next result page.',
      category: 'query',
      databasePath: databasePath,
      sql: tab.lastSql ?? tab.sql,
      details: <String, Object?>{
        'tab_id': resolvedTabId,
        'cursor_id': tab.cursorId,
      },
    );

    try {
      final page = await _gateway.fetchNextPage(
        cursorId: tab.cursorId!,
        pageSize: config.defaultPageSize,
      );
      if (!_isCurrentGeneration(resolvedTabId, generation)) {
        if (page.cursorId != null) {
          unawaited(_gateway.cancelQuery(page.cursorId!));
        }
        return;
      }

      _mutateTab(resolvedTabId, (current) {
        final rowCount = current.resultRows.length + page.rows.length;
        final statusMessage = page.done
            ? 'Loaded $rowCount total rows.'
            : 'Loaded $rowCount rows so far.';
        final updated = current.copyWith(
          phase: QueryPhase.completed,
          resultRows: <Map<String, Object?>>[
            ...current.resultRows,
            ...page.rows,
          ],
          cursorId: page.cursorId,
          hasMoreRows: !page.done,
          elapsed: (current.elapsed ?? Duration.zero) + page.elapsed,
          statusMessage: statusMessage,
          messageHistory: _appendMessage(
            current.messageHistory,
            QueryMessageLevel.info,
            statusMessage,
          ),
        );
        final withPlan = _isExplainSql(current.lastSql ?? current.sql)
            ? updated.copyWith(
                executionPlan: updated.executionPlan.copyWith(
                  columns: updated.resultColumns,
                  rows: updated.resultRows,
                  isLoading: !page.done,
                  errorMessage: null,
                ),
              )
            : updated;
        if (!page.done) {
          return withPlan;
        }
        _logger.logQueryTiming(
          databasePath: databasePath ?? '',
          sql: withPlan.lastSql ?? withPlan.sql,
          rowCount: withPlan.resultRows.length,
          rowsAffected: withPlan.rowsAffected,
          elapsedNanos: _durationToNanos(withPlan.elapsed ?? page.elapsed),
          details: <String, Object?>{
            'tab_id': resolvedTabId,
            'completed_via_fetch': true,
          },
        );
        return withPlan.copyWith(
          queryHistory: _appendQueryHistory(
            withPlan.queryHistory,
            _buildQueryHistoryEntry(
              withPlan,
              outcome: QueryHistoryOutcome.completed,
              rowsLoaded: withPlan.resultRows.length,
              rowsAffected: withPlan.rowsAffected,
              elapsed: withPlan.elapsed,
            ),
          ),
        );
      }, notify: false);
    } catch (error) {
      if (_isCurrentGeneration(resolvedTabId, generation)) {
        _mutateTab(resolvedTabId, (current) {
          final failure = QueryErrorDetails.fromError(
            error,
            stage: QueryErrorStage.paging,
          );
          final updated = current.copyWith(
            phase: QueryPhase.failed,
            error: failure,
            statusMessage: null,
            cursorId: null,
            hasMoreRows: false,
            executionPlan: _isExplainSql(current.lastSql ?? current.sql)
                ? current.executionPlan.copyWith(
                    isLoading: false,
                    errorMessage: failure.message,
                  )
                : current.executionPlan,
            messageHistory: _appendMessage(
              current.messageHistory,
              QueryMessageLevel.error,
              '${failure.stageLabel}: ${failure.message}',
            ),
          );
          return updated.copyWith(
            queryHistory: _appendQueryHistory(
              updated.queryHistory,
              _buildQueryHistoryEntry(
                updated,
                outcome: QueryHistoryOutcome.failed,
                errorMessage: failure.message,
                rowsLoaded: updated.resultRows.length,
                rowsAffected: updated.rowsAffected,
                elapsed: updated.elapsed,
              ),
            ),
          );
        }, notify: false);
        _logError(
          'fetch_page',
          'Fetching the next query page failed.',
          category: 'query',
          databasePath: databasePath,
          sql: tab.lastSql ?? tab.sql,
          elapsedNanos: _durationToNanos(stopwatch.elapsed),
          error: error,
          details: <String, Object?>{'tab_id': resolvedTabId},
        );
      }
    } finally {
      _safeNotify();
    }
  }

  Future<void> cancelActiveQuery() => cancelTabQuery(activeTabId);

  Future<void> cancelTabQuery(String tabId) async {
    final tab = tabById(tabId);
    if (tab == null || !tab.canCancel) {
      return;
    }

    final stopwatch = Stopwatch()..start();

    final generation = tab.executionGeneration + 1;
    final hasPartialRows = tab.resultRows.isNotEmpty;
    final cursorId = tab.cursorId;
    _mutateTab(
      tabId,
      (current) => current.copyWith(
        phase: QueryPhase.cancelling,
        error: null,
        statusMessage: 'Cancelling query...',
        cursorId: null,
        hasMoreRows: false,
        executionGeneration: generation,
        executionPlan: current.executionPlan.copyWith(isLoading: false),
      ),
      notify: false,
    );
    _safeNotify();
    _logWarning(
      'cancel_query',
      'Cancelling active query.',
      category: 'query',
      databasePath: databasePath,
      sql: tab.lastSql ?? tab.sql,
      details: <String, Object?>{'tab_id': tabId},
    );

    if (cursorId != null) {
      try {
        await _gateway.cancelQuery(cursorId);
      } catch (error) {
        if (_isCurrentGeneration(tabId, generation)) {
          _mutateTab(tabId, (current) {
            final failure = QueryErrorDetails.fromError(
              error,
              stage: QueryErrorStage.cancellation,
            );
            final updated = current.copyWith(
              phase: QueryPhase.failed,
              error: failure,
              statusMessage: null,
              messageHistory: _appendMessage(
                current.messageHistory,
                QueryMessageLevel.error,
                '${failure.stageLabel}: ${failure.message}',
              ),
            );
            return updated.copyWith(
              queryHistory: _appendQueryHistory(
                updated.queryHistory,
                _buildQueryHistoryEntry(
                  updated,
                  outcome: QueryHistoryOutcome.failed,
                  errorMessage: failure.message,
                  rowsLoaded: updated.resultRows.length,
                  rowsAffected: updated.rowsAffected,
                  elapsed: updated.elapsed,
                ),
              ),
            );
          }, notify: false);
          _safeNotify();
          _logError(
            'cancel_query',
            'Query cancellation failed.',
            category: 'query',
            databasePath: databasePath,
            sql: tab.lastSql ?? tab.sql,
            elapsedNanos: _durationToNanos(stopwatch.elapsed),
            error: error,
            details: <String, Object?>{'tab_id': tabId},
          );
        }
        return;
      }
    }

    if (_isCurrentGeneration(tabId, generation)) {
      _mutateTab(tabId, (current) {
        final statusMessage = hasPartialRows
            ? 'Query cancelled. Partial results remain visible.'
            : 'Query cancelled before a complete page was loaded.';
        final updated = current.copyWith(
          phase: QueryPhase.cancelled,
          error: null,
          statusMessage: statusMessage,
          isResultPartial: hasPartialRows,
          hasMoreRows: false,
          messageHistory: _appendMessage(
            current.messageHistory,
            QueryMessageLevel.warning,
            statusMessage,
          ),
        );
        return updated.copyWith(
          queryHistory: _appendQueryHistory(
            updated.queryHistory,
            _buildQueryHistoryEntry(
              updated,
              outcome: QueryHistoryOutcome.cancelled,
              rowsLoaded: updated.resultRows.length,
              rowsAffected: updated.rowsAffected,
              elapsed: updated.elapsed,
            ),
          ),
        );
      }, notify: false);
      _safeNotify();
      _logWarning(
        'cancel_query',
        'Query cancellation completed.',
        category: 'query',
        databasePath: databasePath,
        sql: tab.lastSql ?? tab.sql,
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        details: <String, Object?>{
          'tab_id': tabId,
          'partial_results': hasPartialRows,
        },
      );
    }
  }

  Future<void> exportCurrentQuery() => exportTabQuery(activeTabId);

  Future<void> exportTabQuery(String tabId) async {
    final tab = tabById(tabId);
    if (tab == null) {
      return;
    }

    final stopwatch = Stopwatch()..start();

    final exportPath = tab.exportPath.trim().isEmpty
        ? suggestExportPath(tabId)
        : tab.exportPath.trim();
    if (!tab.canExport) {
      _setTabError(
        tabId,
        QueryErrorDetails(
          stage: QueryErrorStage.export,
          message: 'Run a row-producing query before exporting CSV.',
        ),
      );
      return;
    }
    if (exportPath.isEmpty) {
      _setTabError(
        tabId,
        QueryErrorDetails(
          stage: QueryErrorStage.export,
          message: 'Enter a CSV destination path first.',
        ),
      );
      return;
    }

    _mutateTab(
      tabId,
      (current) => current.copyWith(
        isExporting: true,
        error: null,
        statusMessage: 'Exporting CSV...',
        messageHistory: _appendMessage(
          current.messageHistory,
          QueryMessageLevel.info,
          'Exporting CSV...',
        ),
      ),
      notify: false,
    );
    _safeNotify();
    _logInfo(
      'export_csv',
      'Exporting query results to CSV.',
      category: 'export',
      databasePath: databasePath,
      sql: tab.lastSql,
      details: <String, Object?>{'tab_id': tabId, 'path': exportPath},
    );

    try {
      final result = await _gateway.exportCsv(
        sql: tab.lastSql!,
        params: tab.lastParams,
        pageSize: config.defaultPageSize,
        path: exportPath,
        delimiter: config.csvDelimiter,
        includeHeaders: config.csvIncludeHeaders,
      );
      _mutateTab(tabId, (current) {
        final statusMessage =
            'Exported ${result.rowCount} rows to ${result.path}.';
        return current.copyWith(
          isExporting: false,
          statusMessage: statusMessage,
          messageHistory: _appendMessage(
            current.messageHistory,
            QueryMessageLevel.info,
            statusMessage,
          ),
        );
      }, notify: false);
      _logInfo(
        'export_csv',
        'CSV export completed.',
        category: 'export',
        databasePath: databasePath,
        sql: tab.lastSql,
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        rowCount: result.rowCount,
        details: <String, Object?>{'tab_id': tabId, 'path': result.path},
      );
    } catch (error) {
      _mutateTab(tabId, (current) {
        final failure = QueryErrorDetails.fromError(
          error,
          stage: QueryErrorStage.export,
        );
        return current.copyWith(
          isExporting: false,
          error: failure,
          statusMessage: null,
          messageHistory: _appendMessage(
            current.messageHistory,
            QueryMessageLevel.error,
            '${failure.stageLabel}: ${failure.message}',
          ),
        );
      }, notify: false);
      _logError(
        'export_csv',
        'CSV export failed.',
        category: 'export',
        databasePath: databasePath,
        sql: tab.lastSql,
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
        details: <String, Object?>{'tab_id': tabId, 'path': exportPath},
      );
    } finally {
      _safeNotify();
    }
  }

  Future<void> updateDefaultPageSize(String rawValue) async {
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null || parsed <= 0) {
      _setWorkspaceError('Page size must be a positive integer.');
      return;
    }

    config = config.copyWith(defaultPageSize: parsed);
    await _persistConfig('Updated default page size to $parsed rows.');
  }

  Future<void> updateCsvDelimiter(String rawValue) async {
    if (rawValue.isEmpty) {
      _setWorkspaceError('CSV delimiter cannot be empty.');
      return;
    }
    config = config.copyWith(csvDelimiter: rawValue);
    await _persistConfig('Updated CSV delimiter.');
  }

  Future<void> updateCsvIncludeHeaders(bool value) async {
    config = config.copyWith(csvIncludeHeaders: value);
    await _persistConfig(
      value
          ? 'CSV exports will include headers.'
          : 'CSV exports will omit headers.',
    );
  }

  Future<void> updateAutocompleteEnabled(bool value) async {
    config = config.copyWith(
      editorSettings: config.editorSettings.copyWith(
        autocompleteEnabled: value,
      ),
    );
    await _persistConfig(
      value ? 'SQL autocomplete enabled.' : 'SQL autocomplete disabled.',
    );
  }

  Future<void> updateAutocompleteMaxSuggestions(String rawValue) async {
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null || parsed <= 0) {
      _setWorkspaceError(
        'Autocomplete suggestions must be a positive integer.',
      );
      return;
    }
    config = config.copyWith(
      editorSettings: config.editorSettings.copyWith(
        autocompleteMaxSuggestions: parsed,
      ),
    );
    await _persistConfig('Updated autocomplete suggestion limit.');
  }

  Future<void> updateFormatterUppercaseKeywords(bool value) async {
    config = config.copyWith(
      editorSettings: config.editorSettings.copyWith(
        formatUppercaseKeywords: value,
      ),
    );
    await _persistConfig(
      value
          ? 'Formatter will uppercase SQL keywords.'
          : 'Formatter will preserve keyword casing.',
    );
  }

  Future<void> updateEditorIndentSpaces(String rawValue) async {
    final parsed = int.tryParse(rawValue.trim());
    if (parsed == null || parsed <= 0) {
      _setWorkspaceError('Indent spaces must be a positive integer.');
      return;
    }
    config = config.copyWith(
      editorSettings: config.editorSettings.copyWith(indentSpaces: parsed),
    );
    await _persistConfig('Updated SQL formatter indentation.');
  }

  Future<void> saveSnippet(SqlSnippet snippet) async {
    config = config.upsertSnippet(snippet);
    await _persistConfig('Saved snippet "${snippet.name}".');
  }

  Future<void> deleteSnippet(String snippetId) async {
    final existing = config.snippets.where((item) => item.id == snippetId);
    if (existing.isEmpty) {
      return;
    }
    config = config.removeSnippet(snippetId);
    await _persistConfig('Deleted snippet "${existing.first.name}".');
  }

  Future<void> updateShellPreferences(
    WorkspaceShellPreferences preferences, {
    String? statusMessage,
  }) async {
    config = _layoutPersistenceService.save(config, preferences);
    await _persistConfig(statusMessage);
  }

  Future<void> reloadConfig() async {
    try {
      config = await _configStore.load();
      _logger.updateMinimumLevel(config.logging.verbosity);
      workspaceError = null;
      _logInfo(
        'reload_config',
        'Reloaded application configuration.',
        category: 'config',
        details: <String, Object?>{
          'theme_id': config.appearance.activeTheme,
          'verbosity': config.logging.verbosity.name,
        },
      );
      _safeNotify();
    } catch (error) {
      _setWorkspaceError(error.toString());
      _logError(
        'reload_config',
        'Reloading application configuration failed.',
        category: 'config',
        error: error,
      );
    }
  }

  Future<bool> applyAppConfig(AppConfig next, {String? statusMessage}) async {
    final validationError = _validateAppConfig(next);
    if (validationError != null) {
      _setWorkspaceError(validationError);
      return false;
    }

    config = next.copyWith(
      configVersion: AppConfig.currentConfigVersion,
      shellPreferences: next.shellPreferences.normalized(),
    );
    await _persistConfig(statusMessage ?? 'Updated application preferences.');
    _logger.updateMinimumLevel(config.logging.verbosity);
    if (workspaceError == null) {
      _logInfo(
        'apply_config',
        'Applied application configuration changes.',
        category: 'config',
        details: <String, Object?>{
          'theme_id': config.appearance.activeTheme,
          'verbosity': config.logging.verbosity.name,
          'show_line_numbers': config.editorSettings.showLineNumbers,
        },
      );
    }
    return workspaceError == null;
  }

  void beginExcelImport({String sourcePath = ''}) {
    final trimmedSource = sourcePath.trim();
    excelImportSession = ExcelImportSession.initial(sourcePath: trimmedSource)
        .copyWith(
          targetPath: trimmedSource.isEmpty
              ? ''
              : _suggestImportTargetPath(trimmedSource),
        );
    _safeNotify();
    _logInfo(
      'begin_excel_import',
      'Opened Excel import workflow.',
      category: 'import.excel',
      details: <String, Object?>{'source_path': trimmedSource},
    );
    if (trimmedSource.isNotEmpty) {
      unawaited(loadExcelImportSource(trimmedSource));
    }
  }

  void closeExcelImportSession() {
    if (excelImportSession?.phase == ExcelImportJobPhase.running ||
        excelImportSession?.phase == ExcelImportJobPhase.cancelling) {
      return;
    }
    excelImportSession = null;
    _safeNotify();
  }

  Future<void> loadExcelImportSource(String rawPath) async {
    final stopwatch = Stopwatch()..start();
    final normalized = rawPath.trim();
    if (normalized.isEmpty) {
      _setExcelImportError('Choose an Excel workbook first.');
      return;
    }

    final session =
        excelImportSession ??
        ExcelImportSession.initial(sourcePath: normalized);
    excelImportSession = session.copyWith(
      phase: ExcelImportJobPhase.inspecting,
      sourcePath: normalized,
      targetPath: session.targetPath.trim().isEmpty
          ? _suggestImportTargetPath(normalized)
          : session.targetPath,
      sheets: const <ExcelImportSheetDraft>[],
      warnings: const <String>[],
      focusedSheet: null,
      progress: null,
      summary: null,
      error: null,
      jobId: null,
    );
    _safeNotify();

    try {
      final inspection = await _gateway.inspectExcelSource(
        sourcePath: normalized,
        headerRow: session.headerRow,
      );
      final focused = inspection.sheets.where((sheet) => sheet.selected).isEmpty
          ? (inspection.sheets.isEmpty
                ? null
                : inspection.sheets.first.sourceName)
          : inspection.sheets.firstWhere((sheet) => sheet.selected).sourceName;
      excelImportSession = excelImportSession?.copyWith(
        phase: ExcelImportJobPhase.ready,
        sourcePath: inspection.sourcePath,
        headerRow: inspection.headerRow,
        sheets: inspection.sheets,
        warnings: inspection.warnings,
        focusedSheet: focused,
        error: inspection.sheets.isEmpty
            ? 'No worksheets were found in the selected workbook.'
            : null,
      );
      _logInfo(
        'inspect_excel_source',
        'Loaded Excel import inspection.',
        category: 'import.excel',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        details: buildImportInspectionLogDetails(
          sourcePath: inspection.sourcePath,
          tableCount: inspection.sheets.length,
          warnings: inspection.warnings,
          extra: <String, Object?>{'header_row': inspection.headerRow},
        ),
      );
      if (inspection.warnings.isNotEmpty) {
        _logWarning(
          'inspect_excel_source_warnings',
          'Excel inspection produced warnings.',
          category: 'import.excel',
          elapsedNanos: _durationToNanos(stopwatch.elapsed),
          details: buildImportInspectionLogDetails(
            sourcePath: inspection.sourcePath,
            tableCount: inspection.sheets.length,
            warnings: inspection.warnings,
            extra: <String, Object?>{'header_row': inspection.headerRow},
          ),
        );
      }
      _safeNotify();
    } catch (error) {
      _setExcelImportError(error.toString(), phase: ExcelImportJobPhase.failed);
      _logError(
        'inspect_excel_source',
        'Excel source inspection failed.',
        category: 'import.excel',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
        details: <String, Object?>{'source_path': normalized},
      );
    }
  }

  Future<void> updateExcelImportHeaderRow(bool value) async {
    final session = excelImportSession;
    if (session == null) {
      return;
    }
    excelImportSession = session.copyWith(headerRow: value, error: null);
    _safeNotify();
    if (session.sourcePath.trim().isNotEmpty) {
      await loadExcelImportSource(session.sourcePath);
    }
  }

  void setExcelImportStep(ExcelImportWizardStep step) {
    final session = excelImportSession;
    if (session == null) {
      return;
    }
    excelImportSession = session.copyWith(step: step, error: null);
    _safeNotify();
  }

  void updateExcelImportTargetPath(String value) {
    final session = excelImportSession;
    if (session == null) {
      return;
    }
    excelImportSession = session.copyWith(targetPath: value, error: null);
    _safeNotify();
  }

  void updateExcelImportIntoExistingTarget(bool value) {
    final session = excelImportSession;
    if (session == null) {
      return;
    }
    excelImportSession = session.copyWith(
      importIntoExistingTarget: value,
      replaceExistingTarget: value ? false : session.replaceExistingTarget,
      error: null,
    );
    _safeNotify();
  }

  void updateExcelImportReplaceExistingTarget(bool value) {
    final session = excelImportSession;
    if (session == null || session.importIntoExistingTarget) {
      return;
    }
    excelImportSession = session.copyWith(
      replaceExistingTarget: value,
      error: null,
    );
    _safeNotify();
  }

  void toggleExcelImportSheetSelection(String sourceName, bool selected) {
    final session = excelImportSession;
    if (session == null) {
      return;
    }

    final updatedSheets = <ExcelImportSheetDraft>[
      for (final sheet in session.sheets)
        if (sheet.sourceName == sourceName)
          sheet.copyWith(selected: selected)
        else
          sheet,
    ];
    String? focused;
    if (updatedSheets.any(
      (sheet) => sheet.sourceName == session.focusedSheet && sheet.selected,
    )) {
      focused = session.focusedSheet;
    } else {
      for (final sheet in updatedSheets) {
        if (sheet.selected) {
          focused = sheet.sourceName;
          break;
        }
      }
    }
    excelImportSession = session.copyWith(
      sheets: updatedSheets,
      focusedSheet: focused,
      error: null,
    );
    _safeNotify();
  }

  void focusExcelImportSheet(String sourceName) {
    final session = excelImportSession;
    if (session == null) {
      return;
    }
    excelImportSession = session.copyWith(focusedSheet: sourceName);
    _safeNotify();
  }

  void renameExcelImportSheet(String sourceName, String targetName) {
    _mutateExcelImportSheet(
      sourceName,
      (sheet) => sheet.copyWith(targetName: targetName),
    );
  }

  void renameExcelImportColumn(
    String sourceSheetName,
    int sourceColumnIndex,
    String targetName,
  ) {
    _mutateExcelImportSheet(
      sourceSheetName,
      (sheet) => sheet.copyWith(
        columns: <ExcelImportColumnDraft>[
          for (final column in sheet.columns)
            if (column.sourceIndex == sourceColumnIndex)
              column.copyWith(targetName: targetName)
            else
              column,
        ],
      ),
    );
  }

  void overrideExcelImportColumnType(
    String sourceSheetName,
    int sourceColumnIndex,
    String targetType,
  ) {
    _mutateExcelImportSheet(
      sourceSheetName,
      (sheet) => sheet.copyWith(
        columns: <ExcelImportColumnDraft>[
          for (final column in sheet.columns)
            if (column.sourceIndex == sourceColumnIndex)
              column.copyWith(targetType: targetType)
            else
              column,
        ],
      ),
    );
  }

  Future<void> runExcelImport() async {
    final stopwatch = Stopwatch()..start();
    final session = excelImportSession;
    if (session == null) {
      return;
    }
    if (session.selectedSheets.isEmpty) {
      _setExcelImportError('Select at least one worksheet to import.');
      return;
    }
    if (!session.canAdvanceFromTransforms) {
      _setExcelImportError(
        'Resolve duplicate or empty target names before starting the import.',
      );
      return;
    }
    if (session.targetPath.trim().isEmpty) {
      _setExcelImportError('Choose a target DecentDB file first.');
      return;
    }

    await _excelImportSubscription?.cancel();
    final jobId = createExcelImportJobId();
    final request = ExcelImportRequest(
      jobId: jobId,
      sourcePath: session.sourcePath,
      targetPath: session.targetPath.trim(),
      importIntoExistingTarget: session.importIntoExistingTarget,
      replaceExistingTarget: session.replaceExistingTarget,
      headerRow: session.headerRow,
      sheets: session.sheets,
    );

    excelImportSession = session.copyWith(
      step: ExcelImportWizardStep.execute,
      phase: ExcelImportJobPhase.running,
      error: null,
      summary: null,
      jobId: jobId,
      progress: ExcelImportProgress(
        jobId: jobId,
        currentSheet: request.selectedSheets.first.targetName,
        completedSheets: 0,
        totalSheets: request.selectedSheets.length,
        currentSheetRowsCopied: 0,
        currentSheetRowCount: request.selectedSheets.first.rowCount,
        totalRowsCopied: 0,
        message: 'Preparing Excel import...',
      ),
    );
    _safeNotify();
    _logInfo(
      'run_excel_import',
      'Starting Excel import.',
      category: 'import.excel',
      details: buildExcelImportRequestLogDetails(request),
    );

    _excelImportSubscription = _gateway.importExcel(request: request).listen((
      update,
    ) {
      final current = excelImportSession;
      if (current == null || current.jobId != update.jobId) {
        return;
      }

      switch (update.kind) {
        case ExcelImportUpdateKind.progress:
          excelImportSession = current.copyWith(
            phase: current.phase == ExcelImportJobPhase.cancelling
                ? ExcelImportJobPhase.cancelling
                : ExcelImportJobPhase.running,
            progress: update.progress,
            error: null,
          );
          break;
        case ExcelImportUpdateKind.completed:
          final summary = update.summary;
          excelImportSession = current.copyWith(
            step: ExcelImportWizardStep.summary,
            phase: ExcelImportJobPhase.completed,
            summary: summary,
            error: null,
          );
          workspaceMessage = summary?.statusMessage;
          workspaceError = null;
          _logInfo(
            'run_excel_import',
            'Excel import completed.',
            category: 'import.excel',
            databasePath: summary?.targetPath,
            rowCount: summary?.totalRowsCopied,
            elapsedNanos: _durationToNanos(stopwatch.elapsed),
            details: summary == null
                ? <String, Object?>{'job_id': update.jobId}
                : buildExcelImportSummaryLogDetails(summary),
          );
          if (summary != null && summary.warnings.isNotEmpty) {
            _logWarning(
              'run_excel_import_warnings',
              'Excel import completed with warnings.',
              category: 'import.excel',
              databasePath: summary.targetPath,
              rowCount: summary.totalRowsCopied,
              elapsedNanos: _durationToNanos(stopwatch.elapsed),
              details: buildExcelImportSummaryLogDetails(summary),
            );
          }
          break;
        case ExcelImportUpdateKind.cancelled:
          final summary = update.summary;
          excelImportSession = current.copyWith(
            step: ExcelImportWizardStep.summary,
            phase: ExcelImportJobPhase.cancelled,
            summary: summary,
            error: null,
          );
          workspaceMessage = summary?.statusMessage;
          workspaceError = null;
          _logWarning(
            'run_excel_import',
            'Excel import was cancelled.',
            category: 'import.excel',
            databasePath: summary?.targetPath,
            rowCount: summary?.totalRowsCopied,
            elapsedNanos: _durationToNanos(stopwatch.elapsed),
            details: summary == null
                ? <String, Object?>{'job_id': update.jobId}
                : buildExcelImportSummaryLogDetails(summary),
          );
          break;
        case ExcelImportUpdateKind.failed:
          excelImportSession = current.copyWith(
            step: ExcelImportWizardStep.summary,
            phase: ExcelImportJobPhase.failed,
            error: update.message ?? 'Excel import failed.',
          );
          _logError(
            'run_excel_import',
            'Excel import failed.',
            category: 'import.excel',
            elapsedNanos: _durationToNanos(stopwatch.elapsed),
            details: <String, Object?>{
              'job_id': update.jobId,
              'source_path': current.sourcePath,
              'target_path': current.targetPath,
              'selected_sheet_count': current.selectedSheets.length,
              'message': update.message,
            },
          );
          break;
      }
      _safeNotify();
    });
  }

  Future<void> cancelExcelImport() async {
    final stopwatch = Stopwatch()..start();
    final session = excelImportSession;
    if (session == null || session.jobId == null) {
      return;
    }
    excelImportSession = session.copyWith(
      phase: ExcelImportJobPhase.cancelling,
      error: null,
    );
    _safeNotify();
    _logWarning(
      'cancel_excel_import',
      'Cancelling Excel import.',
      category: 'import.excel',
      details: <String, Object?>{'job_id': session.jobId},
    );
    try {
      await _gateway.cancelImport(session.jobId!);
    } catch (error) {
      _setExcelImportError(error.toString(), phase: ExcelImportJobPhase.failed);
      _logError(
        'cancel_excel_import',
        'Excel import cancellation failed.',
        category: 'import.excel',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
        details: <String, Object?>{'job_id': session.jobId},
      );
    }
  }

  Future<void> openExcelImportedDatabaseFromSummary() async {
    final summary = excelImportSession?.summary;
    if (summary == null) {
      return;
    }
    await openDatabase(summary.targetPath, createIfMissing: false);
    excelImportSession = null;
    _safeNotify();
  }

  Future<void> runQueryForExcelImportedTable() async {
    final summary = excelImportSession?.summary;
    if (summary == null) {
      return;
    }
    await openDatabase(summary.targetPath, createIfMissing: false);
    if (summary.firstImportedTable != null) {
      createTab(
        sql:
            'SELECT *\nFROM ${_quoteIdentifier(summary.firstImportedTable!)}\nLIMIT ${config.defaultPageSize};',
      );
    }
    excelImportSession = null;
    _safeNotify();
  }

  void beginSqlDumpImport({String sourcePath = ''}) {
    final trimmedSource = sourcePath.trim();
    sqlDumpImportSession =
        SqlDumpImportSession.initial(sourcePath: trimmedSource).copyWith(
          targetPath: trimmedSource.isEmpty
              ? ''
              : _suggestImportTargetPath(trimmedSource),
        );
    _safeNotify();
    _logInfo(
      'begin_sql_dump_import',
      'Opened SQL dump import workflow.',
      category: 'import.sql_dump',
      details: <String, Object?>{'source_path': trimmedSource},
    );
    if (trimmedSource.isNotEmpty) {
      unawaited(loadSqlDumpImportSource(trimmedSource));
    }
  }

  void closeSqlDumpImportSession() {
    if (sqlDumpImportSession?.phase == SqlDumpImportJobPhase.running ||
        sqlDumpImportSession?.phase == SqlDumpImportJobPhase.cancelling) {
      return;
    }
    sqlDumpImportSession = null;
    _safeNotify();
  }

  Future<void> loadSqlDumpImportSource(String rawPath) async {
    final stopwatch = Stopwatch()..start();
    final normalized = rawPath.trim();
    if (normalized.isEmpty) {
      _setSqlDumpImportError('Choose a SQL dump file first.');
      return;
    }

    final session =
        sqlDumpImportSession ??
        SqlDumpImportSession.initial(sourcePath: normalized);
    sqlDumpImportSession = session.copyWith(
      phase: SqlDumpImportJobPhase.inspecting,
      sourcePath: normalized,
      targetPath: session.targetPath.trim().isEmpty
          ? _suggestImportTargetPath(normalized)
          : session.targetPath,
      tables: const <SqlDumpImportTableDraft>[],
      warnings: const <String>[],
      skippedStatements: const <SqlDumpImportSkippedStatement>[],
      totalStatements: 0,
      focusedTable: null,
      progress: null,
      summary: null,
      error: null,
      jobId: null,
    );
    _safeNotify();

    try {
      final inspection = await _gateway.inspectSqlDumpSource(
        sourcePath: normalized,
        encoding: session.encoding,
      );
      final focused = inspection.tables.isEmpty
          ? null
          : inspection.tables.first.sourceName;
      sqlDumpImportSession = sqlDumpImportSession?.copyWith(
        phase: SqlDumpImportJobPhase.ready,
        sourcePath: inspection.sourcePath,
        encoding: inspection.requestedEncoding,
        resolvedEncoding: inspection.resolvedEncoding,
        tables: inspection.tables,
        warnings: inspection.warnings,
        skippedStatements: inspection.skippedStatements,
        totalStatements: inspection.totalStatements,
        focusedTable: focused,
        error: inspection.tables.isEmpty
            ? 'No supported CREATE TABLE statements were parsed from the selected dump.'
            : null,
      );
      _logInfo(
        'inspect_sql_dump_source',
        'Loaded SQL dump inspection.',
        category: 'import.sql_dump',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        details: buildImportInspectionLogDetails(
          sourcePath: inspection.sourcePath,
          tableCount: inspection.tables.length,
          warnings: inspection.warnings,
          extra: <String, Object?>{
            'skipped_statement_count': inspection.skippedStatements.length,
            'encoding': inspection.resolvedEncoding,
          },
        ),
      );
      if (inspection.warnings.isNotEmpty) {
        _logWarning(
          'inspect_sql_dump_source_warnings',
          'SQL dump inspection produced warnings.',
          category: 'import.sql_dump',
          elapsedNanos: _durationToNanos(stopwatch.elapsed),
          details: buildImportInspectionLogDetails(
            sourcePath: inspection.sourcePath,
            tableCount: inspection.tables.length,
            warnings: inspection.warnings,
            extra: <String, Object?>{
              'skipped_statement_count': inspection.skippedStatements.length,
              'encoding': inspection.resolvedEncoding,
            },
          ),
        );
      }
      _safeNotify();
    } catch (error) {
      _setSqlDumpImportError(
        error.toString(),
        phase: SqlDumpImportJobPhase.failed,
      );
      _logError(
        'inspect_sql_dump_source',
        'SQL dump inspection failed.',
        category: 'import.sql_dump',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
        details: <String, Object?>{'source_path': normalized},
      );
    }
  }

  Future<void> updateSqlDumpImportEncoding(String value) async {
    final session = sqlDumpImportSession;
    if (session == null) {
      return;
    }
    sqlDumpImportSession = session.copyWith(encoding: value, error: null);
    _safeNotify();
    if (session.sourcePath.trim().isNotEmpty) {
      await loadSqlDumpImportSource(session.sourcePath);
    }
  }

  void setSqlDumpImportStep(SqlDumpImportWizardStep step) {
    final session = sqlDumpImportSession;
    if (session == null) {
      return;
    }
    sqlDumpImportSession = session.copyWith(step: step, error: null);
    _safeNotify();
  }

  void updateSqlDumpImportTargetPath(String value) {
    final session = sqlDumpImportSession;
    if (session == null) {
      return;
    }
    sqlDumpImportSession = session.copyWith(targetPath: value, error: null);
    _safeNotify();
  }

  void updateSqlDumpImportIntoExistingTarget(bool value) {
    final session = sqlDumpImportSession;
    if (session == null) {
      return;
    }
    sqlDumpImportSession = session.copyWith(
      importIntoExistingTarget: value,
      replaceExistingTarget: value ? false : session.replaceExistingTarget,
      error: null,
    );
    _safeNotify();
  }

  void updateSqlDumpImportReplaceExistingTarget(bool value) {
    final session = sqlDumpImportSession;
    if (session == null || session.importIntoExistingTarget) {
      return;
    }
    sqlDumpImportSession = session.copyWith(
      replaceExistingTarget: value,
      error: null,
    );
    _safeNotify();
  }

  void toggleSqlDumpImportTableSelection(String sourceName, bool selected) {
    final session = sqlDumpImportSession;
    if (session == null) {
      return;
    }

    final updatedTables = <SqlDumpImportTableDraft>[
      for (final table in session.tables)
        if (table.sourceName == sourceName)
          table.copyWith(selected: selected)
        else
          table,
    ];
    String? focused;
    if (updatedTables.any(
      (table) => table.sourceName == session.focusedTable && table.selected,
    )) {
      focused = session.focusedTable;
    } else {
      for (final table in updatedTables) {
        if (table.selected) {
          focused = table.sourceName;
          break;
        }
      }
    }
    sqlDumpImportSession = session.copyWith(
      tables: updatedTables,
      focusedTable: focused,
      error: null,
    );
    _safeNotify();
  }

  void focusSqlDumpImportTable(String sourceName) {
    final session = sqlDumpImportSession;
    if (session == null) {
      return;
    }
    sqlDumpImportSession = session.copyWith(focusedTable: sourceName);
    _safeNotify();
  }

  void renameSqlDumpImportTable(String sourceName, String targetName) {
    _mutateSqlDumpImportTable(
      sourceName,
      (table) => table.copyWith(targetName: targetName),
    );
  }

  void renameSqlDumpImportColumn(
    String sourceTableName,
    int sourceColumnIndex,
    String targetName,
  ) {
    _mutateSqlDumpImportTable(
      sourceTableName,
      (table) => table.copyWith(
        columns: <SqlDumpImportColumnDraft>[
          for (final column in table.columns)
            if (column.sourceIndex == sourceColumnIndex)
              column.copyWith(targetName: targetName)
            else
              column,
        ],
      ),
    );
  }

  void overrideSqlDumpImportColumnType(
    String sourceTableName,
    int sourceColumnIndex,
    String targetType,
  ) {
    _mutateSqlDumpImportTable(
      sourceTableName,
      (table) => table.copyWith(
        columns: <SqlDumpImportColumnDraft>[
          for (final column in table.columns)
            if (column.sourceIndex == sourceColumnIndex)
              column.copyWith(targetType: targetType)
            else
              column,
        ],
      ),
    );
  }

  Future<void> runSqlDumpImport() async {
    final stopwatch = Stopwatch()..start();
    final session = sqlDumpImportSession;
    if (session == null) {
      return;
    }
    if (session.selectedTables.isEmpty) {
      _setSqlDumpImportError('Select at least one parsed table to import.');
      return;
    }
    if (!session.canAdvanceFromTransforms) {
      _setSqlDumpImportError(
        'Resolve duplicate or empty target names before starting the import.',
      );
      return;
    }
    if (session.targetPath.trim().isEmpty) {
      _setSqlDumpImportError('Choose a target DecentDB file first.');
      return;
    }

    await _sqlDumpImportSubscription?.cancel();
    final jobId = createSqlDumpImportJobId();
    final request = SqlDumpImportRequest(
      jobId: jobId,
      sourcePath: session.sourcePath,
      targetPath: session.targetPath.trim(),
      importIntoExistingTarget: session.importIntoExistingTarget,
      replaceExistingTarget: session.replaceExistingTarget,
      encoding: session.encoding,
      tables: session.tables,
    );

    sqlDumpImportSession = session.copyWith(
      step: SqlDumpImportWizardStep.execute,
      phase: SqlDumpImportJobPhase.running,
      error: null,
      summary: null,
      jobId: jobId,
      progress: SqlDumpImportProgress(
        jobId: jobId,
        currentTable: request.selectedTables.first.targetName,
        completedTables: 0,
        totalTables: request.selectedTables.length,
        currentTableRowsCopied: 0,
        currentTableRowCount: request.selectedTables.first.rowCount,
        totalRowsCopied: 0,
        message: 'Preparing SQL dump import...',
      ),
    );
    _safeNotify();
    _logInfo(
      'run_sql_dump_import',
      'Starting SQL dump import.',
      category: 'import.sql_dump',
      details: buildSqlDumpImportRequestLogDetails(request),
    );

    _sqlDumpImportSubscription = _gateway
        .importSqlDump(request: request)
        .listen((update) {
          final current = sqlDumpImportSession;
          if (current == null || current.jobId != update.jobId) {
            return;
          }

          switch (update.kind) {
            case SqlDumpImportUpdateKind.progress:
              sqlDumpImportSession = current.copyWith(
                phase: current.phase == SqlDumpImportJobPhase.cancelling
                    ? SqlDumpImportJobPhase.cancelling
                    : SqlDumpImportJobPhase.running,
                progress: update.progress,
                error: null,
              );
              break;
            case SqlDumpImportUpdateKind.completed:
              final summary = update.summary;
              sqlDumpImportSession = current.copyWith(
                step: SqlDumpImportWizardStep.summary,
                phase: SqlDumpImportJobPhase.completed,
                summary: summary,
                error: null,
              );
              workspaceMessage = summary?.statusMessage;
              workspaceError = null;
              _logInfo(
                'run_sql_dump_import',
                'SQL dump import completed.',
                category: 'import.sql_dump',
                databasePath: summary?.targetPath,
                rowCount: summary?.totalRowsCopied,
                elapsedNanos: _durationToNanos(stopwatch.elapsed),
                details: summary == null
                    ? <String, Object?>{'job_id': update.jobId}
                    : buildSqlDumpImportSummaryLogDetails(summary),
              );
              if (summary != null && summary.warnings.isNotEmpty) {
                _logWarning(
                  'run_sql_dump_import_warnings',
                  'SQL dump import completed with warnings.',
                  category: 'import.sql_dump',
                  databasePath: summary.targetPath,
                  rowCount: summary.totalRowsCopied,
                  elapsedNanos: _durationToNanos(stopwatch.elapsed),
                  details: buildSqlDumpImportSummaryLogDetails(summary),
                );
              }
              break;
            case SqlDumpImportUpdateKind.cancelled:
              final summary = update.summary;
              sqlDumpImportSession = current.copyWith(
                step: SqlDumpImportWizardStep.summary,
                phase: SqlDumpImportJobPhase.cancelled,
                summary: summary,
                error: null,
              );
              workspaceMessage = summary?.statusMessage;
              workspaceError = null;
              _logWarning(
                'run_sql_dump_import',
                'SQL dump import was cancelled.',
                category: 'import.sql_dump',
                databasePath: summary?.targetPath,
                rowCount: summary?.totalRowsCopied,
                elapsedNanos: _durationToNanos(stopwatch.elapsed),
                details: summary == null
                    ? <String, Object?>{'job_id': update.jobId}
                    : buildSqlDumpImportSummaryLogDetails(summary),
              );
              break;
            case SqlDumpImportUpdateKind.failed:
              sqlDumpImportSession = current.copyWith(
                step: SqlDumpImportWizardStep.summary,
                phase: SqlDumpImportJobPhase.failed,
                error: update.message ?? 'SQL dump import failed.',
              );
              _logError(
                'run_sql_dump_import',
                'SQL dump import failed.',
                category: 'import.sql_dump',
                elapsedNanos: _durationToNanos(stopwatch.elapsed),
                details: <String, Object?>{
                  'job_id': update.jobId,
                  'source_path': current.sourcePath,
                  'target_path': current.targetPath,
                  'selected_table_count': current.selectedTables.length,
                  'message': update.message,
                },
              );
              break;
          }
          _safeNotify();
        });
  }

  Future<void> cancelSqlDumpImport() async {
    final stopwatch = Stopwatch()..start();
    final session = sqlDumpImportSession;
    if (session == null || session.jobId == null) {
      return;
    }
    sqlDumpImportSession = session.copyWith(
      phase: SqlDumpImportJobPhase.cancelling,
      error: null,
    );
    _safeNotify();
    _logWarning(
      'cancel_sql_dump_import',
      'Cancelling SQL dump import.',
      category: 'import.sql_dump',
      details: <String, Object?>{'job_id': session.jobId},
    );
    try {
      await _gateway.cancelImport(session.jobId!);
    } catch (error) {
      _setSqlDumpImportError(
        error.toString(),
        phase: SqlDumpImportJobPhase.failed,
      );
      _logError(
        'cancel_sql_dump_import',
        'SQL dump import cancellation failed.',
        category: 'import.sql_dump',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
        details: <String, Object?>{'job_id': session.jobId},
      );
    }
  }

  Future<void> openSqlDumpImportedDatabaseFromSummary() async {
    final summary = sqlDumpImportSession?.summary;
    if (summary == null) {
      return;
    }
    await openDatabase(summary.targetPath, createIfMissing: false);
    sqlDumpImportSession = null;
    _safeNotify();
  }

  Future<void> runQueryForSqlDumpImportedTable() async {
    final summary = sqlDumpImportSession?.summary;
    if (summary == null) {
      return;
    }
    await openDatabase(summary.targetPath, createIfMissing: false);
    if (summary.firstImportedTable != null) {
      createTab(
        sql:
            'SELECT *\nFROM ${_quoteIdentifier(summary.firstImportedTable!)}\nLIMIT ${config.defaultPageSize};',
      );
    }
    sqlDumpImportSession = null;
    _safeNotify();
  }

  void beginSqliteImport({String sourcePath = ''}) {
    final trimmedSource = sourcePath.trim();
    sqliteImportSession = SqliteImportSession.initial(sourcePath: trimmedSource)
        .copyWith(
          targetPath: trimmedSource.isEmpty
              ? ''
              : _suggestImportTargetPath(trimmedSource),
        );
    _safeNotify();
    _logInfo(
      'begin_sqlite_import',
      'Opened SQLite import workflow.',
      category: 'import.sqlite',
      details: <String, Object?>{'source_path': trimmedSource},
    );
    if (trimmedSource.isNotEmpty) {
      unawaited(loadSqliteImportSource(trimmedSource));
    }
  }

  void closeSqliteImportSession() {
    if (sqliteImportSession?.phase == SqliteImportJobPhase.running ||
        sqliteImportSession?.phase == SqliteImportJobPhase.cancelling) {
      return;
    }
    sqliteImportSession = null;
    _safeNotify();
  }

  Future<void> loadSqliteImportSource(String rawPath) async {
    final stopwatch = Stopwatch()..start();
    final normalized = rawPath.trim();
    if (normalized.isEmpty) {
      _setSqliteImportError('Choose a SQLite source file first.');
      return;
    }

    final session =
        sqliteImportSession ??
        SqliteImportSession.initial(sourcePath: normalized);
    sqliteImportSession = session.copyWith(
      phase: SqliteImportJobPhase.inspecting,
      sourcePath: normalized,
      targetPath: session.targetPath.trim().isEmpty
          ? _suggestImportTargetPath(normalized)
          : session.targetPath,
      tables: const <SqliteImportTableDraft>[],
      warnings: const <String>[],
      focusedTable: null,
      progress: null,
      summary: null,
      error: null,
      jobId: null,
      loadingPreviewTable: null,
    );
    _safeNotify();

    try {
      final inspection = await _gateway.inspectSqliteSource(
        sourcePath: normalized,
      );
      final focused = inspection.tables.isEmpty
          ? null
          : inspection.tables.first.sourceName;
      sqliteImportSession = sqliteImportSession?.copyWith(
        phase: SqliteImportJobPhase.ready,
        sourcePath: inspection.sourcePath,
        tables: inspection.tables,
        warnings: inspection.warnings,
        focusedTable: focused,
        error: inspection.tables.isEmpty
            ? 'No user tables were found in the selected SQLite file.'
            : null,
      );
      _logInfo(
        'inspect_sqlite_source',
        'Loaded SQLite source inspection.',
        category: 'import.sqlite',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        details: buildImportInspectionLogDetails(
          sourcePath: inspection.sourcePath,
          tableCount: inspection.tables.length,
          warnings: inspection.warnings,
        ),
      );
      if (inspection.warnings.isNotEmpty) {
        _logWarning(
          'inspect_sqlite_source_warnings',
          'SQLite inspection produced warnings.',
          category: 'import.sqlite',
          elapsedNanos: _durationToNanos(stopwatch.elapsed),
          details: buildImportInspectionLogDetails(
            sourcePath: inspection.sourcePath,
            tableCount: inspection.tables.length,
            warnings: inspection.warnings,
          ),
        );
      }
      _safeNotify();
      if (focused != null) {
        await loadSqliteImportPreview(focused);
      }
    } catch (error) {
      _setSqliteImportError(
        error.toString(),
        phase: SqliteImportJobPhase.failed,
      );
      _logError(
        'inspect_sqlite_source',
        'SQLite source inspection failed.',
        category: 'import.sqlite',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
        details: <String, Object?>{'source_path': normalized},
      );
    }
  }

  void setSqliteImportStep(SqliteImportWizardStep step) {
    final session = sqliteImportSession;
    if (session == null) {
      return;
    }
    sqliteImportSession = session.copyWith(step: step, error: null);
    _safeNotify();
  }

  void updateSqliteImportTargetPath(String value) {
    final session = sqliteImportSession;
    if (session == null) {
      return;
    }
    sqliteImportSession = session.copyWith(targetPath: value, error: null);
    _safeNotify();
  }

  void updateSqliteImportIntoExistingTarget(bool value) {
    final session = sqliteImportSession;
    if (session == null) {
      return;
    }
    sqliteImportSession = session.copyWith(
      importIntoExistingTarget: value,
      replaceExistingTarget: value ? false : session.replaceExistingTarget,
      error: null,
    );
    _safeNotify();
  }

  void updateSqliteImportReplaceExistingTarget(bool value) {
    final session = sqliteImportSession;
    if (session == null || session.importIntoExistingTarget) {
      return;
    }
    sqliteImportSession = session.copyWith(
      replaceExistingTarget: value,
      error: null,
    );
    _safeNotify();
  }

  void toggleSqliteImportTableSelection(String sourceName, bool selected) {
    final session = sqliteImportSession;
    if (session == null) {
      return;
    }

    final updatedTables = <SqliteImportTableDraft>[
      for (final table in session.tables)
        if (table.sourceName == sourceName)
          table.copyWith(selected: selected)
        else
          table,
    ];
    String? focused;
    if (updatedTables.any(
      (table) => table.sourceName == session.focusedTable && table.selected,
    )) {
      focused = session.focusedTable;
    } else {
      for (final table in updatedTables) {
        if (table.selected) {
          focused = table.sourceName;
          break;
        }
      }
    }
    sqliteImportSession = session.copyWith(
      tables: updatedTables,
      focusedTable: focused,
      error: null,
    );
    _safeNotify();
    if (selected && focused != null) {
      unawaited(loadSqliteImportPreview(focused));
    }
  }

  Future<void> focusSqliteImportTable(String sourceName) async {
    final session = sqliteImportSession;
    if (session == null) {
      return;
    }
    sqliteImportSession = session.copyWith(focusedTable: sourceName);
    _safeNotify();
    await loadSqliteImportPreview(sourceName);
  }

  Future<void> loadSqliteImportPreview(String sourceName) async {
    final session = sqliteImportSession;
    if (session == null || session.sourcePath.trim().isEmpty) {
      return;
    }
    final table = session.tables.where((item) => item.sourceName == sourceName);
    if (table.isEmpty ||
        table.first.previewLoaded ||
        session.loadingPreviewTable == sourceName) {
      return;
    }

    sqliteImportSession = session.copyWith(
      loadingPreviewTable: sourceName,
      error: null,
    );
    _safeNotify();

    try {
      final preview = await _gateway.loadSqlitePreview(
        sourcePath: session.sourcePath,
        tableName: sourceName,
      );
      _mutateSqliteImportTable(
        sourceName,
        (table) => table.copyWith(
          previewRows: preview.rows,
          previewLoaded: true,
          previewError: null,
        ),
      );
    } catch (error) {
      _mutateSqliteImportTable(
        sourceName,
        (table) => table.copyWith(
          previewLoaded: false,
          previewError: error.toString(),
        ),
      );
    } finally {
      sqliteImportSession = sqliteImportSession?.copyWith(
        loadingPreviewTable: null,
      );
      _safeNotify();
    }
  }

  void renameSqliteImportTable(String sourceName, String targetName) {
    _mutateSqliteImportTable(
      sourceName,
      (table) => table.copyWith(targetName: targetName),
    );
  }

  void renameSqliteImportColumn(
    String sourceTableName,
    String sourceColumnName,
    String targetName,
  ) {
    _mutateSqliteImportTable(
      sourceTableName,
      (table) => table.copyWith(
        columns: <SqliteImportColumnDraft>[
          for (final column in table.columns)
            if (column.sourceName == sourceColumnName)
              column.copyWith(targetName: targetName)
            else
              column,
        ],
      ),
    );
  }

  void overrideSqliteImportColumnType(
    String sourceTableName,
    String sourceColumnName,
    String targetType,
  ) {
    _mutateSqliteImportTable(
      sourceTableName,
      (table) => table.copyWith(
        columns: <SqliteImportColumnDraft>[
          for (final column in table.columns)
            if (column.sourceName == sourceColumnName)
              column.copyWith(targetType: targetType)
            else
              column,
        ],
      ),
    );
  }

  Future<void> runSqliteImport() async {
    final stopwatch = Stopwatch()..start();
    final session = sqliteImportSession;
    if (session == null) {
      return;
    }
    if (session.selectedTables.isEmpty) {
      _setSqliteImportError('Select at least one SQLite table to import.');
      return;
    }
    if (!session.canAdvanceFromTransforms) {
      _setSqliteImportError(
        'Resolve duplicate or empty target names before starting the import.',
      );
      return;
    }
    if (session.targetPath.trim().isEmpty) {
      _setSqliteImportError('Choose a target DecentDB file first.');
      return;
    }

    await _sqliteImportSubscription?.cancel();
    final jobId = createSqliteImportJobId();
    final request = SqliteImportRequest(
      jobId: jobId,
      sourcePath: session.sourcePath,
      targetPath: session.targetPath.trim(),
      importIntoExistingTarget: session.importIntoExistingTarget,
      replaceExistingTarget: session.replaceExistingTarget,
      tables: session.tables,
    );

    sqliteImportSession = session.copyWith(
      step: SqliteImportWizardStep.execute,
      phase: SqliteImportJobPhase.running,
      error: null,
      summary: null,
      jobId: jobId,
      progress: SqliteImportProgress(
        jobId: jobId,
        currentTable: request.selectedTables.first.targetName,
        completedTables: 0,
        totalTables: request.selectedTables.length,
        currentTableRowsCopied: 0,
        currentTableRowCount: request.selectedTables.first.rowCount,
        totalRowsCopied: 0,
        message: 'Preparing SQLite import...',
      ),
    );
    _safeNotify();
    _logInfo(
      'run_sqlite_import',
      'Starting SQLite import.',
      category: 'import.sqlite',
      details: buildSqliteImportRequestLogDetails(request),
    );

    _sqliteImportSubscription = _gateway.importSqlite(request: request).listen((
      update,
    ) {
      final current = sqliteImportSession;
      if (current == null || current.jobId != update.jobId) {
        return;
      }

      switch (update.kind) {
        case SqliteImportUpdateKind.progress:
          sqliteImportSession = current.copyWith(
            phase: current.phase == SqliteImportJobPhase.cancelling
                ? SqliteImportJobPhase.cancelling
                : SqliteImportJobPhase.running,
            progress: update.progress,
            error: null,
          );
          break;
        case SqliteImportUpdateKind.completed:
          final summary = update.summary;
          sqliteImportSession = current.copyWith(
            step: SqliteImportWizardStep.summary,
            phase: SqliteImportJobPhase.completed,
            summary: summary,
            error: null,
          );
          workspaceMessage = summary?.statusMessage;
          workspaceError = null;
          _logInfo(
            'run_sqlite_import',
            'SQLite import completed.',
            category: 'import.sqlite',
            databasePath: summary?.targetPath,
            rowCount: summary?.totalRowsCopied,
            elapsedNanos: _durationToNanos(stopwatch.elapsed),
            details: summary == null
                ? <String, Object?>{'job_id': update.jobId}
                : buildSqliteImportSummaryLogDetails(summary),
          );
          if (summary != null && summary.warnings.isNotEmpty) {
            _logWarning(
              'run_sqlite_import_warnings',
              'SQLite import completed with warnings.',
              category: 'import.sqlite',
              databasePath: summary.targetPath,
              rowCount: summary.totalRowsCopied,
              elapsedNanos: _durationToNanos(stopwatch.elapsed),
              details: buildSqliteImportSummaryLogDetails(summary),
            );
          }
          break;
        case SqliteImportUpdateKind.cancelled:
          final summary = update.summary;
          sqliteImportSession = current.copyWith(
            step: SqliteImportWizardStep.summary,
            phase: SqliteImportJobPhase.cancelled,
            summary: summary,
            error: null,
          );
          workspaceMessage = summary?.statusMessage;
          workspaceError = null;
          _logWarning(
            'run_sqlite_import',
            'SQLite import was cancelled.',
            category: 'import.sqlite',
            databasePath: summary?.targetPath,
            rowCount: summary?.totalRowsCopied,
            elapsedNanos: _durationToNanos(stopwatch.elapsed),
            details: summary == null
                ? <String, Object?>{'job_id': update.jobId}
                : buildSqliteImportSummaryLogDetails(summary),
          );
          break;
        case SqliteImportUpdateKind.failed:
          sqliteImportSession = current.copyWith(
            step: SqliteImportWizardStep.summary,
            phase: SqliteImportJobPhase.failed,
            error: update.message ?? 'SQLite import failed.',
          );
          _logError(
            'run_sqlite_import',
            'SQLite import failed.',
            category: 'import.sqlite',
            elapsedNanos: _durationToNanos(stopwatch.elapsed),
            details: <String, Object?>{
              'job_id': update.jobId,
              'source_path': current.sourcePath,
              'target_path': current.targetPath,
              'selected_table_count': current.selectedTables.length,
              'message': update.message,
            },
          );
          break;
      }
      _safeNotify();
    });
  }

  Future<void> cancelSqliteImport() async {
    final stopwatch = Stopwatch()..start();
    final session = sqliteImportSession;
    if (session == null || session.jobId == null) {
      return;
    }
    sqliteImportSession = session.copyWith(
      phase: SqliteImportJobPhase.cancelling,
      error: null,
    );
    _safeNotify();
    _logWarning(
      'cancel_sqlite_import',
      'Cancelling SQLite import.',
      category: 'import.sqlite',
      details: <String, Object?>{'job_id': session.jobId},
    );
    try {
      await _gateway.cancelImport(session.jobId!);
    } catch (error) {
      _setSqliteImportError(
        error.toString(),
        phase: SqliteImportJobPhase.failed,
      );
      _logError(
        'cancel_sqlite_import',
        'SQLite import cancellation failed.',
        category: 'import.sqlite',
        elapsedNanos: _durationToNanos(stopwatch.elapsed),
        error: error,
        details: <String, Object?>{'job_id': session.jobId},
      );
    }
  }

  Future<void> openImportedDatabaseFromSummary() async {
    final summary = sqliteImportSession?.summary;
    if (summary == null) {
      return;
    }
    await openDatabase(summary.targetPath, createIfMissing: false);
    sqliteImportSession = null;
    _safeNotify();
  }

  Future<void> runQueryForImportedTable() async {
    final summary = sqliteImportSession?.summary;
    if (summary == null) {
      return;
    }
    await openDatabase(summary.targetPath, createIfMissing: false);
    if (summary.firstImportedTable != null) {
      createTab(
        sql:
            'SELECT *\nFROM ${_quoteIdentifier(summary.firstImportedTable!)}\nLIMIT ${config.defaultPageSize};',
      );
    }
    sqliteImportSession = null;
    _safeNotify();
  }

  String createSnippetId() =>
      'snippet-${DateTime.now().microsecondsSinceEpoch.toString()}';

  String createExcelImportJobId() =>
      'excel-import-${DateTime.now().microsecondsSinceEpoch}';

  String createSqlDumpImportJobId() =>
      'sql-dump-import-${DateTime.now().microsecondsSinceEpoch}';

  String createSqliteImportJobId() =>
      'sqlite-import-${DateTime.now().microsecondsSinceEpoch}';

  String suggestExportPath([String? tabId]) {
    final tab = tabId == null ? activeTab : tabById(tabId) ?? activeTab;
    return _suggestExportPathForTitle(tab.title);
  }

  String? errorDetailsForTab(String tabId) {
    final tab = tabById(tabId);
    if (tab?.error == null) {
      return null;
    }
    return tab!.error!.toClipboardText(sql: tab.lastSql ?? tab.sql);
  }

  List<SchemaObjectSummary> filterSchemaObjects(String rawFilter) {
    final filter = rawFilter.trim().toLowerCase();
    if (filter.isEmpty) {
      return schema.objects;
    }
    return schema.objects.where((object) {
      if (object.name.toLowerCase().contains(filter)) {
        return true;
      }
      if (object.columns.any(
        (column) =>
            column.name.toLowerCase().contains(filter) ||
            column.type.toLowerCase().contains(filter) ||
            column.constraintSummaries.any(
              (summary) => summary.toLowerCase().contains(filter),
            ),
      )) {
        return true;
      }
      return schema
          .indexesForObject(object.name)
          .any(
            (index) =>
                index.name.toLowerCase().contains(filter) ||
                index.kind.toLowerCase().contains(filter) ||
                index.columns.any(
                  (column) => column.toLowerCase().contains(filter),
                ),
          );
    }).toList();
  }

  List<String> schemaNotesForObject(SchemaObjectSummary object) {
    return <String>[
      if (object.kind == SchemaObjectKind.table && object.ddl == null)
        'Table DDL is not exposed by the current DecentDB Dart schema API.',
      if (object.kind == SchemaObjectKind.view && object.ddl == null)
        'View definition text is not exposed for this object.',
      'Trigger metadata is not exposed by the current DecentDB Dart schema API.',
      'Generated-column metadata is not exposed by the current DecentDB Dart schema API.',
      'Temporary-object metadata is not exposed by the current DecentDB Dart schema API.',
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    _workspaceSaveDebounce?.cancel();
    unawaited(_excelImportSubscription?.cancel() ?? Future<void>.value());
    unawaited(_sqlDumpImportSubscription?.cancel() ?? Future<void>.value());
    unawaited(_sqliteImportSubscription?.cancel() ?? Future<void>.value());
    if (hasOpenDatabase) {
      unawaited(_persistWorkspaceStateNow());
    }
    unawaited(_gateway.dispose());
    super.dispose();
  }

  QueryTabState _applyFirstPage(
    QueryTabState tab,
    QueryResultPage page, {
    required String statusMessage,
  }) {
    return tab.copyWith(
      resultColumns: page.columns,
      resultRows: page.rows,
      cursorId: page.cursorId,
      rowsAffected: page.rowsAffected,
      elapsed: page.elapsed,
      hasMoreRows: !page.done,
      phase: QueryPhase.completed,
      statusMessage: statusMessage,
    );
  }

  Future<void> _loadExecutionPlanForTab(
    String tabId, {
    required int generation,
    required String sql,
    required List<Object?> params,
  }) async {
    try {
      var planPage = await _gateway.runQuery(
        sql: 'EXPLAIN $sql',
        params: params,
        pageSize: config.defaultPageSize,
      );
      if (!_isCurrentGeneration(tabId, generation)) {
        if (planPage.cursorId != null) {
          unawaited(_gateway.cancelQuery(planPage.cursorId!));
        }
        return;
      }

      final columns = <String>[...planPage.columns];
      final rows = <Map<String, Object?>>[...planPage.rows];
      while (planPage.cursorId != null) {
        planPage = await _gateway.fetchNextPage(
          cursorId: planPage.cursorId!,
          pageSize: config.defaultPageSize,
        );
        if (!_isCurrentGeneration(tabId, generation)) {
          if (planPage.cursorId != null) {
            unawaited(_gateway.cancelQuery(planPage.cursorId!));
          }
          return;
        }
        if (columns.isEmpty && planPage.columns.isNotEmpty) {
          columns.addAll(planPage.columns);
        }
        rows.addAll(planPage.rows);
      }

      if (!_isCurrentGeneration(tabId, generation)) {
        return;
      }
      _mutateTab(
        tabId,
        (current) => current.copyWith(
          executionPlan: QueryExecutionPlanState(
            columns: columns,
            rows: rows,
            isLoading: false,
          ),
        ),
        notify: false,
      );
      _safeNotify();
    } catch (error) {
      if (!_isCurrentGeneration(tabId, generation)) {
        return;
      }
      final failure = QueryErrorDetails.fromError(
        error,
        stage: QueryErrorStage.opening,
      );
      _mutateTab(
        tabId,
        (current) => current.copyWith(
          executionPlan: current.executionPlan.copyWith(
            isLoading: false,
            errorMessage: failure.message,
          ),
        ),
        notify: false,
      );
      _safeNotify();
      _logWarning(
        'load_execution_plan',
        'Execution plan could not be loaded.',
        category: 'query',
        databasePath: databasePath,
        sql: sql,
        error: error,
        details: <String, Object?>{'tab_id': tabId},
      );
    }
  }

  List<QueryMessageEntry> _appendMessage(
    List<QueryMessageEntry> history,
    QueryMessageLevel level,
    String message, {
    DateTime? timestamp,
  }) {
    final updated = <QueryMessageEntry>[
      ...history,
      QueryMessageEntry(
        level: level,
        message: message,
        timestamp: timestamp ?? DateTime.now(),
      ),
    ];
    if (updated.length <= _maxMessageHistoryEntries) {
      return updated;
    }
    return updated.sublist(updated.length - _maxMessageHistoryEntries);
  }

  List<QueryHistoryEntry> _appendQueryHistory(
    List<QueryHistoryEntry> history,
    QueryHistoryEntry entry,
  ) {
    final updated = <QueryHistoryEntry>[...history, entry];
    if (updated.length <= _maxQueryHistoryEntries) {
      return updated;
    }
    return updated.sublist(updated.length - _maxQueryHistoryEntries);
  }

  QueryHistoryEntry _buildQueryHistoryEntry(
    QueryTabState tab, {
    required QueryHistoryOutcome outcome,
    String? errorMessage,
    int? rowsLoaded,
    int? rowsAffected,
    Duration? elapsed,
  }) {
    return QueryHistoryEntry(
      sql: tab.lastSql ?? tab.sql,
      parameterJson: tab.lastParameterJson ?? tab.parameterJson,
      ranAt: tab.lastRunStartedAt ?? DateTime.now(),
      outcome: outcome,
      elapsed: elapsed ?? Duration.zero,
      rowsLoaded: rowsLoaded,
      rowsAffected: rowsAffected,
      errorMessage: errorMessage,
    );
  }

  bool _isExplainSql(String sql) {
    return RegExp(r'^\s*EXPLAIN\b', caseSensitive: false).hasMatch(sql);
  }

  bool _shouldLoadExecutionPlan({
    required String sql,
    required QueryResultPage page,
  }) {
    return !_isExplainSql(sql) && page.rowsAffected == null;
  }

  Future<void> _cancelAllOpenCursors() async {
    for (final tab in tabs) {
      if (tab.cursorId == null) {
        continue;
      }
      try {
        await _gateway.cancelQuery(tab.cursorId!);
      } catch (_) {
        // Ignore stale cancellation failures during workspace switches.
      }
    }
  }

  List<Object?>? _parseParameters(String tabId, String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) {
      return const <Object?>[];
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) {
        _setTabError(
          tabId,
          const QueryErrorDetails(
            stage: QueryErrorStage.validation,
            message: 'Parameters must be a JSON array such as [1, "alice"].',
          ),
        );
        return null;
      }
      return decoded.cast<Object?>();
    } catch (error) {
      _setTabError(
        tabId,
        QueryErrorDetails(
          stage: QueryErrorStage.validation,
          message: 'Could not parse parameter JSON: $error',
        ),
      );
      return null;
    }
  }

  bool _isCurrentGeneration(String tabId, int generation) {
    final tab = tabById(tabId);
    return tab != null && tab.executionGeneration == generation;
  }

  void _setTabError(String tabId, QueryErrorDetails error) {
    _mutateTab(
      tabId,
      (current) => current.copyWith(
        phase: QueryPhase.failed,
        error: error,
        statusMessage: null,
        messageHistory: _appendMessage(
          current.messageHistory,
          QueryMessageLevel.error,
          '${error.stageLabel}: ${error.message}',
        ),
      ),
      notify: false,
    );
    _safeNotify();
    _logError(
      'tab_error',
      error.message,
      category: 'query',
      databasePath: databasePath,
      details: <String, Object?>{
        'tab_id': tabId,
        'stage': error.stage.name,
        if (error.code != null) 'code': error.code,
        if (error.location != null) 'location': error.location!.shortLabel,
      },
    );
  }

  void _setWorkspaceError(String message) {
    workspaceError = message;
    workspaceMessage = null;
    _safeNotify();
    _logError('workspace_error', message, databasePath: databasePath);
  }

  String? _validateAppConfig(AppConfig next) {
    if (next.appearance.activeTheme.trim().isEmpty) {
      return 'Active theme cannot be empty.';
    }
    if (next.defaultPageSize <= 0) {
      return 'Page size must be a positive integer.';
    }
    if (next.csvDelimiter.isEmpty) {
      return 'CSV delimiter cannot be empty.';
    }
    if (next.editorSettings.autocompleteMaxSuggestions <= 0) {
      return 'Autocomplete suggestions must be a positive integer.';
    }
    if (next.editorSettings.indentSpaces <= 0) {
      return 'Indent spaces must be a positive integer.';
    }

    final snippetIds = <String>{};
    final snippetTriggers = <String>{};
    for (final snippet in next.snippets) {
      if (snippet.id.trim().isEmpty) {
        return 'Snippet identifiers cannot be empty.';
      }
      if (snippet.name.trim().isEmpty) {
        return 'Snippet names cannot be empty.';
      }
      if (snippet.trigger.trim().isEmpty) {
        return 'Snippet triggers cannot be empty.';
      }
      if (snippet.body.trim().isEmpty) {
        return 'Snippet bodies cannot be empty.';
      }
      if (!snippetIds.add(snippet.id.trim())) {
        return 'Snippet identifiers must be unique.';
      }
      if (!snippetTriggers.add(snippet.trigger.trim().toLowerCase())) {
        return 'Snippet triggers must be unique.';
      }
    }

    return null;
  }

  Future<void> _persistConfig([String? statusMessage]) async {
    try {
      await _configStore.save(config);
      if (statusMessage != null) {
        workspaceMessage = statusMessage;
        workspaceError = null;
      }
      _logInfo(
        'persist_config',
        'Persisted application configuration.',
        category: 'config',
        details: <String, Object?>{
          'theme_id': config.appearance.activeTheme,
          'verbosity': config.logging.verbosity.name,
        },
      );
    } catch (error) {
      workspaceError = error.toString();
      workspaceMessage = null;
      _logError(
        'persist_config',
        'Persisting application configuration failed.',
        category: 'config',
        error: error,
      );
    } finally {
      _safeNotify();
    }
  }

  void _setSqlDumpImportError(String message, {SqlDumpImportJobPhase? phase}) {
    final session = sqlDumpImportSession;
    if (session == null) {
      workspaceError = message;
      workspaceMessage = null;
      _safeNotify();
      _logError('sql_dump_import_error', message, category: 'import.sql_dump');
      return;
    }
    sqlDumpImportSession = session.copyWith(
      error: message,
      phase: phase ?? session.phase,
    );
    _safeNotify();
    _logError(
      'sql_dump_import_error',
      message,
      category: 'import.sql_dump',
      details: <String, Object?>{
        'phase': (phase ?? session.phase).name,
        'source_path': session.sourcePath,
      },
    );
  }

  void _setExcelImportError(String message, {ExcelImportJobPhase? phase}) {
    final session = excelImportSession;
    if (session == null) {
      workspaceError = message;
      workspaceMessage = null;
      _safeNotify();
      _logError('excel_import_error', message, category: 'import.excel');
      return;
    }
    excelImportSession = session.copyWith(
      error: message,
      phase: phase ?? session.phase,
    );
    _safeNotify();
    _logError(
      'excel_import_error',
      message,
      category: 'import.excel',
      details: <String, Object?>{
        'phase': (phase ?? session.phase).name,
        'source_path': session.sourcePath,
      },
    );
  }

  void _setSqliteImportError(String message, {SqliteImportJobPhase? phase}) {
    final session = sqliteImportSession;
    if (session == null) {
      workspaceError = message;
      workspaceMessage = null;
      _safeNotify();
      _logError('sqlite_import_error', message, category: 'import.sqlite');
      return;
    }
    sqliteImportSession = session.copyWith(
      error: message,
      phase: phase ?? session.phase,
    );
    _safeNotify();
    _logError(
      'sqlite_import_error',
      message,
      category: 'import.sqlite',
      details: <String, Object?>{
        'phase': (phase ?? session.phase).name,
        'source_path': session.sourcePath,
      },
    );
  }

  void _mutateSqlDumpImportTable(
    String sourceName,
    SqlDumpImportTableDraft Function(SqlDumpImportTableDraft table) transform,
  ) {
    final session = sqlDumpImportSession;
    if (session == null) {
      return;
    }
    final updatedTables = <SqlDumpImportTableDraft>[
      for (final table in session.tables)
        if (table.sourceName == sourceName) transform(table) else table,
    ];
    sqlDumpImportSession = session.copyWith(tables: updatedTables, error: null);
    _safeNotify();
  }

  void _mutateExcelImportSheet(
    String sourceName,
    ExcelImportSheetDraft Function(ExcelImportSheetDraft sheet) transform,
  ) {
    final session = excelImportSession;
    if (session == null) {
      return;
    }
    final updatedSheets = <ExcelImportSheetDraft>[
      for (final sheet in session.sheets)
        if (sheet.sourceName == sourceName) transform(sheet) else sheet,
    ];
    excelImportSession = session.copyWith(sheets: updatedSheets, error: null);
    _safeNotify();
  }

  void _mutateSqliteImportTable(
    String sourceName,
    SqliteImportTableDraft Function(SqliteImportTableDraft table) transform,
  ) {
    final session = sqliteImportSession;
    if (session == null) {
      return;
    }
    final updatedTables = <SqliteImportTableDraft>[
      for (final table in session.tables)
        if (table.sourceName == sourceName) transform(table) else table,
    ];
    sqliteImportSession = session.copyWith(tables: updatedTables, error: null);
    _safeNotify();
  }

  void _mutateActiveTab(
    QueryTabState Function(QueryTabState current) transform, {
    bool persist = false,
  }) {
    _mutateTab(activeTabId, transform, persist: persist);
  }

  void _mutateTab(
    String tabId,
    QueryTabState Function(QueryTabState current) transform, {
    bool persist = false,
    bool notify = true,
  }) {
    final index = tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) {
      return;
    }
    final updated = <QueryTabState>[...tabs];
    updated[index] = transform(updated[index]);
    tabs = updated;
    if (persist) {
      _scheduleWorkspaceStateSave();
    }
    if (notify) {
      _safeNotify();
    }
  }

  void _resetTabs({required bool notify, bool resetCounters = false}) {
    if (resetCounters) {
      _nextTabIdCounter = 1;
      _nextTabTitleCounter = 1;
    }
    final title = _newTabTitle();
    tabs = <QueryTabState>[
      QueryTabState.initial(
        id: _newTabId(),
        title: title,
        exportPath: _suggestExportPathForTitle(title),
      ),
    ];
    _activeTabId = tabs.first.id;
    if (notify) {
      _safeNotify();
    }
  }

  void _restoreTabs(
    PersistedWorkspaceState? persistedState, {
    required bool notify,
  }) {
    if (persistedState == null || persistedState.tabs.isEmpty) {
      _resetTabs(notify: notify, resetCounters: true);
      return;
    }

    final restoredTabs = <QueryTabState>[
      for (final draft in persistedState.tabs)
        QueryTabState.initial(
          id: draft.id,
          title: draft.title,
          sql: draft.sql,
          parameterJson: draft.parameterJson,
          exportPath: draft.exportPath.isEmpty
              ? _suggestExportPathForTitle(draft.title)
              : draft.exportPath,
        ).copyWith(
          messageHistory: draft.messageHistory,
          queryHistory: draft.queryHistory,
        ),
    ];
    tabs = restoredTabs;
    _activeTabId =
        restoredTabs.any((tab) => tab.id == persistedState.activeTabId)
        ? persistedState.activeTabId
        : restoredTabs.first.id;
    _recomputeTabCounters();
    if (notify) {
      _safeNotify();
    }
  }

  void _recomputeTabCounters() {
    var maxId = 0;
    var maxTitle = 0;
    final idPattern = RegExp(r'^query-tab-(\d+)$');
    final titlePattern = RegExp(r'^Query (\d+)$');
    for (final tab in tabs) {
      final idMatch = idPattern.firstMatch(tab.id);
      if (idMatch != null) {
        maxId = maxId > int.parse(idMatch.group(1)!)
            ? maxId
            : int.parse(idMatch.group(1)!);
      }
      final titleMatch = titlePattern.firstMatch(tab.title);
      if (titleMatch != null) {
        maxTitle = maxTitle > int.parse(titleMatch.group(1)!)
            ? maxTitle
            : int.parse(titleMatch.group(1)!);
      }
    }
    _nextTabIdCounter = maxId + 1;
    _nextTabTitleCounter = maxTitle + 1;
  }

  String _newTabId() => 'query-tab-${_nextTabIdCounter++}';

  String _newTabTitle() => 'Query ${_nextTabTitleCounter++}';

  Future<void> _restoreStartupQueryState() async {
    final replay = _latestRestorableQuery();
    if (replay != null) {
      _activeTabId = replay.tabId;
      loadHistoryEntryIntoTab(replay.tabId, replay.entry);
      await runTab(replay.tabId);
      return;
    }

    final firstTable = schema.tables.isEmpty ? null : schema.tables.first.name;
    if (firstTable == null) {
      return;
    }
    final fallbackSql =
        'SELECT *\n'
        'FROM ${_quoteIdentifier(firstTable)}\n'
        'LIMIT ${config.defaultPageSize};';
    _mutateActiveTab(
      (tab) => tab.copyWith(sql: fallbackSql, parameterJson: ''),
      persist: true,
    );
    await runActiveTab();
  }

  _RestoredQueryReplay? _latestRestorableQuery() {
    final latest = _latestCompletedQuery();
    if (latest == null || !_canRestoreStartupQuery(latest.entry)) {
      return null;
    }
    return latest;
  }

  _RestoredQueryReplay? _latestCompletedQuery() {
    _RestoredQueryReplay? latest;
    for (final tab in tabs) {
      for (final entry in tab.queryHistory) {
        if (entry.outcome != QueryHistoryOutcome.completed) {
          continue;
        }
        final candidate = _RestoredQueryReplay(tabId: tab.id, entry: entry);
        if (latest == null ||
            candidate.entry.ranAt.isAfter(latest.entry.ranAt)) {
          latest = candidate;
        }
      }
    }
    return latest;
  }

  bool _canRestoreStartupQuery(QueryHistoryEntry entry) {
    return entry.rowsAffected == null && _isStartupReplaySafeSql(entry.sql);
  }

  bool _isStartupReplaySafeSql(String sql) {
    final keyword = _leadingSqlKeyword(sql);
    return switch (keyword) {
      'SELECT' || 'EXPLAIN' || 'PRAGMA' || 'VALUES' || 'WITH' => true,
      _ => false,
    };
  }

  String? _leadingSqlKeyword(String sql) {
    final match = RegExp(
      r'^(?:\s|--[^\r\n]*(?:\r?\n|$)|/\*[\s\S]*?\*/)*([A-Za-z]+)',
      caseSensitive: false,
    ).firstMatch(sql);
    return match?.group(1)?.toUpperCase();
  }

  void _scheduleWorkspaceStateSave() {
    final currentDatabasePath = databasePath;
    if (currentDatabasePath == null) {
      return;
    }
    _workspaceSaveDebounce?.cancel();
    _workspaceSaveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_persistWorkspaceStateNow(databasePath: currentDatabasePath));
    });
  }

  Future<void> _persistWorkspaceStateNow({String? databasePath}) async {
    final targetPath = databasePath ?? this.databasePath;
    if (targetPath == null) {
      return;
    }
    try {
      await _workspaceStateStore.save(targetPath, _serializeWorkspaceState());
    } catch (error) {
      workspaceError = 'Could not save workspace state: $error';
      workspaceMessage = null;
      _safeNotify();
    }
  }

  PersistedWorkspaceState _serializeWorkspaceState() {
    return PersistedWorkspaceState(
      schemaVersion: PersistedWorkspaceState.currentSchemaVersion,
      activeTabId: _activeTabId,
      tabs: <WorkspaceTabDraft>[
        for (final tab in tabs)
          WorkspaceTabDraft(
            id: tab.id,
            title: tab.title,
            sql: tab.sql,
            parameterJson: tab.parameterJson,
            exportPath: tab.exportPath.trim().isEmpty
                ? suggestExportPath(tab.id)
                : tab.exportPath,
            messageHistory: tab.messageHistory,
            queryHistory: tab.queryHistory,
          ),
      ],
    );
  }

  String _suggestExportPathForTitle(String title) {
    final safeTitle = title.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    if (databasePath == null) {
      return p.join(
        Directory.current.path,
        'decent-bench-${safeTitle.isEmpty ? 'query' : safeTitle}.csv',
      );
    }
    final directory = p.dirname(databasePath!);
    final basename = p.basenameWithoutExtension(databasePath!);
    final suffix = safeTitle.isEmpty ? 'query' : safeTitle;
    return p.join(directory, '$basename-$suffix.csv');
  }

  String _suggestImportTargetPath(String sourcePath) {
    final directory = p.dirname(sourcePath);
    final basename = p.basenameWithoutExtension(sourcePath);
    return p.join(directory, '$basename.ddb');
  }

  String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}

class _RestoredQueryReplay {
  const _RestoredQueryReplay({required this.tabId, required this.entry});

  final String tabId;
  final QueryHistoryEntry entry;
}
