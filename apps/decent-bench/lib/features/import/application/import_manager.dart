import '../domain/import_models.dart';
import '../infrastructure/import_detection_service.dart';
import '../infrastructure/import_format_registry.dart';

class ImportManager {
  ImportManager({
    ImportFormatRegistry? registry,
    ImportDetectionService? detectionService,
  }) : registry = registry ?? ImportFormatRegistry.instance,
       detectionService =
           detectionService ?? ImportDetectionService(registry: registry);

  final ImportFormatRegistry registry;
  final ImportDetectionService detectionService;

  Future<ImportDetectionResult> detectSource(String sourcePath) {
    return detectionService.detect(sourcePath);
  }

  Future<String> extractArchiveCandidate({
    required String archivePath,
    required ImportFormatKey wrapperKey,
    required ImportArchiveCandidate candidate,
  }) {
    return detectionService.extractArchiveCandidate(
      archivePath: archivePath,
      wrapperKey: wrapperKey,
      candidate: candidate,
    );
  }
}
