# Gridlock — Product Requirements Document (PRD) v0.1

**Product:** Gridlock  
**Type:** Cross‑platform desktop SQL-style app (Flutter)  
**License:** Apache 2.0  
**Primary purpose:** Help power users **import data from common sources into DecentDB**, then **inspect schema** and **run fast SELECT-style queries** to shape/export data.

**Critical initial task:** Users can **drag-and-drop a file** (Excel, SQLite, DB dumps/backups, etc.) onto Gridlock.
- If it’s a **DecentDB** file, Gridlock opens it immediately.
- If it’s **not** a DecentDB file, Gridlock launches an **Import Wizard** tailored to the file type.

---

## 1. Problem statement

Power users often have data trapped in **Excel files**, **existing SQLite files**, or **other databases**. Moving that data into **DecentDB** is painful: tooling is fragmented, import paths are inconsistent, and even after import, users still need a fast way to **inspect** and **query** the data to export it in the shape they need.

Gridlock solves this by being a **DecentDB-first import + query workbench**:
- Import from popular sources into a **DecentDB file**
- Quickly inspect schema and data
- Run queries (mostly SELECT) and export results

---

## 2. Goals and non-goals

### Goals (what we will deliver)
1. **Drag-and-drop entry point (primary UX)**
   - Drag-and-drop a file onto the app window.
   - Auto-detect type: DecentDB vs import source.
   - Open DecentDB immediately, or launch Import Wizard for non-DecentDB.
2. **DecentDB-first workspace**
   - Open/create a DecentDB database file (local file).
2. **Import into DecentDB**
   - Import from: Excel, SQLite, and “other databases” (via connectors) into DecentDB.
4. **Fast schema inspection**
   - Browse tables/views, columns, indexes (as supported by DecentDB).
5. **Fast query workflow**
   - Write and run queries quickly (optimized for SELECT).
   - View results in a performant grid with copy/export.
6. **Export shaped results**
   - Export query results to common formats (CSV initially; others later).
7. **Safe + non-annoying performance**
   - Responsiveness matters: avoid UI stalls, handle large results gracefully.

### Non-goals (explicitly out of scope for MVP)
- Managing external databases as “first-class” targets (Gridlock is **not** a DBeaver competitor for admin/ops).
- Collaborative editing, shared connections, multi-user features.
- Full migration tooling (schema diff, migrations framework).
- Advanced **script orchestration** engine (e.g., run a multi-step SQL script with variables, conditional branches, loops, file IO, and pipeline-style dependencies).
  - **Note:** This is **not** the same as having multiple query tabs. Query tabs with paired results are **in scope** for MVP.

---

## 3. Target users

### Primary persona: Power user / data wrangler
- Comfortable with SQL.
- Needs to bring in data from Excel/SQLite/other sources into a local database file for analysis, reshaping, and export.
- Values speed, keyboard workflows, and predictable behavior.

### Secondary persona: Developer / builder
- Uses DecentDB files as portable data artifacts.
- Wants a quick tool to inspect and query without heavy IDEs.

---

## 4. Top jobs to be done (JTBD)

1. **Import data into DecentDB**
   - “When I receive an Excel/SQLite/DB dump, I want to import it into a DecentDB file quickly so I can query it.”
2. **Inspect schema quickly**
   - “When I open a DecentDB file, I want to see what tables/columns exist immediately so I can write queries.”
3. **Run queries quickly (mostly SELECT)**
   - “When I’m iterating on a SELECT query, I want to run it repeatedly and see results instantly without friction.”
4. **Export shaped results**
   - “When I get the data in the right shape via SQL, I want to export it easily for sharing/reporting.”

---

## 5. Success metrics

**Primary success:** Adoption + day-to-day usability.  
Indicators:
- Users can complete an import → query → export workflow without reading docs.
- App feels “not annoying”: fast startup, fast query iterations, minimal UI jank.

Suggested measurable targets (initial, refine later):
- App cold start to usable workspace: **< 3 seconds** on a typical dev laptop.
- Schema tree population after opening DecentDB: **< 1 second** for typical DB sizes.
- Query execution UI feedback: **immediate** (shows running state instantly; results stream/paginate).
- Grid scroll + selection stays responsive up to **100k rows** (with pagination/virtualization).

---

## 6. User journeys (MVP)

### Journey 0: Drag-and-drop → Wizard or Open
1. User drags a file onto Gridlock (or uses File → Open/Import).
2. Gridlock detects:
   - **DecentDB file** → open in workspace.
   - **Import source** → launch Import Wizard.
3. Wizard gathers required options, shows a preview, and runs the import into a chosen/new DecentDB file.
4. On completion, Gridlock focuses the imported table(s) and offers “Run a query” and “Export” next steps.

### Journey A: Excel → DecentDB → Query → Export
1. Create/open DecentDB file
2. Import Excel (sheet selection, headers, type inference)
3. Inspect imported table schema
4. Write SELECT query (with syntax highlighting)
5. Run query, view results
6. Export results (CSV)

### Journey B: SQLite file → DecentDB
1. Open DecentDB file
2. Import SQLite file (select tables)
3. Verify schema and row counts
4. Run SELECT queries and export

### Journey C: External database → DecentDB (connector)
1. Configure external connection (read-only intent)
2. Select schema/tables to import
3. Import into DecentDB (mapping)
4. Query/export locally

---

## 7. Functional requirements

### 7.1 Workspace & files
- Open/create DecentDB database file.
- Recent files list.
- App configuration stored as **TOML** (preferred). If TOML proves unusually difficult in Flutter/Dart, fall back to a minimal, stable alternative while keeping TOML as the target.
- “Safe mode” prompts for destructive operations (if any exist in MVP).

### 7.2 Connections (external sources)
**MVP intent:** External sources exist only to **import into DecentDB**.
- Connection profiles stored locally (encrypted at rest if credentials are stored).
- Test connection.
- Read-only usage by default (no “run query on external DB” in MVP).

### 7.3 Import

#### Drag-and-drop import entry (MVP)
- Import Wizard includes **transform steps** before commit:
  - Rename columns
  - Basic computed columns (expressions) when feasible
  - Type adjustments (always DecentDB native types; user can override)
- App accepts drag-and-drop of local files onto the main window.
- On drop, Gridlock performs **type detection** (by extension + lightweight signature checks where safe):
  - DecentDB database file → open directly.
  - Excel (.xls/.xlsx) → Excel import wizard.
  - SQLite (.db/.sqlite/.sqlite3) → SQLite import wizard.
  - SQL dump files (.sql) → “SQL Dump import wizard” (initially MariaDB/MySQL-style; extensible).
  - Postgres backup (.bak/.backup/.dump/.tar/.custom) → “Postgres backup import wizard” (may be MVP-lite).
- If the dropped file type is recognized but **not yet supported**, Gridlock still opens the wizard and clearly shows:
  - “Not supported in this version”
  - What *is* supported today
  - A link/button to track the feature (issue/roadmap) and suggested workaround.

#### Excel import (MVP)

- Select workbook file and sheet(s).
- Options:
  - First row headers on/off
  - Column type inference with override
  - Table name mapping
- Progress indicator; cancel if possible.
- Import summary (rows imported, errors).

#### SQLite import (MVP)
- Select SQLite file.
- Choose tables to import.
- Preserve table/column names where possible.
- Handle common SQLite types → DecentDB baseline types mapping.

#### SQL dump import (MVP-lite)
- Accept `.sql` dump files (initially **MariaDB/MySQL-style** dumps).
- Wizard steps:
  - Encoding detection/override
  - Target schema/table name mapping
  - Preview parsed table definitions + a sample of rows
  - Import execution with progress + error summary
- MVP-lite acceptance can be limited to common patterns (CREATE TABLE + INSERT statements).

#### Postgres backup import (MVP-lite / Next)
- Accept common Postgres backup formats (`.backup`, `.dump`, `.tar`, custom formats) and/or `.sql` plain dumps.
- If custom-format backups require external tooling, wizard must clearly explain requirements.

#### “Other DBs” import (post-MVP)
- Connector strategy that can grow (Postgres, MySQL/MariaDB, SQL Server, etc.).
- External sources are **import-only** targets (read-only intent by default).

### 7.4 Schema browser
- Tree view: tables, views (if supported), columns.
- Click table:
  - Preview top N rows
  - Show column list + types
- Search/filter schema items.

### 7.5 SQL editor
- Multi-tab query editor.
- Syntax highlighting.
- Run/stop query.
- Basic keyboard shortcuts:
  - Run (Ctrl/Cmd+Enter)
  - New tab (Ctrl/Cmd+T)
  - Find (Ctrl/Cmd+F)


### 7.6 Results grid
- Virtualized/paginated grid (no loading millions of rows into memory).
- Copy cell/row selection.
- Export results (CSV MVP).
- Show execution time, rows returned, and warnings.

### 7.7 Export
- Export query results to CSV (MVP).
- Export options:
  - delimiter, quote style
  - include headers
- Destination: save file dialog.

---

## 8. Non-functional requirements

### Performance
- No UI freezes during import or long queries.
- Results grid must remain responsive under large results via pagination/virtualization.
- Query cancellation must be attempted (best-effort if engine supports).

### Reliability
- Import operations are transactional where possible:
  - Either the imported table is complete or it rolls back/cleans up.
- Crash-safe: database file is not corrupted by partial operations.

### Cross-platform
- Windows, macOS, Linux (desktop).
- Consistent keyboard shortcuts per platform.

### Security & privacy
- Local-first; no data leaves the machine by default.
- Credentials stored securely (OS keychain/secure storage where available).
- Telemetry: **off by default** (decide policy explicitly).

### Licensing
- All dependencies must be compatible with Apache 2.0 distribution goals.
- Track third-party licenses.

---

## 8.1 DecentDB engine integration (binding strategy)

Gridlock must speak to DecentDB with **best compatibility and performance**. Flutter does not provide a built-in database “driver” layer; database access is done via packages, platform channels, or **Dart FFI** to native libraries.

**MVP approach:** Provide a **Dart/Flutter binding** to DecentDB using Dart FFI.
- Prefer a stable, C-compatible surface (either an existing C ABI from DecentDB, or a thin C shim around the Nim API).
- Generate Dart bindings with `ffigen` and ship platform-specific dynamic libraries with the desktop builds.
- Keep the binding small and focused on Gridlock needs: open/close DB, exec SQL, streaming/pagination, cancellation (if supported), and schema introspection.

**Why:** The Nim API is the canonical embedded API today, but Flutter/Dart needs a native bridge to call it efficiently.

## 8.2 Engineering governance: ADRs (must-have)

Gridlock will maintain **Architecture Decision Records (ADRs)** from day one. Any decision with meaningful trade-offs, long-term impact, or compatibility implications must be captured as an ADR.

### ADR requirements (MVP)
- Repository contains `design/adr/` with:
  - `README.md` describing when/how to create ADRs and lifecycle rules
  - `0000-template.md` used for all ADRs
- Every eligible PR includes an ADR (or explicitly states why none is needed).
- ADRs are numbered sequentially (`NNNN-short-title.md`) and kept concise.

### ADR template
Use the standard sections:
- Decision
- Rationale
- Alternatives considered
- Trade-offs
- References

### Examples of decisions that require ADRs
- DecentDB binding strategy (FFI vs platform channels; C shim vs direct)
- File format compatibility assumptions and versioning
- Import type inference + override rules
- Result pagination/streaming approach
- Export format libraries and their licensing implications
- Secure credential storage approach per OS

## 9. Product scope: MVP vs Next

### MVP (v1)
- Drag-and-drop file open/import + Import Wizard
- DecentDB file open/create
- Excel import
- SQLite import
- SQL dump import (MVP-lite, MariaDB/MySQL-style `.sql`)
- Import transforms (rename columns, basic computed columns, type overrides)
- Schema browser covering the full DecentDB surface
- SQL editor (tabs + per-tab results, run/stop, schema-aware autocomplete, snippets, formatter)
- Results grid (virtualized)
- Export formats: CSV, JSON, Parquet, Excel
- (Requested) ERD designer, query plans, and stored procedure workflow support (scope to be defined)

### Next (v1.1+)
- One additional DB connector (choose based on your audience)
- Schema-aware autocomplete
- More export formats (JSON, Parquet, Excel)
- Import transform options (rename columns, basic computed columns)
- Saved queries / workspace projects

---

## 10. Decisions locked for MVP (based on current direction)

1. External sources prioritized: **SQLite + DecentDB** first; Excel remains core.
2. DecentDB feature surface: Schema browser and SQL tooling must align with the **DecentDB SQL Feature Matrix**.
3. Type system: Always use **DecentDB native types**; default inference should be smart and the wizard must allow overrides.
4. Secret storage: Use OS best-practice secure storage (Keychain / Credential Manager / libsecret), with a fallback if required.
5. Multiple DecentDB files open at once: **Not required for MVP**.
6. File type detection: **Extension-based detection** is acceptable for MVP; users can rename files if needed.
7. Multi-drop behavior: **Single file** for MVP; if multiple files are dropped, import the first and show a warning dialog.

## 10. Risks & open questions

### Risks
- **Connector/driver availability** in Flutter/Dart for “other databases” may be uneven.
- Handling huge datasets: needs careful virtualization and streaming.
- Type mapping from Excel/SQLite/others → DecentDB baseline types.

### Open questions (to answer before we lock MVP)
1. Which **one** “other database” connector is most valuable first (if any for MVP)?
2. DecentDB capabilities to assume in v1:
   - transactions? streaming results? cancellation? views? indexes metadata?
3. Import mapping rules:
   - How strict is type inference? When do we fall back to TEXT?
4. How should we store connection secrets on each OS?
5. Do we support multiple DecentDB files open at once in MVP?
6. What are the exact **file-type detection** rules (extensions vs signatures) and how do we avoid false positives?
7. Should drag-and-drop support dropping **multiple files** at once (batch import) in MVP?

---

## 11. Acceptance criteria (MVP “definition of done”)

A user can:
1. **Drag-and-drop** a file onto Gridlock and:
   - If it’s a DecentDB file, it opens.
   - If it’s not a DecentDB file, an **Import Wizard** appears.
2. Create a new DecentDB file (from the wizard or File → New).
3. Import an Excel sheet into a new table with inferred types.
4. Import a SQLite database and select tables to import.
5. (MVP-lite) Drop a MariaDB/MySQL-style `.sql` dump and import at least one table successfully.
6. Use the import wizard to **rename columns**, adjust types, and add a simple computed column before importing.
7. See the imported tables and columns (and other supported objects) in a schema tree.
8. In the SQL editor: get **schema-aware autocomplete**, insert a snippet, and format SQL.
9. Run a SELECT query and view results in a responsive grid.
10. Export the query results to CSV and at least one additional format (JSON/Parquet/Excel).
11. Perform all of the above without noticeable UI hangs.

Engineering/process:
- Repo includes ADR folder + template + README, and at least **one accepted ADR** exists covering a major early decision (e.g., DecentDB Flutter binding strategy).

---

## 12. Notes for the upcoming TECH_DESIGN (not in PRD scope)
- Import pipeline architecture
- Connector abstraction strategy
- Result streaming/pagination approach
- Grid implementation constraints
- Secure storage selection per platform
