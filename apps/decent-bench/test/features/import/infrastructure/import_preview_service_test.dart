import 'dart:io';

import 'package:decent_bench/features/import/domain/import_models.dart';
import 'package:decent_bench/features/import/infrastructure/import_format_registry.dart';
import 'package:decent_bench/features/import/infrastructure/import_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late ImportPreviewService service;
  late Directory tempDir;
  final registry = ImportFormatRegistry.instance;

  String resolveHtmlFixturePath(String filename) {
    final candidates = <String>[
      p.normalize(
        p.join(
          Directory.current.path,
          '..',
          '..',
          'test-data',
          'html',
          filename,
        ),
      ),
      p.normalize(
        p.join(Directory.current.path, 'test-data', 'html', filename),
      ),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    throw StateError(
      'Could not locate test-data/html/$filename from ${Directory.current.path}',
    );
  }

  setUp(() async {
    service = ImportPreviewService();
    tempDir = await Directory.systemTemp.createTemp(
      'decent-bench-preview-test-',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('parses delimited files with inferred types', () async {
    final file = File(p.join(tempDir.path, 'people.csv'))
      ..writeAsStringSync('id,name,active\n1,Ada,true\n2,Lin,false\n');

    final inspection = await service.inspect(
      sourcePath: file.path,
      format: registry.forKey(ImportFormatKey.csv),
      options: const GenericImportOptions(),
    );

    expect(inspection.tables, hasLength(1));
    expect(
      inspection.tables.single.columns.map((column) => column.targetType),
      <String>['INTEGER', 'TEXT', 'BOOLEAN'],
    );
  });

  test('parses custom-escaped delimited values', () async {
    final file = File(p.join(tempDir.path, 'quoted.txt'))
      ..writeAsStringSync('id|note\n1|"Ada said \\"hi\\""\n');

    final inspection = await service.inspect(
      sourcePath: file.path,
      format: registry.forKey(ImportFormatKey.genericDelimited),
      options: const GenericImportOptions(
        delimiter: '|',
        quoteCharacter: '"',
        escapeCharacter: '\\',
      ),
    );

    expect(
      inspection.tables.single.previewRows.single['note'],
      'Ada said "hi"',
    );
  });

  test('normalizes JSON arrays into child tables', () async {
    final file = File(p.join(tempDir.path, 'orders.json'))
      ..writeAsStringSync(
        '{"customer":{"id":1,"name":"Ada"},"orders":[{"item":"Keyboard"},{"item":"Mouse"}]}',
      );

    final inspection = await service.inspect(
      sourcePath: file.path,
      format: registry.forKey(ImportFormatKey.json),
      options: const GenericImportOptions(
        structuredStrategy: StructuredImportStrategy.normalize,
      ),
    );

    expect(inspection.tables.length, greaterThan(1));
    expect(
      inspection.tables.any(
        (table) =>
            table.columns.any((column) => column.sourceName == 'parent_id'),
      ),
      isTrue,
    );
  });

  test('flattens NDJSON into one table', () async {
    final file = File(p.join(tempDir.path, 'events.jsonl'))
      ..writeAsStringSync('{"id":1,"kind":"start"}\n{"id":2,"kind":"stop"}\n');

    final inspection = await service.inspect(
      sourcePath: file.path,
      format: registry.forKey(ImportFormatKey.ndjson),
      options: const GenericImportOptions(),
    );

    expect(inspection.tables, hasLength(1));
    expect(inspection.tables.single.rowCount, 2);
  });

  test('normalizes XML repeated elements into related tables', () async {
    final file = File(p.join(tempDir.path, 'catalog.xml'))
      ..writeAsStringSync(
        '<catalog><customer id="1"><name>Ada</name><orders><order><item>Keyboard</item></order><order><item>Mouse</item></order></orders></customer></catalog>',
      );

    final inspection = await service.inspect(
      sourcePath: file.path,
      format: registry.forKey(ImportFormatKey.xml),
      options: const GenericImportOptions(
        structuredStrategy: StructuredImportStrategy.normalize,
      ),
    );

    expect(inspection.tables.length, greaterThan(1));
    expect(
      inspection.tables.any((table) => table.targetName.contains('orders')),
      isTrue,
    );
  });

  test('extracts multiple HTML tables', () async {
    final file = File(p.join(tempDir.path, 'tables.html'))
      ..writeAsStringSync('''
        <html>
          <body>
            <table id="customers"><caption>Customers</caption><tr><th>id</th><th>name</th></tr><tr><td>1</td><td>Ada</td></tr></table>
            <table><tr><th>kind</th><th>count</th></tr><tr><td>open</td><td>2</td></tr></table>
          </body>
        </html>
      ''');

    final inspection = await service.inspect(
      sourcePath: file.path,
      format: registry.forKey(ImportFormatKey.htmlTable),
      options: const GenericImportOptions(),
    );

    expect(inspection.tables, hasLength(2));
    expect(inspection.tables.first.targetName, contains('Customers'));
    expect(inspection.tables.every((table) => table.selected), isTrue);
  });

  test(
    'keeps every detected table selected for checked-in HTML fixtures',
    () async {
      final inspection = await service.inspect(
        sourcePath: resolveHtmlFixturePath('report_tables.html'),
        format: registry.forKey(ImportFormatKey.htmlTable),
        options: const GenericImportOptions(),
      );

      expect(inspection.tables, hasLength(2));
      expect(inspection.tables.every((table) => table.selected), isTrue);
    },
  );
}
