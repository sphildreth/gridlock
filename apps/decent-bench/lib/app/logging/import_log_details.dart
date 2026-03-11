import '../../features/import/domain/import_models.dart';
import '../../features/workspace/domain/excel_import_models.dart';
import '../../features/workspace/domain/sql_dump_import_models.dart';
import '../../features/workspace/domain/sqlite_import_models.dart';

Map<String, Object?> buildImportInspectionLogDetails({
  required String sourcePath,
  required int tableCount,
  required List<String> warnings,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return <String, Object?>{
    'source_path': sourcePath,
    'table_count': tableCount,
    'warning_count': warnings.length,
    if (warnings.isNotEmpty) 'warnings': warnings,
    ...extra,
  };
}

Map<String, Object?> buildExcelImportRequestLogDetails(
  ExcelImportRequest request,
) {
  return <String, Object?>{
    'job_id': request.jobId,
    'source_path': request.sourcePath,
    'target_path': request.targetPath,
    'import_into_existing_target': request.importIntoExistingTarget,
    'replace_existing_target': request.replaceExistingTarget,
    'header_row': request.headerRow,
    'selected_sheet_count': request.selectedSheets.length,
    'selected_row_estimate': request.selectedSheets.fold<int>(
      0,
      (sum, sheet) => sum + sheet.rowCount,
    ),
    'selected_sheets': request.selectedSheets
        .map((sheet) => sheet.targetName)
        .toList(growable: false),
  };
}

Map<String, Object?> buildExcelImportSummaryLogDetails(
  ExcelImportSummary summary,
) {
  return _buildSummaryDetails(
    jobId: summary.jobId,
    sourcePath: summary.sourcePath,
    targetPath: summary.targetPath,
    importedTables: summary.importedTables,
    importedViews: summary.importedViews,
    rowsCopiedByTable: summary.rowsCopiedByTable,
    warnings: summary.warnings,
    rolledBack: summary.rolledBack,
    extra: <String, Object?>{'status_message': summary.statusMessage},
  );
}

Map<String, Object?> buildSqlDumpImportRequestLogDetails(
  SqlDumpImportRequest request,
) {
  return <String, Object?>{
    'job_id': request.jobId,
    'source_path': request.sourcePath,
    'target_path': request.targetPath,
    'import_into_existing_target': request.importIntoExistingTarget,
    'replace_existing_target': request.replaceExistingTarget,
    'encoding': request.encoding,
    'selected_table_count': request.selectedTables.length,
    'selected_row_estimate': request.selectedTables.fold<int>(
      0,
      (sum, table) => sum + table.rowCount,
    ),
    'selected_tables': request.selectedTables
        .map((table) => table.targetName)
        .toList(growable: false),
  };
}

Map<String, Object?> buildSqlDumpImportSummaryLogDetails(
  SqlDumpImportSummary summary,
) {
  return _buildSummaryDetails(
    jobId: summary.jobId,
    sourcePath: summary.sourcePath,
    targetPath: summary.targetPath,
    importedTables: summary.importedTables,
    rowsCopiedByTable: summary.rowsCopiedByTable,
    warnings: summary.warnings,
    rolledBack: summary.rolledBack,
    extra: <String, Object?>{
      'status_message': summary.statusMessage,
      'skipped_statement_count': summary.skippedStatementCount,
      if (summary.skippedStatements.isNotEmpty)
        'skipped_statements': summary.skippedStatements
            .map(
              (statement) => <String, Object?>{
                'ordinal': statement.ordinal,
                'kind': statement.kind,
                'reason': statement.reason,
                'snippet': statement.snippet,
              },
            )
            .toList(growable: false),
    },
  );
}

Map<String, Object?> buildSqliteImportRequestLogDetails(
  SqliteImportRequest request,
) {
  return <String, Object?>{
    'job_id': request.jobId,
    'source_path': request.sourcePath,
    'target_path': request.targetPath,
    'import_into_existing_target': request.importIntoExistingTarget,
    'replace_existing_target': request.replaceExistingTarget,
    'selected_table_count': request.selectedTables.length,
    'selected_row_estimate': request.selectedTables.fold<int>(
      0,
      (sum, table) => sum + table.rowCount,
    ),
    'selected_tables': request.selectedTables
        .map((table) => table.targetName)
        .toList(growable: false),
  };
}

Map<String, Object?> buildSqliteImportSummaryLogDetails(
  SqliteImportSummary summary,
) {
  return _buildSummaryDetails(
    jobId: summary.jobId,
    sourcePath: summary.sourcePath,
    targetPath: summary.targetPath,
    importedTables: summary.importedTables,
    rowsCopiedByTable: summary.rowsCopiedByTable,
    warnings: summary.warnings,
    rolledBack: summary.rolledBack,
    extra: <String, Object?>{
      'status_message': summary.statusMessage,
      'index_count': summary.indexesCreated.length,
      if (summary.indexesCreated.isNotEmpty)
        'indexes_created': summary.indexesCreated,
      'skipped_item_count': summary.skippedItems.length,
      if (summary.skippedItems.isNotEmpty)
        'skipped_items': summary.skippedItems
            .map(
              (item) => <String, Object?>{
                'name': item.name,
                'reason': item.reason,
                'table_name': item.tableName,
              },
            )
            .toList(growable: false),
    },
  );
}

Map<String, Object?> buildGenericImportRequestLogDetails({
  required GenericImportRequest request,
  required String formatLabel,
}) {
  return <String, Object?>{
    'job_id': request.jobId,
    'source_path': request.sourcePath,
    'target_path': request.targetPath,
    'format_key': request.formatKey.name,
    'format_label': formatLabel,
    'import_into_existing_target': request.importIntoExistingTarget,
    'replace_existing_target': request.replaceExistingTarget,
    'selected_table_count': request.selectedTables.length,
    'selected_row_estimate': request.selectedTables.fold<int>(
      0,
      (sum, table) => sum + table.rowCount,
    ),
    'selected_tables': request.selectedTables
        .map((table) => table.targetName)
        .toList(growable: false),
    'options': request.options.toMap(),
  };
}

Map<String, Object?> buildGenericImportSummaryLogDetails(
  GenericImportSummary summary,
) {
  return _buildSummaryDetails(
    jobId: summary.jobId,
    sourcePath: summary.sourcePath,
    targetPath: summary.targetPath,
    importedTables: summary.importedTables,
    rowsCopiedByTable: summary.rowsCopiedByTable,
    warnings: summary.warnings,
    rolledBack: summary.rolledBack,
    extra: <String, Object?>{
      'format_label': summary.formatLabel,
      'status_message': summary.statusMessage,
    },
  );
}

Map<String, Object?> _buildSummaryDetails({
  required String jobId,
  required String sourcePath,
  required String targetPath,
  required List<String> importedTables,
  List<String> importedViews = const <String>[],
  required Map<String, int> rowsCopiedByTable,
  required List<String> warnings,
  required bool rolledBack,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  return <String, Object?>{
    'job_id': jobId,
    'source_path': sourcePath,
    'target_path': targetPath,
    'imported_table_count': importedTables.length,
    'imported_tables': importedTables,
    'imported_view_count': importedViews.length,
    'imported_views': importedViews,
    'total_rows_copied': rowsCopiedByTable.values.fold<int>(
      0,
      (sum, value) => sum + value,
    ),
    'rows_copied_by_table': rowsCopiedByTable,
    'warning_count': warnings.length,
    if (warnings.isNotEmpty) 'warnings': warnings,
    'rolled_back': rolledBack,
    ...extra,
  };
}
