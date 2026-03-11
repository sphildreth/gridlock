## Import Format Registry And Generic Wizard
**Date:** 2026-03-11
**Status:** Accepted

### Decision

Decent Bench introduces a shared import subsystem for file detection and the new
generic import families while preserving the existing Excel, SQLite, and SQL
dump workflows.

The accepted architecture is:

- a central `ImportFormatRegistry` that defines format families, support state,
  file extensions, and the implementation path for each known format;
- an `ImportDetectionService` that routes dropped files, `--import` startup
  paths, and file-picker selections through the same detection contract;
- a generic preview/execution pipeline for delimited text, structured
  documents, HTML tables, and ZIP/GZip wrappers;
- continued reuse of the existing Excel, SQLite, and SQL dump wizards through
  legacy handler routing instead of a full rewrite in this slice.

### Rationale

`design/IMPORT_SUPPORT_PLAN.md` expands the product from a few one-off import
dialogs into a family-aware ingestion workbench. The app already had working
MVP import paths for Excel, SQLite, and SQL dump sources, but it lacked a
single place to express support state, route wrapper formats, or add new import
families without more ad hoc `switch` statements.

The registry + detector model makes supported, partial, and planned formats
explicit in code and in docs. A generic wizard for the new text/structured/web
formats delivers immediate value without destabilizing the legacy import flows
that were already aligned to accepted ADRs.

### Alternatives Considered

- Rewrite all existing import wizards into a single controller before adding any
  new formats
- Keep adding format-specific entry logic directly in `workspace_screen.dart`
- Defer the generic families until a larger architecture refactor is possible

### Trade-offs

- The app now has two import implementation paths in the short term: legacy
  wizards for Excel/SQLite/SQL dump and the generic wizard for the new families
- The shared registry and detection model reduce future coupling, but they do
  not yet unify every existing import session model into one controller
- ZIP handling currently routes one selected inner file at a time through the
  normal flow, which preserves the existing single-import-session UX but is not
  a bulk archive recipe system yet

### References

- [design/IMPORT_SUPPORT_PLAN.md](/home/steven/source/decent-bench/design/IMPORT_SUPPORT_PLAN.md)
- [design/PRD.md](/home/steven/source/decent-bench/design/PRD.md)
- [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
- [AGENTS.md](/home/steven/source/decent-bench/AGENTS.md)
- [apps/decent-bench/lib/features/import/](/home/steven/source/decent-bench/apps/decent-bench/lib/features/import/)
