# Decent Bench — Product Requirements Document (PRD) v0.2

**Product:** Decent Bench  
**Type:** Cross-platform desktop SQL-style app (Flutter)  
**License:** Apache 2.0  
**Primary purpose:** Help power users **import data from common sources into
DecentDB**, then **inspect schema** and **run fast SELECT-style queries** to
shape and export data.

**Critical initial task:** Users can **drag and drop a file** (Excel, SQLite,
DecentDB, or supported SQL dump) onto Decent Bench.
- If it is a **DecentDB** file, Decent Bench opens it immediately.
- If it is a supported **import source**, Decent Bench launches an
  **Import Wizard** tailored to the file type.
- If it is a recognized but unsupported file type, Decent Bench shows a clear
  "not supported in this version" path and suggested workaround.

---

## 1. Problem statement

Power users often have data trapped in **Excel files**, **SQLite databases**,
or **database dump files**. Moving that data into **DecentDB** is painful:
tooling is fragmented, import paths are inconsistent, and even after import,
users still need a fast way to **inspect** and **query** the data to export it
in the shape they need.

Decent Bench solves this by being a **DecentDB-first import + query workbench**:
- Import from supported sources into a **DecentDB file**
- Quickly inspect schema and data
- Run queries, optimized for **SELECT-style workflows**
- Export shaped results

---

## 2. Product framing

### 2.1 Product promise
Decent Bench is a **local-first desktop workbench for DecentDB**. It is not a
general-purpose database administration tool. Its core workflow is:

1. Open or create a DecentDB file
2. Import data into it from supported sources
3. Inspect schema quickly
4. Run queries with responsive results
5. Export the shaped output

### 2.2 Design principles
1. **DecentDB-first**
   - The primary workspace is always a local DecentDB file.
2. **Fast feedback**
   - Opening a DB, loading schema, running a query, and viewing early rows
     should all feel immediate.
3. **No large default materialization**
   - Results should page/stream by default rather than loading fully into
     memory.
4. **Local-first and privacy-first**
   - Data stays on the user’s machine by default.
5. **Scope discipline**
   - MVP prioritizes a reliable import → query → export loop over breadth.

---

## 3. Goals and non-goals

### 3.1 Goals (MVP)
1. **Drag-and-drop entry point**
   - Drag and drop a file onto the app window.
   - Detect whether it is a DecentDB file or a supported import source.
   - Open DecentDB files directly.
   - Launch Import Wizard for supported non-DecentDB files.

2. **DecentDB workspace**
   - Open an existing DecentDB database file.
   - Create a new DecentDB database file.
   - Maintain a recent-files list.

3. **Import into DecentDB**
   - Support import from:
     - Excel (`.xls`, `.xlsx`)
     - SQLite (`.db`, `.sqlite`, `.sqlite3`)
     - MariaDB/MySQL-style `.sql` dumps (**MVP-lite**)
   - Support import-time transforms:
     - Rename columns
     - Type overrides
     - Basic computed columns, only if they remain implementable without
       destabilizing MVP scope

4. **Fast schema inspection**
   - Browse DecentDB objects required for core query workflows in the pinned
     DecentDB version.
   - Prioritize tables, views, columns, and indexes first.

5. **Fast query workflow**
   - Multi-tab SQL editor
   - Run and stop query
   - Per-tab results pane
   - Responsive results backed by paging/streaming

6. **Export shaped results**
   - Export query results to **CSV** in MVP.

7. **Safe and non-annoying performance**
   - Avoid UI stalls.
   - Keep long-running work off the UI thread.
   - Handle large result sets via paging/virtualization.

### 3.2 Next / post-MVP
These are important, but not required for MVP:
- JSON export
- Parquet export
- Excel export
- Additional database connectors
- Postgres backup import beyond plain SQL
- Richer import transforms
- Saved queries / workspace projects
- More advanced SQL productivity features beyond the MVP set

### 3.3 Non-goals (explicitly out of scope for MVP)
- Managing external databases as first-class live query targets
- Being a DBeaver-style admin or operations tool
- Collaborative editing, shared connections, or multi-user workflows
- Full migration tooling
- Advanced script orchestration engines
- Multi-workspace support (multiple DecentDB files open simultaneously)
- Postgres custom-format backup import
- ERD designer, query plans, or stored procedure workflows

---

## 4. Target users

### Primary persona: Power user / data wrangler
- Comfortable with SQL
- Needs to bring in data from Excel, SQLite, or dumps into a local database
  file for analysis and reshaping
- Values speed, keyboard workflows, and predictable behavior

### Secondary persona: Developer / builder
- Uses DecentDB files as portable data artifacts
- Wants a quick tool to inspect and query data without a heavy IDE

---

## 5. Top jobs to be done

1. **Import data into DecentDB**
   - "When I receive an Excel, SQLite, or supported SQL dump file, I want to
     import it into a DecentDB file quickly so I can query it."

2. **Inspect schema quickly**
   - "When I open a DecentDB file, I want to see what tables and columns exist
     immediately so I can write queries."

3. **Run queries quickly**
   - "When I’m iterating on a SELECT query, I want to run it repeatedly and see
     results quickly without friction."

4. **Export shaped results**
   - "When I get the data into the right shape via SQL, I want to export it
     easily for sharing or downstream use."

---

## 6. Success metrics

**Primary success:** users can complete an import → query → export workflow
without reading docs, and the app feels responsive.

Suggested measurable targets:
- App cold start to usable workspace: **< 3 seconds** on a typical dev laptop
- Schema tree population after opening DecentDB: **< 1 second** for typical DB
  sizes
- Query execution UI feedback: **immediate**
- Grid scroll and selection stay responsive up to **100k rows** via paging /
  virtualization
- Long-running work does not freeze the UI

---

## 7. Core user journeys

### Journey 0: Drag-and-drop → open or import
1. User drags a file onto Decent Bench, or uses File → Open / Import.
2. Decent Bench detects:
   - **DecentDB file** → open in workspace
   - **Supported import source** → launch Import Wizard
   - **Recognized but unsupported type** → open a guidance path with clear
     messaging
3. Wizard gathers options, shows preview, and runs import into a chosen or new
   DecentDB file.
4. On completion, Decent Bench focuses the imported table(s) and offers
   next-step actions such as "Run a query" and "Export CSV".

### Journey A: Excel → DecentDB → query → export
1. Create or open DecentDB file
2. Import Excel workbook / sheet
3. Inspect imported schema
4. Write SELECT query
5. Run query and view results
6. Export results to CSV

### Journey B: SQLite → DecentDB
1. Open DecentDB file
2. Import SQLite file and select tables
3. Verify schema and row counts
4. Run SELECT queries
5. Export results to CSV

### Journey C: SQL dump → DecentDB
1. Open or create DecentDB file
2. Import supported MariaDB/MySQL-style `.sql` dump
3. Review import warnings / skipped statements
4. Inspect imported schema
5. Query and export

---

## 8. Functional requirements

### 8.1 Workspace and files
- Open existing DecentDB database file
- Create a new DecentDB database file
- Maintain recent files list
- Store app configuration as **TOML**
- Use safe prompts for destructive operations if any such operations exist in
  MVP

### 8.2 Import entry and file handling
- Accept drag-and-drop of local files onto the main window
- Use extension-based detection for MVP, with lightweight signature checks only
  where safe and low-complexity
- Single-file drop for MVP
- If multiple files are dropped, process the first and show a warning

### 8.3 Supported imports for MVP
#### Excel import
- Select workbook and sheet(s)
- Header row on/off
- Column type inference with override
- Table name mapping
- Progress indicator
- Import summary

#### SQLite import
- Select SQLite file
- Choose tables to import
- Preserve names where possible
- Map common SQLite types to DecentDB native types

#### SQL dump import (MVP-lite)
- Accept `.sql` dump files
- Initial scope is common MariaDB/MySQL-style dumps
- MVP-lite acceptance may be limited to:
  - `CREATE TABLE`
  - `INSERT INTO`
- Unsupported statements may be skipped with warnings

### 8.4 Import transforms
MVP transforms are:
- Rename columns
- Type overrides

**Basic computed columns** may be included only if implemented as a constrained,
testable slice that does not destabilize the import workflow. If not, they move
to post-MVP.

### 8.5 Schema browser
- Show schema information needed for core query workflows
- MVP priority objects:
  - tables
  - views, if supported by the pinned DecentDB version
  - columns
  - indexes
- Search / filter schema items
- Preview top rows for a selected table

### 8.6 SQL editor
- Multi-tab editor
- Per-tab results pane
- Syntax highlighting
- Run / stop query
- Basic keyboard shortcuts:
  - Run: `Ctrl/Cmd+Enter`
  - New tab: `Ctrl/Cmd+T`
  - Find: `Ctrl/Cmd+F`

### 8.7 Results grid
- Virtualized / paginated grid
- No loading of millions of rows into memory by default
- Copy cell / row selection
- Show execution time, rows returned, and warnings
- Support best-effort query cancellation in the UI

### 8.8 Export
- Export query results to **CSV** in MVP
- Export options:
  - delimiter
  - quote style
  - include headers
- Save file dialog destination

---

## 9. Non-functional requirements

### 9.1 Performance
- No UI freezes during import, query execution, paging, or export
- Results grid remains responsive under large results via pagination /
  virtualization
- Query cancellation is best-effort
- Heavy work must run off the UI thread

### 9.2 Reliability
- Import operations are transactional where possible
- Failed imports should roll back or clean up partial results where possible
- The DecentDB file should not be corrupted by partial operations

### 9.3 Cross-platform
- Windows, macOS, Linux desktop
- Platform-appropriate keyboard shortcuts
- Consistent behavior across supported desktop platforms

### 9.4 Security and privacy
- Local-first; no data leaves the machine by default
- Credentials, if stored for future non-MVP connectors, must use OS secure
  storage where available
- Telemetry is off by default unless explicitly defined otherwise in a later
  decision

### 9.5 Licensing
- All dependencies must be compatible with Apache 2.0 distribution goals
- Third-party licenses must be tracked

---

## 10. Architecture decisions locked for MVP

### 10.1 DecentDB integration
Decent Bench integrates with DecentDB through **Dart FFI**.

Per the accepted binding strategy decision, the app will use **DecentDB’s
official upstream Dart FFI bindings** as the supported integration mechanism for
MVP. The project should not introduce a custom C shim or alternative binding
layer unless the upstream bindings prove insufficient for required capability or
performance.

### 10.2 Query results model
MVP uses a **cursor-based paging / streaming** model for query results:
- query execution opens a cursor
- the UI fetches pages incrementally
- results are virtualized in the grid
- full materialization is not the default behavior

### 10.3 Threading model
Heavy work must not run on the UI thread. This includes:
- import parsing
- query execution and page fetching
- export

---

## 11. Product scope matrix

| Area | MVP | Next / Later |
|---|---|---|
| Open DecentDB file | Yes | — |
| Create DecentDB file | Yes | — |
| Drag-and-drop file handling | Yes | — |
| Excel import | Yes | — |
| SQLite import | Yes | — |
| MariaDB/MySQL `.sql` import | Yes, MVP-lite | Broader SQL-dump support |
| Postgres plain `.sql` import | No | Candidate |
| Postgres custom backup import | No | Candidate |
| Live external DB querying | No | Candidate |
| Schema browser | Yes, core query objects first | Broader object coverage |
| Multi-tab SQL editor | Yes | — |
| Schema-aware autocomplete | Yes | Further refinement |
| Snippets | Yes | Further refinement |
| SQL formatter | Yes | Further refinement |
| Results paging / virtualization | Yes | — |
| CSV export | Yes | — |
| JSON export | No | Yes |
| Parquet export | No | Yes |
| Excel export | No | Yes |
| Multi-workspace support | No | Candidate |

---

## 12. Risks and open questions

### 12.1 Risks
- Upstream DecentDB bindings may lack one or more capabilities required by the
  UX contract
- Import type mapping can become complex, especially for SQL dumps and Excel
- Large-data responsiveness depends on disciplined paging, background work, and
  cancellation behavior
- Cross-platform packaging of native libraries may introduce build complexity

### 12.2 Open questions to resolve before or during implementation
1. What is the canonical DecentDB file extension for desktop UX?
2. What exact DecentDB object classes are in scope for the first schema browser
   slice?
3. Do basic computed columns remain in MVP, or should they move to post-MVP to
   keep the import workflow smaller and more reliable?
4. What is the exact configuration file location and schema per OS?
5. What is the exact query-tab execution state model for idle, running,
   cancelling, failed, completed, and cancelled states?

---

## 13. Acceptance criteria for MVP

A user can:
1. Drag and drop a file onto Decent Bench and:
   - if it is a DecentDB file, it opens
   - if it is a supported import source, the Import Wizard appears
2. Create a new DecentDB file
3. Import an Excel sheet into a new table with inferred types
4. Import a SQLite database and select tables to import
5. Import at least one supported MariaDB/MySQL-style `.sql` dump containing
   common `CREATE TABLE` and `INSERT INTO` statements
6. Rename columns and override types before import
7. See imported tables and columns in the schema browser
8. Open at least one SQL tab, run a SELECT query, and view results in a
   responsive paged grid
9. Stop a running query with best-effort cancellation semantics
10. Export query results to CSV
11. Perform the above without noticeable UI hangs on typical development
    hardware