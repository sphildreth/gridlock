## Aggregate Excel Summary Sheets As Views
**Date:** 2026-03-11
**Status:** Accepted

### Decision

Decent Bench keeps the conservative Excel formula contract for ordinary
row-oriented sheets: formula cells still land as formula text in imported
tables.

For a narrower class of workbook tabs, the Excel import path now creates
DecentDB views instead of tables:

- the worksheet must be imported with header-row mode enabled
- every populated data row must contain supported aggregate formulas
- the supported summary formulas are currently `COUNTIF`, `COUNTA`, `SUM`,
  `SUMIF`, and `SUMPRODUCT`
- supporting row-level formulas referenced by those summaries may use the
  existing workbook formulas for `VLOOKUP`, `IF`, comparisons, and arithmetic

If a selected summary sheet matches that shape and its dependencies are also
available for translation, the importer generates a `CREATE VIEW` statement for
that worksheet name. If translation is not possible, the sheet falls back to
the existing table import behavior and the summary records a warning.

The Excel import summary now reports imported views alongside imported tables.

### Rationale

The checked-in Excel fixture pack already contains workbook tabs like
`Dashboard` and `Summary` that are not source tables; they are derived report
surfaces built from other sheets. Importing those tabs as tables preserved only
formula text, which lost the intended semantics and made schema browsing less
accurate.

Treating aggregate-only summary sheets as views preserves the existing
formula-as-text fallback for general spreadsheets while giving workbook
dashboards a closer DecentDB representation without requiring full Excel
formula support across every sheet type.

### Alternatives Considered

- Keep importing every Excel worksheet as a table, regardless of formula shape
- Promote every worksheet containing formulas to a view, including mixed
  row-level data-entry sheets
- Evaluate formulas eagerly and store only static computed values in tables

### Trade-offs

- View generation is intentionally limited to a small supported formula set and
  still falls back for unsupported workbook logic
- Imported summary views depend on the selected workbook dependencies needed for
  translation; if those dependencies are missing, the importer reverts to a
  warning-backed table import
- Mixed row-oriented sheets with formula columns still import as tables, so the
  behavior remains intentionally asymmetric between operational sheets and
  workbook dashboards

### References

- [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
- [design/adr/0012-legacy-xls-conversion-and-formula-import-contract.md](/home/steven/source/decent-bench/design/adr/0012-legacy-xls-conversion-and-formula-import-contract.md)
- [test-data/excel-test-pack/cross_sheet_calculations.xlsx](/home/steven/source/decent-bench/test-data/excel-test-pack/cross_sheet_calculations.xlsx)
- [test-data/excel-test-pack/inventory_pricing_complex.xlsx](/home/steven/source/decent-bench/test-data/excel-test-pack/inventory_pricing_complex.xlsx)
- [apps/decent-bench/lib/features/workspace/infrastructure/excel_import_support.dart](/home/steven/source/decent-bench/apps/decent-bench/lib/features/workspace/infrastructure/excel_import_support.dart)
