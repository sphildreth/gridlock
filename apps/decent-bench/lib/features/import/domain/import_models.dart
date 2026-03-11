import '../../workspace/domain/import_target_types.dart';

const int genericImportPreviewRowLimit = 8;
const int genericImportProgressBatchSize = 200;

enum ImportFamily {
  delimitedText,
  spreadsheet,
  structuredDocument,
  database,
  databaseDump,
  analytical,
  legacyBusiness,
  webMarkup,
  compressedArchive,
  logsEvents,
}

enum ImportSupportState {
  complete,
  partial,
  planned,
  deferred,
  investigate,
  notStarted,
}

enum ImportImplementationKind {
  directOpen,
  legacyWizard,
  genericWizard,
  wrapper,
  recognizedUnsupported,
  unknown,
}

enum ImportFormatKey {
  decentDb,
  csv,
  tsv,
  genericDelimited,
  fixedWidth,
  xlsx,
  xls,
  ods,
  json,
  ndjson,
  xml,
  yaml,
  toml,
  htmlTable,
  markdownTable,
  sqlite,
  duckdb,
  access,
  dbf,
  sqlDump,
  postgresPlainDump,
  parquet,
  zipArchive,
  gzipArchive,
  bzip2Archive,
  xzArchive,
  jsonLogStream,
  delimitedLog,
  clipboardTable,
  pdfTables,
  unknown,
}

enum GenericImportWizardStep {
  source,
  target,
  preview,
  transforms,
  execute,
  summary,
}

enum GenericImportJobPhase {
  idle,
  inspecting,
  ready,
  running,
  cancelling,
  completed,
  failed,
  cancelled,
}

enum GenericImportUpdateKind { progress, completed, failed, cancelled }

enum StructuredImportStrategy { flatten, normalize }

enum DelimitedMalformedRowStrategy { padOrTruncate, skipRow }

enum GenericImportEncoding { auto, utf8, latin1 }

class ImportFormatDefinition {
  const ImportFormatDefinition({
    required this.key,
    required this.label,
    required this.family,
    required this.supportState,
    required this.extensions,
    required this.implementationKind,
    required this.description,
    this.note,
  });

  final ImportFormatKey key;
  final String label;
  final ImportFamily family;
  final ImportSupportState supportState;
  final List<String> extensions;
  final ImportImplementationKind implementationKind;
  final String description;
  final String? note;

  bool get isImplemented =>
      implementationKind == ImportImplementationKind.directOpen ||
      implementationKind == ImportImplementationKind.legacyWizard ||
      implementationKind == ImportImplementationKind.genericWizard ||
      implementationKind == ImportImplementationKind.wrapper;

  bool get launchesGenericWizard =>
      implementationKind == ImportImplementationKind.genericWizard;

  bool get launchesLegacyWizard =>
      implementationKind == ImportImplementationKind.legacyWizard;

  bool get isWrapper => implementationKind == ImportImplementationKind.wrapper;

  bool get isDirectOpen =>
      implementationKind == ImportImplementationKind.directOpen;

  bool get isRecognizedButUnavailable =>
      implementationKind == ImportImplementationKind.recognizedUnsupported;
}

class ImportArchiveCandidate {
  const ImportArchiveCandidate({
    required this.entryPath,
    required this.displayName,
    required this.innerFormatKey,
    required this.innerFormatLabel,
    required this.supportState,
  });

  final String entryPath;
  final String displayName;
  final ImportFormatKey innerFormatKey;
  final String innerFormatLabel;
  final ImportSupportState supportState;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'entryPath': entryPath,
      'displayName': displayName,
      'innerFormatKey': innerFormatKey.name,
      'innerFormatLabel': innerFormatLabel,
      'supportState': supportState.name,
    };
  }

  factory ImportArchiveCandidate.fromMap(Map<String, Object?> map) {
    return ImportArchiveCandidate(
      entryPath: map['entryPath']! as String,
      displayName: map['displayName']! as String,
      innerFormatKey: ImportFormatKey.values.byName(
        map['innerFormatKey']! as String,
      ),
      innerFormatLabel: map['innerFormatLabel']! as String,
      supportState: ImportSupportState.values.byName(
        map['supportState']! as String,
      ),
    );
  }
}

class ImportDetectionResult {
  const ImportDetectionResult({
    required this.sourcePath,
    required this.format,
    required this.warnings,
    this.archiveCandidates = const <ImportArchiveCandidate>[],
  });

  final String sourcePath;
  final ImportFormatDefinition format;
  final List<String> warnings;
  final List<ImportArchiveCandidate> archiveCandidates;

  bool get isWrapper => format.isWrapper;

  bool get hasArchiveCandidates => archiveCandidates.isNotEmpty;

  bool get isSupported => format.isImplemented;
}

class ImportColumnDraft {
  const ImportColumnDraft({
    required this.sourceName,
    required this.targetName,
    required this.inferredTargetType,
    required this.targetType,
    required this.containsNulls,
  });

  final String sourceName;
  final String targetName;
  final String inferredTargetType;
  final String targetType;
  final bool containsNulls;

  ImportColumnDraft copyWith({
    String? sourceName,
    String? targetName,
    String? inferredTargetType,
    String? targetType,
    bool? containsNulls,
  }) {
    return ImportColumnDraft(
      sourceName: sourceName ?? this.sourceName,
      targetName: targetName ?? this.targetName,
      inferredTargetType: inferredTargetType ?? this.inferredTargetType,
      targetType: targetType ?? this.targetType,
      containsNulls: containsNulls ?? this.containsNulls,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourceName': sourceName,
      'targetName': targetName,
      'inferredTargetType': inferredTargetType,
      'targetType': targetType,
      'containsNulls': containsNulls,
    };
  }

  factory ImportColumnDraft.fromMap(Map<String, Object?> map) {
    return ImportColumnDraft(
      sourceName: map['sourceName']! as String,
      targetName: map['targetName']! as String,
      inferredTargetType: map['inferredTargetType']! as String,
      targetType: map['targetType']! as String,
      containsNulls: map['containsNulls']! as bool,
    );
  }
}

class ImportTableDraft {
  const ImportTableDraft({
    required this.sourceId,
    required this.sourceName,
    required this.targetName,
    required this.selected,
    required this.rowCount,
    required this.columns,
    required this.previewRows,
    this.description,
    this.warnings = const <String>[],
  });

  final String sourceId;
  final String sourceName;
  final String targetName;
  final bool selected;
  final int rowCount;
  final List<ImportColumnDraft> columns;
  final List<Map<String, Object?>> previewRows;
  final String? description;
  final List<String> warnings;

  ImportTableDraft copyWith({
    String? sourceId,
    String? sourceName,
    String? targetName,
    bool? selected,
    int? rowCount,
    List<ImportColumnDraft>? columns,
    List<Map<String, Object?>>? previewRows,
    Object? description = _unset,
    List<String>? warnings,
  }) {
    return ImportTableDraft(
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      targetName: targetName ?? this.targetName,
      selected: selected ?? this.selected,
      rowCount: rowCount ?? this.rowCount,
      columns: columns ?? this.columns,
      previewRows: previewRows ?? this.previewRows,
      description: description == _unset
          ? this.description
          : description as String?,
      warnings: warnings ?? this.warnings,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourceId': sourceId,
      'sourceName': sourceName,
      'targetName': targetName,
      'selected': selected,
      'rowCount': rowCount,
      'columns': <Map<String, Object?>>[
        for (final column in columns) column.toMap(),
      ],
      'previewRows': previewRows,
      'description': description,
      'warnings': warnings,
    };
  }

  factory ImportTableDraft.fromMap(Map<String, Object?> map) {
    return ImportTableDraft(
      sourceId: map['sourceId']! as String,
      sourceName: map['sourceName']! as String,
      targetName: map['targetName']! as String,
      selected: map['selected']! as bool,
      rowCount: map['rowCount']! as int,
      columns: ((map['columns'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (entry) => ImportColumnDraft.fromMap(
              entry.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      previewRows: ((map['previewRows'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map((row) => row.map((key, value) => MapEntry(key as String, value)))
          .toList(),
      description: map['description'] as String?,
      warnings: ((map['warnings'] as List?) ?? const <Object?>[])
          .cast<String>(),
    );
  }
}

class GenericImportOptions {
  const GenericImportOptions({
    this.headerRow = true,
    this.delimiter = ',',
    this.quoteCharacter = '"',
    this.escapeCharacter = '"',
    this.encoding = GenericImportEncoding.auto,
    this.malformedRowStrategy = DelimitedMalformedRowStrategy.padOrTruncate,
    this.structuredStrategy = StructuredImportStrategy.flatten,
    this.preserveHtmlMetadata = true,
  });

  final bool headerRow;
  final String delimiter;
  final String quoteCharacter;
  final String escapeCharacter;
  final GenericImportEncoding encoding;
  final DelimitedMalformedRowStrategy malformedRowStrategy;
  final StructuredImportStrategy structuredStrategy;
  final bool preserveHtmlMetadata;

  GenericImportOptions copyWith({
    bool? headerRow,
    String? delimiter,
    String? quoteCharacter,
    String? escapeCharacter,
    GenericImportEncoding? encoding,
    DelimitedMalformedRowStrategy? malformedRowStrategy,
    StructuredImportStrategy? structuredStrategy,
    bool? preserveHtmlMetadata,
  }) {
    return GenericImportOptions(
      headerRow: headerRow ?? this.headerRow,
      delimiter: delimiter ?? this.delimiter,
      quoteCharacter: quoteCharacter ?? this.quoteCharacter,
      escapeCharacter: escapeCharacter ?? this.escapeCharacter,
      encoding: encoding ?? this.encoding,
      malformedRowStrategy: malformedRowStrategy ?? this.malformedRowStrategy,
      structuredStrategy: structuredStrategy ?? this.structuredStrategy,
      preserveHtmlMetadata: preserveHtmlMetadata ?? this.preserveHtmlMetadata,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'headerRow': headerRow,
      'delimiter': delimiter,
      'quoteCharacter': quoteCharacter,
      'escapeCharacter': escapeCharacter,
      'encoding': encoding.name,
      'malformedRowStrategy': malformedRowStrategy.name,
      'structuredStrategy': structuredStrategy.name,
      'preserveHtmlMetadata': preserveHtmlMetadata,
    };
  }

  factory GenericImportOptions.fromMap(Map<String, Object?> map) {
    return GenericImportOptions(
      headerRow: map['headerRow'] as bool? ?? true,
      delimiter: map['delimiter'] as String? ?? ',',
      quoteCharacter: map['quoteCharacter'] as String? ?? '"',
      escapeCharacter: map['escapeCharacter'] as String? ?? '"',
      encoding: GenericImportEncoding.values.byName(
        map['encoding'] as String? ?? GenericImportEncoding.auto.name,
      ),
      malformedRowStrategy: DelimitedMalformedRowStrategy.values.byName(
        map['malformedRowStrategy'] as String? ??
            DelimitedMalformedRowStrategy.padOrTruncate.name,
      ),
      structuredStrategy: StructuredImportStrategy.values.byName(
        map['structuredStrategy'] as String? ??
            StructuredImportStrategy.flatten.name,
      ),
      preserveHtmlMetadata: map['preserveHtmlMetadata'] as bool? ?? true,
    );
  }
}

class GenericImportInspection {
  const GenericImportInspection({
    required this.sourcePath,
    required this.format,
    required this.options,
    required this.tables,
    required this.warnings,
    this.explanation,
  });

  final String sourcePath;
  final ImportFormatDefinition format;
  final GenericImportOptions options;
  final List<ImportTableDraft> tables;
  final List<String> warnings;
  final String? explanation;
}

class MaterializedImportTableData {
  const MaterializedImportTableData({
    required this.sourceId,
    required this.sourceName,
    required this.suggestedTargetName,
    required this.rows,
    this.description,
    this.warnings = const <String>[],
  });

  final String sourceId;
  final String sourceName;
  final String suggestedTargetName;
  final List<Map<String, Object?>> rows;
  final String? description;
  final List<String> warnings;
}

class MaterializedImportSource {
  const MaterializedImportSource({
    required this.sourcePath,
    required this.format,
    required this.options,
    required this.tables,
    required this.warnings,
    this.explanation,
  });

  final String sourcePath;
  final ImportFormatDefinition format;
  final GenericImportOptions options;
  final List<MaterializedImportTableData> tables;
  final List<String> warnings;
  final String? explanation;
}

class GenericImportRequest {
  const GenericImportRequest({
    required this.jobId,
    required this.sourcePath,
    required this.targetPath,
    required this.importIntoExistingTarget,
    required this.replaceExistingTarget,
    required this.formatKey,
    required this.options,
    required this.tables,
  });

  final String jobId;
  final String sourcePath;
  final String targetPath;
  final bool importIntoExistingTarget;
  final bool replaceExistingTarget;
  final ImportFormatKey formatKey;
  final GenericImportOptions options;
  final List<ImportTableDraft> tables;

  List<ImportTableDraft> get selectedTables =>
      tables.where((table) => table.selected).toList(growable: false);

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'importIntoExistingTarget': importIntoExistingTarget,
      'replaceExistingTarget': replaceExistingTarget,
      'formatKey': formatKey.name,
      'options': options.toMap(),
      'tables': <Map<String, Object?>>[
        for (final table in tables) table.toMap(),
      ],
    };
  }

  factory GenericImportRequest.fromMap(Map<String, Object?> map) {
    return GenericImportRequest(
      jobId: map['jobId']! as String,
      sourcePath: map['sourcePath']! as String,
      targetPath: map['targetPath']! as String,
      importIntoExistingTarget: map['importIntoExistingTarget']! as bool,
      replaceExistingTarget: map['replaceExistingTarget']! as bool,
      formatKey: ImportFormatKey.values.byName(map['formatKey']! as String),
      options: GenericImportOptions.fromMap(
        ((map['options'] as Map?) ?? const <Object?, Object?>{}).map(
          (key, value) => MapEntry(key as String, value),
        ),
      ),
      tables: ((map['tables'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (table) => ImportTableDraft.fromMap(
              table.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
    );
  }
}

class GenericImportProgress {
  const GenericImportProgress({
    required this.jobId,
    required this.currentTable,
    required this.completedTables,
    required this.totalTables,
    required this.currentTableRowsCopied,
    required this.currentTableRowCount,
    required this.totalRowsCopied,
    required this.message,
  });

  final String jobId;
  final String currentTable;
  final int completedTables;
  final int totalTables;
  final int currentTableRowsCopied;
  final int currentTableRowCount;
  final int totalRowsCopied;
  final String message;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'currentTable': currentTable,
      'completedTables': completedTables,
      'totalTables': totalTables,
      'currentTableRowsCopied': currentTableRowsCopied,
      'currentTableRowCount': currentTableRowCount,
      'totalRowsCopied': totalRowsCopied,
      'message': message,
    };
  }

  factory GenericImportProgress.fromMap(Map<String, Object?> map) {
    return GenericImportProgress(
      jobId: map['jobId']! as String,
      currentTable: map['currentTable']! as String,
      completedTables: map['completedTables']! as int,
      totalTables: map['totalTables']! as int,
      currentTableRowsCopied: map['currentTableRowsCopied']! as int,
      currentTableRowCount: map['currentTableRowCount']! as int,
      totalRowsCopied: map['totalRowsCopied']! as int,
      message: map['message']! as String,
    );
  }
}

class GenericImportSummary {
  const GenericImportSummary({
    required this.jobId,
    required this.sourcePath,
    required this.targetPath,
    required this.formatLabel,
    required this.importedTables,
    required this.rowsCopiedByTable,
    required this.warnings,
    required this.statusMessage,
    required this.rolledBack,
  });

  final String jobId;
  final String sourcePath;
  final String targetPath;
  final String formatLabel;
  final List<String> importedTables;
  final Map<String, int> rowsCopiedByTable;
  final List<String> warnings;
  final String statusMessage;
  final bool rolledBack;

  int get totalRowsCopied =>
      rowsCopiedByTable.values.fold<int>(0, (sum, value) => sum + value);

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'formatLabel': formatLabel,
      'importedTables': importedTables,
      'rowsCopiedByTable': rowsCopiedByTable,
      'warnings': warnings,
      'statusMessage': statusMessage,
      'rolledBack': rolledBack,
    };
  }

  factory GenericImportSummary.fromMap(Map<String, Object?> map) {
    return GenericImportSummary(
      jobId: map['jobId']! as String,
      sourcePath: map['sourcePath']! as String,
      targetPath: map['targetPath']! as String,
      formatLabel: map['formatLabel']! as String,
      importedTables: ((map['importedTables'] as List?) ?? const <Object?>[])
          .cast<String>(),
      rowsCopiedByTable:
          ((map['rowsCopiedByTable'] as Map?) ?? const <Object?, Object?>{})
              .map((key, value) => MapEntry(key as String, value as int)),
      warnings: ((map['warnings'] as List?) ?? const <Object?>[])
          .cast<String>(),
      statusMessage: map['statusMessage']! as String,
      rolledBack: map['rolledBack']! as bool,
    );
  }
}

class GenericImportUpdate {
  const GenericImportUpdate({
    required this.kind,
    required this.jobId,
    this.progress,
    this.summary,
    this.message,
  });

  final GenericImportUpdateKind kind;
  final String jobId;
  final GenericImportProgress? progress;
  final GenericImportSummary? summary;
  final String? message;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'kind': kind.name,
      'jobId': jobId,
      'progress': progress?.toMap(),
      'summary': summary?.toMap(),
      'message': message,
    };
  }

  factory GenericImportUpdate.fromMap(Map<String, Object?> map) {
    return GenericImportUpdate(
      kind: GenericImportUpdateKind.values.byName(map['kind']! as String),
      jobId: map['jobId']! as String,
      progress: map['progress'] is Map<Object?, Object?>
          ? GenericImportProgress.fromMap(
              (map['progress']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key as String, value),
              ),
            )
          : null,
      summary: map['summary'] is Map<Object?, Object?>
          ? GenericImportSummary.fromMap(
              (map['summary']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key as String, value),
              ),
            )
          : null,
      message: map['message'] as String?,
    );
  }
}

class GenericImportDialogResult {
  const GenericImportDialogResult({
    required this.targetPath,
    required this.summary,
  });

  final String targetPath;
  final GenericImportSummary summary;
}

String placeholderForTargetType(String targetType, int index) {
  if (isDecimalTargetType(targetType) || isUuidTargetType(targetType)) {
    return 'CAST(\$$index AS $targetType)';
  }
  return '\$$index';
}

bool isDecimalTargetType(String targetType) {
  return targetType.startsWith('DECIMAL') || targetType.startsWith('NUMERIC');
}

bool isUuidTargetType(String targetType) {
  return targetType == 'UUID';
}

bool hasDistinctNames(Iterable<String> names) {
  final normalized = names
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList(growable: false);
  return normalized.length == normalized.toSet().length;
}

bool isSupportedTargetType(String value) {
  return decentDbImportTargetTypes.contains(value);
}

const Object _unset = Object();
