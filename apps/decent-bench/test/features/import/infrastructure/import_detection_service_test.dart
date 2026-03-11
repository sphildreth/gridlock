import 'dart:io';

import 'package:archive/archive.dart';
import 'package:decent_bench/features/import/domain/import_models.dart';
import 'package:decent_bench/features/import/infrastructure/import_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late ImportDetectionService service;
  late Directory tempDir;

  setUp(() async {
    service = ImportDetectionService();
    tempDir = await Directory.systemTemp.createTemp('decent-bench-detect-test-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('detects CSV as a supported generic import', () async {
    final file = File(p.join(tempDir.path, 'records.csv'))
      ..writeAsStringSync('id,name\n1,Ada\n2,Lin');

    final result = await service.detect(file.path);

    expect(result.format.key, ImportFormatKey.csv);
    expect(result.format.launchesGenericWizard, isTrue);
    expect(result.warnings, isEmpty);
  });

  test('detects ZIP wrapper candidates', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('customers.csv', 14, 'id,name\n1,Ada\n'.codeUnits))
      ..addFile(ArchiveFile('snapshot.json', 11, '[{"id":1}]'.codeUnits))
      ..addFile(ArchiveFile('notes.bin', 3, <int>[1, 2, 3]));
    final zipBytes = ZipEncoder().encode(archive)!;
    final file = File(p.join(tempDir.path, 'bundle.zip'))
      ..writeAsBytesSync(zipBytes, flush: true);

    final result = await service.detect(file.path);

    expect(result.format.key, ImportFormatKey.zipArchive);
    expect(result.archiveCandidates, hasLength(2));
    expect(
      result.archiveCandidates.map((candidate) => candidate.innerFormatKey),
      containsAll(<ImportFormatKey>[ImportFormatKey.csv, ImportFormatKey.json]),
    );
  });

  test('detects GZip wrapper candidate from inner filename', () async {
    final bytes = GZipEncoder().encode('id,name\n1,Ada\n'.codeUnits)!;
    final file = File(p.join(tempDir.path, 'customers.csv.gz'))
      ..writeAsBytesSync(bytes, flush: true);

    final result = await service.detect(file.path);

    expect(result.format.key, ImportFormatKey.gzipArchive);
    expect(result.archiveCandidates, hasLength(1));
    expect(result.archiveCandidates.single.innerFormatKey, ImportFormatKey.csv);
  });

  test('recognizes planned spreadsheet formats', () async {
    final file = File(p.join(tempDir.path, 'report.ods'))..writeAsStringSync('');

    final result = await service.detect(file.path);

    expect(result.format.key, ImportFormatKey.ods);
    expect(result.format.isRecognizedButUnavailable, isTrue);
    expect(result.format.supportState, ImportSupportState.planned);
  });
}
