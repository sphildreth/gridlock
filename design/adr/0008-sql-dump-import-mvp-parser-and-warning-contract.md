## SQL Dump Import MVP Parser And Warning Contract
**Date:** 2026-03-10
**Status:** Accepted

### Decision

Phase 6 implements SQL dump import as an MVP-lite workflow with a constrained,
in-repo parser and a warning-oriented compatibility contract.

The accepted Phase 6 contract is:

- supported input is MariaDB/MySQL-style `.sql` dumps containing common
  `CREATE TABLE` statements plus `INSERT ... VALUES` row batches
- inspection and import run off the UI thread using the existing background
  worker pattern
- decoding is limited to `auto`, `utf8`, and `latin1`
- unsupported statements are preserved as skipped-statement warnings in the
  wizard and summary whenever the import can continue safely
- imported tables remain transactional at the DecentDB target layer so cancel
  and failure paths can roll back the target file for the current job
- the implementation does not add a new general-purpose SQL parser dependency

### Rationale

Phase 6 needs a practical SQL dump path that fits the current desktop app
architecture, stays Apache-2.0-compatible, and is testable against the local
DecentDB bridge without introducing another large dependency surface.

MariaDB/MySQL dump files are highly variable. Supporting the full ecosystem of
session directives, engine clauses, stored routines, trigger bodies, view
definitions, and multi-statement migration behavior would materially expand MVP
scope and create a large correctness surface before the rest of the product is
finished.

A constrained parser focused on the MVP acceptance path is enough to deliver:

- drag-and-drop `.sql` entry
- inspection of parsed tables and sample rows
- rename and type-override transforms
- background import with progress
- summary reporting that makes skipped statements visible

### Alternatives Considered

- Add a third-party SQL parser dependency for MySQL/MariaDB dialects
- Defer SQL dump import until a broader parser strategy exists
- Treat any unsupported statement as a hard import failure
- Execute the dump directly against another embedded engine first, then copy out

### Trade-offs

- The delivered workflow is intentionally narrower than “arbitrary SQL dump
  compatibility”; contributors must preserve the documented MVP-lite scope
- Users get a usable import path now, but dumps with procedures, views, trigger
  bodies, custom delimiters, or broader migration semantics may still need
  manual cleanup first
- Warning-based skipped statements improve usability, but they require clear UI
  visibility so partially supported dumps are not mistaken for full replay
- Avoiding a new parser dependency keeps licensing and packaging simpler, but it
  means more parser logic is owned in-repo
- Restricting decode options to `auto`, `utf8`, and `latin1` covers the common
  desktop cases without implying universal encoding support

### References

- [design/PRD.md](/home/steven/source/decent-bench/design/PRD.md)
- [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
- [design/IMPLEMENTATION_PHASES.md](/home/steven/source/decent-bench/design/IMPLEMENTATION_PHASES.md)
