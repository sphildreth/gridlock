import 'package:decent_bench/features/workspace/domain/workspace_file_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects DecentDB and SQLite files by extension', () {
    expect(canonicalDecentDbExtension, '.ddb');
    expect(
      detectWorkspaceIncomingFileKind('/tmp/workbench.ddb'),
      WorkspaceIncomingFileKind.decentDb,
    );
    expect(
      detectWorkspaceIncomingFileKind('/tmp/source.sqlite'),
      WorkspaceIncomingFileKind.sqlite,
    );
    expect(
      detectWorkspaceIncomingFileKind('/tmp/source.db'),
      WorkspaceIncomingFileKind.sqlite,
    );
    expect(
      detectWorkspaceIncomingFileKind('/tmp/source.sqlite3'),
      WorkspaceIncomingFileKind.sqlite,
    );
  });

  test('classifies future import types and unknown files', () {
    expect(
      detectWorkspaceIncomingFileKind('/tmp/workbook.xlsx'),
      WorkspaceIncomingFileKind.excel,
    );
    expect(
      detectWorkspaceIncomingFileKind('/tmp/dump.sql'),
      WorkspaceIncomingFileKind.sqlDump,
    );
    expect(
      detectWorkspaceIncomingFileKind('/tmp/archive.bin'),
      WorkspaceIncomingFileKind.unknown,
    );
  });

  test('picks the first dropped file and reports multi-drop', () {
    final decision = decideWorkspaceIncomingFiles(<String>[
      '/tmp/first.sqlite',
      '/tmp/second.ddb',
    ]);

    expect(decision.primaryPath, '/tmp/first.sqlite');
    expect(decision.kind, WorkspaceIncomingFileKind.sqlite);
    expect(decision.hadMultipleFiles, isTrue);
  });
}
