# FOSS Cross-Platform SQL Database Editor Project – Flutter Tech Stack Guide

**Project Overview**  
This document compiles recommendations and details for building an open-source, cross-platform desktop SQL database editor similar to Beekeeper Studio, DBeaver, or SQL Server Management Studio (SSMS).  

The app will support:  
- Managing database connections (MySQL, PostgreSQL, SQL Server, SQLite, DecentDB, etc.)  
- Schema explorer (tree view: databases → schemas → tables → columns → indexes, etc.)  
- SQL query editor with syntax highlighting and basic autocompletion  
- Result grid for displaying, sorting, filtering, and inline editing query results  
- Basic CRUD operations on tables  
- Export results (CSV, JSON)  
- Settings for themes, recent connections, etc.  

**Working Title**
Gridlock: The GUI for DecentDB – Because Perfection is Overrated

**Core Goals & Constraints**  
- Cross-platform desktop: Windows, macOS, Linux  `
- Simple by design → high success rate for AI coding agents (generation & troubleshooting)  
- "Fast enough" performance (native compilation, low memory footprint, not Electron-heavy)  
- **100% permissively licensed components** (MIT, BSD-3, etc.) – no copyleft (GPL/AGPL) restrictions for your FOSS project license choice  
- FOSS-friendly stack for easy contributions  

**Recommended Tech Stack (All Permissive Licenses)**

### Framework & Build
- **Flutter** (License: BSD-3-Clause)  
  Single Dart codebase compiles to native desktop apps (via `flutter build windows`, `macos`, `linux`).  
  Mature desktop support (stable since ~2021, excellent in 2026).  
  Material 3 theming, hot reload for fast iteration, great for AI-assisted coding due to declarative widgets.

### State Management
- **Riverpod 3.x** (MIT) – Preferred  
  Modern, compile-time safe, low boilerplate, excellent for managing:  
  - Database connections  
  - Current query state  
  - Result sets  
  - UI reactivity  
  Alternative: **flutter_bloc** (MIT) if event-driven architecture is preferred.

### Database Connectivity (Direct Drivers – Pure Dart, Permissive)`
Use lightweight, direct Dart packages (no heavy ORMs):  
- MySQL: `mysql_client` or `mysql1` (MIT)  
- PostgreSQL: `postgres` (MIT)  
- SQL Server (MSSQL): `mssql_connection` or community Dart MSSQL clients (MIT)  
- SQLite: `sqflite` (MIT) – local files or in-memory  
- Others (Oracle, etc.): Add as community drivers emerge.  
Focus on raw SQL execution + result mapping to avoid bloat.

### UI & Component Libraries (All MIT)
- **Query Editor** (syntax highlighting, folding, basic autocomplete):  
  `flutter_code_editor` (MIT) – Supports SQL + 100+ languages, themes, line numbers, custom completion logic.  
  Fallback/Enhance with: `highlight` package for core SQL highlighting rules.

- **Data Grid / Results Table** (display rows, sort, filter, inline edit, pagination):  
  `pluto_grid` (MIT) – Top recommendation. Keyboard-controllable, desktop-optimized, cell editing, column freezing, filtering, sorting, custom renderers. Handles thousands of rows efficiently.  
  Alternative: `data_table_2` (MIT) – Lightweight enhancement of Flutter's built-in `DataTable` (fixed headers, better scrolling).

- **Forms & Dialogs** (connection setup, query params, settings):  
  `flutter_form_builder` (MIT) – Ready-made fields (text, dropdown, checkbox, date), validation, dynamic forms, minimal boilerplate.

- **Schema Explorer** (hierarchical tree: DBs → tables → columns):  
  Built-in widgets + `flutter_treeview` (MIT) or custom `ExpansionTile` / `ListView` tree.  
  Simple recursive tree nodes for databases, schemas, tables, views, columns.

- **Helpers** (MIT):  
  - `file_picker` – Export results to CSV/JSON  
  - `url_launcher` – Open external docs/help  
  - `intl` – Format dates/numbers in grids  
  - `shared_preferences` – Persist recent connections, theme, window size  
  - Optional: `bitsdojo_window` (MIT) for custom window titlebar/menus if desired

### Project Structure Sketch (Clean & AI-Friendly)