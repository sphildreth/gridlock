import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:decent_bench/features/import/domain/import_models.dart';
import 'package:decent_bench/features/import/infrastructure/import_detection_service.dart';
import 'package:decent_bench/features/import/infrastructure/import_execution_service.dart';
import 'package:decent_bench/features/import/infrastructure/import_format_registry.dart';
import 'package:decent_bench/features/import/infrastructure/import_preview_service.dart';
import 'package:decent_bench/features/import/infrastructure/type_inference_service.dart';
import 'package:decent_bench/features/workspace/domain/excel_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sql_dump_import_models.dart';
import 'package:decent_bench/features/workspace/domain/sqlite_import_models.dart';
import 'package:decent_bench/features/workspace/domain/workspace_models.dart';
import 'package:decent_bench/features/workspace/infrastructure/decentdb_bridge.dart';
import 'package:decent_bench/features/workspace/infrastructure/excel_import_support.dart';
import 'package:decent_bench/features/workspace/infrastructure/native_library_resolver.dart';
import 'package:decent_bench/features/workspace/infrastructure/sql_dump_import_support.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/import_fixture_manifest.dart';

class _FixedResolver extends NativeLibraryResolver {
  _FixedResolver(this.path);

  final String path;

  @override
  Future<String> resolve() async => path;
}

typedef _TypedColumn = ({String name, String targetType});

class _ResolvedFixtureSource {
  const _ResolvedFixtureSource({
    required this.sourcePath,
    required this.formatKey,
    this.cleanupDirectory,
  });

  final String sourcePath;
  final ImportFormatKey formatKey;
  final Directory? cleanupDirectory;
}

const Set<String> _nonImportDocumentationFixturePaths = <String>{
  'test-data/README.md',
  'test-data/excel/README.txt',
};

bool _isIgnoredFixturePath(String relativePath) {
  return _nonImportDocumentationFixturePaths.contains(relativePath) ||
      relativePath.endsWith('.ddb') ||
      relativePath.endsWith('.ddb-wal') ||
      relativePath.endsWith('.ddb-shm');
}

void main() {
  const defaultNativeLib = '/home/steven/source/decentdb/build/libc_api.so';
  final nativeLib =
      Platform.environment['DECENTDB_NATIVE_LIB'] ?? defaultNativeLib;
  final nativeLibExists = File(nativeLib).existsSync();
  final skipReason = nativeLibExists
      ? null
      : 'Expected DecentDB native library at $nativeLib';

  final registry = ImportFormatRegistry.instance;
  late DecentDbBridge bridge;
  late ImportDetectionService detectionService;
  late ImportPreviewService previewService;
  late ImportExecutionService executionService;
  late Directory suiteTempDir;

  setUpAll(() async {
    bridge = DecentDbBridge(resolver: _FixedResolver(nativeLib));
    detectionService = ImportDetectionService();
    previewService = ImportPreviewService();
    executionService = ImportExecutionService(
      resolver: _FixedResolver(nativeLib),
    );
    suiteTempDir = await Directory.systemTemp.createTemp(
      'decent-bench-import-fixtures-',
    );
  });

  tearDownAll(() async {
    await bridge.dispose();
    if (await suiteTempDir.exists()) {
      await suiteTempDir.delete(recursive: true);
    }
  });

  test('fixture manifest covers every non-document file under test-data', () {
    final fixtureRoot = Directory(_resolveRepoRelativePath('test-data'));
    final repoRoot = p.dirname(fixtureRoot.path);
    final discoveredFixturePaths = fixtureRoot
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => p.normalize(p.relative(file.path, from: repoRoot)))
        .toSet();
    final importFixturePaths = discoveredFixturePaths
        .where((path) => !_isIgnoredFixturePath(path))
        .toSet();
    final manifestFixturePaths = _manifestCoveredFixturePaths();
    final uncoveredFixturePaths = importFixturePaths.difference(
      manifestFixturePaths,
    );
    final staleManifestPaths = manifestFixturePaths.difference(
      importFixturePaths,
    );

    expect(
      uncoveredFixturePaths,
      isEmpty,
      reason:
          'Add every new test-data fixture to an import test manifest. Missing: ${uncoveredFixturePaths.toList()..sort()}',
    );
    expect(
      staleManifestPaths,
      isEmpty,
      reason:
          'Remove or fix manifest entries for missing fixtures: ${staleManifestPaths.toList()..sort()}',
    );
  });

  group('generic import round-trip fixtures', () {
    for (final fixture in genericImportRoundTripFixtures) {
      test(
        'imports ${fixture.relativePath}',
        skip: skipReason,
        timeout: const Timeout(Duration(minutes: 2)),
        () async {
          final resolved = await _resolveFixtureSource(
            relativePath: fixture.relativePath,
            formatKey: fixture.formatKey,
            extractWrappedSource: fixture.extractWrappedSource,
            detectionService: detectionService,
          );
          try {
            final options =
                fixture.options ??
                defaultGenericImportOptionsFor(resolved.formatKey);
            final format = registry.forKey(resolved.formatKey);
            final inspection = await previewService.inspect(
              sourcePath: resolved.sourcePath,
              format: format,
              options: options,
            );
            final selectedTables = inspection.tables
                .where((table) => table.selected)
                .toList(growable: false);

            expect(
              selectedTables,
              isNotEmpty,
              reason:
                  'Expected at least one selected import table for ${fixture.relativePath}',
            );
            final expectedTableNames = fixture.expectedTableNames;
            if (expectedTableNames != null) {
              expect(
                selectedTables.map((table) => table.targetName).toSet(),
                equals(expectedTableNames.toSet()),
                reason: 'Unexpected preview tables for ${fixture.relativePath}',
              );
            }
            for (final table in selectedTables) {
              final expectedRowCount =
                  fixture.expectedRowCountsByTable[table.targetName];
              if (expectedRowCount != null) {
                expect(
                  table.rowCount,
                  expectedRowCount,
                  reason:
                      'Unexpected preview row count for ${fixture.relativePath}:${table.targetName}',
                );
              }
              final requiredColumns =
                  fixture.requiredColumnsByTable[table.targetName];
              if (requiredColumns != null) {
                expect(
                  table.columns.map((column) => column.sourceName),
                  containsAll(requiredColumns),
                  reason:
                      'Unexpected preview columns for ${fixture.relativePath}:${table.targetName}',
                );
              }
            }

            final request = GenericImportRequest(
              jobId: _jobIdFor(fixture.relativePath),
              sourcePath: resolved.sourcePath,
              targetPath: _targetPathFor(fixture.relativePath, suiteTempDir),
              importIntoExistingTarget: false,
              replaceExistingTarget: true,
              formatKey: resolved.formatKey,
              options: options,
              tables: inspection.tables,
            );
            final materialized = executionService.materializeRequest(request);
            final materializedBySourceId =
                <String, MaterializedImportTableData>{
                  for (final table in materialized.tables)
                    table.sourceId: table,
                };

            final updates = await executionService
                .execute(request: request)
                .toList();
            final terminal = updates.last;

            expect(
              terminal.kind,
              GenericImportUpdateKind.completed,
              reason: 'Import failed for ${fixture.relativePath}',
            );
            expect(File(request.targetPath).existsSync(), isTrue);

            final summary = terminal.summary!;
            expect(
              summary.importedTables.toSet(),
              equals(selectedTables.map((table) => table.targetName).toSet()),
            );

            await bridge.openDatabase(request.targetPath);
            for (final table in selectedTables) {
              final materializedTable = materializedBySourceId[table.sourceId];
              expect(
                materializedTable,
                isNotNull,
                reason:
                    'Missing materialized rows for ${fixture.relativePath}:${table.sourceName}',
              );

              expect(
                summary.rowsCopiedByTable[table.targetName],
                materializedTable!.rows.length,
                reason:
                    'Copied row count mismatch for ${fixture.relativePath}:${table.targetName}',
              );

              final actualRows = await _queryAllRows(
                bridge,
                'SELECT ${table.columns.map((column) => _quoteIdentifier(column.targetName)).join(", ")} '
                'FROM ${_quoteIdentifier(table.targetName)}',
              );

              final expectedSignatures = _canonicalizeGenericExpectedRows(
                materializedTable.rows,
                table.columns,
              );
              final actualSignatures =
                  _canonicalizeActualRows(actualRows, <_TypedColumn>[
                    for (final column in table.columns)
                      (name: column.targetName, targetType: column.targetType),
                  ]);
              final expectedRowCount =
                  fixture.expectedRowCountsByTable[table.targetName];
              if (expectedRowCount != null) {
                expect(
                  actualRows,
                  hasLength(expectedRowCount),
                  reason:
                      'Unexpected imported row count for ${fixture.relativePath}:${table.targetName}',
                );
              }

              expect(
                actualSignatures,
                orderedEquals(expectedSignatures),
                reason:
                    'Row mismatch for ${fixture.relativePath}:${table.targetName}',
              );
            }
          } finally {
            final cleanupDirectory = resolved.cleanupDirectory;
            if (cleanupDirectory != null && cleanupDirectory.existsSync()) {
              await cleanupDirectory.delete(recursive: true);
            }
          }
        },
      );
    }
  });

  group('generic inspection-only fixtures', () {
    for (final fixture in genericInspectionFixtures) {
      test(
        'inspects ${fixture.relativePath}',
        skip: skipReason,
        timeout: const Timeout(Duration(minutes: 2)),
        () async {
          final resolved = await _resolveFixtureSource(
            relativePath: fixture.relativePath,
            formatKey: fixture.formatKey,
            extractWrappedSource: fixture.extractWrappedSource,
            detectionService: detectionService,
          );
          try {
            final options =
                fixture.options ??
                defaultGenericImportOptionsFor(resolved.formatKey);
            final format = registry.forKey(resolved.formatKey);
            final inspection = await previewService.inspect(
              sourcePath: resolved.sourcePath,
              format: format,
              options: options,
            );
            final request = GenericImportRequest(
              jobId: _jobIdFor(fixture.relativePath),
              sourcePath: resolved.sourcePath,
              targetPath: _targetPathFor(fixture.relativePath, suiteTempDir),
              importIntoExistingTarget: false,
              replaceExistingTarget: true,
              formatKey: resolved.formatKey,
              options: options,
              tables: inspection.tables,
            );
            final materialized = executionService.materializeRequest(request);

            expect(inspection.tables, hasLength(fixture.expectedTableCount));
            expect(
              inspection.tables.where((table) => table.selected),
              hasLength(fixture.expectedSelectedTableCount),
            );
            expect(materialized.tables, hasLength(fixture.expectedTableCount));
            for (final substring in fixture.expectedWarningSubstrings) {
              expect(
                inspection.warnings.join('\n'),
                contains(substring),
                reason:
                    'Expected warning for ${fixture.relativePath}: $substring',
              );
            }
          } finally {
            final cleanupDirectory = resolved.cleanupDirectory;
            if (cleanupDirectory != null && cleanupDirectory.existsSync()) {
              await cleanupDirectory.delete(recursive: true);
            }
          }
        },
      );
    }
  });

  group('SQLite import round-trip fixtures', () {
    for (final fixture in sqliteImportRoundTripFixtures) {
      test(
        'imports ${fixture.relativePath}',
        skip: skipReason,
        timeout: const Timeout(Duration(minutes: 2)),
        () async {
          final sourcePath = _resolveRepoRelativePath(fixture.relativePath);
          final inspection = await bridge.inspectSqliteSource(
            sourcePath: sourcePath,
          );
          final selectedTables = inspection.tables
              .where((table) => table.selected)
              .toList(growable: false);

          expect(
            selectedTables,
            isNotEmpty,
            reason:
                'Expected at least one selected SQLite table for ${fixture.relativePath}',
          );
          final expectedTableNames = fixture.expectedTableNames;
          if (expectedTableNames != null) {
            expect(
              selectedTables.map((table) => table.targetName).toSet(),
              equals(expectedTableNames.toSet()),
              reason: 'Unexpected preview tables for ${fixture.relativePath}',
            );
          }
          for (final table in selectedTables) {
            final expectedRowCount =
                fixture.expectedRowCountsByTable[table.targetName];
            if (expectedRowCount != null) {
              expect(
                table.rowCount,
                expectedRowCount,
                reason:
                    'Unexpected preview row count for ${fixture.relativePath}:${table.targetName}',
              );
            }
            final expectedColumnTypes =
                fixture.expectedColumnTypesByTable[table.targetName];
            if (expectedColumnTypes == null) {
              continue;
            }
            final previewColumnTypes = <String, String>{
              for (final column in table.columns)
                column.targetName: column.targetType,
            };
            for (final entry in expectedColumnTypes.entries) {
              expect(
                previewColumnTypes[entry.key],
                entry.value,
                reason:
                    'Unexpected preview type for ${fixture.relativePath}:${table.targetName}.${entry.key}',
              );
            }
          }

          final request = SqliteImportRequest(
            jobId: _jobIdFor(fixture.relativePath),
            sourcePath: sourcePath,
            targetPath: _targetPathFor(fixture.relativePath, suiteTempDir),
            importIntoExistingTarget: false,
            replaceExistingTarget: true,
            tables: inspection.tables,
          );
          final updates = await bridge.importSqlite(request: request).toList();
          final terminal = updates.last;

          expect(
            terminal.kind,
            SqliteImportUpdateKind.completed,
            reason: 'Import failed for ${fixture.relativePath}',
          );
          expect(File(request.targetPath).existsSync(), isTrue);

          final summary = terminal.summary!;
          expect(
            summary.importedTables.toSet(),
            equals(selectedTables.map((table) => table.targetName).toSet()),
          );

          await bridge.openDatabase(request.targetPath);
          final schema = await bridge.loadSchema();
          for (final table in selectedTables) {
            final actualRows = await _queryAllRows(
              bridge,
              'SELECT ${table.columns.map((column) => _quoteIdentifier(column.targetName)).join(", ")} '
              'FROM ${_quoteIdentifier(table.targetName)}',
            );
            final expectedSignatures = _loadSqliteExpectedRows(
              sourcePath: sourcePath,
              table: table,
            );
            final actualSignatures =
                _canonicalizeActualRows(actualRows, <_TypedColumn>[
                  for (final column in table.columns)
                    (name: column.targetName, targetType: column.targetType),
                ]);

            expect(
              summary.rowsCopiedByTable[table.targetName],
              table.rowCount,
              reason:
                  'Copied row count mismatch for ${fixture.relativePath}:${table.targetName}',
            );
            final expectedColumnTypes =
                fixture.expectedColumnTypesByTable[table.targetName];
            if (expectedColumnTypes != null) {
              final importedObject = schema.objectNamed(table.targetName);
              expect(
                importedObject,
                isNotNull,
                reason:
                    'Missing imported schema for ${fixture.relativePath}:${table.targetName}',
              );
              final importedColumnTypes = <String, String>{
                for (final column in importedObject!.columns)
                  column.name: _normalizeImportedSchemaType(column.type),
              };
              for (final entry in expectedColumnTypes.entries) {
                expect(
                  importedColumnTypes[entry.key],
                  entry.value,
                  reason:
                      'Unexpected imported type for ${fixture.relativePath}:${table.targetName}.${entry.key}',
                );
              }
            }
            expect(
              actualSignatures,
              orderedEquals(expectedSignatures),
              reason:
                  'Row mismatch for ${fixture.relativePath}:${table.targetName}',
            );
          }
        },
      );
    }
  });

  group('SQLite inspection-only fixtures', () {
    for (final fixture in sqliteInspectionFixtures) {
      test(
        'inspects ${fixture.relativePath}',
        skip: skipReason,
        timeout: const Timeout(Duration(minutes: 2)),
        () async {
          final sourcePath = _resolveRepoRelativePath(fixture.relativePath);
          final detection = await detectionService.detect(sourcePath);

          expect(detection.format.key, ImportFormatKey.sqlite);
          for (final substring in fixture.expectedDetectionWarningSubstrings) {
            expect(
              detection.warnings.join('\n'),
              contains(substring),
              reason:
                  'Expected detection warning for ${fixture.relativePath}: $substring',
            );
          }

          final inspection = await bridge.inspectSqliteSource(
            sourcePath: sourcePath,
          );
          final expectedTableCount = fixture.expectedTableCount;
          if (expectedTableCount != null) {
            expect(inspection.tables, hasLength(expectedTableCount));
          } else {
            expect(inspection.tables, isNotEmpty);
          }
        },
      );
    }
  });

  group('Excel import round-trip fixtures', () {
    for (final fixture in excelImportRoundTripFixtures) {
      test(
        'imports ${fixture.relativePath}',
        skip: skipReason,
        timeout: const Timeout(Duration(minutes: 2)),
        () async {
          final sourcePath = _resolveRepoRelativePath(fixture.relativePath);
          final inspection = await bridge.inspectExcelSource(
            sourcePath: sourcePath,
            headerRow: fixture.headerRow,
          );
          final selectedSheets = inspection.sheets
              .where((sheet) => sheet.selected)
              .toList(growable: false);

          expect(
            selectedSheets,
            isNotEmpty,
            reason:
                'Expected at least one selected Excel sheet for ${fixture.relativePath}',
          );

          final request = ExcelImportRequest(
            jobId: _jobIdFor(fixture.relativePath),
            sourcePath: sourcePath,
            targetPath: _targetPathFor(fixture.relativePath, suiteTempDir),
            importIntoExistingTarget: false,
            replaceExistingTarget: true,
            headerRow: fixture.headerRow,
            sheets: inspection.sheets,
          );
          final materialized = materializeExcelImportSourceFile(
            sourcePath: sourcePath,
            headerRow: fixture.headerRow,
            sheets: inspection.sheets,
          );
          final materializedTablesByTarget =
              <String, ExcelMaterializedTableData>{
                for (final table in materialized.tables)
                  table.targetName: table,
              };
          final materializedViewsByTarget = <String, ExcelMaterializedViewData>{
            for (final view in materialized.views) view.targetName: view,
          };

          final updates = await bridge.importExcel(request: request).toList();
          final terminal = updates.last;

          expect(
            terminal.kind,
            ExcelImportUpdateKind.completed,
            reason: 'Import failed for ${fixture.relativePath}',
          );
          expect(File(request.targetPath).existsSync(), isTrue);

          final summary = terminal.summary!;
          expect(
            summary.importedTables.toSet(),
            equals(materializedTablesByTarget.keys.toSet()),
          );
          expect(
            summary.importedViews.toSet(),
            equals(materializedViewsByTarget.keys.toSet()),
          );

          if (p.extension(sourcePath).toLowerCase() == '.xls') {
            expect(
              <String>[
                ...inspection.warnings,
                ...materialized.warnings,
                ...summary.warnings,
              ].join('\n'),
              contains('converted to temporary `.xlsx`'),
              reason:
                  'Expected legacy workbook conversion warning for ${fixture.relativePath}',
            );
          }

          await bridge.openDatabase(request.targetPath);
          final schema = await bridge.loadSchema();
          for (final sheet in selectedSheets) {
            if (materializedTablesByTarget.containsKey(sheet.targetName)) {
              final materializedTable =
                  materializedTablesByTarget[sheet.targetName]!;
              final actualRows = await _queryAllRows(
                bridge,
                'SELECT ${sheet.columns.map((column) => _quoteIdentifier(column.targetName)).join(", ")} '
                'FROM ${_quoteIdentifier(sheet.targetName)}',
              );
              final expectedSignatures = _canonicalizeExcelExpectedRows(
                materializedTable.rows,
                sheet.columns,
              );
              final actualSignatures =
                  _canonicalizeActualRows(actualRows, <_TypedColumn>[
                    for (final column in sheet.columns)
                      (name: column.targetName, targetType: column.targetType),
                  ]);

              expect(
                summary.rowsCopiedByTable[sheet.targetName],
                materializedTable.rows.length,
                reason:
                    'Copied row count mismatch for ${fixture.relativePath}:${sheet.targetName}',
              );
              expect(
                actualSignatures,
                orderedEquals(expectedSignatures),
                reason:
                    'Row mismatch for ${fixture.relativePath}:${sheet.targetName}',
              );
              continue;
            }

            final materializedView =
                materializedViewsByTarget[sheet.targetName]!;
            final schemaView = schema.objects.firstWhere(
              (object) =>
                  object.name.toLowerCase() == sheet.targetName.toLowerCase(),
              orElse: () => const SchemaObjectSummary(
                name: '',
                kind: SchemaObjectKind.table,
                temporary: false,
                ddl: null,
                columns: <SchemaColumn>[],
              ),
            );
            final viewCountRows = await _queryAllRows(
              bridge,
              'SELECT COUNT(*) AS row_count FROM ${_quoteIdentifier(sheet.targetName)}',
            );

            expect(
              schemaView.name,
              isNotEmpty,
              reason:
                  'View missing from schema for ${fixture.relativePath}:${sheet.targetName}',
            );
            expect(
              schemaView.kind,
              SchemaObjectKind.view,
              reason:
                  'Imported object is not a view for ${fixture.relativePath}:${sheet.targetName}',
            );
            expect(
              viewCountRows.single['row_count'],
              materializedView.rowCount,
              reason:
                  'View row count mismatch for ${fixture.relativePath}:${sheet.targetName}',
            );
            expect(
              schemaView.columns
                  .map((column) => column.name)
                  .toList(growable: false),
              orderedEquals(materializedView.columnNames),
              reason:
                  'View column mismatch for ${fixture.relativePath}:${sheet.targetName}',
            );
          }
        },
      );
    }
  });

  group('SQL dump import round-trip fixtures', () {
    for (final fixture in sqlDumpImportRoundTripFixtures) {
      test(
        'imports ${fixture.relativePath}',
        skip: skipReason,
        timeout: const Timeout(Duration(minutes: 2)),
        () async {
          final resolved = await _resolveFixtureSource(
            relativePath: fixture.relativePath,
            formatKey: ImportFormatKey.sqlDump,
            extractWrappedSource: fixture.extractWrappedSource,
            detectionService: detectionService,
          );
          try {
            final inspection = await bridge.inspectSqlDumpSource(
              sourcePath: resolved.sourcePath,
              encoding: fixture.encoding,
            );
            final selectedTables = inspection.tables
                .where((table) => table.selected)
                .toList(growable: false);

            expect(
              selectedTables,
              isNotEmpty,
              reason:
                  'Expected at least one selected SQL dump table for ${fixture.relativePath}',
            );

            final request = SqlDumpImportRequest(
              jobId: _jobIdFor(fixture.relativePath),
              sourcePath: resolved.sourcePath,
              targetPath: _targetPathFor(fixture.relativePath, suiteTempDir),
              importIntoExistingTarget: false,
              replaceExistingTarget: true,
              encoding: fixture.encoding,
              tables: inspection.tables,
            );
            final materialized = materializeSqlDumpSourceFile(
              resolved.sourcePath,
              encoding: fixture.encoding,
              tables: inspection.tables,
            );
            final materializedByTarget = <String, SqlDumpMaterializedTableData>{
              for (final table in materialized.tables) table.targetName: table,
            };

            final updates = await bridge
                .importSqlDump(request: request)
                .toList();
            final terminal = updates.last;

            expect(
              terminal.kind,
              SqlDumpImportUpdateKind.completed,
              reason: 'Import failed for ${fixture.relativePath}',
            );
            expect(File(request.targetPath).existsSync(), isTrue);

            final summary = terminal.summary!;
            expect(
              summary.importedTables.toSet(),
              equals(materializedByTarget.keys.toSet()),
            );
            expect(
              summary.skippedStatementCount,
              materialized.skippedStatements.length,
            );
            if (fixture.requireSkippedStatements) {
              expect(
                summary.skippedStatementCount,
                greaterThan(0),
                reason:
                    'Expected partial-support skipped statements for ${fixture.relativePath}',
              );
            }

            await bridge.openDatabase(request.targetPath);
            for (final table in selectedTables) {
              final materializedTable = materializedByTarget[table.targetName]!;
              final actualRows = await _queryAllRows(
                bridge,
                'SELECT ${table.columns.map((column) => _quoteIdentifier(column.targetName)).join(", ")} '
                'FROM ${_quoteIdentifier(table.targetName)}',
              );
              final expectedSignatures = _canonicalizeSqlDumpExpectedRows(
                materializedTable.rows,
                table.columns,
              );
              final actualSignatures =
                  _canonicalizeActualRows(actualRows, <_TypedColumn>[
                    for (final column in table.columns)
                      (name: column.targetName, targetType: column.targetType),
                  ]);

              expect(
                summary.rowsCopiedByTable[table.targetName] ?? 0,
                materializedTable.rows.length,
                reason:
                    'Copied row count mismatch for ${fixture.relativePath}:${table.targetName}',
              );
              expect(
                actualSignatures,
                orderedEquals(expectedSignatures),
                reason:
                    'Row mismatch for ${fixture.relativePath}:${table.targetName}',
              );
            }
          } finally {
            final cleanupDirectory = resolved.cleanupDirectory;
            if (cleanupDirectory != null && cleanupDirectory.existsSync()) {
              await cleanupDirectory.delete(recursive: true);
            }
          }
        },
      );
    }
  });

  group('detection-only fixtures', () {
    for (final fixture in detectionFixtures) {
      test(
        'detects ${fixture.relativePath}',
        timeout: const Timeout(Duration(minutes: 2)),
        () async {
          final sourcePath = _resolveRepoRelativePath(fixture.relativePath);
          final detection = await detectionService.detect(sourcePath);

          expect(detection.format.key, fixture.expectedFormatKey);
          expect(detection.format.supportState, fixture.expectedSupportState);
          expect(
            detection.format.implementationKind,
            fixture.expectedImplementationKind,
          );
          expect(
            detection.archiveCandidates.map((item) => item.innerFormatKey),
            orderedEquals(fixture.expectedArchiveCandidateKeys),
          );
          for (final substring in fixture.expectedWarningSubstrings) {
            expect(
              detection.warnings.join('\n'),
              contains(substring),
              reason:
                  'Expected detection warning for ${fixture.relativePath}: $substring',
            );
          }
        },
      );
    }
  });
}

Future<_ResolvedFixtureSource> _resolveFixtureSource({
  required String relativePath,
  required ImportFormatKey formatKey,
  required bool extractWrappedSource,
  required ImportDetectionService detectionService,
}) async {
  final sourcePath = _resolveRepoRelativePath(relativePath);
  if (!extractWrappedSource) {
    return _ResolvedFixtureSource(sourcePath: sourcePath, formatKey: formatKey);
  }

  final detection = await detectionService.detect(sourcePath);
  final candidate = detection.archiveCandidates.firstWhere(
    (entry) => entry.innerFormatKey == formatKey,
    orElse: () => throw StateError(
      'Could not find ${formatKey.name} candidate for $relativePath',
    ),
  );
  final extractedPath = await detectionService.extractArchiveCandidate(
    archivePath: sourcePath,
    wrapperKey: detection.format.key,
    candidate: candidate,
  );

  return _ResolvedFixtureSource(
    sourcePath: extractedPath,
    formatKey: candidate.innerFormatKey,
    cleanupDirectory: Directory(p.dirname(extractedPath)),
  );
}

Future<List<Map<String, Object?>>> _queryAllRows(
  DecentDbBridge bridge,
  String sql,
) async {
  final firstPage = await bridge.runQuery(
    sql: sql,
    params: const <Object?>[],
    pageSize: 256,
  );
  final rows = <Map<String, Object?>>[...firstPage.rows];
  var cursorId = firstPage.cursorId;

  while (cursorId != null) {
    final nextPage = await bridge.fetchNextPage(
      cursorId: cursorId,
      pageSize: 256,
    );
    rows.addAll(nextPage.rows);
    cursorId = nextPage.cursorId;
  }

  return rows;
}

List<String> _canonicalizeGenericExpectedRows(
  List<Map<String, Object?>> rows,
  List<ImportColumnDraft> columns,
) {
  final typedColumns = <_TypedColumn>[
    for (final column in columns)
      (name: column.targetName, targetType: column.targetType),
  ];
  final typeInferenceService = const TypeInferenceService();
  final signatures = <String>[
    for (final row in rows)
      _typedRowSignature(<String, Object?>{
        for (final column in columns)
          column.targetName: _coerceGenericExpectedValue(
            typeInferenceService.coerceValue(
              row[column.sourceName],
              column.targetType,
            ),
            column.targetType,
          ),
      }, typedColumns),
  ];
  signatures.sort();
  return signatures;
}

Object? _coerceGenericExpectedValue(Object? value, String targetType) {
  if (targetType == 'UUID' && value is String) {
    return _uuidBytes(value);
  }
  return value;
}

List<String> _loadSqliteExpectedRows({
  required String sourcePath,
  required SqliteImportTableDraft table,
}) {
  final database = sqlite.sqlite3.open(
    sourcePath,
    mode: sqlite.OpenMode.readOnly,
  );
  try {
    final sourceColumns = table.columns
        .map((column) => _quoteIdentifier(column.sourceName))
        .join(', ');
    final rows = database.select(
      'SELECT $sourceColumns FROM ${_quoteIdentifier(table.sourceName)}',
    );
    final typedColumns = <_TypedColumn>[
      for (final column in table.columns)
        (name: column.targetName, targetType: column.targetType),
    ];
    final signatures = <String>[
      for (final row in rows)
        _typedRowSignature(<String, Object?>{
          for (final column in table.columns)
            column.targetName: _adaptSqliteImportValue(
              row[column.sourceName],
              column.targetType,
            ),
        }, typedColumns),
    ];
    signatures.sort();
    return signatures;
  } finally {
    database.close();
  }
}

List<String> _canonicalizeActualRows(
  List<Map<String, Object?>> rows,
  List<_TypedColumn> columns,
) {
  final signatures = <String>[
    for (final row in rows) _typedRowSignature(row, columns),
  ];
  signatures.sort();
  return signatures;
}

List<String> _canonicalizeExcelExpectedRows(
  List<Map<String, Object?>> rows,
  List<ExcelImportColumnDraft> columns,
) {
  final typedColumns = <_TypedColumn>[
    for (final column in columns)
      (name: column.targetName, targetType: column.targetType),
  ];
  final signatures = <String>[
    for (final row in rows)
      _typedRowSignature(<String, Object?>{
        for (final column in columns)
          column.targetName: _coerceGenericExpectedValue(
            row[column.targetName],
            column.targetType,
          ),
      }, typedColumns),
  ];
  signatures.sort();
  return signatures;
}

List<String> _canonicalizeSqlDumpExpectedRows(
  List<Map<String, Object?>> rows,
  List<SqlDumpImportColumnDraft> columns,
) {
  final typedColumns = <_TypedColumn>[
    for (final column in columns)
      (name: column.targetName, targetType: column.targetType),
  ];
  final signatures = <String>[
    for (final row in rows)
      _typedRowSignature(<String, Object?>{
        for (final column in columns)
          column.targetName: _coerceGenericExpectedValue(
            row[column.targetName],
            column.targetType,
          ),
      }, typedColumns),
  ];
  signatures.sort();
  return signatures;
}

String _typedRowSignature(
  Map<String, Object?> row,
  List<_TypedColumn> columns,
) {
  final ordered = <Object?>[
    for (final column in columns)
      <Object?>[
        column.name,
        _canonicalizeTypedValue(row[column.name], column.targetType),
      ],
  ];
  return jsonEncode(ordered);
}

Object? _canonicalizeTypedValue(Object? value, String targetType) {
  if (_isDecimalType(targetType)) {
    return _canonicalizeValue(_normalizeDecimalValue(value));
  }
  if (value is num) {
    return _canonicalizeValue(_normalizeNumericValue(value));
  }
  return _canonicalizeValue(value);
}

Object? _canonicalizeValue(Object? value) {
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is Uint8List) {
    return base64Encode(value);
  }
  if (value is List<Object?>) {
    return value.map(_canonicalizeValue).toList(growable: false);
  }
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.map((key) => '$key').toList(growable: false)
      ..sort();
    return <Object?>[
      for (final key in keys) <Object?>[key, _canonicalizeValue(value[key])],
    ];
  }
  return value;
}

Object _normalizeNumericValue(num value) {
  final asDouble = value.toDouble();
  if (asDouble.isNaN) {
    return 'NaN';
  }
  if (asDouble.isInfinite) {
    return asDouble.isNegative ? '-Infinity' : 'Infinity';
  }
  return asDouble == asDouble.roundToDouble() ? asDouble.toInt() : asDouble;
}

Object? _normalizeDecimalValue(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    if (RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(trimmed)) {
      final negative = trimmed.startsWith('-');
      final unsigned = negative ? trimmed.substring(1) : trimmed;
      final parts = unsigned.split('.');
      final wholePart = parts[0];
      if (parts.length == 1) {
        return trimmed == '-0' ? '0' : trimmed;
      }

      final fractionPart = parts[1].replaceFirst(RegExp(r'0+$'), '');
      final normalizedWhole = wholePart == '0' && fractionPart.isEmpty
          ? '0'
          : wholePart;
      final normalized = fractionPart.isEmpty
          ? normalizedWhole
          : '$normalizedWhole.$fractionPart';
      if (normalized == '0') {
        return '0';
      }
      return negative ? '-$normalized' : normalized;
    }
    return value;
  }
  if (value is num) {
    return _normalizeDecimalValue(value.toString());
  }
  return value;
}

Object? _adaptSqliteImportValue(Object? value, String targetType) {
  if (value == null) {
    return null;
  }
  if (targetType == 'BOOLEAN') {
    return _coerceSqliteBooleanValue(value);
  }
  if (targetType == 'TEXT' && value is Uint8List) {
    return formatCellValue(value);
  }
  if (targetType == 'BLOB' && value is String) {
    return Uint8List.fromList(value.codeUnits);
  }
  if (targetType == 'TIMESTAMP') {
    return _tryParseSqliteTimestampValue(value) ?? value;
  }
  if (targetType == 'UUID' && value is String) {
    return _uuidBytes(value);
  }
  if ((targetType.startsWith('DECIMAL') || targetType.startsWith('NUMERIC')) &&
      value is num) {
    return value.toString();
  }
  return value;
}

Object? _coerceSqliteBooleanValue(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is int && (value == 0 || value == 1)) {
    return value == 1;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (const <String>{'true', '1', 'yes', 'y'}.contains(normalized)) {
      return true;
    }
    if (const <String>{'false', '0', 'no', 'n'}.contains(normalized)) {
      return false;
    }
  }
  return value;
}

DateTime? _tryParseSqliteTimestampValue(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is int) {
    return _tryParseEpochTimestampValue(value);
  }
  if (value is double && value == value.roundToDouble()) {
    return _tryParseEpochTimestampValue(value.toInt());
  }
  if (value is! String) {
    return null;
  }

  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final parsed = DateTime.tryParse(trimmed);
  if (parsed != null) {
    return parsed.toUtc();
  }

  final slashParsed = _tryParseSlashTimestampValue(trimmed);
  if (slashParsed != null) {
    return slashParsed;
  }

  final dotParsed = _tryParseDotTimestampValue(trimmed);
  if (dotParsed != null) {
    return dotParsed;
  }

  final timeOnlyParsed = _tryParseTimeOnlyTimestampValue(trimmed);
  if (timeOnlyParsed != null) {
    return timeOnlyParsed;
  }

  final asInteger = int.tryParse(trimmed);
  if (asInteger == null) {
    return null;
  }
  return _tryParseEpochTimestampValue(asInteger);
}

DateTime? _tryParseTimeOnlyTimestampValue(String value) {
  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  final microsRaw = match.group(4) ?? '';
  final micros = microsRaw.isEmpty
      ? 0
      : int.parse(microsRaw.padRight(6, '0').substring(0, 6));
  return _buildUtcTimestampValue(
    year: 0,
    month: 1,
    day: 1,
    hour: int.parse(match.group(1)!),
    minute: int.parse(match.group(2)!),
    second: int.tryParse(match.group(3) ?? '0') ?? 0,
    microsecond: micros,
  );
}

DateTime? _tryParseSlashTimestampValue(String value) {
  final match = RegExp(
    r'^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  return _buildUtcTimestampValue(
    year: int.parse(match.group(3)!),
    month: int.parse(match.group(1)!),
    day: int.parse(match.group(2)!),
    hour: int.tryParse(match.group(4) ?? '0') ?? 0,
    minute: int.tryParse(match.group(5) ?? '0') ?? 0,
    second: int.tryParse(match.group(6) ?? '0') ?? 0,
  );
}

DateTime? _tryParseDotTimestampValue(String value) {
  final match = RegExp(
    r'^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  return _buildUtcTimestampValue(
    year: int.parse(match.group(3)!),
    month: int.parse(match.group(2)!),
    day: int.parse(match.group(1)!),
    hour: int.tryParse(match.group(4) ?? '0') ?? 0,
    minute: int.tryParse(match.group(5) ?? '0') ?? 0,
    second: int.tryParse(match.group(6) ?? '0') ?? 0,
  );
}

DateTime? _buildUtcTimestampValue({
  required int year,
  required int month,
  required int day,
  int hour = 0,
  int minute = 0,
  int second = 0,
  int microsecond = 0,
}) {
  try {
    final parsed = DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      0,
      microsecond,
    );
    if (parsed.year != year ||
        parsed.month != month ||
        parsed.day != day ||
        parsed.hour != hour ||
        parsed.minute != minute ||
        parsed.second != second ||
        parsed.microsecond != microsecond) {
      return null;
    }
    return parsed;
  } catch (_) {
    return null;
  }
}

DateTime? _tryParseEpochTimestampValue(int value) {
  if (value >= 0 && value <= 4102444800) {
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }
  if (value >= 0 && value <= 4102444800000) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  return null;
}

Uint8List _uuidBytes(String value) {
  final hex = value.replaceAll('-', '');
  if (hex.length != 32) {
    return Uint8List.fromList(utf8.encode(value));
  }
  final bytes = <int>[];
  for (var index = 0; index < hex.length; index += 2) {
    bytes.add(int.parse(hex.substring(index, index + 2), radix: 16));
  }
  return Uint8List.fromList(bytes);
}

bool _isDecimalType(String targetType) {
  return targetType.startsWith('DECIMAL') || targetType.startsWith('NUMERIC');
}

String _resolveRepoRelativePath(String relativePath) {
  final candidates = <String>[
    p.normalize(p.join(Directory.current.path, relativePath)),
    p.normalize(p.join(Directory.current.path, '..', relativePath)),
    p.normalize(p.join(Directory.current.path, '..', '..', relativePath)),
  ];
  for (final candidate in candidates) {
    if (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
      return candidate;
    }
  }
  throw StateError(
    'Could not resolve $relativePath from ${Directory.current.path}',
  );
}

String _targetPathFor(String relativePath, Directory tempRoot) {
  final basename = relativePath.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  return p.join(tempRoot.path, '$basename.ddb');
}

String _jobIdFor(String relativePath) {
  return relativePath
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}

String _quoteIdentifier(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

String _normalizeImportedSchemaType(String type) {
  return switch (type.toUpperCase()) {
    'INT64' => 'INTEGER',
    'BOOL' => 'BOOLEAN',
    _ => type.toUpperCase(),
  };
}

Set<String> _manifestCoveredFixturePaths() {
  return <String>{
    for (final fixture in genericImportRoundTripFixtures) fixture.relativePath,
    for (final fixture in genericInspectionFixtures) fixture.relativePath,
    for (final fixture in sqliteImportRoundTripFixtures) fixture.relativePath,
    for (final fixture in sqliteInspectionFixtures) fixture.relativePath,
    for (final fixture in excelImportRoundTripFixtures) fixture.relativePath,
    for (final fixture in sqlDumpImportRoundTripFixtures) fixture.relativePath,
    for (final fixture in detectionFixtures) fixture.relativePath,
  };
}
