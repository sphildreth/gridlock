import 'package:decent_bench/app/logging/import_log_details.dart';
import 'package:decent_bench/features/import/domain/import_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildGenericImportRequestLogDetails includes table and option stats', () {
    const request = GenericImportRequest(
      jobId: 'job-1',
      sourcePath: '/tmp/source.csv',
      targetPath: '/tmp/target.ddb',
      importIntoExistingTarget: false,
      replaceExistingTarget: true,
      formatKey: ImportFormatKey.csv,
      options: GenericImportOptions(delimiter: ';'),
      tables: <ImportTableDraft>[
        ImportTableDraft(
          sourceId: 'people',
          sourceName: 'people',
          targetName: 'imported_people',
          selected: true,
          rowCount: 3,
          columns: <ImportColumnDraft>[
            ImportColumnDraft(
              sourceName: 'id',
              targetName: 'id',
              inferredTargetType: 'INTEGER',
              targetType: 'INTEGER',
              containsNulls: false,
            ),
          ],
          previewRows: <Map<String, Object?>>[
            <String, Object?>{'id': 1},
          ],
        ),
      ],
    );

    final details = buildGenericImportRequestLogDetails(
      request: request,
      formatLabel: 'CSV',
    );

    expect(details['job_id'], 'job-1');
    expect(details['selected_table_count'], 1);
    expect(details['selected_row_estimate'], 3);
    expect(details['selected_tables'], <String>['imported_people']);
    expect(details['format_label'], 'CSV');
    expect((details['options'] as Map<String, Object?>)['delimiter'], ';');
  });

  test('buildGenericImportSummaryLogDetails includes copied row stats', () {
    const summary = GenericImportSummary(
      jobId: 'job-1',
      sourcePath: '/tmp/source.csv',
      targetPath: '/tmp/target.ddb',
      formatLabel: 'CSV',
      importedTables: <String>['imported_people'],
      rowsCopiedByTable: <String, int>{'imported_people': 3},
      warnings: <String>['Header row was inferred automatically.'],
      statusMessage: 'Imported 3 rows.',
      rolledBack: false,
    );

    final details = buildGenericImportSummaryLogDetails(summary);

    expect(details['total_rows_copied'], 3);
    expect(details['imported_table_count'], 1);
    expect(
      details['rows_copied_by_table'],
      <String, int>{'imported_people': 3},
    );
    expect(details['warning_count'], 1);
    expect(
      details['warnings'],
      <String>['Header row was inferred automatically.'],
    );
    expect(details['format_label'], 'CSV');
  });
}
