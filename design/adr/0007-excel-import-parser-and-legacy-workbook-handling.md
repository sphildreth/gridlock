## Excel Import Parser And Legacy Workbook Handling
**Date:** 2026-03-10
**Status:** Accepted

### Decision

Phase 5 implements Excel import through the existing import-wizard and
isolate-worker architecture using the Dart `excel` package as the workbook
parser.

The delivered Phase 5 behavior is:

- `.xlsx` workbooks are inspected and imported in background isolates.
- workbook inspection supports sheet selection, header-row on/off, sample
  preview, table naming, column renaming, and per-column type overrides.
- import execution reuses the existing transactional DecentDB worker model with
  progress updates, best-effort cancellation, and rollback-oriented summaries.
- legacy `.xls` files are still recognized at entry, but the wizard stops with
  an explicit "save as `.xlsx` and retry" message instead of attempting a
  partial or lossy import.

### Rationale

Phase 5 needs a pure-Dart workbook parser that can run inside the existing
Flutter/Dart isolate model, stays compatible with Apache 2.0 distribution, and
provides worksheet/cell access suitable for preview, type inference, and row
copying into DecentDB.

The `excel` package satisfies the immediate `.xlsx` needs and is MIT licensed.
It also keeps the import path testable inside the current Dart codebase without
introducing an external converter or a separate native helper.

During evaluation, a maintained Apache-compatible parser for legacy binary
`.xls` workbooks was not available in the current stack with the same
integration simplicity. Phase 5 therefore ships a clear, explicit limitation
for `.xls` instead of silently degrading behavior.

### Alternatives Considered

- Shell out to LibreOffice or another external converter before import
- Add a native helper or separate process for workbook parsing
- Delay Excel import until both `.xlsx` and `.xls` can be supported together
- Parse `.xls` through a best-effort unsupported path with unclear fidelity

### Trade-offs

- Phase 5 delivers the MVP workbook flow for `.xlsx` now, but legacy `.xls`
  remains a known gap that should be revisited when a suitable parser or
  conversion strategy is chosen.
- The selected parser loads workbook bytes into memory up front, so the import
  path is backgrounded and row processing is bounded, but parsing is not fully
  streaming at the file-format layer.
- Formula cells are imported as formula text, which is deterministic and
  explainable, but it does not evaluate workbook formulas during import.

### References

- [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
- [design/IMPLEMENTATION_PHASES.md](/home/steven/source/decent-bench/design/IMPLEMENTATION_PHASES.md)
- [THIRD_PARTY_NOTICES.md](/home/steven/source/decent-bench/THIRD_PARTY_NOTICES.md)
- [AGENTS.md](/home/steven/source/decent-bench/AGENTS.md)
