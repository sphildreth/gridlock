# Decent Bench — Implementation Phases

**Status:** Draft  
**Last updated:** 2026-03-09  
**Primary references:** `docs/PRD.md`, `docs/SPEC.md`, `design/adr/`

This document defines the recommended delivery sequence for Decent Bench.

It exists to keep implementation aligned with the product documents while
reducing delivery risk. The project’s MVP is intentionally broader than the
first implementation slice, so work should proceed in phases rather than trying
to land the entire product in one step.

## Goals of this roadmap

- Deliver a runnable desktop app early
- De-risk the hardest architectural pieces first
- Keep scope under control
- Preserve responsiveness and paging-first behavior from day one
- Create small, testable slices that can be validated independently

## Planning principles

1. **Phase 1 before feature breadth**
   - Land the smallest useful end-to-end DecentDB workflow first.
2. **No heavy work on the UI thread**
   - Imports, queries, paging, and exports must be designed as background work.
3. **Paging and cancellation are foundational**
   - Do not build a results UX that assumes full in-memory materialization.
4. **ADRs before long-lived decisions**
   - If a phase introduces a major dependency, contract, or user-visible
     workflow shift, record the decision in an ADR first.
5. **Prefer vertical slices**
   - Each phase should produce demonstrable user value or architectural
     certainty.

---

## Phase 0 — Repository and delivery foundation

### Objective
Prepare the repository for implementation by aligning docs, roadmap, and
decision records.

### Deliverables
- Aligned `PRD`, `SPEC`, and ADR references
- Accepted ADRs for:
  - DecentDB binding strategy
  - results paging/streaming contract
- This implementation roadmap
- Clear MVP vs post-MVP boundaries
- Placeholder app structure retained until runnable scaffold begins

### Exit criteria
- Contributors can identify:
  - what MVP includes
  - what Phase 1 includes
  - which docs govern scope and architecture

### Notes
This phase is documentation-heavy and should remain small. It exists to prevent
scope drift before coding accelerates.

---

## Phase 1 — Runnable scaffold and core query loop

### Objective
Land the smallest runnable Decent Bench slice that proves the app shell,
DecentDB integration, query execution, paging, cancellation, and CSV export.

### In scope
- Flutter desktop scaffold under `apps/decent-bench/`
- App shell and composition root
- Open existing DecentDB file
- Create new DecentDB file
- Schema browser for:
  - tables
  - columns
- Single SQL editor tab
- Run query
- Best-effort cancel query
- Cursor-based paging/streaming integration
- Results grid with paged loading
- CSV export from query results
- Minimal TOML configuration:
  - recent files
  - default page size
  - export defaults
- Basic automated tests
- CI hooks for analysis and tests

### Out of scope
- Import wizard
- Excel import
- SQLite import
- SQL dump import
- Multi-tab editing
- Autocomplete
- Snippets
- SQL formatter
- JSON/Parquet/Excel export

### Why this phase comes first
This phase proves the highest-risk architectural assumptions:
- the upstream DecentDB bindings work for the app
- paging can drive the grid without full materialization
- cancellation can be expressed in a usable UI model
- background work and app state management are viable

### Suggested technical milestones
1. Create runnable desktop app scaffold
2. Add local DecentDB adapter over upstream bindings
3. Implement open/create DB workflow
4. Load schema metadata for tables/columns
5. Add single-tab query execution
6. Add cursor paging and result state machine
7. Add cancel behavior and stale-event protection
8. Add CSV export over paged results
9. Add tests and CI

### Exit criteria
A contributor can:
1. run the app
2. open or create a DecentDB file
3. inspect tables and columns
4. execute a query
5. receive paged results
6. cancel a running query
7. export results to CSV
8. run analyzer and tests successfully

---

## Phase 2 — Workspace ergonomics and multi-tab query experience

### Objective
Expand the query workflow into a more realistic daily-use workbench.

### In scope
- Multi-tab SQL editor
- Per-tab results ownership
- Query tab execution state model
- Keyboard navigation between tabs and panes
- Improved schema browser details:
  - views, if available
  - indexes, if available
  - additional supported object metadata where practical
- Better workspace persistence:
  - recent files
  - reopening behavior as defined later
- Results pane UX polish:
  - empty state
  - partial/cancelled state
  - error details copy action

### Dependencies
- Phase 1 complete
- Query state model stable enough for multiple concurrent tab states

### Risks
- Tab state complexity
- stale event handling across multiple executions
- schema browser scope creep

### Exit criteria
- Multiple query tabs can be used reliably
- Each tab owns its own execution/result state
- The schema browser is useful for normal query authoring
- The app remains responsive during normal query iteration

---

## Phase 3 — SQL productivity features

### Objective
Add the editor capabilities required by MVP without destabilizing the core data
path.

### In scope
- Schema-aware autocomplete
- User-editable snippets
- Deterministic SQL formatter
- Editor-focused settings in TOML
- Tests for:
  - autocomplete sources/rules
  - formatter behavior
  - snippet storage and retrieval

### Dependencies
- Stable schema metadata model
- Stable multi-tab editor framework
- Dependency choices validated for licensing compatibility

### Risks
- Editor feature complexity can expand quickly
- formatter/autocomplete packages may create licensing or correctness issues
- schema-aware suggestions can become slow on large schemas if caching is poor

### Exit criteria
- Users can author queries with helpful completions
- Snippets and formatting are usable and deterministic
- These features do not degrade editor responsiveness

---

## Phase 4 — SQLite import

### Objective
Deliver the first robust import workflow using a source format that is highly
valuable and relatively bounded.

### In scope
- Drag-and-drop file handling for SQLite files
- Import Wizard scaffold
- Target DecentDB file selection
- Table selection
- Type mapping from SQLite affinities to DecentDB native types
- Preview and summary
- Rename columns
- Type overrides
- Import job status and cancellation where feasible
- Tests with representative SQLite fixtures

### Why SQLite first
SQLite import is likely easier to reason about than Excel and SQL dump parsing,
while still delivering strong user value and validating the import architecture.

### Risks
- schema fidelity edge cases
- BLOB handling
- STRICT / WITHOUT ROWID behavior
- transactional cleanup behavior on failure

### Exit criteria
- User can import selected SQLite tables into DecentDB
- Import summary and failure behavior are understandable
- App remains responsive during import

---

## Phase 5 — Excel import

### Objective
Add Excel import with preview, headers control, type inference, and type
overrides.

### In scope
- Drag-and-drop Excel file entry
- Workbook and sheet selection
- Header row on/off
- Type inference with override
- Table naming
- Sample preview
- Import execution and summary
- Streaming or bounded-memory reading for large files

### Dependencies
- Import Wizard framework from Phase 4
- Dependency choice for Excel parsing validated for license compatibility and
  streaming behavior

### Risks
- mixed-type columns
- date/time interpretation
- large workbook memory usage
- sheet parsing performance

### Exit criteria
- User can import a workbook/sheet into DecentDB
- Type inference is understandable and overridable
- Large files do not freeze the UI

---

## Phase 6 — SQL dump import (MVP-lite)

### Objective
Support import of common MariaDB/MySQL-style `.sql` dumps within a constrained
and testable parsing scope.

### In scope
- Drag-and-drop `.sql` file entry
- Encoding detect/override
- Parsing support for common:
  - `CREATE TABLE`
  - `INSERT INTO`
- Preview of parsed schema and sample rows
- Import summary with skipped statement count
- Warnings for unsupported statements

### Explicit limitations
- This is not a general SQL parser for all dump dialects
- Unsupported statements may be skipped
- Broad database-dump compatibility is out of scope for MVP-lite

### Risks
- syntax variability across dump generators
- encoding issues
- type mapping edge cases
- temptation to broaden parser scope too quickly

### Exit criteria
- At least one representative MariaDB/MySQL-style dump imports successfully
- Unsupported constructs fail clearly or warn clearly
- The import path is stable and testable

---

## Phase 7 — MVP hardening

### Objective
Complete the MVP quality bar and resolve remaining gaps across performance,
packaging, testing, and documentation.

### In scope
- Broader automated coverage
- Performance-sensitive regression scenarios
- Packaging verification for desktop platforms
- Native library discovery hardening
- Config versioning/migration decisions if needed
- Documentation updates for setup, validation, and user flows
- Manual verification checklists for:
  - large query paging
  - cancellation
  - long-running imports
  - export behavior

### Questions to close in this phase
- canonical DecentDB file extension
- exact schema browser object coverage for the pinned engine version
- any remaining config layout details
- whether any stretch work should be promoted to MVP or deferred

### Exit criteria
- MVP acceptance criteria in `docs/SPEC.md` are satisfied
- tests are passing
- analyzer is clean
- major workflows are documented
- packaging/startup behavior is repeatable

---

## Explicitly deferred until after MVP

These should not block MVP unless later promoted through a documented scope
change:

- JSON export
- Parquet export
- Excel export from query results
- Postgres import
- additional external connectors
- computed-column transforms during import
- multi-workspace support
- collaboration features
- ERD designer
- query plan visualizer
- stored procedure workflows
- advanced script orchestration

---

## Recommended issue grouping

To keep work reviewable, create issues or milestones around these streams:

1. **App scaffold and CI**
2. **DecentDB adapter and packaging**
3. **Query execution + paging + cancellation**
4. **Schema browser**
5. **Results grid**
6. **Export**
7. **Import framework**
8. **SQLite import**
9. **Excel import**
10. **SQL dump import**
11. **Editor productivity features**
12. **Documentation and ADR alignment**

---

## Definition of done per phase

A phase is done when:

- the scoped deliverables are implemented
- tests exist for non-trivial behavior
- documented validation steps are clear
- no new UI-thread-heavy behavior was introduced
- docs remain aligned with the accepted ADRs
- unresolved trade-offs are captured in ADRs or clearly deferred

---

## Change management

If a phase introduces any of the following, record the decision in an ADR before
or alongside implementation:

- a major new dependency
- a binding strategy change
- a new paging/export/import contract
- a user-visible workflow change that alters MVP scope
- a persistent format or config migration rule
- a packaging/distribution decision with long-term consequences

---

## Summary

The intended delivery order is:

1. Phase 0 — docs and decision alignment
2. Phase 1 — runnable scaffold + core query loop
3. Phase 2 — multi-tab workspace ergonomics
4. Phase 3 — SQL productivity features
5. Phase 4 — SQLite import
6. Phase 5 — Excel import
7. Phase 6 — SQL dump import
8. Phase 7 — MVP hardening

This sequencing keeps the project focused on its highest-risk technical
assumptions first while still moving toward the full MVP defined in the product
documents.