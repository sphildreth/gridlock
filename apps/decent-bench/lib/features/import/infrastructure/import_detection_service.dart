import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../domain/import_models.dart';
import 'import_format_registry.dart';

class ImportDetectionService {
  ImportDetectionService({ImportFormatRegistry? registry})
    : _registry = registry ?? ImportFormatRegistry.instance;

  final ImportFormatRegistry _registry;

  Future<ImportDetectionResult> detect(String sourcePath) async {
    final file = File(sourcePath);
    final format = _registry.detectByPath(sourcePath);
    final warnings = <String>[];
    if (format.key == ImportFormatKey.zipArchive) {
      final candidates = await _detectZipCandidates(sourcePath);
      if (candidates.isEmpty) {
        warnings.add(
          'The archive does not contain any recognized import sources yet.',
        );
      }
      return ImportDetectionResult(
        sourcePath: sourcePath,
        format: format,
        warnings: warnings,
        archiveCandidates: candidates,
      );
    }
    if (format.key == ImportFormatKey.gzipArchive) {
      final candidate = await _detectGzipCandidate(sourcePath);
      return ImportDetectionResult(
        sourcePath: sourcePath,
        format: format,
        warnings: candidate == null
            ? <String>[
                'The GZip filename does not indicate a supported inner source.',
              ]
            : warnings,
        archiveCandidates: candidate == null
            ? const <ImportArchiveCandidate>[]
            : <ImportArchiveCandidate>[candidate],
      );
    }
    if (format.key == ImportFormatKey.sqlite && file.existsSync()) {
      final header = await file
          .openRead(0, 16)
          .fold<List<int>>(
            <int>[],
            (bytes, chunk) => <int>[...bytes, ...chunk],
          );
      final signature = String.fromCharCodes(header);
      if (!signature.startsWith('SQLite format 3')) {
        warnings.add(
          'The file uses a SQLite-like extension, but the header does not match the SQLite signature.',
        );
      }
    }
    return ImportDetectionResult(
      sourcePath: sourcePath,
      format: format,
      warnings: warnings,
    );
  }

  Future<List<ImportArchiveCandidate>> _detectZipCandidates(
    String sourcePath,
  ) async {
    final file = File(sourcePath);
    if (!file.existsSync()) {
      return const <ImportArchiveCandidate>[];
    }
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final candidates = <ImportArchiveCandidate>[];
    for (final entry in archive) {
      if (!entry.isFile) {
        continue;
      }
      final innerFormat = _registry.detectByPath(entry.name);
      if (innerFormat.key == ImportFormatKey.unknown) {
        continue;
      }
      candidates.add(
        ImportArchiveCandidate(
          entryPath: entry.name,
          displayName: entry.name,
          innerFormatKey: innerFormat.key,
          innerFormatLabel: innerFormat.label,
          supportState: innerFormat.supportState,
        ),
      );
    }
    return candidates;
  }

  Future<ImportArchiveCandidate?> _detectGzipCandidate(
    String sourcePath,
  ) async {
    final innerName = p.basenameWithoutExtension(sourcePath);
    final innerFormat = _registry.detectByPath(innerName);
    if (innerFormat.key == ImportFormatKey.unknown) {
      return null;
    }
    return ImportArchiveCandidate(
      entryPath: innerName,
      displayName: innerName,
      innerFormatKey: innerFormat.key,
      innerFormatLabel: innerFormat.label,
      supportState: innerFormat.supportState,
    );
  }

  Future<String> extractArchiveCandidate({
    required String archivePath,
    required ImportFormatKey wrapperKey,
    required ImportArchiveCandidate candidate,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'decent-bench-import-',
    );
    final outputPath = p.join(tempDir.path, p.basename(candidate.entryPath));
    if (wrapperKey == ImportFormatKey.zipArchive) {
      final archive = ZipDecoder().decodeBytes(
        await File(archivePath).readAsBytes(),
      );
      for (final entry in archive) {
        if (entry.isFile && entry.name == candidate.entryPath) {
          final bytes = entry.content as List<int>;
          final output = File(outputPath);
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes, flush: true);
          return output.path;
        }
      }
      throw StateError(
        'Archive entry `${candidate.entryPath}` was not found in $archivePath.',
      );
    }
    if (wrapperKey == ImportFormatKey.gzipArchive) {
      final decoded = GZipDecoder().decodeBytes(
        await File(archivePath).readAsBytes(),
      );
      final output = File(outputPath);
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(decoded, flush: true);
      return output.path;
    }
    throw StateError('Unsupported wrapper extraction for ${wrapperKey.name}.');
  }
}
