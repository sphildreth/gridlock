import 'dart:convert';
import 'dart:io';

import 'package:decent_bench/features/workspace/domain/excel_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sql_dump_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sqlite_import_models.dart';
import 'package:decent_bench/features/workspace/domain/workspace_models.dart';
import 'package:decent_bench/features/workspace/infrastructure/decentdb_bridge.dart';
import 'package:decent_bench/features/workspace/infrastructure/native_library_resolver.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

class _FixedResolver extends NativeLibraryResolver {
  _FixedResolver(this.path);

  final String path;

  @override
  Future<String> resolve() async => path;
}

void main() {
  const defaultNativeLib = '/home/steven/source/decentdb/build/libc_api.so';
  final nativeLib =
      Platform.environment['DECENTDB_NATIVE_LIB'] ?? defaultNativeLib;
  final nativeLibExists = File(nativeLib).existsSync();
  final skipReason = nativeLibExists
      ? null
      : 'Expected DecentDB native library at $nativeLib';

  group('DecentDbBridge smoke tests', () {
    late DecentDbBridge bridge;
    late Directory tempDir;
    late String dbPath;

    Future<QueryResultPage> runQuery(
      String sql, {
      List<Object?> params = const <Object?>[],
      int pageSize = 64,
    }) {
      return bridge.runQuery(sql: sql, params: params, pageSize: pageSize);
    }

    Future<void> exec(
      String sql, {
      List<Object?> params = const <Object?>[],
    }) async {
      await runQuery(sql, params: params);
    }

    Future<List<Map<String, Object?>>> queryAllRows(
      String sql, {
      List<Object?> params = const <Object?>[],
      int pageSize = 64,
    }) async {
      final firstPage = await runQuery(sql, params: params, pageSize: pageSize);
      final rows = <Map<String, Object?>>[...firstPage.rows];
      var cursorId = firstPage.cursorId;

      while (cursorId != null) {
        final nextPage = await bridge.fetchNextPage(
          cursorId: cursorId,
          pageSize: pageSize,
        );
        rows.addAll(nextPage.rows);
        cursorId = nextPage.cursorId;
      }

      return rows;
    }

    Future<void> expectBridgeFailure(
      Future<Object?> Function() action, {
      String? containsMessage,
    }) async {
      await expectLater(
        action,
        throwsA(
          isA<BridgeFailure>().having(
            (error) => error.message,
            'message',
            containsMessage == null ? isNotEmpty : contains(containsMessage),
          ),
        ),
      );
    }

    String createSqliteSource(String filename) {
      final sourcePath = p.join(tempDir.path, filename);
      final source = sqlite.sqlite3.open(sourcePath);
      try {
        source.execute('PRAGMA foreign_keys = ON;');
        source.execute('''
CREATE TABLE users (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
)
''');
        source.execute('''
CREATE TABLE notes (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT
)
''');
        source.execute('''
CREATE TABLE feature_flags (
  id INTEGER PRIMARY KEY,
  enabled BOOL NOT NULL DEFAULT 1
)
''');
        source.execute('''
CREATE TABLE blob_samples (
  id INTEGER PRIMARY KEY,
  price NUMERIC(10,2),
  payload BLOB
)
''');
        source.execute(
          'CREATE TABLE strict_flags (id INTEGER PRIMARY KEY, enabled INTEGER NOT NULL) STRICT',
        );
        source.execute(
          'CREATE TABLE tag_codes (code TEXT PRIMARY KEY) WITHOUT ROWID',
        );
        source.execute('CREATE INDEX idx_notes_title ON notes (title)');
        source.execute("INSERT INTO users VALUES (1, 'Ada')");
        source.execute("INSERT INTO users VALUES (2, 'Grace')");
        source.execute("INSERT INTO notes VALUES (1, 1, 'Alpha')");
        source.execute("INSERT INTO notes VALUES (2, 2, 'Beta')");
        source.execute('INSERT INTO feature_flags VALUES (1, 1)');
        source.execute("INSERT INTO blob_samples VALUES (1, 19.95, x'414243')");
        source.execute('INSERT INTO strict_flags VALUES (1, 1)');
        source.execute("INSERT INTO tag_codes VALUES ('demo')");
      } finally {
        source.close();
      }
      return sourcePath;
    }

    String createExcelSource(String filename) {
      final sourcePath = p.join(tempDir.path, filename);
      final workbook = xls.Excel.createExcel();
      workbook.rename('Sheet1', 'people');

      final people = workbook['people'];
      people.cell(xls.CellIndex.indexByString('A1')).value = xls.TextCellValue(
        'id',
      );
      people.cell(xls.CellIndex.indexByString('B1')).value = xls.TextCellValue(
        'name',
      );
      people.cell(xls.CellIndex.indexByString('C1')).value = xls.TextCellValue(
        'active',
      );
      people.cell(xls.CellIndex.indexByString('D1')).value = xls.TextCellValue(
        'created_at',
      );
      people.cell(xls.CellIndex.indexByString('A2')).value = xls.IntCellValue(
        1,
      );
      people.cell(xls.CellIndex.indexByString('B2')).value = xls.TextCellValue(
        'Ada',
      );
      people.cell(xls.CellIndex.indexByString('C2')).value = xls.BoolCellValue(
        true,
      );
      people.cell(xls.CellIndex.indexByString('D2')).value =
          xls.DateTimeCellValue.fromDateTime(DateTime.utc(2026, 3, 10, 12, 0));
      people.cell(xls.CellIndex.indexByString('A3')).value = xls.IntCellValue(
        2,
      );
      people.cell(xls.CellIndex.indexByString('B3')).value = xls.TextCellValue(
        'Grace',
      );
      people.cell(xls.CellIndex.indexByString('C3')).value = xls.BoolCellValue(
        false,
      );
      people.cell(xls.CellIndex.indexByString('D3')).value =
          xls.DateTimeCellValue.fromDateTime(DateTime.utc(2026, 3, 11, 9, 30));

      final metrics = workbook['metrics'];
      metrics.cell(xls.CellIndex.indexByString('A1')).value = xls.TextCellValue(
        'quarter',
      );
      metrics.cell(xls.CellIndex.indexByString('B1')).value = xls.TextCellValue(
        'revenue',
      );
      metrics.cell(xls.CellIndex.indexByString('C1')).value = xls.TextCellValue(
        'calculated',
      );
      metrics.cell(xls.CellIndex.indexByString('A2')).value = xls.TextCellValue(
        'Q1',
      );
      metrics.cell(xls.CellIndex.indexByString('B2')).value =
          xls.DoubleCellValue(1200.5);
      metrics.cell(xls.CellIndex.indexByString('C2')).value =
          const xls.FormulaCellValue('SUM(B2)');
      metrics.cell(xls.CellIndex.indexByString('A3')).value = xls.TextCellValue(
        'Q2',
      );
      metrics.cell(xls.CellIndex.indexByString('B3')).value =
          xls.DoubleCellValue(1800.25);
      metrics.cell(xls.CellIndex.indexByString('C3')).value =
          const xls.FormulaCellValue('SUM(B3)');

      final bytes = workbook.save();
      File(sourcePath).writeAsBytesSync(bytes!);
      return sourcePath;
    }

    String createSqlDumpSource(String filename) {
      final sourcePath = p.join(tempDir.path, filename);
      final dump = '''
SET NAMES latin1;
CREATE TABLE `people` (
  `id` INT NOT NULL,
  `name` VARCHAR(255) NOT NULL,
  `active` TINYINT(1) DEFAULT 1,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
INSERT INTO `people` (`id`, `name`, `active`) VALUES
  (1, 'José', 1),
  (2, 'Ana', 0);
LOCK TABLES `people` WRITE;
UNLOCK TABLES;
CREATE TABLE `metrics` (
  `quarter` VARCHAR(16) NOT NULL,
  `revenue` DECIMAL(10,2),
  PRIMARY KEY (`quarter`)
);
INSERT INTO `metrics` VALUES ('Q1', 1200.50), ('Q2', 1800.25);
''';
      File(sourcePath).writeAsBytesSync(latin1.encode(dump));
      return sourcePath;
    }

    String resolveExcelFixturePackPath() {
      final candidates = <String>[
        p.normalize(
          p.join(
            Directory.current.path,
            '..',
            '..',
            'test-data',
            'excel-test-pack',
          ),
        ),
        p.normalize(
          p.join(Directory.current.path, '..', '..', 'test-data', 'excel'),
        ),
        p.normalize(
          p.join(Directory.current.path, 'test-data', 'excel-test-pack'),
        ),
        p.normalize(p.join(Directory.current.path, 'test-data', 'excel')),
      ];
      for (final candidate in candidates) {
        if (Directory(candidate).existsSync()) {
          return candidate;
        }
      }
      throw StateError(
        'Could not locate test-data/excel-test-pack from ${Directory.current.path}',
      );
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('decent-bench-phase1-');
      dbPath = p.join(tempDir.path, 'phase1.ddb');
      bridge = DecentDbBridge(resolver: _FixedResolver(nativeLib));
      await bridge.initialize();
      await bridge.openDatabase(dbPath);
    });

    tearDown(() async {
      await bridge.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('supports CSV export from query results', skip: skipReason, () async {
      await exec(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await exec("INSERT INTO users VALUES (1, 'Ada')");
      await exec("INSERT INTO users VALUES (2, 'Grace')");

      final exportPath = p.join(tempDir.path, 'users.csv');
      final export = await bridge.exportCsv(
        sql: 'SELECT id, name FROM users ORDER BY id',
        params: const <Object?>[],
        pageSize: 1,
        path: exportPath,
        delimiter: ',',
        includeHeaders: true,
      );

      expect(export.rowCount, 2);
      expect(
        await File(exportPath).readAsString(),
        allOf(contains('id,name'), contains('Ada'), contains('Grace')),
      );
    });

    test('supports parameters and paged cursors', skip: skipReason, () async {
      await exec('CREATE TABLE nums (id INTEGER PRIMARY KEY, label TEXT)');
      for (var i = 1; i <= 5; i++) {
        await exec(
          'INSERT INTO nums VALUES (\$1, \$2)',
          params: <Object?>[i, 'n$i'],
        );
      }

      final firstPage = await runQuery(
        'SELECT id, label FROM nums WHERE id >= \$1 ORDER BY id',
        params: const <Object?>[2],
        pageSize: 2,
      );

      expect(firstPage.rows.length, 2);
      expect(firstPage.rows.first['id'], 2);
      expect(firstPage.rows.last['id'], 3);
      expect(firstPage.cursorId, isNotNull);

      final rows = <Map<String, Object?>>[...firstPage.rows];
      var cursorId = firstPage.cursorId;
      while (cursorId != null) {
        final nextPage = await bridge.fetchNextPage(
          cursorId: cursorId,
          pageSize: 2,
        );
        rows.addAll(nextPage.rows);
        cursorId = nextPage.cursorId;
      }

      expect(
        rows.map((row) => row['id']),
        orderedEquals(<Object?>[2, 3, 4, 5]),
      );
      expect(
        rows.map((row) => row['label']),
        orderedEquals(<Object?>['n2', 'n3', 'n4', 'n5']),
      );
    });

    test(
      'handles broader schema snapshots and larger paged result sets',
      skip: skipReason,
      () async {
        for (var i = 0; i < 24; i++) {
          await exec(
            'CREATE TABLE bulk_table_$i (id INTEGER PRIMARY KEY, label TEXT)',
          );
        }
        await exec(
          'CREATE TABLE large_rows (id INTEGER PRIMARY KEY, label TEXT NOT NULL)',
        );
        for (var i = 1; i <= 1500; i++) {
          await exec(
            'INSERT INTO large_rows VALUES (\$1, \$2)',
            params: <Object?>[i, 'row-$i'],
          );
        }

        final schema = await bridge.loadSchema();
        final rows = await queryAllRows(
          'SELECT id, label FROM large_rows ORDER BY id',
          pageSize: 128,
        );

        expect(
          schema.tables.where((table) => table.name.startsWith('bulk_table_')),
          hasLength(24),
        );
        expect(rows, hasLength(1500));
        expect(rows.first['id'], 1);
        expect(rows.last['id'], 1500);
      },
    );

    test('supports views and indexes', skip: skipReason, () async {
      await exec(
        'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await exec("INSERT INTO users VALUES (1, 'Ada')");
      await exec("INSERT INTO users VALUES (2, 'Grace')");
      await exec('CREATE VIEW user_names AS SELECT id, name FROM users');
      await exec('CREATE INDEX idx_users_name ON users (name)');

      final viewRows = await queryAllRows(
        'SELECT id, name FROM user_names ORDER BY id',
      );
      final schema = await bridge.loadSchema();

      expect(viewRows.length, 2);
      expect(viewRows.first['name'], 'Ada');
      expect(schema.tables.any((item) => item.name == 'users'), isTrue);
      expect(schema.views.any((item) => item.name == 'user_names'), isTrue);
      expect(
        schema.indexes.any((item) => item.name == 'idx_users_name'),
        isTrue,
      );
    });

    test(
      'supports recursive CTEs and cursor cancellation',
      skip: skipReason,
      () async {
        const recursiveSql = '''
WITH RECURSIVE cnt(x) AS (
  SELECT 1
  UNION ALL
  SELECT x + 1 FROM cnt WHERE x < 5
)
SELECT x FROM cnt
''';

        final firstPage = await runQuery(recursiveSql, pageSize: 2);
        expect(
          firstPage.rows.map((row) => row['x']),
          orderedEquals(<Object?>[1, 2]),
        );
        expect(firstPage.cursorId, isNotNull);

        await bridge.cancelQuery(firstPage.cursorId!);
        await expectBridgeFailure(
          () =>
              bridge.fetchNextPage(cursorId: firstPage.cursorId!, pageSize: 2),
          containsMessage: 'Query cursor is no longer available.',
        );

        final rows = await queryAllRows(recursiveSql, pageSize: 10);
        expect(
          rows.map((row) => row['x']),
          orderedEquals(<Object?>[1, 2, 3, 4, 5]),
        );
      },
    );

    test(
      'supports constraints and generated stored columns',
      skip: skipReason,
      () async {
        await exec('''
CREATE TABLE line_items (
  id INTEGER PRIMARY KEY,
  sku TEXT NOT NULL UNIQUE,
  price REAL NOT NULL CHECK (price > 0),
  qty INTEGER NOT NULL CHECK (qty > 0),
  status TEXT DEFAULT 'active',
  total REAL GENERATED ALWAYS AS (price * qty) STORED
)
''');

        await exec(
          'INSERT INTO line_items (id, sku, price, qty) VALUES (1, \$1, \$2, \$3)',
          params: const <Object?>['A-1', 9.5, 2],
        );

        final rows = await queryAllRows(
          'SELECT sku, status, total FROM line_items WHERE id = 1',
        );
        expect(rows.single['sku'], 'A-1');
        expect(rows.single['status'], 'active');
        expect(rows.single['total'], closeTo(19.0, 0.0001));

        await expectBridgeFailure(
          () => exec(
            'INSERT INTO line_items (id, sku, price, qty) VALUES (2, \$1, \$2, \$3)',
            params: const <Object?>['A-1', 5.0, 1],
          ),
        );
        await expectBridgeFailure(
          () => exec(
            'INSERT INTO line_items (id, sku, price, qty) VALUES (3, \$1, \$2, \$3)',
            params: const <Object?>['B-2', 5.0, 0],
          ),
        );

        await bridge.openDatabase(dbPath);
        final reopenedRows = await queryAllRows(
          'SELECT total FROM line_items WHERE id = 1',
        );
        expect(reopenedRows.single['total'], closeTo(19.0, 0.0001));
      },
    );

    test('supports window and aggregate functions', skip: skipReason, () async {
      await exec(
        'CREATE TABLE payroll (id INTEGER PRIMARY KEY, dept TEXT, employee TEXT, salary INTEGER)',
      );
      await exec("INSERT INTO payroll VALUES (1, 'eng', 'Ada', 120)");
      await exec("INSERT INTO payroll VALUES (2, 'eng', 'Grace', 110)");
      await exec("INSERT INTO payroll VALUES (3, 'ops', 'Linus', 90)");
      await exec("INSERT INTO payroll VALUES (4, 'ops', 'Ken', 80)");

      final rankedRows = await queryAllRows('''
SELECT dept, employee, salary, ROW_NUMBER() OVER (
  PARTITION BY dept
  ORDER BY salary DESC
) AS rn
FROM payroll
ORDER BY dept, rn
''');
      final aggregateRows = await queryAllRows('''
SELECT dept, COUNT(*) AS members, SUM(salary) AS total_salary
FROM payroll
GROUP BY dept
ORDER BY dept
''');

      expect(rankedRows.first['employee'], 'Ada');
      expect(rankedRows.first['rn'], 1);
      expect(rankedRows[2]['employee'], 'Linus');
      expect(rankedRows[2]['rn'], 1);
      expect(aggregateRows.first['dept'], 'eng');
      expect(aggregateRows.first['members'], 2);
      expect(aggregateRows.first['total_salary'], 230);
      expect(aggregateRows.last['dept'], 'ops');
      expect(aggregateRows.last['total_salary'], 170);
    });

    test('supports JSON table-valued functions', skip: skipReason, () async {
      final eachRows = await queryAllRows(
        '''SELECT key, value, type FROM json_each('{"name":"Alice","age":30}') ORDER BY key''',
      );
      final treeRows = await queryAllRows(
        '''SELECT key, value, type, path FROM json_tree('{"a":1,"b":[2,3]}')''',
      );

      final ageRow = eachRows.firstWhere((row) => row['key'] == 'age');
      final nameRow = eachRows.firstWhere((row) => row['key'] == 'name');

      expect(eachRows.length, 2);
      expect(ageRow['type'], 'number');
      expect(ageRow['value'].toString(), '30');
      expect(nameRow['type'], 'string');
      expect(nameRow['value'].toString(), contains('Alice'));
      expect(
        treeRows.any(
          (row) => row['type'] == 'object' && row['path'].toString() == r'$',
        ),
        isTrue,
      );
      expect(
        treeRows.any(
          (row) =>
              row['key'] == 'a' &&
              row['type'] == 'number' &&
              row['path'].toString() == r'$.a',
        ),
        isTrue,
      );
    });

    test('supports transactions and savepoints', skip: skipReason, () async {
      await exec('CREATE TABLE txn_events (id INTEGER PRIMARY KEY, note TEXT)');
      await exec('BEGIN');
      await exec("INSERT INTO txn_events VALUES (1, 'kept')");
      await exec('SAVEPOINT sp1');
      await exec("INSERT INTO txn_events VALUES (2, 'rolled-back')");
      await exec('ROLLBACK TO SAVEPOINT sp1');
      await exec('COMMIT');

      final rows = await queryAllRows(
        'SELECT id, note FROM txn_events ORDER BY id',
      );
      expect(rows.length, 1);
      expect(rows.single['id'], 1);
      expect(rows.single['note'], 'kept');
    });

    test('supports row triggers', skip: skipReason, () async {
      await exec(
        'CREATE TABLE events (id INTEGER PRIMARY KEY, label TEXT NOT NULL)',
      );
      await exec('CREATE TABLE audit (tag TEXT)');
      await exec(
        "CREATE TRIGGER events_ins_audit AFTER INSERT ON events FOR EACH ROW EXECUTE FUNCTION decentdb_exec_sql('INSERT INTO audit(tag) VALUES (''I'')')",
      );
      await exec("INSERT INTO events VALUES (1, 'launch')");

      final auditRows = await queryAllRows('SELECT tag FROM audit');
      expect(auditRows.single['tag'], 'I');
    });

    test('supports temp tables and temp views', skip: skipReason, () async {
      await exec('CREATE TEMP TABLE temp_results (id INTEGER, value TEXT)');
      await exec("INSERT INTO temp_results VALUES (1, 'ephemeral')");
      await exec(
        'CREATE TEMP VIEW temp_summary AS SELECT value FROM temp_results',
      );

      final tempRows = await queryAllRows('SELECT value FROM temp_summary');
      expect(tempRows.single['value'], 'ephemeral');

      await bridge.openDatabase(dbPath);
      await expectBridgeFailure(
        () => queryAllRows('SELECT value FROM temp_summary'),
      );
    });

    test('supports planner introspection', skip: skipReason, () async {
      await exec(
        'CREATE TABLE explain_items (id INTEGER PRIMARY KEY, score INTEGER)',
      );
      await exec('INSERT INTO explain_items VALUES (1, 10)');
      await exec('INSERT INTO explain_items VALUES (2, 20)');

      final explainRows = await queryAllRows(
        'EXPLAIN SELECT id FROM explain_items WHERE score > 10',
      );
      final analyzeRows = await queryAllRows(
        'EXPLAIN ANALYZE SELECT id FROM explain_items WHERE score > 10',
      );

      expect(explainRows, isNotEmpty);
      expect(analyzeRows, isNotEmpty);
      expect(explainRows.first.keys, contains('query_plan'));
      expect(analyzeRows.first.keys, contains('query_plan'));
    });

    test('supports statistics collection', skip: skipReason, () async {
      await exec('CREATE TABLE stats_items (id INTEGER PRIMARY KEY, grp TEXT)');
      await exec("INSERT INTO stats_items VALUES (1, 'a')");
      await exec("INSERT INTO stats_items VALUES (2, 'a')");
      await exec("INSERT INTO stats_items VALUES (3, 'b')");
      await exec('CREATE INDEX idx_stats_grp ON stats_items (grp)');

      await exec('ANALYZE stats_items');

      final rows = await queryAllRows(
        "SELECT COUNT(*) AS row_count FROM stats_items WHERE grp = 'a'",
      );
      expect(rows.single['row_count'], 2);
    });

    test(
      'inspects SQLite sources and loads preview rows',
      skip: skipReason,
      () async {
        final sourcePath = createSqliteSource('phase4-source.sqlite');

        final inspection = await bridge.inspectSqliteSource(
          sourcePath: sourcePath,
        );
        final featureFlags = inspection.tables.firstWhere(
          (table) => table.sourceName == 'feature_flags',
        );
        final blobSamples = inspection.tables.firstWhere(
          (table) => table.sourceName == 'blob_samples',
        );
        final notes = inspection.tables.firstWhere(
          (table) => table.sourceName == 'notes',
        );

        expect(inspection.tables, hasLength(6));
        expect(inspection.warnings, contains(contains('STRICT')));
        expect(inspection.warnings, contains(contains('WITHOUT ROWID')));
        expect(
          featureFlags.columns
              .firstWhere((column) => column.sourceName == 'enabled')
              .targetType,
          'BOOLEAN',
        );
        expect(
          blobSamples.columns
              .firstWhere((column) => column.sourceName == 'price')
              .targetType,
          'DECIMAL(10,2)',
        );
        expect(
          blobSamples.columns
              .firstWhere((column) => column.sourceName == 'payload')
              .targetType,
          'BLOB',
        );
        expect(notes.indexes.single.name, 'idx_notes_title');

        final preview = await bridge.loadSqlitePreview(
          sourcePath: sourcePath,
          tableName: 'notes',
        );
        expect(preview.rows, hasLength(2));
        expect(preview.rows.first['title'], 'Alpha');
      },
    );

    test(
      'imports selected SQLite tables into DecentDB',
      skip: skipReason,
      () async {
        final sourcePath = createSqliteSource('phase4-import.sqlite');
        final inspection = await bridge.inspectSqliteSource(
          sourcePath: sourcePath,
        );
        final targetPath = p.join(tempDir.path, 'phase4-import.ddb');
        final selectedTables = inspection.tables.map((table) {
          if (table.sourceName == 'notes') {
            return table.copyWith(
              targetName: 'imported_notes',
              columns: <SqliteImportColumnDraft>[
                for (final column in table.columns)
                  if (column.sourceName == 'title')
                    column.copyWith(targetName: 'note_title')
                  else
                    column,
              ],
            );
          }
          return table.copyWith(
            selected:
                table.sourceName == 'users' || table.sourceName == 'notes',
          );
        }).toList();
        final request = SqliteImportRequest(
          jobId: 'smoke-import',
          sourcePath: sourcePath,
          targetPath: targetPath,
          importIntoExistingTarget: false,
          replaceExistingTarget: true,
          tables: selectedTables,
        );

        final updates = await bridge.importSqlite(request: request).toList();
        final terminal = updates.last;

        expect(terminal.kind, SqliteImportUpdateKind.completed);
        expect(terminal.summary, isNotNull);
        expect(
          terminal.summary!.importedTables,
          orderedEquals(<String>['users', 'imported_notes']),
        );
        expect(terminal.summary!.rowsCopiedByTable['users'], 2);
        expect(terminal.summary!.rowsCopiedByTable['imported_notes'], 2);

        await bridge.openDatabase(targetPath);
        final rows = await queryAllRows('''
SELECT u.name, n.note_title
FROM users AS u
JOIN imported_notes AS n ON n.user_id = u.id
ORDER BY n.id
''');
        final schema = await bridge.loadSchema();

        expect(rows, hasLength(2));
        expect(rows.first['name'], 'Ada');
        expect(rows.first['note_title'], 'Alpha');
        expect(rows.last['name'], 'Grace');
        expect(schema.tables.any((table) => table.name == 'users'), isTrue);
        expect(
          schema.tables.any((table) => table.name == 'imported_notes'),
          isTrue,
        );
        expect(
          schema.indexes.any(
            (index) =>
                index.name == 'idx_notes_title' &&
                index.table == 'imported_notes',
          ),
          isTrue,
        );
      },
    );

    test(
      'inspects Excel workbooks and imports selected sheets',
      skip: skipReason,
      () async {
        final sourcePath = createExcelSource('phase5-source.xlsx');
        final targetPath = p.join(tempDir.path, 'phase5-import.ddb');

        final inspection = await bridge.inspectExcelSource(
          sourcePath: sourcePath,
          headerRow: true,
        );
        final noHeaderInspection = await bridge.inspectExcelSource(
          sourcePath: sourcePath,
          headerRow: false,
        );
        expect(
          inspection.sheets.map((sheet) => sheet.sourceName),
          containsAll(<String>['people', 'metrics']),
        );
        expect(
          noHeaderInspection.sheets.first.columns.first.sourceName,
          'column_1',
        );

        final people = inspection.sheets.firstWhere(
          (sheet) => sheet.sourceName == 'people',
        );
        expect(
          people.columns.map((column) => column.targetType),
          orderedEquals(<String>['INTEGER', 'TEXT', 'BOOLEAN', 'TIMESTAMP']),
        );
        expect(people.previewRows.first['name'], 'Ada');

        final metrics = inspection.sheets.firstWhere(
          (sheet) => sheet.sourceName == 'metrics',
        );
        final request = ExcelImportRequest(
          jobId: 'excel-smoke',
          sourcePath: sourcePath,
          targetPath: targetPath,
          importIntoExistingTarget: false,
          replaceExistingTarget: true,
          headerRow: true,
          sheets: <ExcelImportSheetDraft>[
            people.copyWith(targetName: 'imported_people'),
            metrics.copyWith(
              selected: true,
              targetName: 'metrics_import',
              columns: <ExcelImportColumnDraft>[
                for (final column in metrics.columns)
                  if (column.sourceName == 'calculated')
                    column.copyWith(
                      targetName: 'formula_text',
                      targetType: 'TEXT',
                    )
                  else
                    column,
              ],
            ),
          ],
        );

        final updates = await bridge.importExcel(request: request).toList();
        final terminal = updates.last;

        expect(terminal.kind, ExcelImportUpdateKind.completed);
        expect(
          terminal.summary?.importedTables,
          containsAll(<String>['imported_people', 'metrics_import']),
        );
        expect(terminal.summary?.warnings, isNotEmpty);

        await bridge.openDatabase(targetPath);
        final peopleRows = await queryAllRows(
          'SELECT id, name, active FROM imported_people ORDER BY id',
        );
        final metricRows = await queryAllRows(
          'SELECT quarter, formula_text FROM metrics_import ORDER BY quarter',
        );

        expect(peopleRows.first['name'], 'Ada');
        expect(peopleRows.first['active'], true);
        expect(metricRows.first['formula_text'], '=SUM(B2)');
      },
    );

    test(
      'imports aggregate-only Excel summary sheets as views',
      skip: skipReason,
      () async {
        final fixturePackPath = resolveExcelFixturePackPath();
        final sourcePath = p.join(
          fixturePackPath,
          'cross_sheet_calculations.xlsx',
        );
        final targetPath = p.join(tempDir.path, 'cross-sheet-view.ddb');

        final inspection = await bridge.inspectExcelSource(
          sourcePath: sourcePath,
          headerRow: true,
        );
        final request = ExcelImportRequest(
          jobId: 'fixture-cross-sheet-view',
          sourcePath: sourcePath,
          targetPath: targetPath,
          importIntoExistingTarget: false,
          replaceExistingTarget: true,
          headerRow: true,
          sheets: inspection.sheets,
        );

        final updates = await bridge.importExcel(request: request).toList();
        final terminal = updates.last;

        expect(terminal.kind, ExcelImportUpdateKind.completed);
        expect(
          terminal.summary?.importedViews,
          contains('Dashboard'),
          reason: (terminal.summary?.warnings ?? const <String>[]).join('\n'),
        );

        await bridge.openDatabase(targetPath);
        final schema = await bridge.loadSchema();
        expect(
          schema.views.any((item) => item.name.toLowerCase() == 'dashboard'),
          isTrue,
        );

        final dashboardRows = await queryAllRows(
          'SELECT "Region", "OrderCount", "Revenue" '
          'FROM "Dashboard" ORDER BY "Region"',
        );
        final byRegion = <String, Map<String, Object?>>{
          for (final row in dashboardRows) row['Region']! as String: row,
        };

        expect(
          byRegion.keys,
          orderedEquals(<String>['East', 'North', 'South', 'West']),
        );
        expect(byRegion['North']?['OrderCount'], 28);
        expect(
          (byRegion['North']?['Revenue'] as num).toDouble(),
          closeTo(35378.06, 0.01),
        );
        expect(byRegion['South']?['OrderCount'], 24);
        expect(
          (byRegion['South']?['Revenue'] as num).toDouble(),
          closeTo(32640.03, 0.01),
        );
        expect(byRegion['East']?['OrderCount'], 15);
        expect(
          (byRegion['East']?['Revenue'] as num).toDouble(),
          closeTo(17176.03, 0.01),
        );
        expect(byRegion['West']?['OrderCount'], 13);
        expect(
          (byRegion['West']?['Revenue'] as num).toDouble(),
          closeTo(18386.97, 0.01),
        );
      },
    );

    test(
      'imports every workbook from the checked-in Excel fixture pack',
      skip: skipReason,
      () async {
        final fixturePackPath = resolveExcelFixturePackPath();
        final workbookFiles =
            Directory(fixturePackPath)
                .listSync()
                .whereType<File>()
                .where((file) {
                  final extension = p.extension(file.path).toLowerCase();
                  return extension == '.xls' || extension == '.xlsx';
                })
                .toList(growable: false)
              ..sort((left, right) => left.path.compareTo(right.path));

        expect(workbookFiles, isNotEmpty);

        for (final workbookFile in workbookFiles) {
          final inspection = await bridge.inspectExcelSource(
            sourcePath: workbookFile.path,
            headerRow: true,
          );
          final request = ExcelImportRequest(
            jobId: 'fixture-${p.basenameWithoutExtension(workbookFile.path)}',
            sourcePath: workbookFile.path,
            targetPath: p.join(
              tempDir.path,
              '${p.basenameWithoutExtension(workbookFile.path)}.ddb',
            ),
            importIntoExistingTarget: false,
            replaceExistingTarget: true,
            headerRow: true,
            sheets: inspection.sheets,
          );

          expect(
            request.selectedSheets,
            isNotEmpty,
            reason:
                'Expected at least one selected sheet for ${p.basename(workbookFile.path)}',
          );

          final updates = await bridge.importExcel(request: request).toList();
          final terminal = updates.last;

          expect(
            terminal.kind,
            ExcelImportUpdateKind.completed,
            reason: 'Import failed for ${p.basename(workbookFile.path)}',
          );
          expect(
            File(request.targetPath).existsSync(),
            isTrue,
            reason:
                'Expected DecentDB file for ${p.basename(workbookFile.path)}',
          );

          await bridge.openDatabase(request.targetPath);
          final schema = await bridge.loadSchema();
          final importedTables =
              terminal.summary?.importedTables ?? const <String>[];
          final importedViews =
              terminal.summary?.importedViews ?? const <String>[];
          final schemaTableNames = schema.tables
              .map((table) => table.name.toLowerCase())
              .toList(growable: false);
          final schemaViewNames = schema.views
              .map((view) => view.name.toLowerCase())
              .toList(growable: false);

          expect(
            importedTables,
            isNotEmpty,
            reason:
                'Expected imported tables for ${p.basename(workbookFile.path)}',
          );
          expect(
            schemaTableNames,
            containsAll(
              importedTables.map((tableName) => tableName.toLowerCase()),
            ),
            reason:
                'Schema missing imported tables for ${p.basename(workbookFile.path)}',
          );
          expect(
            schemaViewNames,
            containsAll(
              importedViews.map((viewName) => viewName.toLowerCase()),
            ),
            reason:
                'Schema missing imported views for ${p.basename(workbookFile.path)}',
          );

          if (p.extension(workbookFile.path).toLowerCase() == '.xls') {
            expect(
              <String>[
                ...inspection.warnings,
                ...(terminal.summary?.warnings ?? const <String>[]),
              ].join('\n'),
              contains('converted to temporary `.xlsx`'),
              reason:
                  'Expected conversion warning for ${p.basename(workbookFile.path)}',
            );
          }
        }
      },
    );

    test(
      'inspects SQL dumps and imports selected parsed tables',
      skip: skipReason,
      () async {
        final sourcePath = createSqlDumpSource('phase6-source.sql');
        final targetPath = p.join(tempDir.path, 'phase6-import.ddb');

        final inspection = await bridge.inspectSqlDumpSource(
          sourcePath: sourcePath,
          encoding: 'auto',
        );
        expect(inspection.resolvedEncoding, 'latin1');
        expect(
          inspection.tables.map((table) => table.sourceName),
          orderedEquals(<String>['people', 'metrics']),
        );
        expect(inspection.skippedStatementCount, 3);
        expect(
          inspection.tables
              .firstWhere((table) => table.sourceName == 'people')
              .columns
              .firstWhere((column) => column.sourceName == 'active')
              .targetType,
          'BOOLEAN',
        );
        expect(
          inspection.tables
              .firstWhere((table) => table.sourceName == 'metrics')
              .columns
              .firstWhere((column) => column.sourceName == 'revenue')
              .targetType,
          'DECIMAL(10,2)',
        );
        expect(
          inspection.tables
              .firstWhere((table) => table.sourceName == 'people')
              .previewRows
              .first['name'],
          'José',
        );

        final request = SqlDumpImportRequest(
          jobId: 'sql-dump-smoke',
          sourcePath: sourcePath,
          targetPath: targetPath,
          importIntoExistingTarget: false,
          replaceExistingTarget: true,
          encoding: 'auto',
          tables: inspection.tables.map((table) {
            if (table.sourceName == 'people') {
              return table.copyWith(
                targetName: 'imported_people',
                columns: <SqlDumpImportColumnDraft>[
                  for (final column in table.columns)
                    if (column.sourceName == 'name')
                      column.copyWith(targetName: 'display_name')
                    else
                      column,
                ],
              );
            }
            return table.copyWith(targetName: 'imported_metrics');
          }).toList(),
        );

        final updates = await bridge.importSqlDump(request: request).toList();
        final terminal = updates.last;

        expect(terminal.kind, SqlDumpImportUpdateKind.completed);
        expect(
          terminal.summary?.importedTables,
          orderedEquals(<String>['imported_people', 'imported_metrics']),
        );
        expect(terminal.summary?.skippedStatementCount, 3);

        await bridge.openDatabase(targetPath);
        final peopleRows = await queryAllRows(
          'SELECT id, display_name, active FROM imported_people ORDER BY id',
        );
        final metricRows = await queryAllRows(
          'SELECT quarter, revenue FROM imported_metrics ORDER BY quarter',
        );

        expect(peopleRows, hasLength(2));
        expect(peopleRows.first['display_name'], 'José');
        expect(peopleRows.first['active'], true);
        expect(peopleRows.last['active'], false);
        expect(metricRows, hasLength(2));
        expect(metricRows.first['quarter'], 'Q1');
      },
    );
  });
}
