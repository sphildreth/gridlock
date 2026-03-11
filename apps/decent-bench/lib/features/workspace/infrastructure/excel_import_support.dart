import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:decentdb/decentdb.dart';
import 'package:excel/excel.dart' as xls;
import 'package:path/path.dart' as p;

import '../domain/excel_import_models.dart';
import '../domain/workspace_models.dart';
import 'excel_source_preparer.dart';

const int _excelPreviewRowLimit = 8;
const int _excelProgressBatchSize = 200;

Future<ExcelImportInspection> inspectExcelSourceInBackground(
  String sourcePath, {
  required bool headerRow,
}) {
  return Isolate.run(
    () => inspectExcelSourceFile(sourcePath, headerRow: headerRow),
  );
}

ExcelImportInspection inspectExcelSourceFile(
  String sourcePath, {
  required bool headerRow,
}) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    throw BridgeFailure('Excel source file does not exist: $sourcePath');
  }
  final loadedWorkbook = _loadWorkbookFromSource(sourcePath);
  try {
    final warnings = <String>[...loadedWorkbook.warnings];
    final sheets = <ExcelImportSheetDraft>[];
    for (final entry in loadedWorkbook.workbook.tables.entries) {
      sheets.add(
        _inspectSheet(
          entry.key,
          entry.value,
          headerRow: headerRow,
          warnings: warnings,
        ),
      );
    }

    return ExcelImportInspection(
      sourcePath: sourcePath,
      headerRow: headerRow,
      sheets: sheets,
      warnings: warnings,
    );
  } finally {
    loadedWorkbook.dispose();
  }
}

@pragma('vm:entry-point')
Future<void> excelImportWorkerMain(List<Object?> bootstrap) async {
  final mainPort = bootstrap[0]! as SendPort;
  final libraryPath = bootstrap[1]! as String;
  final request = ExcelImportRequest.fromMap(
    (bootstrap[2]! as Map<Object?, Object?>).map(
      (key, value) => MapEntry(key as String, value),
    ),
  );

  final commandPort = ReceivePort();
  mainPort.send(commandPort.sendPort);

  var cancelled = false;
  late final StreamSubscription<Object?> commandSubscription;
  commandSubscription = commandPort.listen((message) {
    if (message == 'cancel') {
      cancelled = true;
    }
  });

  try {
    final summary = await _runExcelImport(
      request: request,
      libraryPath: libraryPath,
      sendUpdate: (update) => mainPort.send(update.toMap()),
      isCancelled: () => cancelled,
    );
    mainPort.send(
      ExcelImportUpdate(
        kind: cancelled
            ? ExcelImportUpdateKind.cancelled
            : ExcelImportUpdateKind.completed,
        jobId: request.jobId,
        summary: summary,
      ).toMap(),
    );
  } on _ExcelImportCancelled catch (error) {
    mainPort.send(
      ExcelImportUpdate(
        kind: ExcelImportUpdateKind.cancelled,
        jobId: request.jobId,
        summary: error.summary,
        message: error.summary.statusMessage,
      ).toMap(),
    );
  } catch (error) {
    mainPort.send(
      ExcelImportUpdate(
        kind: ExcelImportUpdateKind.failed,
        jobId: request.jobId,
        message: error.toString(),
      ).toMap(),
    );
  } finally {
    await commandSubscription.cancel();
    commandPort.close();
  }
}

enum _ExcelImportObjectKind { table, view }

class _ResolvedExcelImportObject {
  const _ResolvedExcelImportObject.table(this.sheet)
    : kind = _ExcelImportObjectKind.table,
      viewSql = null;

  const _ResolvedExcelImportObject.view(this.sheet, this.viewSql)
    : kind = _ExcelImportObjectKind.view;

  final ExcelImportSheetDraft sheet;
  final _ExcelImportObjectKind kind;
  final String? viewSql;

  bool get isTable => kind == _ExcelImportObjectKind.table;

  bool get isView => kind == _ExcelImportObjectKind.view;
}

class _SelectedExcelSheetContext {
  const _SelectedExcelSheetContext({
    required this.draft,
    required this.sheet,
    required this.bounds,
  });

  final ExcelImportSheetDraft draft;
  final xls.Sheet sheet;
  final _SheetBounds bounds;

  String get sourceName => draft.sourceName;

  String get targetName => draft.targetName;
}

Future<ExcelImportSummary> _runExcelImport({
  required ExcelImportRequest request,
  required String libraryPath,
  required void Function(ExcelImportUpdate update) sendUpdate,
  required bool Function() isCancelled,
}) async {
  if (request.selectedSheets.isEmpty) {
    throw const BridgeFailure('Select at least one worksheet to import.');
  }

  _validateRequestNames(request);

  final sourceFile = File(request.sourcePath);
  if (!sourceFile.existsSync()) {
    throw BridgeFailure(
      'Excel source file does not exist: ${request.sourcePath}',
    );
  }

  final targetFile = File(request.targetPath);
  if (request.importIntoExistingTarget) {
    if (!targetFile.existsSync()) {
      throw BridgeFailure(
        'Target DecentDB file does not exist: ${request.targetPath}',
      );
    }
  } else {
    targetFile.parent.createSync(recursive: true);
    if (targetFile.existsSync()) {
      if (!request.replaceExistingTarget) {
        throw BridgeFailure(
          'Refusing to replace an existing DecentDB file without confirmation: ${request.targetPath}',
        );
      }
      targetFile.deleteSync();
      final walFile = File('${request.targetPath}-wal');
      if (walFile.existsSync()) {
        walFile.deleteSync();
      }
    }
  }

  final loadedWorkbook = _loadWorkbookFromSource(request.sourcePath);
  try {
    final target = Database.open(request.targetPath, libraryPath: libraryPath);
    var transactionOpen = false;
    final rowsCopied = <String, int>{};
    final createdViews = <String>[];
    final warnings = <String>[...loadedWorkbook.warnings];

    try {
      final resolvedImports = _resolveSelectedExcelImports(
        workbook: loadedWorkbook.workbook,
        request: request,
        warnings: warnings,
      );
      final tableImports = resolvedImports
          .where((item) => item.isTable)
          .toList(growable: false);
      final viewImports = resolvedImports
          .where((item) => item.isView)
          .toList(growable: false);
      final existingObjects = <String>{
        ...target.schema.listTables(),
        ...target.schema.listViews(),
      };
      final colliding = resolvedImports
          .map((item) => item.sheet.targetName)
          .where(existingObjects.contains)
          .toList();
      if (colliding.isNotEmpty) {
        throw BridgeFailure(
          'Target already contains object(s): ${colliding.join(", ")}. Rename them or choose another DecentDB file.',
        );
      }

      target.begin();
      transactionOpen = true;

      for (var i = 0; i < tableImports.length; i++) {
        final sheet = tableImports[i].sheet;
        _throwIfCancelled(isCancelled);
        target.execute(_buildCreateTableSql(sheet));
        sendUpdate(
          ExcelImportUpdate(
            kind: ExcelImportUpdateKind.progress,
            jobId: request.jobId,
            progress: ExcelImportProgress(
              jobId: request.jobId,
              currentSheet: sheet.targetName,
              completedSheets: i,
              totalSheets: resolvedImports.length,
              currentSheetRowsCopied: 0,
              currentSheetRowCount: sheet.rowCount,
              totalRowsCopied: rowsCopied.values.fold<int>(
                0,
                (sum, value) => sum + value,
              ),
              message: 'Created table ${sheet.targetName}.',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      for (var i = 0; i < tableImports.length; i++) {
        final sheet = tableImports[i].sheet;
        final copied = await _copySheetData(
          workbook: loadedWorkbook.workbook,
          target: target,
          request: request,
          sheet: sheet,
          completedSheets: i,
          totalSheets: resolvedImports.length,
          priorRowsCopied: rowsCopied.values.fold<int>(
            0,
            (sum, value) => sum + value,
          ),
          sendUpdate: sendUpdate,
          isCancelled: isCancelled,
          warnings: warnings,
        );
        rowsCopied[sheet.targetName] = copied;
      }

      for (var i = 0; i < viewImports.length; i++) {
        final viewImport = viewImports[i];
        _throwIfCancelled(isCancelled);
        target.execute(viewImport.viewSql!);
        createdViews.add(viewImport.sheet.targetName);
        sendUpdate(
          ExcelImportUpdate(
            kind: ExcelImportUpdateKind.progress,
            jobId: request.jobId,
            progress: ExcelImportProgress(
              jobId: request.jobId,
              currentSheet: viewImport.sheet.targetName,
              completedSheets: tableImports.length + i,
              totalSheets: resolvedImports.length,
              currentSheetRowsCopied: 0,
              currentSheetRowCount: 0,
              totalRowsCopied: rowsCopied.values.fold<int>(
                0,
                (sum, value) => sum + value,
              ),
              message: 'Created view ${viewImport.sheet.targetName}.',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      target.commit();
      transactionOpen = false;

      return ExcelImportSummary(
        jobId: request.jobId,
        sourcePath: request.sourcePath,
        targetPath: request.targetPath,
        importedTables: tableImports
            .map((item) => item.sheet.targetName)
            .toList(growable: false),
        importedViews: viewImports
            .map((item) => item.sheet.targetName)
            .toList(growable: false),
        rowsCopiedByTable: rowsCopied,
        warnings: warnings,
        statusMessage: _buildExcelImportStatusMessage(
          totalRowsCopied: rowsCopied.values.fold<int>(
            0,
            (sum, value) => sum + value,
          ),
          importedTableCount: tableImports.length,
          importedViewCount: viewImports.length,
          selectedSheetCount: request.selectedSheets.length,
        ),
        rolledBack: false,
      );
    } on _ExcelImportCancelledSignal {
      if (transactionOpen) {
        try {
          target.rollback();
        } catch (_) {
          // Best-effort rollback for cancellation.
        }
      }
      final summary = ExcelImportSummary(
        jobId: request.jobId,
        sourcePath: request.sourcePath,
        targetPath: request.targetPath,
        importedTables: rowsCopied.keys.toList(),
        importedViews: createdViews,
        rowsCopiedByTable: rowsCopied,
        warnings: warnings,
        statusMessage: 'Excel import cancelled and rolled back.',
        rolledBack: true,
      );
      throw _ExcelImportCancelled(summary);
    } catch (_) {
      if (transactionOpen) {
        try {
          target.rollback();
        } catch (_) {
          // Best-effort rollback on failure.
        }
      }
      rethrow;
    } finally {
      target.close();
    }
  } finally {
    loadedWorkbook.dispose();
  }
}

Future<int> _copySheetData({
  required xls.Excel workbook,
  required Database target,
  required ExcelImportRequest request,
  required ExcelImportSheetDraft sheet,
  required int completedSheets,
  required int totalSheets,
  required int priorRowsCopied,
  required void Function(ExcelImportUpdate update) sendUpdate,
  required bool Function() isCancelled,
  required List<String> warnings,
}) async {
  final sourceSheet = workbook.tables[sheet.sourceName];
  if (sourceSheet == null) {
    throw BridgeFailure(
      'Worksheet ${sheet.sourceName} no longer exists in ${request.sourcePath}.',
    );
  }

  final placeholders = <String>[
    for (var i = 0; i < sheet.columns.length; i++)
      _placeholderForType(sheet.columns[i].targetType, i + 1),
  ];
  final targetStatement = target.prepare(
    'INSERT INTO ${_quoteDecentIdent(sheet.targetName)} '
    '(${sheet.columns.map((column) => _quoteDecentIdent(column.targetName)).join(", ")}) '
    'VALUES (${placeholders.join(", ")})',
  );

  var copied = 0;
  var formulaWarningAdded = false;
  try {
    final sheetRows = sourceSheet.rows;
    final bounds = _resolveSheetBounds(
      sheetRows,
      headerRow: request.headerRow,
      expectedColumnCount: sheet.columns.length,
    );
    for (
      var rowIndex = bounds.dataStartRow;
      rowIndex < sheetRows.length;
      rowIndex++
    ) {
      _throwIfCancelled(isCancelled);
      final row = sheetRows[rowIndex];
      if (_isExcelRowEmpty(row, bounds.columnCount)) {
        continue;
      }

      final values = <Object?>[];
      for (final column in sheet.columns) {
        final cellValue = _cellValueAt(row, column.sourceIndex);
        if (!formulaWarningAdded && cellValue is xls.FormulaCellValue) {
          warnings.add(
            '${sheet.sourceName} contains formula cells. Formula expressions are imported as text.',
          );
          formulaWarningAdded = true;
        }
        values.add(
          _adaptImportValue(
            _normalizeExcelCellValue(cellValue),
            column.targetType,
          ),
        );
      }

      targetStatement.reset();
      targetStatement.clearBindings();
      targetStatement.bindAll(values);
      targetStatement.execute();
      copied++;

      if (copied == 1 ||
          copied % _excelProgressBatchSize == 0 ||
          copied == sheet.rowCount) {
        sendUpdate(
          ExcelImportUpdate(
            kind: ExcelImportUpdateKind.progress,
            jobId: request.jobId,
            progress: ExcelImportProgress(
              jobId: request.jobId,
              currentSheet: sheet.targetName,
              completedSheets: completedSheets,
              totalSheets: totalSheets,
              currentSheetRowsCopied: copied,
              currentSheetRowCount: sheet.rowCount,
              totalRowsCopied: priorRowsCopied + copied,
              message: 'Copying ${sheet.targetName}...',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
  } finally {
    targetStatement.dispose();
  }

  return copied;
}

const Set<String> _supportedSummaryAggregateFunctions = <String>{
  'COUNTIF',
  'COUNTA',
  'SUM',
  'SUMIF',
  'SUMPRODUCT',
};

List<_ResolvedExcelImportObject> _resolveSelectedExcelImports({
  required xls.Excel workbook,
  required ExcelImportRequest request,
  required List<String> warnings,
}) {
  if (!request.headerRow) {
    return <_ResolvedExcelImportObject>[
      for (final sheet in request.selectedSheets)
        _ResolvedExcelImportObject.table(sheet),
    ];
  }

  final sheetContexts = <String, _SelectedExcelSheetContext>{};
  for (final sheet in request.selectedSheets) {
    final sourceSheet = workbook.tables[sheet.sourceName];
    if (sourceSheet == null) {
      throw BridgeFailure(
        'Worksheet ${sheet.sourceName} no longer exists in ${request.sourcePath}.',
      );
    }
    sheetContexts[sheet.sourceName] = _SelectedExcelSheetContext(
      draft: sheet,
      sheet: sourceSheet,
      bounds: _resolveSheetBounds(
        sourceSheet.rows,
        headerRow: request.headerRow,
        expectedColumnCount: sheet.columns.length,
      ),
    );
  }

  final plannedKinds = <String, _ExcelImportObjectKind>{
    for (final entry in sheetContexts.entries)
      entry.key: _isAggregateSummaryViewCandidate(entry.value)
          ? _ExcelImportObjectKind.view
          : _ExcelImportObjectKind.table,
  };

  final resolved = <_ResolvedExcelImportObject>[];
  for (final sheet in request.selectedSheets) {
    final context = sheetContexts[sheet.sourceName]!;
    if (plannedKinds[sheet.sourceName] == _ExcelImportObjectKind.view) {
      try {
        final viewSql = _ExcelSummaryViewBuilder(
          sheetContexts: sheetContexts,
          plannedKinds: plannedKinds,
        ).buildViewSql(context);
        resolved.add(_ResolvedExcelImportObject.view(sheet, viewSql));
        continue;
      } on _FormulaTranslationError catch (error) {
        warnings.add(
          '${sheet.sourceName} was imported as a table because ${error.message}',
        );
        plannedKinds[sheet.sourceName] = _ExcelImportObjectKind.table;
      }
    }

    resolved.add(_ResolvedExcelImportObject.table(sheet));
  }

  return resolved;
}

bool _isAggregateSummaryViewCandidate(_SelectedExcelSheetContext context) {
  if (context.draft.rowCount == 0 || context.draft.columns.isEmpty) {
    return false;
  }

  var formulaCellCount = 0;
  final rows = context.sheet.rows;
  for (
    var rowIndex = context.bounds.dataStartRow;
    rowIndex < rows.length;
    rowIndex++
  ) {
    final row = rows[rowIndex];
    if (_isExcelRowEmpty(row, context.bounds.columnCount)) {
      continue;
    }

    var rowHasFormula = false;
    for (
      var columnIndex = 0;
      columnIndex < context.bounds.columnCount;
      columnIndex++
    ) {
      final cellValue = _cellValueAt(row, columnIndex);
      if (cellValue is! xls.FormulaCellValue) {
        continue;
      }

      final parsed = _parseExcelFormula(cellValue.formula);
      if (parsed is! _ExcelFunctionNode ||
          !_supportedSummaryAggregateFunctions.contains(
            parsed.normalizedName,
          )) {
        return false;
      }

      rowHasFormula = true;
      formulaCellCount++;
    }

    if (!rowHasFormula) {
      return false;
    }
  }

  return formulaCellCount > 0;
}

String _buildExcelImportStatusMessage({
  required int totalRowsCopied,
  required int importedTableCount,
  required int importedViewCount,
  required int selectedSheetCount,
}) {
  final rowFragment = importedTableCount == 0
      ? ''
      : 'Imported $totalRowsCopied rows into $importedTableCount table${importedTableCount == 1 ? '' : 's'}';
  final viewFragment = importedViewCount == 0
      ? ''
      : 'created $importedViewCount view${importedViewCount == 1 ? '' : 's'}';
  final sheetFragment =
      'from $selectedSheetCount workbook sheet${selectedSheetCount == 1 ? '' : 's'}.';

  if (rowFragment.isEmpty && viewFragment.isEmpty) {
    return 'Imported $sheetFragment';
  }
  if (rowFragment.isEmpty) {
    return '${_capitalizeSentence(viewFragment)} $sheetFragment';
  }
  if (viewFragment.isEmpty) {
    return '$rowFragment $sheetFragment';
  }
  return '$rowFragment and $viewFragment $sheetFragment';
}

String _capitalizeSentence(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

class _ExcelSummaryViewBuilder {
  _ExcelSummaryViewBuilder({
    required this.sheetContexts,
    required this.plannedKinds,
  });

  final Map<String, _SelectedExcelSheetContext> sheetContexts;
  final Map<String, _ExcelImportObjectKind> plannedKinds;
  final Map<String, _ExcelFormulaNode> _formulaCache =
      <String, _ExcelFormulaNode>{};
  final Set<String> _activeFormulaCells = <String>{};

  var _aliasCounter = 0;

  String buildViewSql(_SelectedExcelSheetContext viewSheet) {
    final selects = <String>[];
    final rows = viewSheet.sheet.rows;
    for (
      var rowIndex = viewSheet.bounds.dataStartRow;
      rowIndex < rows.length;
      rowIndex++
    ) {
      final row = rows[rowIndex];
      if (_isExcelRowEmpty(row, viewSheet.bounds.columnCount)) {
        continue;
      }

      final expressions = <String>[];
      for (
        var columnIndex = 0;
        columnIndex < viewSheet.draft.columns.length;
        columnIndex++
      ) {
        final cellValue = _cellValueAt(row, columnIndex);
        final expression = _translateSummaryCell(
          sheet: viewSheet,
          rowIndex: rowIndex + 1,
          columnIndex: columnIndex + 1,
          value: cellValue,
        );
        expressions.add(
          '$expression AS ${_quoteDecentIdent(viewSheet.draft.columns[columnIndex].targetName)}',
        );
      }
      selects.add('SELECT ${expressions.join(", ")}');
    }

    if (selects.isEmpty) {
      throw const _FormulaTranslationError(
        'it did not contain any data rows that could be translated into a view.',
      );
    }

    return 'CREATE VIEW ${_quoteDecentIdent(viewSheet.targetName)} AS '
        '${selects.join(" UNION ALL ")}';
  }

  String _translateSummaryCell({
    required _SelectedExcelSheetContext sheet,
    required int rowIndex,
    required int columnIndex,
    required xls.CellValue? value,
  }) {
    if (value == null) {
      return 'NULL';
    }
    if (value is! xls.FormulaCellValue) {
      return _sqlLiteral(_normalizeExcelCellValue(value));
    }

    final node = _cachedFormula(value.formula);
    if (node is! _ExcelFunctionNode ||
        !_supportedSummaryAggregateFunctions.contains(node.normalizedName)) {
      throw _FormulaTranslationError(
        'formula ${value.formula} is not supported for automatic view import.',
      );
    }

    return _translateAggregateFunction(
      node,
      currentSheet: sheet,
      currentRowIndex: rowIndex,
    );
  }

  String _translateAggregateFunction(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
  }) {
    return switch (node.normalizedName) {
      'COUNTIF' => _translateCountIf(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
      ),
      'COUNTA' => _translateCountA(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
      ),
      'SUM' => _translateSum(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
      ),
      'SUMIF' => _translateSumIf(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
      ),
      'SUMPRODUCT' => _translateSumProduct(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
      ),
      _ => throw _FormulaTranslationError(
        'aggregate function ${node.normalizedName} is not supported for automatic view import.',
      ),
    };
  }

  String _translateCountIf(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
  }) {
    _expectArgumentCount(node, 2);
    final criteriaRange = _requireRange(
      node.arguments[0],
      currentSheet: currentSheet,
    );
    final sourceSheet = _sheetForRange(
      criteriaRange,
      currentSheet: currentSheet,
    );
    final alias = _nextAlias('countif_src');
    final criteriaExpression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: criteriaRange,
      alias: alias,
    );
    final criterion = _translateRowNode(
      node.arguments[1],
      currentSheet: currentSheet,
      currentRowIndex: currentRowIndex,
    );
    return '(SELECT COUNT(*) FROM ${_quoteDecentIdent(sourceSheet.targetName)} '
        '$alias WHERE $criteriaExpression = $criterion)';
  }

  String _translateCountA(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
  }) {
    _expectArgumentCount(node, 1);
    final range = _requireRange(node.arguments[0], currentSheet: currentSheet);
    final sourceSheet = _sheetForRange(range, currentSheet: currentSheet);
    final alias = _nextAlias('counta_src');
    final expression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: range,
      alias: alias,
    );
    return '(SELECT COUNT($expression) FROM ${_quoteDecentIdent(sourceSheet.targetName)} '
        '$alias)';
  }

  String _translateSum(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
  }) {
    _expectArgumentCount(node, 1);
    final range = _requireRange(node.arguments[0], currentSheet: currentSheet);
    final sourceSheet = _sheetForRange(range, currentSheet: currentSheet);
    final alias = _nextAlias('sum_src');
    final expression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: range,
      alias: alias,
    );
    return 'COALESCE((SELECT SUM($expression) '
        'FROM ${_quoteDecentIdent(sourceSheet.targetName)} $alias), 0)';
  }

  String _translateSumIf(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
  }) {
    _expectArgumentCount(node, 3);
    final criteriaRange = _requireRange(
      node.arguments[0],
      currentSheet: currentSheet,
    );
    final sumRange = _requireRange(
      node.arguments[2],
      currentSheet: currentSheet,
    );
    if (criteriaRange.sheetNameOrNull(currentSheet.sourceName) !=
        sumRange.sheetNameOrNull(currentSheet.sourceName)) {
      throw const _FormulaTranslationError(
        'SUMIF ranges must point at the same worksheet.',
      );
    }

    final sourceSheet = _sheetForRange(
      criteriaRange,
      currentSheet: currentSheet,
    );
    final alias = _nextAlias('sumif_src');
    final criteriaExpression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: criteriaRange,
      alias: alias,
    );
    final sumExpression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: sumRange,
      alias: alias,
    );
    final criterion = _translateRowNode(
      node.arguments[1],
      currentSheet: currentSheet,
      currentRowIndex: currentRowIndex,
    );
    return 'COALESCE((SELECT SUM($sumExpression) '
        'FROM ${_quoteDecentIdent(sourceSheet.targetName)} $alias '
        'WHERE $criteriaExpression = $criterion), 0)';
  }

  String _translateSumProduct(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
  }) {
    _expectArgumentCount(node, 2);
    final leftRange = _requireRange(
      node.arguments[0],
      currentSheet: currentSheet,
    );
    final rightRange = _requireRange(
      node.arguments[1],
      currentSheet: currentSheet,
    );
    if (leftRange.sheetNameOrNull(currentSheet.sourceName) !=
        rightRange.sheetNameOrNull(currentSheet.sourceName)) {
      throw const _FormulaTranslationError(
        'SUMPRODUCT ranges must point at the same worksheet.',
      );
    }
    if (!leftRange.hasSameHeightAs(rightRange)) {
      throw const _FormulaTranslationError(
        'SUMPRODUCT ranges must be the same height.',
      );
    }

    final sourceSheet = _sheetForRange(leftRange, currentSheet: currentSheet);
    final alias = _nextAlias('sumproduct_src');
    final leftExpression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: leftRange,
      alias: alias,
    );
    final rightExpression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: rightRange,
      alias: alias,
    );
    return 'COALESCE((SELECT SUM($leftExpression * $rightExpression) '
        'FROM ${_quoteDecentIdent(sourceSheet.targetName)} $alias), 0)';
  }

  String _rangeColumnExpression({
    required _SelectedExcelSheetContext sheet,
    required _ExcelRangeRefNode range,
    required String alias,
  }) {
    if (!range.isSingleColumn) {
      throw const _FormulaTranslationError(
        'Only single-column ranges are supported for automatic view import.',
      );
    }

    if (plannedKinds[sheet.sourceName] == _ExcelImportObjectKind.view) {
      return '$alias.'
          '${_quoteDecentIdent(sheet.draft.columns[range.startColumnIndex - 1].targetName)}';
    }

    final sampleValue = _cellValueFor(
      sheet,
      range.startRowIndex,
      range.startColumnIndex,
    );
    if (sampleValue is xls.FormulaCellValue) {
      return _translateFormulaCell(
        sheet: sheet,
        rowIndex: range.startRowIndex,
        columnIndex: range.startColumnIndex,
        rowAlias: alias,
      );
    }

    return '$alias.'
        '${_quoteDecentIdent(sheet.draft.columns[range.startColumnIndex - 1].targetName)}';
  }

  String _translateFormulaCell({
    required _SelectedExcelSheetContext sheet,
    required int rowIndex,
    required int columnIndex,
    String? rowAlias,
  }) {
    final key = '${sheet.sourceName}:$rowIndex:$columnIndex:${rowAlias ?? "-"}';
    if (!_activeFormulaCells.add(key)) {
      throw _FormulaTranslationError(
        'formula cycle detected at ${sheet.sourceName}!${_excelColumnLabel(columnIndex)}$rowIndex.',
      );
    }

    try {
      final value = _cellValueFor(sheet, rowIndex, columnIndex);
      if (value == null) {
        return 'NULL';
      }
      if (value is! xls.FormulaCellValue) {
        return _sqlLiteral(_normalizeExcelCellValue(value));
      }

      final node = _cachedFormula(value.formula);
      if (rowAlias == null &&
          node is _ExcelFunctionNode &&
          _supportedSummaryAggregateFunctions.contains(node.normalizedName)) {
        return _translateAggregateFunction(
          node,
          currentSheet: sheet,
          currentRowIndex: rowIndex,
        );
      }
      return _translateRowNode(
        node,
        currentSheet: sheet,
        currentRowIndex: rowIndex,
        rowAlias: rowAlias,
      );
    } finally {
      _activeFormulaCells.remove(key);
    }
  }

  String _translateRowNode(
    _ExcelFormulaNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
    String? rowAlias,
  }) {
    if (node is _ExcelNumberNode) {
      return node.literal;
    }
    if (node is _ExcelStringNode) {
      return _sqlLiteral(node.value);
    }
    if (node is _ExcelBooleanNode) {
      return node.value ? 'TRUE' : 'FALSE';
    }
    if (node is _ExcelUnaryNode) {
      final operand = _translateRowNode(
        node.operand,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
        rowAlias: rowAlias,
      );
      return '(${node.operator}$operand)';
    }
    if (node is _ExcelBinaryNode) {
      final left = _translateRowNode(
        node.left,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
        rowAlias: rowAlias,
      );
      final right = _translateRowNode(
        node.right,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
        rowAlias: rowAlias,
      );
      return '($left ${node.operator} $right)';
    }
    if (node is _ExcelCellRefNode) {
      return _translateCellReference(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
        rowAlias: rowAlias,
      );
    }
    if (node is _ExcelFunctionNode) {
      return _translateRowFunction(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
        rowAlias: rowAlias,
      );
    }
    if (node is _ExcelRangeRefNode) {
      throw const _FormulaTranslationError(
        'Unexpected range in scalar formula expression.',
      );
    }

    throw const _FormulaTranslationError(
      'Unsupported formula node was encountered.',
    );
  }

  String _translateCellReference(
    _ExcelCellRefNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
    String? rowAlias,
  }) {
    final referencedSheet = _resolveReferencedSheet(
      node.sheetName,
      currentSheet: currentSheet,
    );
    final value = _cellValueFor(
      referencedSheet,
      node.rowIndex,
      node.columnIndex,
    );

    final isCurrentRowReference =
        rowAlias != null &&
        referencedSheet.sourceName == currentSheet.sourceName &&
        node.rowIndex == currentRowIndex;
    if (isCurrentRowReference) {
      if (value is xls.FormulaCellValue) {
        return _translateFormulaCell(
          sheet: referencedSheet,
          rowIndex: node.rowIndex,
          columnIndex: node.columnIndex,
          rowAlias: rowAlias,
        );
      }
      return '$rowAlias.'
          '${_quoteDecentIdent(referencedSheet.draft.columns[node.columnIndex - 1].targetName)}';
    }

    if (value is xls.FormulaCellValue) {
      return _translateFormulaCell(
        sheet: referencedSheet,
        rowIndex: node.rowIndex,
        columnIndex: node.columnIndex,
      );
    }

    return _sqlLiteral(_normalizeExcelCellValue(value));
  }

  String _translateRowFunction(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
    String? rowAlias,
  }) {
    return switch (node.normalizedName) {
      'IF' => _translateIf(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
        rowAlias: rowAlias,
      ),
      'VLOOKUP' => _translateVlookup(
        node,
        currentSheet: currentSheet,
        currentRowIndex: currentRowIndex,
        rowAlias: rowAlias,
      ),
      _ => throw _FormulaTranslationError(
        'formula function ${node.normalizedName} is not supported for automatic view import.',
      ),
    };
  }

  String _translateIf(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
    String? rowAlias,
  }) {
    _expectArgumentCount(node, 3);
    final condition = _translateRowNode(
      node.arguments[0],
      currentSheet: currentSheet,
      currentRowIndex: currentRowIndex,
      rowAlias: rowAlias,
    );
    final whenTrue = _translateRowNode(
      node.arguments[1],
      currentSheet: currentSheet,
      currentRowIndex: currentRowIndex,
      rowAlias: rowAlias,
    );
    final whenFalse = _translateRowNode(
      node.arguments[2],
      currentSheet: currentSheet,
      currentRowIndex: currentRowIndex,
      rowAlias: rowAlias,
    );
    return '(CASE WHEN $condition THEN $whenTrue ELSE $whenFalse END)';
  }

  String _translateVlookup(
    _ExcelFunctionNode node, {
    required _SelectedExcelSheetContext currentSheet,
    required int currentRowIndex,
    String? rowAlias,
  }) {
    _expectArgumentCount(node, 4);
    final lookupValue = _translateRowNode(
      node.arguments[0],
      currentSheet: currentSheet,
      currentRowIndex: currentRowIndex,
      rowAlias: rowAlias,
    );
    final range = _requireRange(node.arguments[1], currentSheet: currentSheet);
    final sourceSheet = _sheetForRange(range, currentSheet: currentSheet);
    final columnIndex = _requirePositiveInteger(node.arguments[2]);
    final exactMatch = _requireBoolean(node.arguments[3]);
    if (exactMatch) {
      throw const _FormulaTranslationError(
        'VLOOKUP approximate matches are not supported for automatic view import.',
      );
    }

    final returnColumnIndex = range.startColumnIndex + columnIndex - 1;
    if (returnColumnIndex > range.endColumnIndex) {
      throw _FormulaTranslationError(
        'VLOOKUP column index $columnIndex is outside ${range.displayLabel}.',
      );
    }

    final alias = _nextAlias('lookup_src');
    final keyRange = _ExcelRangeRefNode(
      sheetName: range.sheetName,
      startColumnIndex: range.startColumnIndex,
      startRowIndex: range.startRowIndex,
      endColumnIndex: range.startColumnIndex,
      endRowIndex: range.endRowIndex,
    );
    final valueRange = _ExcelRangeRefNode(
      sheetName: range.sheetName,
      startColumnIndex: returnColumnIndex,
      startRowIndex: range.startRowIndex,
      endColumnIndex: returnColumnIndex,
      endRowIndex: range.endRowIndex,
    );

    final keyExpression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: keyRange,
      alias: alias,
    );
    final valueExpression = _rangeColumnExpression(
      sheet: sourceSheet,
      range: valueRange,
      alias: alias,
    );
    return '(SELECT $valueExpression '
        'FROM ${_quoteDecentIdent(sourceSheet.targetName)} $alias '
        'WHERE $keyExpression = $lookupValue LIMIT 1)';
  }

  _ExcelRangeRefNode _requireRange(
    _ExcelFormulaNode node, {
    required _SelectedExcelSheetContext currentSheet,
  }) {
    if (node case final _ExcelRangeRefNode range) {
      return range.resolveSheet(currentSheet.sourceName);
    }
    throw const _FormulaTranslationError(
      'Expected an Excel range for automatic view import.',
    );
  }

  _SelectedExcelSheetContext _sheetForRange(
    _ExcelRangeRefNode range, {
    required _SelectedExcelSheetContext currentSheet,
  }) {
    return _resolveReferencedSheet(
      range.sheetNameOrNull(currentSheet.sourceName),
      currentSheet: currentSheet,
    );
  }

  _SelectedExcelSheetContext _resolveReferencedSheet(
    String? sheetName, {
    required _SelectedExcelSheetContext currentSheet,
  }) {
    final effectiveName = sheetName ?? currentSheet.sourceName;
    final resolved = sheetContexts[effectiveName];
    if (resolved != null) {
      return resolved;
    }
    throw _FormulaTranslationError(
      'worksheet $effectiveName was not selected for import.',
    );
  }

  xls.CellValue? _cellValueFor(
    _SelectedExcelSheetContext sheet,
    int rowIndex,
    int columnIndex,
  ) {
    if (rowIndex <= 0 || rowIndex > sheet.sheet.rows.length) {
      return null;
    }
    return _cellValueAt(sheet.sheet.rows[rowIndex - 1], columnIndex - 1);
  }

  _ExcelFormulaNode _cachedFormula(String formula) {
    return _formulaCache.putIfAbsent(
      formula,
      () => _parseExcelFormula(formula),
    );
  }

  void _expectArgumentCount(_ExcelFunctionNode node, int expected) {
    if (node.arguments.length != expected) {
      throw _FormulaTranslationError(
        '${node.normalizedName} expects $expected arguments.',
      );
    }
  }

  int _requirePositiveInteger(_ExcelFormulaNode node) {
    if (node is! _ExcelNumberNode) {
      throw const _FormulaTranslationError(
        'Expected a numeric literal for the Excel function argument.',
      );
    }
    final value = int.tryParse(node.literal);
    if (value == null || value <= 0) {
      throw _FormulaTranslationError(
        'Expected a positive integer but found ${node.literal}.',
      );
    }
    return value;
  }

  bool _requireBoolean(_ExcelFormulaNode node) {
    if (node case _ExcelBooleanNode(:final value)) {
      return value;
    }
    if (node case _ExcelFunctionNode(
      normalizedName: 'TRUE',
      arguments: final arguments,
    ) when arguments.isEmpty) {
      return true;
    }
    if (node case _ExcelFunctionNode(
      normalizedName: 'FALSE',
      arguments: final arguments,
    ) when arguments.isEmpty) {
      return false;
    }
    throw _FormulaTranslationError(
      'Expected a TRUE/FALSE literal for the Excel function argument, but found ${node.runtimeType}.',
    );
  }

  String _nextAlias(String prefix) {
    _aliasCounter++;
    return '${prefix}_$_aliasCounter';
  }
}

String _sqlLiteral(Object? value) {
  if (value == null) {
    return 'NULL';
  }
  if (value is bool) {
    return value ? 'TRUE' : 'FALSE';
  }
  if (value is num) {
    return value.toString();
  }
  if (value is DateTime) {
    return "'${value.toUtc().toIso8601String().replaceAll("'", "''")}'";
  }
  if (value is Uint8List) {
    final hex = value
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return "x'$hex'";
  }
  final text = '$value'.replaceAll("'", "''");
  return "'$text'";
}

String _excelColumnLabel(int columnIndex) {
  var current = columnIndex;
  final buffer = StringBuffer();
  while (current > 0) {
    current--;
    buffer.writeCharCode(65 + (current % 26));
    current ~/= 26;
  }
  return buffer.toString().split('').reversed.join();
}

_ExcelFormulaNode _parseExcelFormula(String formula) {
  return _ExcelFormulaParser(formula).parse();
}

class _FormulaTranslationError implements Exception {
  const _FormulaTranslationError(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class _ExcelFormulaNode {
  const _ExcelFormulaNode();
}

class _ExcelNumberNode extends _ExcelFormulaNode {
  const _ExcelNumberNode(this.literal);

  final String literal;
}

class _ExcelStringNode extends _ExcelFormulaNode {
  const _ExcelStringNode(this.value);

  final String value;
}

class _ExcelBooleanNode extends _ExcelFormulaNode {
  const _ExcelBooleanNode(this.value);

  final bool value;
}

class _ExcelCellRefNode extends _ExcelFormulaNode {
  const _ExcelCellRefNode({
    required this.sheetName,
    required this.columnIndex,
    required this.rowIndex,
  });

  final String? sheetName;
  final int columnIndex;
  final int rowIndex;
}

class _ExcelRangeRefNode extends _ExcelFormulaNode {
  const _ExcelRangeRefNode({
    required this.sheetName,
    required this.startColumnIndex,
    required this.startRowIndex,
    required this.endColumnIndex,
    required this.endRowIndex,
  });

  final String? sheetName;
  final int startColumnIndex;
  final int startRowIndex;
  final int endColumnIndex;
  final int endRowIndex;

  bool get isSingleColumn => startColumnIndex == endColumnIndex;

  String get displayLabel =>
      '${_excelColumnLabel(startColumnIndex)}$startRowIndex:${_excelColumnLabel(endColumnIndex)}$endRowIndex';

  bool hasSameHeightAs(_ExcelRangeRefNode other) =>
      (endRowIndex - startRowIndex) ==
      (other.endRowIndex - other.startRowIndex);

  _ExcelRangeRefNode resolveSheet(String fallbackSheetName) {
    return _ExcelRangeRefNode(
      sheetName: sheetName ?? fallbackSheetName,
      startColumnIndex: startColumnIndex,
      startRowIndex: startRowIndex,
      endColumnIndex: endColumnIndex,
      endRowIndex: endRowIndex,
    );
  }

  String? sheetNameOrNull(String fallbackSheetName) =>
      sheetName ?? fallbackSheetName;
}

class _ExcelFunctionNode extends _ExcelFormulaNode {
  const _ExcelFunctionNode({required this.name, required this.arguments});

  final String name;
  final List<_ExcelFormulaNode> arguments;

  String get normalizedName => name.toUpperCase();
}

class _ExcelUnaryNode extends _ExcelFormulaNode {
  const _ExcelUnaryNode({required this.operator, required this.operand});

  final String operator;
  final _ExcelFormulaNode operand;
}

class _ExcelBinaryNode extends _ExcelFormulaNode {
  const _ExcelBinaryNode({
    required this.left,
    required this.operator,
    required this.right,
  });

  final _ExcelFormulaNode left;
  final String operator;
  final _ExcelFormulaNode right;
}

class _ExcelFormulaParser {
  _ExcelFormulaParser(String formula)
    : _input = formula.startsWith('=') ? formula.substring(1) : formula;

  final String _input;
  var _index = 0;

  _ExcelFormulaNode parse() {
    final node = _parseComparison();
    _skipWhitespace();
    if (!_isAtEnd) {
      throw _FormulaTranslationError(
        'Unexpected token in Excel formula near "${_input.substring(_index)}".',
      );
    }
    return node;
  }

  bool get _isAtEnd => _index >= _input.length;

  _ExcelFormulaNode _parseComparison() {
    var node = _parseAdditive();
    while (true) {
      _skipWhitespace();
      final operator = _matchAny(<String>['<=', '>=', '<>', '=', '<', '>']);
      if (operator == null) {
        return node;
      }
      final right = _parseAdditive();
      node = _ExcelBinaryNode(left: node, operator: operator, right: right);
    }
  }

  _ExcelFormulaNode _parseAdditive() {
    var node = _parseMultiplicative();
    while (true) {
      _skipWhitespace();
      final operator = _matchAny(<String>['+', '-']);
      if (operator == null) {
        return node;
      }
      final right = _parseMultiplicative();
      node = _ExcelBinaryNode(left: node, operator: operator, right: right);
    }
  }

  _ExcelFormulaNode _parseMultiplicative() {
    var node = _parseUnary();
    while (true) {
      _skipWhitespace();
      final operator = _matchAny(<String>['*', '/']);
      if (operator == null) {
        return node;
      }
      final right = _parseUnary();
      node = _ExcelBinaryNode(left: node, operator: operator, right: right);
    }
  }

  _ExcelFormulaNode _parseUnary() {
    _skipWhitespace();
    if (_match('-')) {
      return _ExcelUnaryNode(operator: '-', operand: _parseUnary());
    }
    return _parsePrimary();
  }

  _ExcelFormulaNode _parsePrimary() {
    _skipWhitespace();
    if (_match('(')) {
      final inner = _parseComparison();
      _expect(')');
      return inner;
    }
    if (_peek() == '"') {
      return _ExcelStringNode(_parseString());
    }
    if (_isNumberStart(_peek())) {
      return _ExcelNumberNode(_parseNumber());
    }
    return _parseReferenceOrFunction();
  }

  _ExcelFormulaNode _parseReferenceOrFunction() {
    final leadingToken = _parseNameToken();
    _skipWhitespace();
    if (_match('!')) {
      final sheetName = leadingToken;
      final referenceToken = _parseReferenceToken();
      final start = _parseCellRef(referenceToken, sheetName: sheetName);
      _skipWhitespace();
      if (_match(':')) {
        final endToken = _parseReferenceToken();
        final end = _parseCellRef(endToken, sheetName: sheetName);
        return _ExcelRangeRefNode(
          sheetName: sheetName,
          startColumnIndex: start.columnIndex,
          startRowIndex: start.rowIndex,
          endColumnIndex: end.columnIndex,
          endRowIndex: end.rowIndex,
        );
      }
      return start;
    }

    if (_match('(')) {
      final arguments = <_ExcelFormulaNode>[];
      _skipWhitespace();
      if (!_match(')')) {
        do {
          arguments.add(_parseComparison());
          _skipWhitespace();
        } while (_match(','));
        _expect(')');
      }
      return _ExcelFunctionNode(name: leadingToken, arguments: arguments);
    }

    if (_isCellReferenceToken(leadingToken)) {
      final start = _parseCellRef(leadingToken);
      _skipWhitespace();
      if (_match(':')) {
        final endToken = _parseReferenceToken();
        final end = _parseCellRef(endToken);
        return _ExcelRangeRefNode(
          sheetName: null,
          startColumnIndex: start.columnIndex,
          startRowIndex: start.rowIndex,
          endColumnIndex: end.columnIndex,
          endRowIndex: end.rowIndex,
        );
      }
      return start;
    }

    final normalized = leadingToken.toUpperCase();
    if (normalized == 'TRUE') {
      return const _ExcelBooleanNode(true);
    }
    if (normalized == 'FALSE') {
      return const _ExcelBooleanNode(false);
    }

    throw _FormulaTranslationError(
      'Unsupported Excel token "$leadingToken" in formula.',
    );
  }

  String _parseString() {
    _expect('"');
    final buffer = StringBuffer();
    while (!_isAtEnd) {
      final char = _consume();
      if (char == '"') {
        if (_peek() == '"') {
          _consume();
          buffer.write('"');
          continue;
        }
        return buffer.toString();
      }
      buffer.write(char);
    }
    throw const _FormulaTranslationError(
      'Unterminated string literal in formula.',
    );
  }

  String _parseNumber() {
    final start = _index;
    while (!_isAtEnd && _isNumberPart(_peek())) {
      _index++;
    }
    return _input.substring(start, _index);
  }

  String _parseNameToken() {
    _skipWhitespace();
    if (_peek() == "'") {
      return _parseQuotedSheetName();
    }
    final start = _index;
    while (!_isAtEnd && _isNamePart(_peek())) {
      _index++;
    }
    if (start == _index) {
      throw _FormulaTranslationError(
        'Expected a token in formula near "${_input.substring(_index)}".',
      );
    }
    return _input.substring(start, _index);
  }

  String _parseReferenceToken() {
    _skipWhitespace();
    final start = _index;
    while (!_isAtEnd && _isReferencePart(_peek())) {
      _index++;
    }
    if (start == _index) {
      throw _FormulaTranslationError(
        'Expected a cell reference in formula near "${_input.substring(_index)}".',
      );
    }
    return _input.substring(start, _index);
  }

  String _parseQuotedSheetName() {
    _expect("'");
    final buffer = StringBuffer();
    while (!_isAtEnd) {
      final char = _consume();
      if (char == "'") {
        if (_peek() == "'") {
          _consume();
          buffer.write("'");
          continue;
        }
        return buffer.toString();
      }
      buffer.write(char);
    }
    throw const _FormulaTranslationError('Unterminated quoted sheet name.');
  }

  _ExcelCellRefNode _parseCellRef(String token, {String? sheetName}) {
    final cleaned = token.replaceAll(r'$', '').toUpperCase();
    final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(cleaned);
    if (match == null) {
      throw _FormulaTranslationError('Unsupported cell reference "$token".');
    }
    return _ExcelCellRefNode(
      sheetName: sheetName,
      columnIndex: _excelColumnIndex(match.group(1)!),
      rowIndex: int.parse(match.group(2)!),
    );
  }

  bool _match(String value) {
    _skipWhitespace();
    if (_input.startsWith(value, _index)) {
      _index += value.length;
      return true;
    }
    return false;
  }

  String? _matchAny(List<String> values) {
    for (final value in values) {
      if (_input.startsWith(value, _index)) {
        _index += value.length;
        return value;
      }
    }
    return null;
  }

  void _expect(String value) {
    if (!_match(value)) {
      throw _FormulaTranslationError(
        'Expected "$value" in formula near "${_input.substring(_index)}".',
      );
    }
  }

  void _skipWhitespace() {
    while (!_isAtEnd) {
      final char = _input.codeUnitAt(_index);
      if (char == 32 || char == 9 || char == 10 || char == 13) {
        _index++;
        continue;
      }
      return;
    }
  }

  String _consume() {
    final char = _input[_index];
    _index++;
    return char;
  }

  String? _peek() => _isAtEnd ? null : _input[_index];
}

int _excelColumnIndex(String value) {
  var result = 0;
  for (final codeUnit in value.codeUnits) {
    result = (result * 26) + (codeUnit - 64);
  }
  return result;
}

bool _isCellReferenceToken(String token) {
  final cleaned = token.replaceAll(r'$', '');
  return RegExp(r'^[A-Za-z]+\d+$').hasMatch(cleaned);
}

bool _isNumberStart(String? char) {
  if (char == null) {
    return false;
  }
  return RegExp(r'[0-9.]').hasMatch(char);
}

bool _isNumberPart(String? char) {
  if (char == null) {
    return false;
  }
  return RegExp(r'[0-9.]').hasMatch(char);
}

bool _isNamePart(String? char) {
  if (char == null) {
    return false;
  }
  return RegExp(r'[A-Za-z0-9_.$]').hasMatch(char);
}

bool _isReferencePart(String? char) {
  if (char == null) {
    return false;
  }
  return RegExp(r'[A-Za-z0-9$]').hasMatch(char);
}

ExcelImportSheetDraft _inspectSheet(
  String sheetName,
  xls.Sheet sheet, {
  required bool headerRow,
  required List<String> warnings,
}) {
  final rows = sheet.rows;
  final bounds = _resolveSheetBounds(rows, headerRow: headerRow);
  if (bounds.firstNonEmptyRow == null || bounds.columnCount == 0) {
    warnings.add('$sheetName is empty and will not be selected by default.');
    return ExcelImportSheetDraft(
      sourceName: sheetName,
      targetName: sheetName,
      selected: false,
      rowCount: 0,
      columns: const <ExcelImportColumnDraft>[],
      previewRows: const <Map<String, Object?>>[],
    );
  }

  final headerValues = headerRow
      ? _extractHeaderValues(rows[bounds.headerRowIndex!], bounds.columnCount)
      : const <String>[];
  final columnNames = _buildUniqueColumnNames(headerValues, bounds.columnCount);
  final observations = <_ColumnObservation>[
    for (var i = 0; i < bounds.columnCount; i++) _ColumnObservation(),
  ];
  final previewRows = <Map<String, Object?>>[];
  final rowCount = _scanSheetRows(
    rows,
    bounds: bounds,
    columnNames: columnNames,
    observations: observations,
    previewRows: previewRows,
    warnings: warnings,
    sheetName: sheetName,
  );

  final columns = <ExcelImportColumnDraft>[
    for (var i = 0; i < bounds.columnCount; i++)
      ExcelImportColumnDraft(
        sourceIndex: i,
        sourceName: columnNames[i],
        targetName: columnNames[i],
        inferredTargetType: observations[i].inferredTargetType,
        targetType: observations[i].inferredTargetType,
        containsNulls: observations[i].containsNulls || rowCount == 0,
      ),
  ];

  if (rowCount == 0) {
    warnings.add(
      headerRow
          ? '$sheetName has a header row but no data rows.'
          : '$sheetName has no populated rows to import.',
    );
  }

  return ExcelImportSheetDraft(
    sourceName: sheetName,
    targetName: sheetName,
    selected: rowCount > 0,
    rowCount: rowCount,
    columns: columns,
    previewRows: previewRows,
  );
}

int _scanSheetRows(
  List<List<xls.Data?>> rows, {
  required _SheetBounds bounds,
  required List<String> columnNames,
  required List<_ColumnObservation> observations,
  required List<Map<String, Object?>> previewRows,
  required List<String> warnings,
  required String sheetName,
}) {
  var rowCount = 0;
  var warnedAboutFormulaCells = false;

  for (var rowIndex = bounds.dataStartRow; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (_isExcelRowEmpty(row, bounds.columnCount)) {
      continue;
    }
    rowCount++;

    final previewRow = <String, Object?>{};
    for (var columnIndex = 0; columnIndex < bounds.columnCount; columnIndex++) {
      final cellValue = _cellValueAt(row, columnIndex);
      if (!warnedAboutFormulaCells && cellValue is xls.FormulaCellValue) {
        warnings.add(
          '$sheetName contains formula cells. Formula expressions are imported as text.',
        );
        warnedAboutFormulaCells = true;
      }

      observations[columnIndex].observe(cellValue);
      if (previewRows.length < _excelPreviewRowLimit) {
        previewRow[columnNames[columnIndex]] = _normalizeExcelCellValue(
          cellValue,
        );
      }
    }
    if (previewRows.length < _excelPreviewRowLimit) {
      previewRows.add(previewRow);
    }
  }

  return rowCount;
}

_SheetBounds _resolveSheetBounds(
  List<List<xls.Data?>> rows, {
  required bool headerRow,
  int? expectedColumnCount,
}) {
  final columnCount = expectedColumnCount ?? _effectiveColumnCount(rows);
  final firstNonEmptyRow = _firstNonEmptyRowIndex(rows, columnCount);
  if (firstNonEmptyRow == null || columnCount == 0) {
    return const _SheetBounds(
      columnCount: 0,
      firstNonEmptyRow: null,
      headerRowIndex: null,
      dataStartRow: 0,
    );
  }

  final headerRowIndex = headerRow ? firstNonEmptyRow : null;
  return _SheetBounds(
    columnCount: columnCount,
    firstNonEmptyRow: firstNonEmptyRow,
    headerRowIndex: headerRowIndex,
    dataStartRow: headerRow ? firstNonEmptyRow + 1 : firstNonEmptyRow,
  );
}

List<String> _extractHeaderValues(List<xls.Data?> row, int columnCount) {
  return <String>[
    for (var columnIndex = 0; columnIndex < columnCount; columnIndex++)
      _headerNameForCell(_cellValueAt(row, columnIndex)),
  ];
}

List<String> _buildUniqueColumnNames(List<String> rawNames, int columnCount) {
  final used = <String, int>{};
  final names = <String>[];
  for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
    final baseName = columnIndex < rawNames.length
        ? rawNames[columnIndex].trim()
        : '';
    final fallback = 'column_${columnIndex + 1}';
    final candidate = baseName.isEmpty ? fallback : baseName;
    final count = used.update(
      candidate,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    names.add(count == 1 ? candidate : '${candidate}_$count');
  }
  return names;
}

int _effectiveColumnCount(List<List<xls.Data?>> rows) {
  var maxColumnCount = 0;
  for (final row in rows) {
    for (var columnIndex = row.length - 1; columnIndex >= 0; columnIndex--) {
      if (_cellValueAt(row, columnIndex) != null) {
        if (columnIndex + 1 > maxColumnCount) {
          maxColumnCount = columnIndex + 1;
        }
        break;
      }
    }
  }
  return maxColumnCount;
}

int? _firstNonEmptyRowIndex(List<List<xls.Data?>> rows, int columnCount) {
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    if (!_isExcelRowEmpty(rows[rowIndex], columnCount)) {
      return rowIndex;
    }
  }
  return null;
}

bool _isExcelRowEmpty(List<xls.Data?> row, int columnCount) {
  for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
    final value = _normalizeExcelCellValue(_cellValueAt(row, columnIndex));
    if (value is String) {
      if (value.trim().isNotEmpty) {
        return false;
      }
      continue;
    }
    if (value != null) {
      return false;
    }
  }
  return true;
}

xls.CellValue? _cellValueAt(List<xls.Data?> row, int columnIndex) {
  if (columnIndex < 0 || columnIndex >= row.length) {
    return null;
  }
  return row[columnIndex]?.value;
}

String _headerNameForCell(xls.CellValue? value) {
  final normalized = _normalizeExcelCellValue(value);
  return normalized == null ? '' : '$normalized';
}

Object? _normalizeExcelCellValue(xls.CellValue? value) {
  return switch (value) {
    null => null,
    xls.BoolCellValue(:final value) => value,
    xls.IntCellValue(:final value) => value,
    xls.DoubleCellValue(:final value) => value,
    xls.TextCellValue(:final value) => value.toString(),
    xls.FormulaCellValue(:final formula) =>
      formula.startsWith('=') ? formula : '=$formula',
    xls.DateCellValue() => value.asDateTimeUtc(),
    xls.DateTimeCellValue() => value.asDateTimeUtc(),
    xls.TimeCellValue() => value.toString(),
  };
}

void _validateRequestNames(ExcelImportRequest request) {
  final selectedSheets = request.selectedSheets;
  final targetTableNames = <String>{};
  for (final sheet in selectedSheets) {
    final targetTableName = sheet.targetName.trim();
    if (targetTableName.isEmpty) {
      throw const BridgeFailure(
        'Each selected worksheet needs a target DecentDB table name.',
      );
    }
    if (!targetTableNames.add(targetTableName)) {
      throw BridgeFailure(
        'Target table names must be unique. Duplicate: $targetTableName',
      );
    }

    final targetColumnNames = <String>{};
    for (final column in sheet.columns) {
      final targetColumnName = column.targetName.trim();
      if (targetColumnName.isEmpty) {
        throw BridgeFailure(
          'Worksheet ${sheet.sourceName} has an empty target column name.',
        );
      }
      if (!targetColumnNames.add(targetColumnName)) {
        throw BridgeFailure(
          'Worksheet ${sheet.sourceName} has duplicate target column names. Duplicate: $targetColumnName',
        );
      }
    }
  }
}

String _buildCreateTableSql(ExcelImportSheetDraft sheet) {
  final columnSql = <String>[
    for (final column in sheet.columns)
      '${_quoteDecentIdent(column.targetName)} ${column.targetType}',
  ];
  return 'CREATE TABLE ${_quoteDecentIdent(sheet.targetName)} (${columnSql.join(", ")})';
}

String _quoteDecentIdent(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

String _placeholderForType(String targetType, int index) {
  if (_isDecimalType(targetType) || _isUuidType(targetType)) {
    return 'CAST(\$$index AS $targetType)';
  }
  return '\$$index';
}

Object? _adaptImportValue(Object? value, String targetType) {
  if (value == null) {
    return null;
  }
  if (targetType == 'BOOLEAN') {
    if (value is bool) {
      return value;
    }
    if (value is int && (value == 0 || value == 1)) {
      return value == 1;
    }
    if (value is double && (value == 0 || value == 1)) {
      return value == 1;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return value;
  }
  if (targetType == 'TEXT' && value is Uint8List) {
    return formatCellValue(value);
  }
  if (targetType == 'BLOB' && value is String) {
    return Uint8List.fromList(value.codeUnits);
  }
  if (targetType == 'TIMESTAMP' && value is String) {
    final parsed = DateTime.tryParse(value);
    return parsed?.toUtc() ?? value;
  }
  if (targetType == 'TIMESTAMP' && value is DateTime) {
    return value.toUtc();
  }
  if (_isDecimalType(targetType) && value is num) {
    return value.toString();
  }
  return value;
}

bool _isDecimalType(String targetType) {
  return targetType.startsWith('DECIMAL') || targetType.startsWith('NUMERIC');
}

bool _isUuidType(String targetType) {
  return targetType == 'UUID';
}

_LoadedWorkbook _loadWorkbookFromSource(String sourcePath) {
  final preparedSource = prepareExcelWorkbookSource(sourcePath);
  try {
    final workbook = xls.Excel.decodeBytes(
      File(preparedSource.resolvedPath).readAsBytesSync(),
    );
    return _LoadedWorkbook(
      workbook: workbook,
      warnings: preparedSource.warnings,
      dispose: preparedSource.dispose,
    );
  } catch (error) {
    preparedSource.dispose();
    if (p.extension(sourcePath).toLowerCase() != '.xlsx') {
      rethrow;
    }

    final normalizedSource = normalizeExcelWorkbookSource(sourcePath);
    try {
      final workbook = xls.Excel.decodeBytes(
        File(normalizedSource.resolvedPath).readAsBytesSync(),
      );
      return _LoadedWorkbook(
        workbook: workbook,
        warnings: normalizedSource.warnings,
        dispose: normalizedSource.dispose,
      );
    } catch (_) {
      normalizedSource.dispose();
      rethrow;
    }
  }
}

void _throwIfCancelled(bool Function() isCancelled) {
  if (isCancelled()) {
    throw const _ExcelImportCancelledSignal();
  }
}

class _SheetBounds {
  const _SheetBounds({
    required this.columnCount,
    required this.firstNonEmptyRow,
    required this.headerRowIndex,
    required this.dataStartRow,
  });

  final int columnCount;
  final int? firstNonEmptyRow;
  final int? headerRowIndex;
  final int dataStartRow;
}

class _ColumnObservation {
  var sawBool = false;
  var sawInt = false;
  var sawDouble = false;
  var sawTimestamp = false;
  var sawText = false;
  var containsNulls = false;

  void observe(xls.CellValue? value) {
    if (value == null) {
      containsNulls = true;
      return;
    }

    switch (value) {
      case xls.BoolCellValue():
        sawBool = true;
      case xls.IntCellValue():
        sawInt = true;
      case xls.DoubleCellValue():
        sawDouble = true;
      case xls.DateCellValue() || xls.DateTimeCellValue():
        sawTimestamp = true;
      case xls.TimeCellValue() || xls.TextCellValue() || xls.FormulaCellValue():
        sawText = true;
    }
  }

  String get inferredTargetType {
    final categories = <String>{
      if (sawBool) 'bool',
      if (sawInt) 'int',
      if (sawDouble) 'double',
      if (sawTimestamp) 'timestamp',
      if (sawText) 'text',
    };
    if (categories.isEmpty) {
      return 'TEXT';
    }
    if (categories.length > 1) {
      if (categories.length == 2 &&
          categories.contains('int') &&
          categories.contains('double')) {
        return 'FLOAT64';
      }
      return 'TEXT';
    }
    if (sawBool) {
      return 'BOOLEAN';
    }
    if (sawInt) {
      return 'INTEGER';
    }
    if (sawDouble) {
      return 'FLOAT64';
    }
    if (sawTimestamp) {
      return 'TIMESTAMP';
    }
    return 'TEXT';
  }
}

class _ExcelImportCancelled implements Exception {
  const _ExcelImportCancelled(this.summary);

  final ExcelImportSummary summary;
}

class _ExcelImportCancelledSignal implements Exception {
  const _ExcelImportCancelledSignal();
}

class _LoadedWorkbook {
  const _LoadedWorkbook({
    required this.workbook,
    required this.warnings,
    required void Function() dispose,
  }) : _dispose = dispose;

  final xls.Excel workbook;
  final List<String> warnings;
  final void Function() _dispose;

  void dispose() => _dispose();
}
