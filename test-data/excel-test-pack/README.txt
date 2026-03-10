Decent Bench Excel Import Test Pack

Files included
- basic_contacts.xlsx: simple contact/customer-style sheet with dates, booleans, text, currency, and notes.
- sales_orders.xlsx: larger transactional sheet (250 rows) with dates, quantities, currency, percentages, booleans, and categorical fields.
- sensor_timeseries.xlsx: time-series telemetry data (1000 rows), timestamps, numerics, booleans, blanks/nulls, and error/status text.
- inventory_pricing_complex.xlsx: multi-sheet workbook with formulas, summary calculations, and cross-sheet references.
- cross_sheet_calculations.xlsx: multi-sheet workbook where order calculations reference pricing and regional settings from other tabs.
- wide_sparse_dataset.xlsx: wide sheet with 40 columns, mixed data types, empty cells, and date columns.
- legacy_contacts.xls: basic legacy XLS workbook with mixed types.
- legacy_sales.xls: legacy XLS workbook with formula-driven totals.
- legacy_multi_sheet.xls: legacy XLS workbook with multiple tabs and basic formulas.

Complex-workbook notes
- The xlsx "complex" files contain formulas that reference:
  - cells in the same row
  - cells on other sheets
  - summary aggregations
- If Decent Bench eventually supports importing formulas, these are good test cases for:
  - importing calculated values as static columns
  - preserving formulas
  - converting sheet-level derived logic into views or generated queries
- The xls files are simpler than the xlsx files by design, since legacy-format support is usually narrower.

Suggested import tests
1. Basic single-sheet import
2. Wide-table import
3. Time-series import
4. Multi-sheet workbook import
5. Formula-heavy workbook import
6. Legacy .xls import
