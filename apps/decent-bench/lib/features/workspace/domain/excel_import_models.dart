import 'workspace_models.dart';

enum ExcelImportWizardStep {
  source,
  target,
  preview,
  transforms,
  execute,
  summary,
}

enum ExcelImportJobPhase {
  idle,
  inspecting,
  ready,
  running,
  cancelling,
  completed,
  failed,
  cancelled,
}

enum ExcelImportUpdateKind { progress, completed, failed, cancelled }

class ExcelImportColumnDraft {
  const ExcelImportColumnDraft({
    required this.sourceIndex,
    required this.sourceName,
    required this.targetName,
    required this.inferredTargetType,
    required this.targetType,
    required this.containsNulls,
  });

  final int sourceIndex;
  final String sourceName;
  final String targetName;
  final String inferredTargetType;
  final String targetType;
  final bool containsNulls;

  ExcelImportColumnDraft copyWith({
    int? sourceIndex,
    String? sourceName,
    String? targetName,
    String? inferredTargetType,
    String? targetType,
    bool? containsNulls,
  }) {
    return ExcelImportColumnDraft(
      sourceIndex: sourceIndex ?? this.sourceIndex,
      sourceName: sourceName ?? this.sourceName,
      targetName: targetName ?? this.targetName,
      inferredTargetType: inferredTargetType ?? this.inferredTargetType,
      targetType: targetType ?? this.targetType,
      containsNulls: containsNulls ?? this.containsNulls,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourceIndex': sourceIndex,
      'sourceName': sourceName,
      'targetName': targetName,
      'inferredTargetType': inferredTargetType,
      'targetType': targetType,
      'containsNulls': containsNulls,
    };
  }

  factory ExcelImportColumnDraft.fromMap(Map<String, Object?> map) {
    return ExcelImportColumnDraft(
      sourceIndex: map['sourceIndex']! as int,
      sourceName: map['sourceName']! as String,
      targetName: map['targetName']! as String,
      inferredTargetType: map['inferredTargetType']! as String,
      targetType: map['targetType']! as String,
      containsNulls: map['containsNulls']! as bool,
    );
  }
}

class ExcelImportSheetDraft {
  const ExcelImportSheetDraft({
    required this.sourceName,
    required this.targetName,
    required this.selected,
    required this.rowCount,
    required this.columns,
    required this.previewRows,
  });

  final String sourceName;
  final String targetName;
  final bool selected;
  final int rowCount;
  final List<ExcelImportColumnDraft> columns;
  final List<Map<String, Object?>> previewRows;

  ExcelImportSheetDraft copyWith({
    String? sourceName,
    String? targetName,
    bool? selected,
    int? rowCount,
    List<ExcelImportColumnDraft>? columns,
    List<Map<String, Object?>>? previewRows,
  }) {
    return ExcelImportSheetDraft(
      sourceName: sourceName ?? this.sourceName,
      targetName: targetName ?? this.targetName,
      selected: selected ?? this.selected,
      rowCount: rowCount ?? this.rowCount,
      columns: columns ?? this.columns,
      previewRows: previewRows ?? this.previewRows,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourceName': sourceName,
      'targetName': targetName,
      'selected': selected,
      'rowCount': rowCount,
      'columns': <Map<String, Object?>>[
        for (final column in columns) column.toMap(),
      ],
      'previewRows': previewRows,
    };
  }

  factory ExcelImportSheetDraft.fromMap(Map<String, Object?> map) {
    return ExcelImportSheetDraft(
      sourceName: map['sourceName']! as String,
      targetName: map['targetName']! as String,
      selected: map['selected']! as bool,
      rowCount: map['rowCount']! as int,
      columns: ((map['columns'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (column) => ExcelImportColumnDraft.fromMap(
              column.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      previewRows: ((map['previewRows'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map((row) => row.map((key, value) => MapEntry(key as String, value)))
          .toList(),
    );
  }
}

class ExcelImportInspection {
  const ExcelImportInspection({
    required this.sourcePath,
    required this.headerRow,
    required this.sheets,
    required this.warnings,
  });

  final String sourcePath;
  final bool headerRow;
  final List<ExcelImportSheetDraft> sheets;
  final List<String> warnings;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'sourcePath': sourcePath,
      'headerRow': headerRow,
      'sheets': <Map<String, Object?>>[
        for (final sheet in sheets) sheet.toMap(),
      ],
      'warnings': warnings,
    };
  }

  factory ExcelImportInspection.fromMap(Map<String, Object?> map) {
    return ExcelImportInspection(
      sourcePath: map['sourcePath']! as String,
      headerRow: map['headerRow']! as bool,
      sheets: ((map['sheets'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (sheet) => ExcelImportSheetDraft.fromMap(
              sheet.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      warnings: ((map['warnings'] as List?) ?? const <Object?>[])
          .cast<String>(),
    );
  }
}

class ExcelImportRequest {
  const ExcelImportRequest({
    required this.jobId,
    required this.sourcePath,
    required this.targetPath,
    required this.importIntoExistingTarget,
    required this.replaceExistingTarget,
    required this.headerRow,
    required this.sheets,
  });

  final String jobId;
  final String sourcePath;
  final String targetPath;
  final bool importIntoExistingTarget;
  final bool replaceExistingTarget;
  final bool headerRow;
  final List<ExcelImportSheetDraft> sheets;

  List<ExcelImportSheetDraft> get selectedSheets =>
      sheets.where((sheet) => sheet.selected).toList();

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'importIntoExistingTarget': importIntoExistingTarget,
      'replaceExistingTarget': replaceExistingTarget,
      'headerRow': headerRow,
      'sheets': <Map<String, Object?>>[
        for (final sheet in sheets) sheet.toMap(),
      ],
    };
  }

  factory ExcelImportRequest.fromMap(Map<String, Object?> map) {
    return ExcelImportRequest(
      jobId: map['jobId']! as String,
      sourcePath: map['sourcePath']! as String,
      targetPath: map['targetPath']! as String,
      importIntoExistingTarget: map['importIntoExistingTarget']! as bool,
      replaceExistingTarget: map['replaceExistingTarget']! as bool,
      headerRow: map['headerRow']! as bool,
      sheets: ((map['sheets'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (sheet) => ExcelImportSheetDraft.fromMap(
              sheet.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
    );
  }
}

class ExcelImportProgress {
  const ExcelImportProgress({
    required this.jobId,
    required this.currentSheet,
    required this.completedSheets,
    required this.totalSheets,
    required this.currentSheetRowsCopied,
    required this.currentSheetRowCount,
    required this.totalRowsCopied,
    required this.message,
  });

  final String jobId;
  final String currentSheet;
  final int completedSheets;
  final int totalSheets;
  final int currentSheetRowsCopied;
  final int currentSheetRowCount;
  final int totalRowsCopied;
  final String message;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'currentSheet': currentSheet,
      'completedSheets': completedSheets,
      'totalSheets': totalSheets,
      'currentSheetRowsCopied': currentSheetRowsCopied,
      'currentSheetRowCount': currentSheetRowCount,
      'totalRowsCopied': totalRowsCopied,
      'message': message,
    };
  }

  factory ExcelImportProgress.fromMap(Map<String, Object?> map) {
    return ExcelImportProgress(
      jobId: map['jobId']! as String,
      currentSheet: map['currentSheet']! as String,
      completedSheets: map['completedSheets']! as int,
      totalSheets: map['totalSheets']! as int,
      currentSheetRowsCopied: map['currentSheetRowsCopied']! as int,
      currentSheetRowCount: map['currentSheetRowCount']! as int,
      totalRowsCopied: map['totalRowsCopied']! as int,
      message: map['message']! as String,
    );
  }
}

class ExcelImportSummary {
  const ExcelImportSummary({
    required this.jobId,
    required this.sourcePath,
    required this.targetPath,
    required this.importedTables,
    required this.rowsCopiedByTable,
    required this.warnings,
    required this.statusMessage,
    required this.rolledBack,
  });

  final String jobId;
  final String sourcePath;
  final String targetPath;
  final List<String> importedTables;
  final Map<String, int> rowsCopiedByTable;
  final List<String> warnings;
  final String statusMessage;
  final bool rolledBack;

  String? get firstImportedTable =>
      importedTables.isEmpty ? null : importedTables.first;

  int get totalRowsCopied =>
      rowsCopiedByTable.values.fold<int>(0, (sum, value) => sum + value);

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'jobId': jobId,
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'importedTables': importedTables,
      'rowsCopiedByTable': rowsCopiedByTable,
      'warnings': warnings,
      'statusMessage': statusMessage,
      'rolledBack': rolledBack,
    };
  }

  factory ExcelImportSummary.fromMap(Map<String, Object?> map) {
    return ExcelImportSummary(
      jobId: map['jobId']! as String,
      sourcePath: map['sourcePath']! as String,
      targetPath: map['targetPath']! as String,
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

class ExcelImportUpdate {
  const ExcelImportUpdate({
    required this.kind,
    required this.jobId,
    this.progress,
    this.summary,
    this.message,
  });

  final ExcelImportUpdateKind kind;
  final String jobId;
  final ExcelImportProgress? progress;
  final ExcelImportSummary? summary;
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

  factory ExcelImportUpdate.fromMap(Map<String, Object?> map) {
    return ExcelImportUpdate(
      kind: ExcelImportUpdateKind.values.byName(map['kind']! as String),
      jobId: map['jobId']! as String,
      progress: map['progress'] is Map<Object?, Object?>
          ? ExcelImportProgress.fromMap(
              (map['progress']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key as String, value),
              ),
            )
          : null,
      summary: map['summary'] is Map<Object?, Object?>
          ? ExcelImportSummary.fromMap(
              (map['summary']! as Map<Object?, Object?>).map(
                (key, value) => MapEntry(key as String, value),
              ),
            )
          : null,
      message: map['message'] as String?,
    );
  }
}

class ExcelImportSession {
  const ExcelImportSession({
    required this.step,
    required this.phase,
    required this.sourcePath,
    required this.targetPath,
    required this.importIntoExistingTarget,
    required this.replaceExistingTarget,
    required this.headerRow,
    required this.sheets,
    required this.warnings,
    this.focusedSheet,
    this.progress,
    this.summary,
    this.error,
    this.jobId,
  });

  final ExcelImportWizardStep step;
  final ExcelImportJobPhase phase;
  final String sourcePath;
  final String targetPath;
  final bool importIntoExistingTarget;
  final bool replaceExistingTarget;
  final bool headerRow;
  final List<ExcelImportSheetDraft> sheets;
  final List<String> warnings;
  final String? focusedSheet;
  final ExcelImportProgress? progress;
  final ExcelImportSummary? summary;
  final String? error;
  final String? jobId;

  factory ExcelImportSession.initial({String sourcePath = ''}) {
    return ExcelImportSession(
      step: ExcelImportWizardStep.source,
      phase: ExcelImportJobPhase.idle,
      sourcePath: sourcePath,
      targetPath: '',
      importIntoExistingTarget: false,
      replaceExistingTarget: false,
      headerRow: true,
      sheets: const <ExcelImportSheetDraft>[],
      warnings: const <String>[],
    );
  }

  List<ExcelImportSheetDraft> get selectedSheets =>
      sheets.where((sheet) => sheet.selected).toList();

  ExcelImportSheetDraft? get focusedSheetDraft {
    if (focusedSheet == null) {
      return selectedSheets.isEmpty ? null : selectedSheets.first;
    }
    for (final sheet in sheets) {
      if (sheet.sourceName == focusedSheet) {
        return sheet;
      }
    }
    return selectedSheets.isEmpty ? null : selectedSheets.first;
  }

  bool get canAdvanceFromSource =>
      sourcePath.trim().isNotEmpty && sheets.isNotEmpty;

  bool get canAdvanceFromTarget => targetPath.trim().isNotEmpty;

  bool get canAdvanceFromPreview => selectedSheets.isNotEmpty;

  bool get canAdvanceFromTransforms =>
      selectedSheets.isNotEmpty &&
      selectedSheets.every(
        (sheet) =>
            sheet.targetName.trim().isNotEmpty &&
            _hasDistinctNames(
              sheet.columns.map((column) => column.targetName).toList(),
            ),
      ) &&
      _hasDistinctNames(
        selectedSheets.map((sheet) => sheet.targetName).toList(),
      );

  ExcelImportSession copyWith({
    ExcelImportWizardStep? step,
    ExcelImportJobPhase? phase,
    String? sourcePath,
    String? targetPath,
    bool? importIntoExistingTarget,
    bool? replaceExistingTarget,
    bool? headerRow,
    List<ExcelImportSheetDraft>? sheets,
    List<String>? warnings,
    Object? focusedSheet = _unset,
    Object? progress = _unset,
    Object? summary = _unset,
    Object? error = _unset,
    Object? jobId = _unset,
  }) {
    return ExcelImportSession(
      step: step ?? this.step,
      phase: phase ?? this.phase,
      sourcePath: sourcePath ?? this.sourcePath,
      targetPath: targetPath ?? this.targetPath,
      importIntoExistingTarget:
          importIntoExistingTarget ?? this.importIntoExistingTarget,
      replaceExistingTarget:
          replaceExistingTarget ?? this.replaceExistingTarget,
      headerRow: headerRow ?? this.headerRow,
      sheets: sheets ?? this.sheets,
      warnings: warnings ?? this.warnings,
      focusedSheet: focusedSheet == _unset
          ? this.focusedSheet
          : focusedSheet as String?,
      progress: progress == _unset
          ? this.progress
          : progress as ExcelImportProgress?,
      summary: summary == _unset
          ? this.summary
          : summary as ExcelImportSummary?,
      error: error == _unset ? this.error : error as String?,
      jobId: jobId == _unset ? this.jobId : jobId as String?,
    );
  }
}

const Object _unset = Object();

bool _hasDistinctNames(List<String> names) {
  final normalized = names
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty);
  return normalized.length == normalized.toSet().length;
}

String formatExcelImportCellValue(Object? value) {
  return formatCellValue(value);
}
