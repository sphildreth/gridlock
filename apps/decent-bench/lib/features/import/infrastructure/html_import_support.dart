import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../domain/import_models.dart';
import 'type_inference_service.dart';

MaterializedImportSource materializeHtmlTableSourceSync({
  required String sourcePath,
  required ImportFormatDefinition format,
  required GenericImportOptions options,
  required TypeInferenceService typeInferenceService,
}) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    throw StateError('HTML source file does not exist: $sourcePath');
  }

  final warnings = <String>[];
  final text = _decodeHtmlText(
    file.readAsBytesSync(),
    options.encoding,
    warnings,
  );
  final document = html_parser.parse(text);
  final tables = document
      .querySelectorAll('table')
      .where(_isTopLevelTable)
      .toList();
  if (tables.isEmpty) {
    throw StateError(
      'No top-level <table> elements were found in $sourcePath.',
    );
  }

  final drafts = <MaterializedImportTableData>[];
  for (var index = 0; index < tables.length; index++) {
    final table = tables[index];
    final parsed = _parseTable(table, index: index, options: options);
    if (parsed.rows.isEmpty) {
      continue;
    }
    final orderedNames = typeInferenceService.distinctTargetNames(
      parsed.headerNames,
      fallbackPrefix: 'column',
    );
    final mappedRows = <Map<String, Object?>>[
      for (final row in parsed.rows)
        <String, Object?>{
          for (
            var columnIndex = 0;
            columnIndex < orderedNames.length;
            columnIndex++
          )
            orderedNames[columnIndex]:
                columnIndex < row.length && row[columnIndex].trim().isNotEmpty
                ? row[columnIndex].trim()
                : null,
        },
    ];
    final inferredName = parsed.caption?.trim().isNotEmpty == true
        ? parsed.caption!.trim()
        : parsed.tableId?.trim().isNotEmpty == true
        ? parsed.tableId!.trim()
        : '${p.basenameWithoutExtension(sourcePath)}_table_${index + 1}';
    drafts.add(
      MaterializedImportTableData(
        sourceId: 'table_${index + 1}',
        sourceName: parsed.caption ?? parsed.tableId ?? 'Table ${index + 1}',
        suggestedTargetName: typeInferenceService.sanitizeIdentifier(
          inferredName,
          fallbackPrefix: 'html_table',
        ),
        rows: mappedRows,
        description: _buildDescription(parsed),
        warnings: parsed.warnings,
      ),
    );
    warnings.addAll(parsed.warnings);
  }

  if (tables.any((table) => table.querySelector('table') != null)) {
    warnings.add(
      'Nested tables were detected. Decent Bench imports only top-level table structures in this build.',
    );
  }

  return MaterializedImportSource(
    sourcePath: sourcePath,
    format: format,
    options: options,
    tables: drafts,
    warnings: warnings,
    explanation:
        'Each detected HTML table becomes its own DecentDB table draft. Captions and `id` attributes are used to suggest target names when available.',
  );
}

GenericImportInspection inspectHtmlTableSourceSync({
  required String sourcePath,
  required ImportFormatDefinition format,
  required GenericImportOptions options,
  required TypeInferenceService typeInferenceService,
}) {
  final materialized = materializeHtmlTableSourceSync(
    sourcePath: sourcePath,
    format: format,
    options: options,
    typeInferenceService: typeInferenceService,
  );
  final drafts = materialized.tables
      .map((table) {
        final orderedKeys = table.rows.isEmpty
            ? <String>[]
            : table.rows.first.keys.toList();
        final columns = typeInferenceService.inferColumns(
          table.rows,
          orderedKeys,
        );
        final targetColumns = typeInferenceService.distinctTargetNames(
          columns.map((column) => column.targetName),
          fallbackPrefix: 'column',
        );
        final adjustedColumns = <ImportColumnDraft>[
          for (var columnIndex = 0; columnIndex < columns.length; columnIndex++)
            columns[columnIndex].copyWith(
              targetName: targetColumns[columnIndex],
            ),
        ];
        return ImportTableDraft(
          sourceId: table.sourceId,
          sourceName: table.sourceName,
          targetName: table.suggestedTargetName,
          selected: true,
          rowCount: table.rows.length,
          columns: adjustedColumns,
          previewRows: table.rows
              .take(genericImportPreviewRowLimit)
              .toList(growable: false),
          description: table.description,
          warnings: table.warnings,
        );
      })
      .toList(growable: false);
  return GenericImportInspection(
    sourcePath: materialized.sourcePath,
    format: materialized.format,
    options: materialized.options,
    tables: drafts,
    warnings: materialized.warnings,
    explanation: materialized.explanation,
  );
}

String _decodeHtmlText(
  List<int> bytes,
  GenericImportEncoding encoding,
  List<String> warnings,
) {
  if (encoding == GenericImportEncoding.latin1) {
    return latin1.decode(bytes);
  }
  if (encoding == GenericImportEncoding.utf8) {
    return utf8.decode(bytes);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    warnings.add(
      'The file was decoded as Latin-1 after UTF-8 decoding failed.',
    );
    return latin1.decode(bytes);
  }
}

bool _isTopLevelTable(html_dom.Element table) {
  var current = table.parent;
  while (current != null) {
    if (current.localName == 'table') {
      return false;
    }
    current = current.parent;
  }
  return true;
}

class _ParsedHtmlTable {
  const _ParsedHtmlTable({
    required this.headerNames,
    required this.rows,
    required this.caption,
    required this.tableId,
    required this.warnings,
  });

  final List<String> headerNames;
  final List<List<String>> rows;
  final String? caption;
  final String? tableId;
  final List<String> warnings;
}

_ParsedHtmlTable _parseTable(
  html_dom.Element table, {
  required int index,
  required GenericImportOptions options,
}) {
  final warnings = <String>[];
  final caption = table.querySelector('caption')?.text.trim();
  final tableId = table.id.isEmpty ? null : table.id;
  final rows = <List<String>>[];
  List<String>? headerNames;

  final rowElements = table
      .querySelectorAll('tr')
      .where((row) {
        return !_isRowInsideNestedTable(row, table);
      })
      .toList(growable: false);
  for (var rowIndex = 0; rowIndex < rowElements.length; rowIndex++) {
    final row = rowElements[rowIndex];
    final cells = row.children
        .where((child) {
          return child.localName == 'th' || child.localName == 'td';
        })
        .toList(growable: false);
    if (cells.isEmpty) {
      continue;
    }
    final values = cells
        .map((cell) => cell.text.trim())
        .toList(growable: false);
    final hasHeaderCells = cells.any((cell) => cell.localName == 'th');
    if (headerNames == null &&
        (hasHeaderCells || (rowIndex == 0 && options.headerRow))) {
      headerNames = values
          .map(
            (value) =>
                value.isEmpty ? 'column_${values.indexOf(value) + 1}' : value,
          )
          .toList(growable: false);
      continue;
    }
    rows.add(values);
  }

  if (headerNames == null) {
    final width = rows.fold<int>(
      0,
      (max, row) => row.length > max ? row.length : max,
    );
    headerNames = List<String>.generate(
      width,
      (column) => 'column_${column + 1}',
    );
  }

  final resolvedHeaderNames = headerNames;
  if (rows.any((row) => row.length != resolvedHeaderNames.length)) {
    warnings.add(
      'One or more HTML rows had a different number of cells than the inferred header. Missing cells are imported as null.',
    );
  }

  return _ParsedHtmlTable(
    headerNames: resolvedHeaderNames,
    rows: rows,
    caption: caption,
    tableId: tableId,
    warnings: warnings,
  );
}

bool _isRowInsideNestedTable(html_dom.Element row, html_dom.Element table) {
  var current = row.parent;
  while (current != null && current != table) {
    if (current.localName == 'table') {
      return true;
    }
    current = current.parent;
  }
  return false;
}

String _buildDescription(_ParsedHtmlTable parsed) {
  final parts = <String>[];
  if (parsed.caption != null && parsed.caption!.isNotEmpty) {
    parts.add('Caption: ${parsed.caption}');
  }
  if (parsed.tableId != null && parsed.tableId!.isNotEmpty) {
    parts.add('id=${parsed.tableId}');
  }
  if (parts.isEmpty) {
    return 'Top-level HTML table extracted from the source page.';
  }
  return parts.join(' | ');
}
