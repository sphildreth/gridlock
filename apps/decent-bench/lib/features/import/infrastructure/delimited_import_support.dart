import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/import_models.dart';
import 'type_inference_service.dart';

MaterializedImportSource materializeDelimitedSourceSync({
  required String sourcePath,
  required ImportFormatDefinition format,
  required GenericImportOptions options,
  required TypeInferenceService typeInferenceService,
}) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    throw StateError('Delimited source file does not exist: $sourcePath');
  }

  final bytes = file.readAsBytesSync();
  final decoded = _decodeText(bytes, options.encoding);
  final sniffedDelimiter = format.key == ImportFormatKey.csv
      ? ','
      : format.key == ImportFormatKey.tsv
      ? '\t'
      : _detectDelimiter(decoded.text);
  final resolvedOptions = options.copyWith(
    delimiter: options.delimiter.isEmpty ? sniffedDelimiter : options.delimiter,
  );
  final parseResult = parseDelimitedText(
    decoded.text,
    delimiter: resolvedOptions.delimiter,
    quoteCharacter: resolvedOptions.quoteCharacter,
    escapeCharacter: resolvedOptions.escapeCharacter,
  );
  final rows = parseResult.rows
      .where((row) => row.any((value) => value.trim().isNotEmpty))
      .toList();
  if (rows.isEmpty) {
    throw StateError('No non-empty rows were found in $sourcePath.');
  }

  final warnings = <String>[...decoded.warnings, ...parseResult.warnings];
  final headerValues = resolvedOptions.headerRow ? rows.first : null;
  final dataRows = resolvedOptions.headerRow ? rows.skip(1).toList() : rows;
  final columnCount = rows.fold<int>(
    0,
    (max, row) => row.length > max ? row.length : max,
  );
  final headerNames = resolvedOptions.headerRow
      ? List<String>.generate(
          columnCount,
          (index) =>
              index < headerValues!.length &&
                  headerValues[index].trim().isNotEmpty
              ? headerValues[index].trim()
              : 'column_${index + 1}',
        )
      : List<String>.generate(columnCount, (index) => 'column_${index + 1}');
  final distinctNames = typeInferenceService.distinctTargetNames(
    headerNames,
    fallbackPrefix: 'column',
  );

  var skippedRows = 0;
  final tableRows = <Map<String, Object?>>[];
  for (final row in dataRows) {
    if (row.isEmpty || row.every((value) => value.trim().isEmpty)) {
      continue;
    }
    if (row.length != columnCount &&
        resolvedOptions.malformedRowStrategy ==
            DelimitedMalformedRowStrategy.skipRow) {
      skippedRows++;
      continue;
    }
    final normalizedRow = List<String>.from(row);
    if (normalizedRow.length < columnCount) {
      normalizedRow.addAll(
        List<String>.filled(columnCount - normalizedRow.length, ''),
      );
    }
    if (normalizedRow.length > columnCount) {
      normalizedRow.removeRange(columnCount, normalizedRow.length);
      if (!warnings.contains(
        'Rows with extra fields are truncated to the detected column count.',
      )) {
        warnings.add(
          'Rows with extra fields are truncated to the detected column count.',
        );
      }
    }
    final mapped = <String, Object?>{};
    for (var index = 0; index < columnCount; index++) {
      final value = normalizedRow[index].trim();
      mapped[distinctNames[index]] = value.isEmpty ? null : value;
    }
    tableRows.add(mapped);
  }
  if (skippedRows > 0) {
    warnings.add(
      'Skipped $skippedRows malformed row${skippedRows == 1 ? '' : 's'} while previewing the file.',
    );
  }

  final tableName = typeInferenceService.sanitizeIdentifier(
    p.basenameWithoutExtension(sourcePath),
    fallbackPrefix: 'imported_table',
  );

  return MaterializedImportSource(
    sourcePath: sourcePath,
    format: format,
    options: resolvedOptions,
    tables: <MaterializedImportTableData>[
      MaterializedImportTableData(
        sourceId: 'primary_table',
        sourceName: p.basename(sourcePath),
        suggestedTargetName: tableName,
        rows: tableRows,
        description:
            'Detected $columnCount column${columnCount == 1 ? '' : 's'} with delimiter `${_displayDelimiter(resolvedOptions.delimiter)}`.',
        warnings: skippedRows > 0
            ? <String>[
                'Skipped $skippedRows malformed row${skippedRows == 1 ? '' : 's'} during preview.',
              ]
            : const <String>[],
      ),
    ],
    warnings: warnings,
    explanation:
        'Previewing the delimited source as one DecentDB table with inferred column types. You can adjust the delimiter, header setting, and target column types before import.',
  );
}

GenericImportInspection inspectDelimitedSourceSync({
  required String sourcePath,
  required ImportFormatDefinition format,
  required GenericImportOptions options,
  required TypeInferenceService typeInferenceService,
}) {
  final materialized = materializeDelimitedSourceSync(
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
        final targetNames = typeInferenceService.distinctTargetNames(
          columns.map((column) => column.targetName),
          fallbackPrefix: 'column',
        );
        final adjustedColumns = <ImportColumnDraft>[
          for (var i = 0; i < columns.length; i++)
            columns[i].copyWith(targetName: targetNames[i]),
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

class ParsedDelimitedText {
  const ParsedDelimitedText({required this.rows, required this.warnings});

  final List<List<String>> rows;
  final List<String> warnings;
}

class DecodedText {
  const DecodedText({required this.text, required this.warnings});

  final String text;
  final List<String> warnings;
}

DecodedText _decodeText(List<int> bytes, GenericImportEncoding encoding) {
  return switch (encoding) {
    GenericImportEncoding.utf8 => DecodedText(
      text: utf8.decode(bytes),
      warnings: const <String>[],
    ),
    GenericImportEncoding.latin1 => DecodedText(
      text: latin1.decode(bytes),
      warnings: const <String>[],
    ),
    GenericImportEncoding.auto => _decodeAuto(bytes),
  };
}

DecodedText _decodeAuto(List<int> bytes) {
  try {
    return DecodedText(text: utf8.decode(bytes), warnings: const <String>[]);
  } on FormatException {
    return DecodedText(
      text: latin1.decode(bytes),
      warnings: const <String>[
        'The file was decoded as Latin-1 after UTF-8 decoding failed.',
      ],
    );
  }
}

String _displayDelimiter(String delimiter) {
  return delimiter == '\t' ? r'\t' : delimiter;
}

String _detectDelimiter(String text) {
  final lines = LineSplitter.split(text)
      .map((line) => line.trimRight())
      .where((line) => line.isNotEmpty)
      .take(10)
      .toList(growable: false);
  if (lines.isEmpty) {
    return ',';
  }
  final candidates = <String>[',', '\t', ';', '|'];
  var bestDelimiter = ',';
  var bestScore = -1;
  for (final delimiter in candidates) {
    final counts = lines
        .map((line) => _countDelimiter(line, delimiter))
        .toList();
    final distinct = counts.toSet();
    final total = counts.fold<int>(0, (sum, value) => sum + value);
    final score = total > 0 ? (distinct.length == 1 ? total + 100 : total) : -1;
    if (score > bestScore) {
      bestDelimiter = delimiter;
      bestScore = score;
    }
  }
  return bestDelimiter;
}

int _countDelimiter(String line, String delimiter) {
  return delimiter.runes.isEmpty ? 0 : line.split(delimiter).length - 1;
}

ParsedDelimitedText parseDelimitedText(
  String text, {
  required String delimiter,
  required String quoteCharacter,
  required String escapeCharacter,
}) {
  final rows = <List<String>>[];
  final warnings = <String>[];
  final row = <String>[];
  final buffer = StringBuffer();
  final quote = quoteCharacter.isEmpty ? '"' : quoteCharacter;
  final escape = escapeCharacter.isEmpty ? quote : escapeCharacter;
  var inQuotes = false;
  var index = 0;

  void flushField() {
    row.add(buffer.toString());
    buffer.clear();
  }

  void flushRow() {
    rows.add(List<String>.from(row));
    row.clear();
  }

  while (index < text.length) {
    final current = text[index];
    final next = index + 1 < text.length ? text[index + 1] : null;

    if (inQuotes && escape != quote && current == escape && next == quote) {
      buffer.write(quote);
      index += 2;
      continue;
    }

    if (current == quote) {
      if (inQuotes && next == quote) {
        buffer.write(quote);
        index += 2;
        continue;
      }
      inQuotes = !inQuotes;
      index++;
      continue;
    }

    if (!inQuotes && text.startsWith(delimiter, index)) {
      flushField();
      index += delimiter.length;
      continue;
    }

    if (!inQuotes && current == '\n') {
      flushField();
      flushRow();
      index++;
      continue;
    }

    if (!inQuotes && current == '\r') {
      flushField();
      flushRow();
      index += next == '\n' ? 2 : 1;
      continue;
    }

    buffer.write(current);
    index++;
  }

  if (inQuotes) {
    warnings.add('The file ended while a quoted field was still open.');
  }
  if (buffer.isNotEmpty || row.isNotEmpty) {
    flushField();
    flushRow();
  }

  return ParsedDelimitedText(rows: rows, warnings: warnings);
}
