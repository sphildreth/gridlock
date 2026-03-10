import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:decentdb/decentdb.dart';
import 'package:excel/excel.dart' as xls;
import 'package:path/path.dart' as p;

import '../domain/excel_import_models.dart';
import '../domain/workspace_models.dart';

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
  if (p.extension(sourcePath).toLowerCase() == '.xls') {
    throw const BridgeFailure(
      'Legacy `.xls` workbooks are not supported by the current parser yet. Save the workbook as `.xlsx` and retry.',
    );
  }

  final workbook = xls.Excel.decodeBytes(file.readAsBytesSync());
  final warnings = <String>[];
  final sheets = <ExcelImportSheetDraft>[];
  for (final entry in workbook.tables.entries) {
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

  final workbook = _openWorkbook(request.sourcePath);
  final target = Database.open(request.targetPath, libraryPath: libraryPath);
  var transactionOpen = false;
  final rowsCopied = <String, int>{};
  final warnings = <String>[];

  try {
    final existingTables = target.schema.listTables().toSet();
    final colliding = request.selectedSheets
        .map((sheet) => sheet.targetName)
        .where(existingTables.contains)
        .toList();
    if (colliding.isNotEmpty) {
      throw BridgeFailure(
        'Target already contains table(s): ${colliding.join(", ")}. Rename them or choose another DecentDB file.',
      );
    }

    target.begin();
    transactionOpen = true;

    for (var i = 0; i < request.selectedSheets.length; i++) {
      final sheet = request.selectedSheets[i];
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
            totalSheets: request.selectedSheets.length,
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

    for (var i = 0; i < request.selectedSheets.length; i++) {
      final sheet = request.selectedSheets[i];
      final copied = await _copySheetData(
        workbook: workbook,
        target: target,
        request: request,
        sheet: sheet,
        completedSheets: i,
        totalSheets: request.selectedSheets.length,
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

    target.commit();
    transactionOpen = false;

    return ExcelImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      importedTables: request.selectedSheets
          .map((sheet) => sheet.targetName)
          .toList(),
      rowsCopiedByTable: rowsCopied,
      warnings: warnings,
      statusMessage:
          'Imported ${rowsCopied.values.fold<int>(0, (sum, value) => sum + value)} rows from ${request.selectedSheets.length} workbook sheet${request.selectedSheets.length == 1 ? '' : 's'}.',
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

xls.Excel _openWorkbook(String sourcePath) {
  if (p.extension(sourcePath).toLowerCase() == '.xls') {
    throw const BridgeFailure(
      'Legacy `.xls` workbooks are not supported by the current parser yet. Save the workbook as `.xlsx` and retry.',
    );
  }
  return xls.Excel.decodeBytes(File(sourcePath).readAsBytesSync());
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
