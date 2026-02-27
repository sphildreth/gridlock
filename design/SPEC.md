# Gridlock — Product Specification (SPEC) v0.1

**Product:** Gridlock  
**Type:** Cross‑platform desktop SQL-style app (Flutter)  
**License:** Apache 2.0  
**Primary purpose:** Drag‑and‑drop import into **DecentDB**, then inspect schema, run fast queries, and export shaped results.  
**PRD reference:** Gridlock_PRD_v0_4.md

---

## 0. Terminology

- **DecentDB**: The target embedded database format used by Gridlock workspaces.
- **Import source**: A file or external database used only as input to create/load data into DecentDB.
- **Wizard**: The guided flow launched on drag‑and‑drop of a non‑DecentDB file to configure import.
- **Workspace**: An open DecentDB file plus UI state (tabs, saved queries, etc.).
- **Object browser / schema browser**: UI for catalog discovery (tables, views, indexes, triggers, constraints, etc.).

---

## 1. Scope

### 1.1 MVP (must-haves)
**Entry + workflow**
- Drag‑and‑drop file onto app window:
  - If DecentDB → open immediately.
  - Else → launch Import Wizard based on file type.
- Single-file drop for MVP; if multiple files dropped, import the first and show a warning dialog.

**Imports**
- Excel (.xls/.xlsx)
- SQLite (.db/.sqlite/.sqlite3)
- MariaDB/MySQL-style `.sql` dump (MVP‑lite; common CREATE TABLE + INSERT patterns)
- Import transforms before commit:
  - Rename columns
  - Basic computed columns
  - Type overrides (always DecentDB native types)

**Schema browser**
- Must reflect **everything DecentDB supports** (per DecentDB SQL feature matrix).
- Metadata sourced from DecentDB introspection APIs/queries.

**SQL experience**
- Multi-tab editor with per-tab results panes (query + results paired)
- Keyboard navigation between tabs and focus between editor/results
- Schema-aware autocomplete
- Snippets (user-editable)
- SQL formatter (deterministic style)
- Run/stop query (best-effort cancellation)

**Results + export**
- Virtualized/paginated results grid
- Export query results:
  - CSV, JSON, Parquet, Excel

**Config**
- TOML configuration file (local)

**Engineering governance**
- ADRs from day one using provided template and README policy

### 1.2 Out of scope for SPEC v0.1
- Postgres custom-format backup import (explicitly “Next”, unless plain `.sql`)
- Multi-workspace (multiple DecentDB files open simultaneously)
- Collaboration features
- Full migration tooling

---

## 2. Product architecture (high level)

Gridlock is composed of:
1. **UI shell (Flutter)** — windowing, navigation, tabs, dialogs/wizards
2. **DecentDB Engine Binding (Dart FFI)** — open/exec/query/stream/introspect/cancel
3. **Import pipeline** — parsers/connectors + transform planner + bulk load into DecentDB
4. **Export pipeline** — grid data source → exporters (CSV/JSON/Parquet/Excel)
5. **Workspace state** — connections, tabs, results caches, recent files
6. **Config + secrets** — TOML config + OS secure credential storage
7. **ADR process** — repo governance, templates, enforcement checks

---

## 3. Repository layout (proposed)

```
/apps/gridlock/                    # Flutter desktop app
  /lib/
    /app/                          # app shell, routing, theming
    /features/
      /workspace/
      /import_wizard/
      /schema_browser/
      /sql_editor/
      /results_grid/
      /export/
      /settings/
    /shared/                       # shared widgets, utils, abstractions
  /native/                         # native bindings + shim(s)
    /decentdb/                     # DecentDB dynamic libs per platform OR build scripts
    /shim/                         # optional C shim project (if needed)
/design/adr/
  README.md
  0000-template.md
  0001-...
/docs/
  SPEC.md
  PRD.md
```

> ADRs live in `/design/adr` and are required for significant decisions (binding strategy, streaming model, import type mapping, etc.).

---

## 4. Core UX flows (detailed)

### 4.1 Drag‑and‑drop handler (MVP)
**Trigger:** user drops a file onto the main window.

**Detection rules (MVP):**
- Extension-based detection (users can rename for MVP):
  - DecentDB: `.decentdb` (or agreed canonical extension)
  - Excel: `.xls`, `.xlsx`
  - SQLite: `.db`, `.sqlite`, `.sqlite3`
  - SQL dump: `.sql`
- If unrecognized extension:
  - Show wizard “Unknown file type” with guidance + supported types list.

**Behavior:**
- If DecentDB:
  - Open workspace and load schema tree immediately
- Else:
  - Launch import wizard with file preselected

**Multi-drop:**
- If N>1 files dropped:
  - Take first, show dialog warning: “MVP supports importing one file at a time.”

### 4.2 Import wizard common structure
Wizard is a multi-step flow with a consistent scaffold:
1. **Source selection** (pre-filled from drop)
2. **Target selection**
   - Create new DecentDB file OR choose existing DecentDB file
3. **Preview**
   - Show inferred schema + sample rows
4. **Transforms**
   - Rename columns
   - Add computed columns (expressions)
   - Adjust types (DecentDB native types only)
5. **Import execution**
   - progress + cancel (if feasible)
6. **Summary**
   - Rows imported, errors/warnings
   - “Open table” / “Run a query” call-to-action

### 4.3 SQL editor + results tabs
**Requirements:**
- Each tab owns:
  - SQL text buffer
  - execution status
  - result data source + metadata
  - error output panel
- Keyboard:
  - Ctrl/Cmd+Enter: execute
  - Ctrl/Cmd+Tab: next tab
  - Ctrl/Cmd+Shift+Tab: previous tab
  - Tab/Shift+Tab: move focus between editor and results pane controls
- Per-tab history (optional MVP): keep last N executed queries for that tab

### 4.4 Schema browser
- Tree nodes include all object kinds DecentDB supports (as exposed by feature matrix).
- Selecting an object shows details panel:
  - table/view definition
  - columns + types + constraints
  - indexes
  - triggers (if applicable)
- Search box filters nodes instantly (in-memory filter of the currently loaded metadata model).

### 4.5 Export flow
- Export button on results pane
- Choose format: CSV / JSON / Parquet / Excel
- Format-specific options panel
- Save dialog
- Export progress (for large data sets)

---

## 5. DecentDB integration (Dart FFI binding)

### 5.1 Principle
Gridlock’s core functionality depends on best-in-class compatibility and performance with DecentDB. The primary approach is **Dart FFI** to native libraries.

### 5.2 Binding strategy options (ADR required)
- **Option A: Native C ABI from DecentDB**
  - Best if DecentDB provides an official stable C interface.
- **Option B: Thin C shim around Nim API**
  - If Nim API is canonical, expose required calls through a stable C surface.
- **Option C: Platform channel**
  - Avoid unless FFI is blocked; generally worse performance/complexity for heavy DB calls.

> Create ADR for chosen approach (likely A or B).

### 5.3 Required API surface (minimum)
Binding must support:
- Open/close DB (file path, flags)
- Execute SQL (non-query)
- Query SQL with **streaming/pagination**
- Schema introspection queries/calls (catalog listing)
- Cancellation (best-effort)
- Error reporting (SQL error details)

### 5.4 Streaming + pagination contract
- Never load full result set into memory by default.
- Provide an iterator/cursor style API:
  - fetchNextPage(pageSize) → rows + column metadata
  - allow pageSize adjustment
- Support “max rows” default config with override per query.

### 5.5 Threading model
- All heavy work off the UI thread.
- Dart isolates or native background threads must be used for:
  - import parsing
  - query execution & paging
  - export

---

## 6. Import specifications

### 6.1 Type system rules
- Always map to **DecentDB native types**.
- Wizard uses smart inference, but user can override.
- When uncertain, prefer TEXT unless a safer default exists.
- Persist mapping decisions in wizard summary for reproducibility.

### 6.2 Excel import
**Capabilities:**
- Choose workbook + sheet
- Header row on/off
- Type inference
- Preview sample rows
- Import into table (new or replace strategy defined by UI choices)

**Edge cases:**
- Empty columns
- Mixed type columns
- Date/time columns (define mapping; ADR may be needed)
- Very large sheets (stream reading)

### 6.3 SQLite import
**Capabilities:**
- Choose SQLite file
- List tables and select subset
- Copy schema + data
- Map SQLite affinities to DecentDB types

**Edge cases:**
- SQLite STRICT tables
- WITHOUT ROWID tables
- BLOB handling
- NULLability inference

### 6.4 SQL dump import (MariaDB/MySQL style)
**MVP-lite parsing scope:**
- CREATE TABLE statements
- INSERT INTO statements
- Basic data types (int, bigint, varchar/text, float/double, blob, bool, date/time variants)
- Ignore/skip unsupported statements with warnings

**Wizard requirements:**
- Encoding detect/override
- Preview parsed schema + sample rows
- Import summary with skipped statement count

---

## 7. Transform specifications

### 7.1 Rename columns
- UI for renaming before commit
- Enforce unique names
- Show collision warnings
- Apply rename mapping to computed column expressions

### 7.2 Computed columns (basic)
- Allow adding a new column defined by expression over existing columns
- Limit scope for MVP:
  - arithmetic
  - string concat/substr
  - simple CASE
- Validate expression against inferred schema before import commit

### 7.3 Type overrides
- Per-column type dropdown limited to DecentDB native types
- Validation rules (e.g., cannot coerce non-numeric into INT64 without fallback)
- Option to “coerce invalid to NULL” with counts in summary

---

## 8. Autocomplete, snippets, formatter

### 8.1 Schema-aware autocomplete
- Sources:
  - schema browser metadata model (cached)
  - DecentDB keywords/functions list (static + versioned)
- Context-aware:
  - after FROM → tables/views
  - after table alias + dot → columns
  - function calls → function names

### 8.2 Snippets
- Snippet store in TOML config (or separate snippets TOML)
- Include defaults (select * from, join template, export-shaped patterns)
- Insert via:
  - snippet picker (Ctrl/Cmd+Shift+P style palette) OR
  - trigger tokens (e.g., `sel` → expands)

### 8.3 SQL formatter
- Deterministic formatting style with no “random” layout
- Format selection or whole document
- Preserve string literals and comments
- Formatter implementation must be Apache-compatible licensing

---

## 9. Results grid specification

### 9.1 Behavior
- Virtualized scrolling
- Column resize + reorder
- Copy:
  - cell
  - row(s)
  - selection as TSV/CSV to clipboard

### 9.2 Pagination UI
- Show:
  - rows fetched / total unknown or known
  - current page size
- Allow user to “Load more” or auto-fetch when scrolling

### 9.3 Error/empty states
- SQL error panel with message + location (if provided)
- “0 rows returned” state without flashing/jank

---

## 10. Export specifications

### 10.1 CSV
- delimiter, quotes, header on/off

### 10.2 JSON
- array of objects
- pretty vs compact

### 10.3 Parquet
- choose compression (optional)
- map DecentDB types to Parquet logical types (ADR likely)

### 10.4 Excel
- single sheet export
- header row required
- basic formatting (optional; keep minimal)

---

## 11. Configuration & secrets

### 11.1 TOML config
- Location: OS standard app config dir
- Contents:
  - recent files
  - default page size / max rows
  - editor settings (font, tab size)
  - snippet definitions
  - export defaults

### 11.2 Secrets storage
- Use OS secure storage best practice:
  - macOS Keychain
  - Windows Credential Manager
  - Linux libsecret/gnome-keyring
- If unavailable, store encrypted with a user-provided passphrase (fallback; ADR required)

---

## 12. Testing & quality

### 12.1 Automated tests (minimum)
- Unit tests:
  - import parsers
  - type inference
  - computed column evaluator (if separate)
  - SQL formatter (golden tests)
- Integration tests:
  - binding open/exec/query/paging
  - import of sample Excel/SQLite/SQL dump fixtures
- UI tests (Flutter integration tests):
  - drag-drop triggers wizard
  - run query shows results
  - export produces file

### 12.2 Performance tests
- Benchmark scenarios:
  - open DB with N tables
  - run query returning 100k rows with paging
  - export 1M rows to CSV/Parquet
- Define “non-annoying” thresholds as PRD targets and assert regressions.

---

## 13. Packaging & distribution (desktop)

- Bundle native DecentDB library/shim per platform
- Ensure dynamic library discovery works in packaged app
- Sign/notarize as required (macOS)
- Provide portable build for Linux (AppImage) and Windows installer (MSIX/EXE) — can be staged post-MVP

---

## 14. ADR policy (must-have)

- ADRs live at `/design/adr/` and use `0000-template.md`.
- Follow lifecycle defined in ADR README:
  - Accepted/superseded/deprecated, etc.
- CI/PR checks (recommended):
  - “ADR required?” checklist in PR template
  - Lint for ADR filename format and required sections

---

## 15. Open implementation decisions (require ADRs early)

1. DecentDB binding strategy (C ABI vs C shim around Nim)
2. Cursor/streaming model for results paging
3. Excel parsing library choice (streaming support + license)
4. SQL formatter/autocomplete engine choice (license + correctness)
5. Parquet/Excel export libraries (license + fidelity)
6. Computed columns evaluation: pushdown to DecentDB vs pre-import compute

---

## 16. Acceptance criteria for SPEC v0.1

- SPEC aligns with PRD must-haves and enumerates implementable requirements for:
  - Drag-drop wizard entry
  - Imports + transforms
  - Schema browser (DecentDB-complete)
  - Editor: autocomplete/snippets/formatter
  - Results paging
  - Export formats
  - TOML config + secrets storage
  - ADR governance
