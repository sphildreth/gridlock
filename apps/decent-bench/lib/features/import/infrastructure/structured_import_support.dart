import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../domain/import_models.dart';
import 'type_inference_service.dart';

MaterializedImportSource materializeStructuredSourceSync({
  required String sourcePath,
  required ImportFormatDefinition format,
  required GenericImportOptions options,
  required TypeInferenceService typeInferenceService,
}) {
  final file = File(sourcePath);
  if (!file.existsSync()) {
    throw StateError('Structured source file does not exist: $sourcePath');
  }

  final warnings = <String>[];
  final rootName = typeInferenceService.sanitizeIdentifier(
    p.basenameWithoutExtension(sourcePath),
    fallbackPrefix: 'document',
  );
  final source = _readStructuredSource(
    sourcePath: sourcePath,
    format: format,
    options: options,
    warnings: warnings,
  );

  final tables = options.structuredStrategy == StructuredImportStrategy.flatten
      ? _flattenToTables(source: source, rootName: rootName)
      : _normalizeToTables(source: source, rootName: rootName);

  return MaterializedImportSource(
    sourcePath: sourcePath,
    format: format,
    options: options,
    tables: tables,
    warnings: warnings,
    explanation: options.structuredStrategy == StructuredImportStrategy.flatten
        ? 'Flattening nested structures into a query-friendly table. Nested arrays become JSON text so the original structure is still inspectable.'
        : 'Normalizing repeated arrays or elements into child tables and adding `parent_id` links so relationships remain visible after import.',
  );
}

GenericImportInspection inspectStructuredSourceSync({
  required String sourcePath,
  required ImportFormatDefinition format,
  required GenericImportOptions options,
  required TypeInferenceService typeInferenceService,
}) {
  final materialized = materializeStructuredSourceSync(
    sourcePath: sourcePath,
    format: format,
    options: options,
    typeInferenceService: typeInferenceService,
  );
  final drafts = materialized.tables
      .map((table) {
        final orderedKeys = _orderedKeys(table.rows);
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

dynamic _readStructuredSource({
  required String sourcePath,
  required ImportFormatDefinition format,
  required GenericImportOptions options,
  required List<String> warnings,
}) {
  final file = File(sourcePath);
  final bytes = file.readAsBytesSync();
  final text = _decodeStructuredText(bytes, options.encoding, warnings);

  switch (format.key) {
    case ImportFormatKey.json:
      return jsonDecode(text);
    case ImportFormatKey.ndjson:
      return LineSplitter.split(text)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map<dynamic>((line) => jsonDecode(line))
          .toList(growable: false);
    case ImportFormatKey.xml:
      final document = XmlDocument.parse(text);
      final root = document.rootElement;
      return <String, Object?>{root.name.local: _xmlElementToObject(root)};
    default:
      throw StateError(
        'Unsupported structured source format: ${format.key.name}',
      );
  }
}

String _decodeStructuredText(
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

dynamic _xmlElementToObject(XmlElement element) {
  final childElements = element.children.whereType<XmlElement>().toList(
    growable: false,
  );
  final text = element.children
      .whereType<XmlText>()
      .map((node) => node.value.trim())
      .where((value) => value.isNotEmpty)
      .join(' ');

  if (childElements.isEmpty && element.attributes.isEmpty) {
    return text.isEmpty ? null : text;
  }

  final result = <String, Object?>{};
  for (final attribute in element.attributes) {
    result['attr_${attribute.name.local}'] = attribute.value;
  }
  if (text.isNotEmpty) {
    result['text'] = text;
  }
  final grouped = <String, List<Object?>>{};
  for (final child in childElements) {
    grouped
        .putIfAbsent(child.name.local, () => <Object?>[])
        .add(_xmlElementToObject(child));
  }
  for (final entry in grouped.entries) {
    result[entry.key] = entry.value.length == 1
        ? entry.value.first
        : entry.value;
  }
  return result;
}

List<MaterializedImportTableData> _flattenToTables({
  required dynamic source,
  required String rootName,
}) {
  final records = _recordsFromStructuredRoot(source);
  final rows = <Map<String, Object?>>[
    for (final record in records) _flattenRecord(record),
  ];
  return <MaterializedImportTableData>[
    MaterializedImportTableData(
      sourceId: rootName,
      sourceName: rootName,
      suggestedTargetName: rootName,
      rows: rows,
      description: 'Flattened nested objects into one table.',
    ),
  ];
}

List<MaterializedImportTableData> _normalizeToTables({
  required dynamic source,
  required String rootName,
}) {
  final collector = _NormalizedTableCollector();
  final records = _recordsFromStructuredRoot(source);
  for (final record in records) {
    collector.addRecord(rootName, record, parentId: null);
  }
  return collector.buildDrafts();
}

List<dynamic> _recordsFromStructuredRoot(dynamic source) {
  if (source is List) {
    return source;
  }
  if (source is Map<String, Object?> && source.length == 1) {
    final onlyValue = source.values.first;
    if (onlyValue is List) {
      return onlyValue;
    }
    if (onlyValue is Map ||
        onlyValue is String ||
        onlyValue is num ||
        onlyValue is bool) {
      return <dynamic>[onlyValue];
    }
  }
  return <dynamic>[source];
}

Map<String, Object?> _flattenRecord(dynamic value, {String prefix = ''}) {
  final result = <String, Object?>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final key = prefix.isEmpty ? '${entry.key}' : '${prefix}__${entry.key}';
      final entryValue = entry.value;
      if (entryValue is Map) {
        result.addAll(_flattenRecord(entryValue, prefix: key));
      } else if (entryValue is List) {
        result[key] = jsonEncode(entryValue);
      } else {
        result[key] = entryValue;
      }
    }
    return result;
  }
  result[prefix.isEmpty ? 'value' : prefix] = value;
  return result;
}

List<String> _orderedKeys(List<Map<String, Object?>> rows) {
  final keys = <String>[];
  final seen = <String>{};
  for (final row in rows) {
    for (final key in row.keys) {
      if (seen.add(key)) {
        keys.add(key);
      }
    }
  }
  return keys;
}

class _NormalizedTableCollector {
  final Map<String, List<Map<String, Object?>>> _rowsByTable =
      <String, List<Map<String, Object?>>>{};
  final Map<String, String> _descriptions = <String, String>{};
  int _nextId = 1;

  void addRecord(String tableName, dynamic raw, {int? parentId}) {
    if (raw is List) {
      for (final item in raw) {
        addRecord(tableName, item, parentId: parentId);
      }
      return;
    }

    final row = <String, Object?>{'_import_id': _nextId++};
    if (parentId != null) {
      row['parent_id'] = parentId;
    }

    if (raw is Map) {
      final childCollections = <MapEntry<String, dynamic>>[];
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          childCollections.add(MapEntry(key, value));
          continue;
        }
        if (value is Map) {
          if (_containsNestedList(value)) {
            _collectNestedChildren(
              prefix: key,
              value: value,
              row: row,
              childCollections: childCollections,
            );
            continue;
          }
          final flattened = _flattenRecord(value, prefix: key);
          row.addAll(flattened);
          continue;
        }
        row[key] = value;
      }
      _rowsByTable
          .putIfAbsent(tableName, () => <Map<String, Object?>>[])
          .add(row);
      _descriptions[tableName] ??= childCollections.isEmpty
          ? 'Normalized table extracted from the source structure.'
          : 'Normalized table with child tables linked by `parent_id`.';
      final rowId = row['_import_id'] as int;
      for (final child in childCollections) {
        addRecord('${tableName}_${child.key}', child.value, parentId: rowId);
      }
      return;
    }

    row['value'] = raw;
    _rowsByTable
        .putIfAbsent(tableName, () => <Map<String, Object?>>[])
        .add(row);
    _descriptions[tableName] ??=
        'Scalar values stored in a dedicated child table.';
  }

  List<MaterializedImportTableData> buildDrafts() {
    final drafts = <MaterializedImportTableData>[];
    for (final entry in _rowsByTable.entries) {
      drafts.add(
        MaterializedImportTableData(
          sourceId: entry.key,
          sourceName: entry.key,
          suggestedTargetName: entry.key,
          rows: entry.value,
          description: _descriptions[entry.key],
        ),
      );
    }
    drafts.sort((left, right) => left.sourceName.compareTo(right.sourceName));
    return drafts;
  }
}

bool _containsNestedList(dynamic value) {
  if (value is List) {
    return true;
  }
  if (value is Map) {
    return value.values.any(_containsNestedList);
  }
  return false;
}

void _collectNestedChildren({
  required String prefix,
  required Map value,
  required Map<String, Object?> row,
  required List<MapEntry<String, dynamic>> childCollections,
}) {
  for (final entry in value.entries) {
    final nestedKey = '${prefix}_${entry.key}';
    final nestedValue = entry.value;
    if (nestedValue is List) {
      childCollections.add(MapEntry(nestedKey, nestedValue));
      continue;
    }
    if (nestedValue is Map) {
      if (_containsNestedList(nestedValue)) {
        _collectNestedChildren(
          prefix: nestedKey,
          value: nestedValue,
          row: row,
          childCollections: childCollections,
        );
        continue;
      }
      row.addAll(_flattenRecord(nestedValue, prefix: nestedKey));
      continue;
    }
    row[nestedKey] = nestedValue;
  }
}
