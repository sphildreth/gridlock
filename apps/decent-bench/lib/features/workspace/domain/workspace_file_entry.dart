import 'package:path/path.dart' as p;

const String canonicalDecentDbExtension = '.ddb';

enum WorkspaceIncomingFileKind { decentDb, sqlite, excel, sqlDump, unknown }

class WorkspaceIncomingFileDecision {
  const WorkspaceIncomingFileDecision({
    required this.kind,
    required this.primaryPath,
    required this.hadMultipleFiles,
  });

  final WorkspaceIncomingFileKind kind;
  final String? primaryPath;
  final bool hadMultipleFiles;

  bool get hasFile => primaryPath != null;
}

WorkspaceIncomingFileDecision decideWorkspaceIncomingFiles(
  Iterable<String> rawPaths,
) {
  final normalized = rawPaths
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  if (normalized.isEmpty) {
    return const WorkspaceIncomingFileDecision(
      kind: WorkspaceIncomingFileKind.unknown,
      primaryPath: null,
      hadMultipleFiles: false,
    );
  }

  final primaryPath = normalized.first;
  return WorkspaceIncomingFileDecision(
    kind: detectWorkspaceIncomingFileKind(primaryPath),
    primaryPath: primaryPath,
    hadMultipleFiles: normalized.length > 1,
  );
}

WorkspaceIncomingFileKind detectWorkspaceIncomingFileKind(String rawPath) {
  final extension = p.extension(rawPath.trim()).toLowerCase();
  return switch (extension) {
    canonicalDecentDbExtension => WorkspaceIncomingFileKind.decentDb,
    '.db' || '.sqlite' || '.sqlite3' => WorkspaceIncomingFileKind.sqlite,
    '.xls' || '.xlsx' => WorkspaceIncomingFileKind.excel,
    '.sql' => WorkspaceIncomingFileKind.sqlDump,
    _ => WorkspaceIncomingFileKind.unknown,
  };
}

String suggestNewDecentDbTargetPath(String rawSourcePath) {
  final normalized = rawSourcePath.trim();
  if (normalized.isEmpty) {
    return 'workspace$canonicalDecentDbExtension';
  }
  return p.setExtension(normalized, canonicalDecentDbExtension);
}
