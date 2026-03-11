import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:decentdb/decentdb.dart';

import '../../workspace/infrastructure/native_library_resolver.dart';
import '../domain/import_models.dart';
import 'delimited_import_support.dart';
import 'html_import_support.dart';
import 'import_format_registry.dart';
import 'structured_import_support.dart';
import 'type_inference_service.dart';

class ImportExecutionService {
  ImportExecutionService({
    NativeLibraryResolver? resolver,
    ImportFormatRegistry? registry,
    TypeInferenceService? typeInferenceService,
  }) : _resolver = resolver ?? NativeLibraryResolver(),
       _registry = registry ?? ImportFormatRegistry.instance,
       _typeInferenceService =
           typeInferenceService ?? const TypeInferenceService();

  final NativeLibraryResolver _resolver;
  final ImportFormatRegistry _registry;
  final TypeInferenceService _typeInferenceService;
  final Map<String, _GenericImportOperation> _operations =
      <String, _GenericImportOperation>{};

  Future<String> resolveLibraryPath() {
    return _resolver.resolve();
  }

  Stream<GenericImportUpdate> execute({required GenericImportRequest request}) {
    final existing = _operations[request.jobId];
    if (existing != null) {
      return existing.stream;
    }
    final controller = StreamController<GenericImportUpdate>();
    final operation = _GenericImportOperation(controller: controller);
    _operations[request.jobId] = operation;
    unawaited(_spawnImportWorker(request, operation));
    return controller.stream;
  }

  Future<void> cancel(String jobId) async {
    final operation = _operations[jobId];
    operation?.commandPort?.send('cancel');
  }

  Future<void> _spawnImportWorker(
    GenericImportRequest request,
    _GenericImportOperation operation,
  ) async {
    final libraryPath = await resolveLibraryPath();
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn<List<Object?>>(
      genericImportWorkerMain,
      <Object?>[receivePort.sendPort, libraryPath, request.toMap()],
    );
    operation.isolate = isolate;
    operation.receivePort = receivePort;
    receivePort.listen((message) async {
      if (message is SendPort) {
        operation.commandPort = message;
        return;
      }
      if (message is! Map<Object?, Object?>) {
        return;
      }
      final update = GenericImportUpdate.fromMap(
        message.map((key, value) => MapEntry(key as String, value)),
      );
      operation.controller.add(update);
      if (update.kind == GenericImportUpdateKind.completed ||
          update.kind == GenericImportUpdateKind.failed ||
          update.kind == GenericImportUpdateKind.cancelled) {
        await operation.dispose();
        _operations.remove(request.jobId);
      }
    });
  }

  MaterializedImportSource materializeRequest(GenericImportRequest request) {
    final format = _registry.forKey(request.formatKey);
    switch (request.formatKey) {
      case ImportFormatKey.csv:
      case ImportFormatKey.tsv:
      case ImportFormatKey.genericDelimited:
        return materializeDelimitedSourceSync(
          sourcePath: request.sourcePath,
          format: format,
          options: request.options,
          typeInferenceService: _typeInferenceService,
        );
      case ImportFormatKey.json:
      case ImportFormatKey.ndjson:
      case ImportFormatKey.xml:
        return materializeStructuredSourceSync(
          sourcePath: request.sourcePath,
          format: format,
          options: request.options,
          typeInferenceService: _typeInferenceService,
        );
      case ImportFormatKey.htmlTable:
        return materializeHtmlTableSourceSync(
          sourcePath: request.sourcePath,
          format: format,
          options: request.options,
          typeInferenceService: _typeInferenceService,
        );
      default:
        throw StateError(
          'Format ${request.formatKey.name} does not use the generic execution service.',
        );
    }
  }
}

class _GenericImportOperation {
  _GenericImportOperation({required this.controller});

  final StreamController<GenericImportUpdate> controller;
  Isolate? isolate;
  ReceivePort? receivePort;
  SendPort? commandPort;

  Stream<GenericImportUpdate> get stream => controller.stream;

  Future<void> dispose() async {
    receivePort?.close();
    isolate?.kill(priority: Isolate.immediate);
    await controller.close();
  }
}

@pragma('vm:entry-point')
Future<void> genericImportWorkerMain(List<Object?> bootstrap) async {
  final mainPort = bootstrap[0]! as SendPort;
  final libraryPath = bootstrap[1]! as String;
  final request = GenericImportRequest.fromMap(
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
    final summary = await _runGenericImport(
      request: request,
      libraryPath: libraryPath,
      sendUpdate: (update) => mainPort.send(update.toMap()),
      isCancelled: () => cancelled,
    );
    mainPort.send(
      GenericImportUpdate(
        kind: cancelled
            ? GenericImportUpdateKind.cancelled
            : GenericImportUpdateKind.completed,
        jobId: request.jobId,
        summary: summary,
      ).toMap(),
    );
  } on _GenericImportCancelled catch (error) {
    mainPort.send(
      GenericImportUpdate(
        kind: GenericImportUpdateKind.cancelled,
        jobId: request.jobId,
        summary: error.summary,
        message: error.summary.statusMessage,
      ).toMap(),
    );
  } catch (error) {
    mainPort.send(
      GenericImportUpdate(
        kind: GenericImportUpdateKind.failed,
        jobId: request.jobId,
        message: error.toString(),
      ).toMap(),
    );
  } finally {
    await commandSubscription.cancel();
    commandPort.close();
  }
}

Future<GenericImportSummary> _runGenericImport({
  required GenericImportRequest request,
  required String libraryPath,
  required void Function(GenericImportUpdate update) sendUpdate,
  required bool Function() isCancelled,
}) async {
  final executionService = ImportExecutionService();
  final materialized = executionService.materializeRequest(request);
  final selectedDrafts = request.selectedTables;
  if (selectedDrafts.isEmpty) {
    throw StateError('Select at least one table to import.');
  }
  if (!hasDistinctNames(selectedDrafts.map((table) => table.targetName))) {
    throw StateError('Target table names must be distinct.');
  }

  final targetFile = File(request.targetPath);
  if (request.importIntoExistingTarget) {
    if (!targetFile.existsSync()) {
      throw StateError(
        'Target DecentDB file does not exist: ${request.targetPath}',
      );
    }
  } else {
    targetFile.parent.createSync(recursive: true);
    if (targetFile.existsSync()) {
      if (!request.replaceExistingTarget) {
        throw StateError(
          'Refusing to replace an existing DecentDB file without confirmation: ${request.targetPath}',
        );
      }
      targetFile.deleteSync();
      final walFile = File('${request.targetPath}-wal');
      if (walFile.existsSync()) {
        walFile.deleteSync();
      }
      final shmFile = File('${request.targetPath}-shm');
      if (shmFile.existsSync()) {
        shmFile.deleteSync();
      }
    }
  }

  final resolvedTables = <_ResolvedImportTable>[];
  for (final draft in selectedDrafts) {
    final source = materialized.tables.firstWhere(
      (table) => table.sourceId == draft.sourceId,
      orElse: () => throw StateError(
        'Source table `${draft.sourceName}` is no longer available for import.',
      ),
    );
    if (!hasDistinctNames(draft.columns.map((column) => column.targetName))) {
      throw StateError(
        'Column names in `${draft.targetName}` must be distinct.',
      );
    }
    resolvedTables.add(
      _ResolvedImportTable(
        sourceId: draft.sourceId,
        sourceName: draft.sourceName,
        targetName: draft.targetName,
        rows: source.rows,
        columns: draft.columns,
      ),
    );
  }

  final database = Database.open(request.targetPath, libraryPath: libraryPath);
  var transactionOpen = false;
  final warnings = <String>[...materialized.warnings];
  final rowsCopiedByTable = <String, int>{};
  final typeInferenceService = const TypeInferenceService();

  try {
    final existingTables = database.schema.listTables().toSet();
    final colliding = resolvedTables
        .map((table) => table.targetName)
        .where(existingTables.contains)
        .toList(growable: false);
    if (colliding.isNotEmpty) {
      throw StateError(
        'Target already contains table(s): ${colliding.join(", ")}. Rename them or choose another DecentDB file.',
      );
    }

    database.begin();
    transactionOpen = true;

    for (var index = 0; index < resolvedTables.length; index++) {
      final table = resolvedTables[index];
      _throwIfCancelled(isCancelled);
      database.execute(_buildCreateTableSql(table));
      sendUpdate(
        GenericImportUpdate(
          kind: GenericImportUpdateKind.progress,
          jobId: request.jobId,
          progress: GenericImportProgress(
            jobId: request.jobId,
            currentTable: table.targetName,
            completedTables: index,
            totalTables: resolvedTables.length,
            currentTableRowsCopied: 0,
            currentTableRowCount: table.rows.length,
            totalRowsCopied: rowsCopiedByTable.values.fold<int>(
              0,
              (sum, value) => sum + value,
            ),
            message: 'Created table ${table.targetName}.',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }

    for (var index = 0; index < resolvedTables.length; index++) {
      final table = resolvedTables[index];
      final copied = await _copyTableData(
        database: database,
        table: table,
        request: request,
        completedTables: index,
        totalTables: resolvedTables.length,
        priorRowsCopied: rowsCopiedByTable.values.fold<int>(
          0,
          (sum, value) => sum + value,
        ),
        sendUpdate: sendUpdate,
        isCancelled: isCancelled,
        typeInferenceService: typeInferenceService,
      );
      rowsCopiedByTable[table.targetName] = copied;
      warnings.addAll(
        table.columns
            .where((column) => column.targetType != column.inferredTargetType)
            .map(
              (column) =>
                  '${table.targetName}.${column.targetName} overrides ${column.inferredTargetType} as ${column.targetType}.',
            ),
      );
    }

    database.commit();
    transactionOpen = false;
    return GenericImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      formatLabel: materialized.format.label,
      importedTables: resolvedTables
          .map((table) => table.targetName)
          .toList(growable: false),
      rowsCopiedByTable: rowsCopiedByTable,
      warnings: warnings,
      statusMessage:
          'Imported ${rowsCopiedByTable.values.fold<int>(0, (sum, value) => sum + value)} rows from ${resolvedTables.length} table${resolvedTables.length == 1 ? '' : 's'}.',
      rolledBack: false,
    );
  } on _GenericImportCancelledSignal {
    if (transactionOpen) {
      try {
        database.rollback();
      } catch (_) {
        // Best-effort rollback for cancellation.
      }
    }
    final summary = GenericImportSummary(
      jobId: request.jobId,
      sourcePath: request.sourcePath,
      targetPath: request.targetPath,
      formatLabel: materialized.format.label,
      importedTables: rowsCopiedByTable.keys.toList(growable: false),
      rowsCopiedByTable: rowsCopiedByTable,
      warnings: warnings,
      statusMessage: 'Import cancelled and rolled back.',
      rolledBack: true,
    );
    throw _GenericImportCancelled(summary);
  } catch (_) {
    if (transactionOpen) {
      try {
        database.rollback();
      } catch (_) {
        // Best-effort rollback on failure.
      }
    }
    rethrow;
  } finally {
    database.close();
  }
}

Future<int> _copyTableData({
  required Database database,
  required _ResolvedImportTable table,
  required GenericImportRequest request,
  required int completedTables,
  required int totalTables,
  required int priorRowsCopied,
  required void Function(GenericImportUpdate update) sendUpdate,
  required bool Function() isCancelled,
  required TypeInferenceService typeInferenceService,
}) async {
  final placeholders = <String>[
    for (var index = 0; index < table.columns.length; index++)
      placeholderForTargetType(table.columns[index].targetType, index + 1),
  ];
  final statement = database.prepare(
    'INSERT INTO ${_quoteIdentifier(table.targetName)} '
    '(${table.columns.map((column) => _quoteIdentifier(column.targetName)).join(", ")}) '
    'VALUES (${placeholders.join(", ")})',
  );

  var copied = 0;
  try {
    for (final row in table.rows) {
      _throwIfCancelled(isCancelled);
      final values = <Object?>[
        for (final column in table.columns)
          typeInferenceService.coerceValue(
            row[column.sourceName],
            column.targetType,
          ),
      ];
      statement.reset();
      statement.clearBindings();
      statement.bindAll(values);
      statement.execute();
      copied++;
      if (copied == 1 ||
          copied % genericImportProgressBatchSize == 0 ||
          copied == table.rows.length) {
        sendUpdate(
          GenericImportUpdate(
            kind: GenericImportUpdateKind.progress,
            jobId: request.jobId,
            progress: GenericImportProgress(
              jobId: request.jobId,
              currentTable: table.targetName,
              completedTables: completedTables,
              totalTables: totalTables,
              currentTableRowsCopied: copied,
              currentTableRowCount: table.rows.length,
              totalRowsCopied: priorRowsCopied + copied,
              message:
                  'Imported $copied of ${table.rows.length} row${table.rows.length == 1 ? '' : 's'} into ${table.targetName}.',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
  } finally {
    statement.dispose();
  }
  return copied;
}

String _buildCreateTableSql(_ResolvedImportTable table) {
  final columnSql = <String>[
    for (final column in table.columns)
      '${_quoteIdentifier(column.targetName)} ${column.targetType}',
  ];
  return 'CREATE TABLE ${_quoteIdentifier(table.targetName)} (${columnSql.join(", ")})';
}

String _quoteIdentifier(String value) {
  return '"${value.replaceAll('"', '""')}"';
}

void _throwIfCancelled(bool Function() isCancelled) {
  if (isCancelled()) {
    throw const _GenericImportCancelledSignal();
  }
}

class _ResolvedImportTable {
  const _ResolvedImportTable({
    required this.sourceId,
    required this.sourceName,
    required this.targetName,
    required this.rows,
    required this.columns,
  });

  final String sourceId;
  final String sourceName;
  final String targetName;
  final List<Map<String, Object?>> rows;
  final List<ImportColumnDraft> columns;
}

class _GenericImportCancelled implements Exception {
  const _GenericImportCancelled(this.summary);

  final GenericImportSummary summary;
}

class _GenericImportCancelledSignal implements Exception {
  const _GenericImportCancelledSignal();
}
