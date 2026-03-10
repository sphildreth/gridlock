# Decent Bench — Product Specification (SPEC) v0.2

**Product:** Decent Bench  
**Type:** Cross-platform desktop SQL-style app (Flutter)  
**License:** Apache 2.0  
**Primary purpose:** Drag-and-drop import into **DecentDB**, then inspect
schema, run the pinned DecentDB SQL surface, and export shaped results.
**PRD reference:** `design/PRD.md`

**Pinned engine capability baseline:** DecentDB v1.6.x

---

## 0. Terminology

- **DecentDB**: The target embedded database format used by Decent Bench
  workspaces.
- **Import source**: A file or external database used only as input to create
  or load data into DecentDB.
- **Wizard**: The guided flow launched on drag-and-drop of a non-DecentDB file
  to configure import.
- **Workspace**: An open DecentDB file plus UI state, such as tabs, recent
  objects, and per-tab query state.
- **Schema browser**: UI for catalog discovery such as tables, views, columns,
  indexes, triggers, and constraints.
- **Cursor**: A query handle returned by the DecentDB binding that allows page-
  based retrieval of results without full materialization.

---

## 1. Scope

This document distinguishes between:

- **Phase 1 implementation slice**: the smallest useful, runnable slice that
  should land first
- **MVP scope**: the required product scope for `v1`
- **Next**: explicitly deferred beyond MVP

If a feature appears in multiple documents and the scope differs, this SPEC is
the source of truth for implementation scope.

### 1.1 Phase 1 implementation slice

Phase 1 exists to reduce delivery risk and establish a runnable architecture.
It should include only:

- Open an existing DecentDB file
- Create a new DecentDB file
- Load schema browser metadata for tables and columns
- Single query editor tab
- Run and cancel a query
- Paged/streamed results grid
- CSV export from query results
- Minimal TOML configuration
- Runnable desktop scaffold with tests and CI hooks

Phase 1 intentionally excludes import wizard work, autocomplete, snippets,
formatter, JSON/Parquet/Excel export, and multi-tab editing.

### 1.2 MVP (must-haves)

#### Entry + workflow
- Drag-and-drop a file onto the app window:
  - If DecentDB, open immediately
  - Otherwise, launch Import Wizard based on file type
- Single-file drop for MVP
- If multiple files are dropped, import the first and show a warning dialog

#### Imports
- Excel (`.xls`, `.xlsx`)
- SQLite (`.db`, `.sqlite`, `.sqlite3`)
- MariaDB/MySQL-style `.sql` dump (**MVP-lite**; common `CREATE TABLE` +
  `INSERT` patterns)
- Import transforms before commit:
  - Rename columns
  - Type overrides
- **Computed columns are deferred to Next**

#### Schema browser
- Must reflect the supported DecentDB object kinds for the pinned DecentDB
  version used by Decent Bench
- MVP object classes:
  - tables
  - views
  - temp tables/views where exposed by the engine and adapter
  - columns
  - indexes, including richer index metadata where exposed
  - constraints/triggers, where exposed
  - generated-column metadata where exposed
- Unsupported object kinds must degrade gracefully and must not block the rest
  of schema browsing

#### SQL experience
- Multi-tab editor with per-tab results panes
- Keyboard navigation between tabs and focus between editor/results
- Run/stop query with best-effort cancellation
- Execute the full SQL surface documented by the pinned DecentDB engine
  reference, even when dedicated UI affordances for some engine features arrive
  later
- Schema-aware autocomplete
- User-editable snippets
- Deterministic SQL formatter

#### Results + export
- Virtualized/paginated results grid
- Export query results:
  - CSV (**required for MVP**)
- JSON, Parquet, and Excel exports are **Next**

#### Config
- TOML configuration file stored locally

#### Engineering governance
- ADRs from day one using the provided template and README policy

### 1.3 Out of scope for SPEC v0.2

- Postgres custom-format backup import
- Plain Postgres import unless later added by ADR and PRD/SPEC update
- Multi-workspace support
- Collaboration features
- Full migration tooling
- External databases as first-class query targets
- ERD designer
- Query plan visualizer
- Stored procedure workflow tooling
- Script orchestration engine
- Computed-column transforms during import

---

## 2. Product architecture (high level)

Decent Bench is composed of:

1. **UI shell (Flutter)** — windowing, navigation, tabs, dialogs, wizards
2. **DecentDB binding adapter** — Dart-side wrapper over the upstream DecentDB
   Dart FFI bindings
3. **Import pipeline** — parsers/connectors + transform planner + bulk load
4. **Export pipeline** — cursor/grid data source to exporters
5. **Workspace state** — current database, tabs, results, recent files
6. **Config + secrets** — TOML config + OS secure credential storage
7. **ADR process** — decision records for long-lived technical choices

The architecture must preserve these invariants:

- no heavy work on the UI thread
- no default full-result materialization
- cancellation is best-effort but UI responsiveness is mandatory
- imports and exports must run as jobs with explicit status and error reporting

---

## 3. Repository layout (proposed)

```text
/apps/decent-bench/
  /lib/
    /app/                    # app shell, routing, theming, composition root
    /features/
      /workspace/
      /import_wizard/
      /schema_browser/
      /sql_editor/
      /results_grid/
      /export/
      /settings/
    /shared/                 # shared widgets, utilities, abstractions
  /native/                   # native DecentDB artifacts or packaging helpers
/design/
  IMPLEMENTATION_PHASES.md
  /adr/
    README.md
    0000-template.md
    0001-...
  PRD.md
  SPEC.md
```

### 3.1 Code-organization guidance

Feature folders should avoid mixing UI and orchestration logic in the same file.
As implementation grows, each complex feature should separate:

- presentation/widgets
- controllers/view models/state
- domain models/contracts
- infrastructure adapters where needed

This is guidance rather than a mandated folder taxonomy, but the separation of
concerns is required.

---

## 4. Core UX flows

### 4.1 Drag-and-drop handler (MVP)

**Trigger:** user drops a file onto the main window.

**Detection rules (MVP):**
- Extension-based detection:
  - DecentDB: `.ddb`
  - Excel: `.xls`, `.xlsx`
  - SQLite: `.db`, `.sqlite`, `.sqlite3`
  - SQL dump: `.sql`
- Lightweight signature checks may be added where safe, but extension-based
  detection is acceptable for MVP
- If extension is unrecognized:
  - Show an "Unknown file type" wizard/screen with supported types guidance

**Behavior:**
- If DecentDB:
  - Open workspace
  - Load schema browser immediately
- Otherwise:
  - Launch import wizard with source file preselected

**Multi-drop:**
- If more than one file is dropped:
  - take the first
  - show warning: "MVP supports importing one file at a time."

### 4.2 Import wizard common structure

Wizard steps:

1. **Source selection**  
   Pre-filled from drag-and-drop when applicable.
2. **Target selection**  
   Create new DecentDB file or choose existing DecentDB file.
3. **Preview**  
   Show inferred schema and sample rows.
4. **Transforms**
   - Rename columns
   - Adjust types to DecentDB native types
5. **Import execution**
   - progress
   - cancel when feasible
6. **Summary**
   - rows imported
   - errors and warnings
   - actions: "Open table" / "Run a query"

### 4.3 SQL editor and results tabs

Each tab owns:

- SQL text buffer
- execution state
- result data source metadata
- error panel state
- export state for the active result set

Keyboard requirements:

- `Ctrl/Cmd+Enter`: execute
- `Ctrl/Cmd+Tab`: next tab
- `Ctrl/Cmd+Shift+Tab`: previous tab
- `Tab` / `Shift+Tab`: move focus between editor and results controls

Per-tab history is optional for MVP.

### 4.4 Schema browser

The schema browser must be backed by DecentDB metadata queries or APIs and must
not hardcode schema assumptions beyond the pinned engine version.

Selecting an object shows details such as:

- definition text where available
- columns and types
- constraints
- indexes
- triggers, where exposed
- generated-column metadata and temp-object details where exposed

Search/filter should be responsive and operate on an in-memory metadata model
derived from the latest loaded schema snapshot.

### 4.5 Export flow

- Export action is initiated from the results pane
- User chooses format
- User configures format-specific options
- User chooses destination path
- Export runs as a background job with progress and error reporting

For MVP, only CSV is required to be implemented.

---

## 5. DecentDB integration

### 5.1 Binding strategy

The binding strategy is governed by `design/adr/0001-decentdb-flutter-binding-
strategy.md`.

**Normative decision:** Decent Bench uses the **upstream DecentDB Dart FFI
bindings** as the supported integration mechanism.

This SPEC must not be interpreted as requiring a custom C shim or an
alternative binding layer for MVP. If the upstream bindings prove insufficient,
that gap must be addressed through:
1. an ADR update or new ADR
2. an implementation plan update
3. corresponding PRD/SPEC changes if scope changes

### 5.2 Local adapter layer

Although the upstream bindings are the integration mechanism, the app should
still define a local Dart-side adapter/service boundary so UI and feature code
do not depend directly on raw binding calls.

That adapter must encapsulate at least:

- open/close DB
- execute SQL
- open query cursor
- fetch next page
- close cursor
- cancellation request
- schema introspection
- structured error mapping

### 5.3 Required API surface

The effective minimum capabilities required from the adapter and underlying
bindings are:

- open/close DB by file path
- execute arbitrary SQL statements supported by the pinned engine version
- bind positional parameters
- query SQL with page-based retrieval
- schema introspection across supported object kinds
- best-effort cancellation
- structured error reporting where available

### 5.4 Pinned SQL capability baseline

The pinned DecentDB compatibility line (`v1.6.x`) and its official SQL reference are the
normative source of truth for SQL capability in Decent Bench.

For the pinned engine version, Decent Bench should preserve support for the
documented categories below rather than introducing an app-specific reduced SQL
subset:

- DDL: tables, temp tables/views, indexes, view lifecycle, trigger lifecycle,
  generated columns, and supported constraints
- DML: `INSERT`, `SELECT`, `UPDATE`, `DELETE`, `ANALYZE`
- Query features: `WHERE`, scalar functions, common table expressions
  including recursive CTEs, set operations, joins, aggregate functions, window
  functions, transactions, `EXPLAIN`, `EXPLAIN ANALYZE`, table-valued
  functions, and positional parameters

If the pinned engine reference documents a limitation or unsupported feature,
that behavior should be treated as an engine limitation rather than papered
over by Decent Bench documentation.

### 5.5 Threading model

All heavy work must be off the UI thread.

Background execution is required for:

- query execution
- cursor paging
- imports
- exports
- large metadata loads

Implementation may use Dart isolates, native background threads, or both,
depending on the behavior of the upstream bindings and the surrounding adapter.

---

## 6. Query execution and paging contract

The paging model is governed by
`design/adr/0002-results-paging-and-streaming-contract.md`. Until superseded,
this SPEC adopts the cursor-based paging model described there.

### 6.1 Contract

Query execution uses this lifecycle:

1. `queryOpen(sql, options) -> cursor`
2. Repeatedly call
   - `queryNext(cursor, pageSize) -> page`
3. Finish with
   - `queryClose(cursor)`

A page contains:

- column metadata
- row batch
- `done` flag
- optional warnings

### 6.2 Result materialization rule

The application must never load the entire result set into memory by default.

Allowed:
- keeping recent pages in memory for smooth scrolling
- holding export buffers in bounded chunks
- retaining prior successful result metadata for the current tab

Not allowed:
- converting an unbounded query result into an in-memory list before display
- exporting by first materializing the full result set in app memory

### 6.3 Page size

- Default page size is configurable in TOML
- Initial default target: `1000`
- UI may adapt page size later, but fixed-size paging is acceptable for MVP

### 6.4 Execution state machine

Each query tab must implement the following states:

- **idle**: no active execution
- **running**: query is open and pages may still arrive
- **cancelling**: user requested stop; no new user-initiated paging allowed
- **completed**: query finished successfully
- **failed**: query failed
- **cancelled**: query stopped before completion

State requirements:

- `idle -> running` on execute
- `running -> completed` when final page arrives and cursor closes
- `running -> failed` on execution or paging error
- `running -> cancelling` on user stop
- `cancelling -> cancelled` once cursor is closed or the run is abandoned safely
- `cancelling -> failed` if termination surfaces an actionable error
- A new execute action may start from `completed`, `failed`, or `cancelled`
- A new execute action from `cancelling` is not allowed until cleanup completes

### 6.5 Partial-result behavior

If cancellation occurs after one or more pages have been received:

- already received rows may remain visible
- the tab must clearly indicate that the result is partial/cancelled
- partial results must not be mislabeled as complete

### 6.6 Stale event handling

Pages, warnings, and errors from an older execution must be ignored once a newer
execution has started for the same tab. Each execution should have a unique run
identifier at the controller/state level.

### 6.7 Error model

Errors should map into a UI-safe structure containing:

- message
- engine code, if available
- SQL location, if available
- whether the error occurred during open, paging, cancellation, or close

The UI must allow copying error details.

---

## 7. Import specifications

### 7.1 Type-system rules

- Always map to DecentDB native types
- Wizard performs inference, but user may override
- When uncertain, prefer a safe textual representation unless a more specific
  mapping is clearly valid
- Mapping decisions should be visible in the summary step

### 7.2 Excel import

Capabilities:

- choose workbook
- choose sheet(s)
- header row on/off
- type inference with override
- preview sample rows
- import into target table(s)

Edge cases:

- empty columns
- mixed-type columns
- large sheets requiring streaming reads
- date/time columns requiring explicit mapping behavior

### 7.3 SQLite import

Capabilities:

- choose SQLite file
- list and select tables
- copy schema and data
- map SQLite affinities to DecentDB types

Edge cases:

- `STRICT` tables
- `WITHOUT ROWID` tables
- `BLOB` handling
- nullability inference

### 7.4 SQL dump import (MariaDB/MySQL style)

MVP-lite parsing scope:

- `CREATE TABLE`
- `INSERT INTO`
- common scalar types
- unsupported statements may be skipped with warnings

Wizard requirements:

- encoding detect/override
- preview parsed schema
- preview sample rows
- skipped statement count in summary

### 7.5 Import transaction and failure behavior

Imports should be transactional where practical.

Minimum behavior:

- a failed import must not leave the target table in an ambiguous half-finished
  state without surfacing that fact to the user
- summary must distinguish:
  - succeeded
  - partially succeeded with warnings
  - failed and rolled back
  - failed with manual cleanup required

### 7.6 Import jobs

Imports are background jobs with explicit state:

- queued
- running
- cancelling
- completed
- failed
- cancelled

---

## 8. Transform specifications

### 8.1 Rename columns

- UI for renaming before commit
- unique-name enforcement
- collision warnings
- resulting names shown in preview

### 8.2 Type overrides

- per-column type dropdown limited to DecentDB native types
- invalid coercions must be validated before commit where possible
- optional coercion-to-null behavior may be added, but if supported it must be
  surfaced in the summary with counts

### 8.3 Deferred transforms

Computed columns are not part of MVP and must not be treated as required
acceptance criteria for `v0.2` scope.

---

## 9. Autocomplete, snippets, and formatter

These remain in MVP scope but are lower implementation priority than the Phase 1
slice.

### 9.1 Schema-aware autocomplete

Sources:

- schema metadata cache
- full pinned-engine DecentDB keywords/functions/operator list

Context-aware behavior should support at least:

- after `FROM` -> tables/views
- after alias + `.` -> columns
- function suggestion contexts

Autocomplete coverage should track the pinned engine reference for SQL keywords,
DDL/DML verbs, joins, CTEs, scalar functions, aggregate functions, window
functions, table-valued functions, transaction keywords, and `EXPLAIN`
variants.

### 9.2 Snippets

- snippet store in TOML config or a separate TOML file
- include sensible defaults
- user-editable
- insertion may be via picker, shortcut, or token expansion

### 9.3 SQL formatter

- deterministic formatting
- format selection or whole document
- preserve comments and string literals
- formatter dependency must be Apache-compatible

---

## 10. Results grid specification

### 10.1 Behavior

- virtualized scrolling
- responsive selection
- copy support for:
  - cell
  - row(s)
  - selection as TSV/CSV to clipboard

Column resize and reorder are desirable but not mandatory for MVP unless later
promoted by issue or ADR.

### 10.2 Pagination UI

Show at minimum:

- rows fetched
- whether completion is known
- current page size
- running/cancelling/completed/cancelled status

Loading more may be automatic on scroll threshold, manual, or hybrid.

### 10.3 Empty, loading, and error states

The grid/results pane must support:

- loading state without visual jank
- zero-row state
- error panel with message and details
- partial-result state after cancellation

---

## 11. Export specifications

### 11.1 MVP export

CSV is the only required MVP export format.

CSV options:

- delimiter
- quote behavior
- include headers

### 11.2 Deferred exports

The following are explicitly **Next** and not required for MVP:

- JSON
- Parquet
- Excel

If implemented early, they must be treated as optional stretch work, not as MVP
acceptance blockers.

### 11.3 Export execution model

Exports must consume query pages/cursor data in the background and must not
require full preloading of the entire result set into memory.

Export jobs must surface:

- progress when possible
- warnings
- completion state
- destination path
- actionable failure details

---

## 12. Configuration and secrets

### 12.1 TOML config

Config location must follow OS-standard application config directories.

Config should include:

- recent files
- default page size
- max interactive rows guard
- editor settings
- snippets
- export defaults

### 12.2 Workspace state vs user config

The implementation must distinguish between:

- **user config**: global preferences and defaults
- **workspace state**: open-file-specific UI state

They may be stored separately even if both use TOML.

### 12.3 Secrets storage

For any future external connection support:

- macOS: Keychain
- Windows: Credential Manager
- Linux: libsecret/gnome-keyring where available

Any fallback strategy requires an ADR before implementation.

### 12.4 Config versioning

Config format must include a schema version or migration mechanism before the
format is considered stable.

The current TOML config format includes `config_version`, and workspace-state
storage includes an independent schema version for file-specific UI state.

---

## 13. Testing and quality

### 13.1 Minimum automated tests

Unit tests:

- config parsing
- query state transitions
- paging controller logic
- import type inference
- export option validation

Integration tests:

- open DecentDB
- execute `SELECT 1`
- page through a multi-page result
- cancel a query
- load schema metadata

### 13.1.1 Phase 1 representative engine smoke-test matrix

The Phase 1 smoke suite should validate a representative slice of the pinned
DecentDB `v1.6.x` SQL surface. It is not a full compatibility suite, but it
must cover each major engine category that the app intends to preserve.

| Area | Representative operation | Minimum assertion |
|---|---|---|
| Parameters + paging | Create a table, insert/query with `$1`/`$2`, fetch via paged cursor | Parameter binding works and paged retrieval returns expected rows |
| Views + indexes | `CREATE VIEW`, `CREATE INDEX`, query the view, inspect schema metadata | SQL executes successfully and adapter metadata does not regress |
| Recursive CTEs | `WITH RECURSIVE` sequence or hierarchy query | Recursive result set is correct and cancellable through the normal query path |
| Constraints + generated columns | `CHECK`, `UNIQUE`, `DEFAULT`, `GENERATED ALWAYS AS ... STORED` | Valid rows succeed, invalid rows fail, generated values persist correctly |
| Window + aggregate functions | `ROW_NUMBER() OVER (...)` plus grouped aggregates | Result ordering and aggregate values match expectations |
| Table-valued JSON functions | `json_each(...)` and `json_tree(...)` in `FROM` | Returned row shape and representative values match expectations |
| Transactions + savepoints | `BEGIN`, `SAVEPOINT`, `ROLLBACK TO SAVEPOINT`, `COMMIT` | Only committed rows remain visible after rollback paths |
| Triggers + temp objects | `CREATE TRIGGER`, `CREATE TEMP TABLE/VIEW`, run trigger-producing DML | Trigger side effects occur and temp objects remain connection-scoped |
| Planner introspection | `EXPLAIN` and `EXPLAIN ANALYZE` on representative queries | Non-empty plan output is returned without UI hangs |
| Statistics collection | `ANALYZE table_name` outside explicit transaction | Command succeeds and leaves the database usable for subsequent queries |

UI/integration tests:

- open workspace
- run query and display results
- export CSV
- drag-and-drop launches import flow once implemented

### 13.2 Performance-sensitive checks

The project should maintain reproducible scenarios for:

- opening a DB with many tables
- scrolling a large paged result set
- exporting large result sets without UI stalls

Exact performance gates may mature over time, but regressions in responsiveness
are release-blocking.

### 13.3 Validation commands

When the app scaffold exists, expected validation commands are:

- `flutter analyze`
- `flutter test`
- `flutter test integration_test`

CI should run these as soon as the project becomes runnable.

---

## 14. Packaging and distribution

- Bundle required DecentDB native libraries with desktop builds
- Ensure deterministic library discovery at app startup
- Runtime discovery order is:
  1. `DECENTDB_NATIVE_LIB`
  2. the platform-specific bundled desktop app location
  3. a sibling `../decentdb/build/` checkout for development
- The desktop packaging flow may stage the DecentDB native library into the
  generated bundle through a repeatable helper script, but packaged startup
  must not depend on `DECENTDB_NATIVE_LIB`
- Keep packaging aligned with the upstream binding strategy from ADR-0001
- Signing/notarization and final installer formats may be staged after MVP, but
  packaging must not require manual developer-only steps for normal app startup

---

## 15. ADR and document consistency rules

To reduce scope drift:

1. `design/SPEC.md` is the implementation scope source of truth
2. `design/PRD.md` describes product intent and user value
3. Accepted ADRs govern architectural decisions
4. If an accepted ADR changes implementation expectations, the SPEC must be
   updated in the same change or immediately afterward
5. If scope changes materially, update both PRD and SPEC

---

## 16. Acceptance criteria

### 16.1 Phase 1 acceptance

A contributor can:

1. launch a runnable Flutter desktop app
2. open or create a DecentDB file
3. see tables and columns in the schema browser
4. run representative pinned-engine SQL statements in a single tab
5. receive paged results without full materialization
6. cancel a running query and recover the UI
7. export visible query results to CSV
8. pass the Phase 1 representative engine smoke-test matrix
9. run analyzer and tests successfully

### 16.2 MVP acceptance

A user can:

1. drag and drop a DecentDB file and open it
2. drag and drop an Excel, SQLite, or supported `.sql` dump file and enter the
   import wizard
3. import Excel with sheet selection, headers option, and type overrides
4. import SQLite with table selection
5. import at least one MariaDB/MySQL-style `.sql` dump successfully
6. rename columns and adjust target types before import
7. inspect supported schema objects in the schema browser
8. use multi-tab query editing with paired results panes
9. run and cancel queries in a responsive UI
10. use schema-aware autocomplete, snippets, and formatting
11. export query results to CSV
12. complete the above without noticeable UI hangs in normal desktop use
