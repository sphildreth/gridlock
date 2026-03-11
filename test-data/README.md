# Decent Bench Import Test Data

This directory contains the import fixtures used for Decent Bench manual smoke
tests, import pipeline development, and automated test coverage. The files are
grouped by source family so the same assets can be reused for detection,
preview, import execution, and unsupported-format messaging.

The current inventory includes 32 fixture files across delimited text,
structured documents, Excel workbooks, SQLite, and SQL dump scenarios.

## Coverage intent

This pack is aligned with the current import support baseline in
`docs/IMPORT_FORMATS.md`.

- Positive-path fixtures cover formats that are implemented now or partially
  supported now, including CSV/TSV/PSV, JSON, NDJSON, XML, HTML tables, GZip
  wrappers, Excel `.xlsx`, Excel `.xls`, SQLite, and MySQL/MariaDB-style SQL
  dumps.
- Negative-path and future-path fixtures cover formats that are recognized but
  not fully supported in the current build, including fixed-width text,
  PostgreSQL plain SQL dumps, and mock backup formats such as `.bak`, `.dump`,
  and `.backup`.

Not every file in this directory is expected to import successfully today. Some
fixtures exist specifically to validate graceful failure, warning messages, and
wizard routing for unsupported sources.

## Directory map

### `text_seperated_values/`

The folder name is historical and intentionally preserved. It contains the core
delimited-text fixtures plus one fixed-width negative-test file.

- `customers_basic.csv`: small CSV smoke test with text, dates, booleans, and
  numeric values.
- `customers_basic.csv.gz`: GZip-wrapped version of `customers_basic.csv` for
  wrapper detection and decompression coverage.
- `products.tsv`: tab-separated fixture for alternate delimiter detection.
- `orders_pipe.psv`: pipe-delimited fixture for nonstandard delimiter coverage.
- `employees_fixed_width.txt`: fixed-width text sample for unsupported-format
  messaging and future parser work.

### `json/`

- `nested_orders.json`: nested-object and nested-array fixture for structured
  JSON preview/import behavior.
- `events.ndjson`: newline-delimited JSON fixture for row-oriented JSON import.

### `xml/`

- `catalog.xml`: compact XML catalog fixture with nested elements and
  attributes.

### `html/`

- `report_tables.html`: HTML document with multiple tables for table detection,
  selection, and preview behavior.

### `excel/`

Excel fixtures are split between lightweight workbook smoke tests and a broader
workbook pack documented in `excel/README.txt`.

- `workbook_simple.xlsx`: small legacy smoke fixture for basic `.xlsx` import.
- `workbook_formulas.xlsx`: small formula-oriented `.xlsx` smoke fixture.
- `basic_contacts.xlsx`: simple contact-style workbook with dates, booleans,
  text, currency, and notes.
- `sales_orders.xlsx`: larger transactional workbook with mixed scalar types.
- `sensor_timeseries.xlsx`: time-series workbook with nulls, booleans, status
  text, and many rows.
- `wide_sparse_dataset.xlsx`: wide workbook with many columns and sparse cells.
- `inventory_pricing_complex.xlsx`: multi-sheet workbook with formulas,
  summaries, and cross-sheet references.
- `cross_sheet_calculations.xlsx`: workbook focused on cross-sheet formulas and
  derived values.
- `legacy_contacts.xls`: legacy XLS workbook with basic mixed types.
- `legacy_sales.xls`: legacy XLS workbook with formula-driven totals.
- `legacy_multi_sheet.xls`: legacy XLS workbook with multiple sheets and basic
  formulas.
- `README.txt`: scenario notes for the Excel workbook pack.

Use the `.xls` files to validate the current partial legacy workbook path and
its warning behavior.

### `sql_related/`

This directory mixes positive-path database fixtures with negative-test backup
placeholders.

- `sample_app.sqlite`: real SQLite database for SQLite wizard coverage.
- `schema_seed.sql`: compact generic SQL seed file useful for parser and import
  smoke tests.
- `mysql_export.sql`: MySQL-style SQL dump covering `CREATE TABLE`, `INSERT`,
  keys, foreign keys, and a view.
- `mysql_export.sql.gz`: GZip-wrapped MySQL dump for wrapper coverage.
- `mariadb_export.sql`: MariaDB-style SQL dump covering common MVP-lite import
  patterns.
- `mariadb_export.sql.gz`: GZip-wrapped MariaDB dump.
- `postgresql_plain_export.sql`: PostgreSQL plain SQL dump fixture for degraded
  behavior and future support expansion.
- `postgresql_plain_export.sql.gz`: GZip-wrapped PostgreSQL plain dump.
- `mysql_mock_export.bak`: mock unsupported backup file for extension-based
  detection and unsupported-format messaging.
- `mariadb_mock_export.bak`: mock unsupported MariaDB backup fixture.
- `postgresql_mock_binary.dump`: mock unsupported PostgreSQL binary/custom dump
  fixture.
- `postgresql_mock_custom.backup`: mock unsupported PostgreSQL custom backup
  fixture.

The MySQL and MariaDB dumps are current positive-path fixtures. The PostgreSQL
fixtures are retained to verify that unsupported or partially supported SQL dump
sources fail clearly and predictably.

## Recommended usage

Use this pack for the following checks:

1. File-type detection and wizard routing from drag-and-drop or `--import`.
2. Preview generation for tabular, structured, and workbook sources.
3. Import execution against supported source types.
4. Graceful warning and failure behavior for unsupported or deferred formats.
5. Wrapper handling for `.gz` inputs that should route to an inner supported
   format.

When adding new fixtures, keep them deterministic, small enough for routine
test runs, and free of sensitive or licensed third-party data.
