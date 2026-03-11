# Import Formats

This document mirrors the code-level import registry in
`apps/decent-bench/lib/features/import/infrastructure/import_format_registry.dart`.
It summarizes what the current build can import now, what is only partially
supported, and what is recognized but not implemented yet.

## Fully implemented now

- DecentDB `.ddb` open path
- CSV
- TSV
- generic delimited text (`.txt`, `.dat`, `.log`)
- JSON
- NDJSON / JSONL
- XML
- HTML tables (`.html`, `.htm`)
- ZIP wrapper routing to recognized inner files
- GZip wrapper routing to recognized inner files
- Excel `.xlsx` via the existing workbook wizard
- SQLite via the existing SQLite wizard
- SQL dump via the existing MVP-lite SQL dump wizard

## Partial support now

- Excel `.xls`
  - routed through the existing Excel import path
  - relies on the current conversion/normalization contract and surfaces
    warnings when the runtime conversion path is required

## Recognized but not implemented yet

- fixed-width text
- OpenDocument Spreadsheet (`.ods`)
- YAML / YML
- TOML
- Markdown tables
- DuckDB
- Microsoft Access (`.mdb`, `.accdb`)
- DBF / FoxPro
- broader PostgreSQL plain SQL dump handling
- Parquet
- BZip2 / XZ wrapper formats
- clipboard table capture
- PDF table extraction

## Notes on the current architecture

- `ImportFormatRegistry` is the source of truth for family, support state, and
  implementation path.
- `ImportDetectionService` is used for drag-and-drop, `--import`, and the file
  picker entry flow.
- Delimited text, structured documents, HTML tables, and wrappers use the new
  generic preview/execution pipeline.
- Excel, SQLite, and SQL dump still use the existing dedicated wizards and
  background workers, but are now routed through the shared detector.

## Next recommended formats

The next most valuable additions after this slice are:

1. fixed-width text
2. ODS
3. Parquet
4. DuckDB
5. PostgreSQL plain SQL dump expansion
