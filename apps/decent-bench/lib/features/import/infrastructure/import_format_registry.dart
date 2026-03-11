import 'package:path/path.dart' as p;

import '../domain/import_models.dart';

class ImportFormatRegistry {
  ImportFormatRegistry._();

  static final ImportFormatRegistry instance = ImportFormatRegistry._();

  static const List<ImportFormatDefinition> _formats = <ImportFormatDefinition>[
    ImportFormatDefinition(
      key: ImportFormatKey.decentDb,
      label: 'DecentDB',
      family: ImportFamily.database,
      supportState: ImportSupportState.complete,
      extensions: <String>['.ddb'],
      implementationKind: ImportImplementationKind.directOpen,
      description: 'Open an existing DecentDB workspace directly.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.csv,
      label: 'CSV',
      family: ImportFamily.delimitedText,
      supportState: ImportSupportState.complete,
      extensions: <String>['.csv'],
      implementationKind: ImportImplementationKind.genericWizard,
      description:
          'Delimited text import with header, delimiter, quoting, preview, and type overrides.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.tsv,
      label: 'TSV',
      family: ImportFamily.delimitedText,
      supportState: ImportSupportState.complete,
      extensions: <String>['.tsv'],
      implementationKind: ImportImplementationKind.genericWizard,
      description: 'Tab-delimited import using the generic text pipeline.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.genericDelimited,
      label: 'Generic Delimited Text',
      family: ImportFamily.delimitedText,
      supportState: ImportSupportState.complete,
      extensions: <String>['.txt', '.dat', '.log'],
      implementationKind: ImportImplementationKind.genericWizard,
      description:
          'Custom-delimited import for CSV-like text exports and logs.',
      note: 'Use delimiter and malformed-row options to adapt messy exports.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.fixedWidth,
      label: 'Fixed-width Text',
      family: ImportFamily.delimitedText,
      supportState: ImportSupportState.planned,
      extensions: <String>[],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Legacy fixed-width line parsing.',
      note: 'Recognized in the roadmap, but not implemented yet.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.xlsx,
      label: 'Excel (.xlsx)',
      family: ImportFamily.spreadsheet,
      supportState: ImportSupportState.complete,
      extensions: <String>['.xlsx'],
      implementationKind: ImportImplementationKind.legacyWizard,
      description:
          'Existing Excel import wizard with sheet selection and transforms.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.xls,
      label: 'Excel (.xls)',
      family: ImportFamily.spreadsheet,
      supportState: ImportSupportState.partial,
      extensions: <String>['.xls'],
      implementationKind: ImportImplementationKind.legacyWizard,
      description: 'Legacy Excel import using the existing workbook path.',
      note:
          'Legacy workbooks depend on the current conversion/normalization path and surface warnings.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.ods,
      label: 'OpenDocument Spreadsheet',
      family: ImportFamily.spreadsheet,
      supportState: ImportSupportState.planned,
      extensions: <String>['.ods'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'LibreOffice/OpenOffice spreadsheet import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.json,
      label: 'JSON',
      family: ImportFamily.structuredDocument,
      supportState: ImportSupportState.complete,
      extensions: <String>['.json'],
      implementationKind: ImportImplementationKind.genericWizard,
      description:
          'Structured JSON import with flatten or normalize strategies.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.ndjson,
      label: 'NDJSON / JSONL',
      family: ImportFamily.structuredDocument,
      supportState: ImportSupportState.complete,
      extensions: <String>['.ndjson', '.jsonl'],
      implementationKind: ImportImplementationKind.genericWizard,
      description:
          'Line-oriented JSON import with schema drift handling and relational preview.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.xml,
      label: 'XML',
      family: ImportFamily.structuredDocument,
      supportState: ImportSupportState.complete,
      extensions: <String>['.xml'],
      implementationKind: ImportImplementationKind.genericWizard,
      description:
          'XML import with flatten or parent-child normalization strategies.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.yaml,
      label: 'YAML',
      family: ImportFamily.structuredDocument,
      supportState: ImportSupportState.investigate,
      extensions: <String>['.yaml', '.yml'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Structured YAML import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.toml,
      label: 'TOML',
      family: ImportFamily.structuredDocument,
      supportState: ImportSupportState.deferred,
      extensions: <String>['.toml'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Config-oriented TOML import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.htmlTable,
      label: 'HTML Tables',
      family: ImportFamily.webMarkup,
      supportState: ImportSupportState.complete,
      extensions: <String>['.html', '.htm'],
      implementationKind: ImportImplementationKind.genericWizard,
      description:
          'HTML table extraction with table selection, header inference, and metadata hints.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.markdownTable,
      label: 'Markdown Tables',
      family: ImportFamily.webMarkup,
      supportState: ImportSupportState.investigate,
      extensions: <String>['.md'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Markdown table import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.sqlite,
      label: 'SQLite',
      family: ImportFamily.database,
      supportState: ImportSupportState.complete,
      extensions: <String>['.db', '.sqlite', '.sqlite3'],
      implementationKind: ImportImplementationKind.legacyWizard,
      description: 'Existing SQLite import wizard and background worker path.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.duckdb,
      label: 'DuckDB',
      family: ImportFamily.database,
      supportState: ImportSupportState.planned,
      extensions: <String>['.duckdb'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'DuckDB file import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.access,
      label: 'Microsoft Access',
      family: ImportFamily.legacyBusiness,
      supportState: ImportSupportState.investigate,
      extensions: <String>['.mdb', '.accdb'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Access database import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.dbf,
      label: 'DBF / FoxPro',
      family: ImportFamily.legacyBusiness,
      supportState: ImportSupportState.investigate,
      extensions: <String>['.dbf'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Legacy DBF database import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.sqlDump,
      label: 'SQL Dump',
      family: ImportFamily.databaseDump,
      supportState: ImportSupportState.complete,
      extensions: <String>['.sql'],
      implementationKind: ImportImplementationKind.legacyWizard,
      description: 'Existing SQL dump wizard for the MVP-lite parser scope.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.postgresPlainDump,
      label: 'PostgreSQL Plain SQL Dump',
      family: ImportFamily.databaseDump,
      supportState: ImportSupportState.planned,
      extensions: <String>[],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description:
          'Broader plain SQL dump import beyond current MVP-lite scope.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.parquet,
      label: 'Parquet',
      family: ImportFamily.analytical,
      supportState: ImportSupportState.planned,
      extensions: <String>['.parquet'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Columnar Parquet import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.jsonLogStream,
      label: 'JSON Log Stream',
      family: ImportFamily.logsEvents,
      supportState: ImportSupportState.planned,
      extensions: <String>[],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Operational log ingestion built on NDJSON support.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.delimitedLog,
      label: 'Delimited Log File',
      family: ImportFamily.logsEvents,
      supportState: ImportSupportState.investigate,
      extensions: <String>[],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Template-based delimited log import.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.zipArchive,
      label: 'ZIP Wrapper',
      family: ImportFamily.compressedArchive,
      supportState: ImportSupportState.complete,
      extensions: <String>['.zip'],
      implementationKind: ImportImplementationKind.wrapper,
      description:
          'Archive wrapper that discovers supported inner files and routes them into the normal import flow.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.gzipArchive,
      label: 'GZip Wrapper',
      family: ImportFamily.compressedArchive,
      supportState: ImportSupportState.complete,
      extensions: <String>['.gz'],
      implementationKind: ImportImplementationKind.wrapper,
      description:
          'Single-file wrapper that unwraps supported CSV/JSON/NDJSON/XML/HTML/SQL/Excel/SQLite files.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.bzip2Archive,
      label: 'BZip2 Wrapper',
      family: ImportFamily.compressedArchive,
      supportState: ImportSupportState.investigate,
      extensions: <String>['.bz2'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'BZip2 compressed wrapper support.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.xzArchive,
      label: 'XZ Wrapper',
      family: ImportFamily.compressedArchive,
      supportState: ImportSupportState.investigate,
      extensions: <String>['.xz'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'XZ compressed wrapper support.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.clipboardTable,
      label: 'Clipboard Table',
      family: ImportFamily.webMarkup,
      supportState: ImportSupportState.investigate,
      extensions: <String>[],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'Clipboard HTML/pasted table capture.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.pdfTables,
      label: 'PDF Tables',
      family: ImportFamily.webMarkup,
      supportState: ImportSupportState.deferred,
      extensions: <String>['.pdf'],
      implementationKind: ImportImplementationKind.recognizedUnsupported,
      description: 'PDF table extraction.',
    ),
    ImportFormatDefinition(
      key: ImportFormatKey.unknown,
      label: 'Unknown',
      family: ImportFamily.delimitedText,
      supportState: ImportSupportState.notStarted,
      extensions: <String>[],
      implementationKind: ImportImplementationKind.unknown,
      description: 'Unknown or unsupported source.',
    ),
  ];

  List<ImportFormatDefinition> get formats => _formats;

  ImportFormatDefinition forKey(ImportFormatKey key) {
    return _formats.firstWhere((format) => format.key == key);
  }

  ImportFormatDefinition? forExtension(String extension) {
    final normalized = extension.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final format in _formats) {
      if (format.extensions.contains(normalized)) {
        return format;
      }
    }
    return null;
  }

  ImportFormatDefinition detectByPath(String path) {
    final extension = p.extension(path).toLowerCase();
    return forExtension(extension) ?? forKey(ImportFormatKey.unknown);
  }

  List<String> implementedExtensions() {
    final result = <String>{};
    for (final format in _formats) {
      if (!format.isImplemented) {
        continue;
      }
      result.addAll(format.extensions);
    }
    return result.toList()..sort();
  }
}
