import 'dart:isolate';

import '../domain/import_models.dart';
import 'delimited_import_support.dart';
import 'html_import_support.dart';
import 'structured_import_support.dart';
import 'type_inference_service.dart';

class ImportPreviewService {
  ImportPreviewService({TypeInferenceService? typeInferenceService})
    : _typeInferenceService =
          typeInferenceService ?? const TypeInferenceService();

  final TypeInferenceService _typeInferenceService;

  Future<GenericImportInspection> inspect({
    required String sourcePath,
    required ImportFormatDefinition format,
    required GenericImportOptions options,
  }) {
    return Isolate.run(
      () => inspectImportSourceSync(
        sourcePath: sourcePath,
        format: format,
        options: options,
      ),
    );
  }

  GenericImportInspection inspectImportSourceSync({
    required String sourcePath,
    required ImportFormatDefinition format,
    required GenericImportOptions options,
  }) {
    switch (format.key) {
      case ImportFormatKey.csv:
      case ImportFormatKey.tsv:
      case ImportFormatKey.genericDelimited:
        return inspectDelimitedSourceSync(
          sourcePath: sourcePath,
          format: format,
          options: options,
          typeInferenceService: _typeInferenceService,
        );
      case ImportFormatKey.json:
      case ImportFormatKey.ndjson:
      case ImportFormatKey.xml:
        return inspectStructuredSourceSync(
          sourcePath: sourcePath,
          format: format,
          options: options,
          typeInferenceService: _typeInferenceService,
        );
      case ImportFormatKey.htmlTable:
        return inspectHtmlTableSourceSync(
          sourcePath: sourcePath,
          format: format,
          options: options,
          typeInferenceService: _typeInferenceService,
        );
      default:
        throw StateError(
          'Format ${format.label} does not use the generic preview pipeline.',
        );
    }
  }
}
