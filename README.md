# Decent Bench

> The GUI for DecentDB.

Decent Bench is a cross-platform desktop app (Flutter) for power users who need
to work directly with **DecentDB**: open or create a database, inspect schema,
run the full pinned DecentDB SQL surface, export shaped results, and import
SQLite, Excel, and MariaDB/MySQL-style SQL dump sources through guided
workflows.

## Project status

**Pre-alpha / active implementation.** Phase 7 is implemented and runnable
under `apps/decent-bench/`.

Current engine capability baseline: **DecentDB v1.6.x**.
Canonical DecentDB desktop file extension: **`.ddb`**.

### Implemented now (Phase 7)

- open an existing DecentDB file or create a new one
- drag and drop a `.ddb` file to open it immediately
- drag and drop a `.db`, `.sqlite`, or `.sqlite3` file to launch the SQLite
  import wizard
- drag and drop an `.xlsx` file to launch the Excel import wizard
- drag and drop a `.sql` file to launch the SQL dump import wizard
- inspect SQLite sources in the background before import
- inspect Excel workbooks in the background before import
- inspect MariaDB/MySQL-style `.sql` dumps in the background with
  auto-detect, UTF-8, and Latin-1 decode options
- run a six-step SQLite import wizard for source, target, preview, transforms,
  execution, and summary
- run a six-step Excel import wizard for source, target, preview, transforms,
  execution, and summary
- run a six-step SQL dump import wizard for source, target, preview,
  transforms, execution, and summary
- select SQLite tables to import, rename target tables and columns, and apply
  per-column type overrides limited to DecentDB native types
- select Excel worksheets to import, toggle header-row handling, rename target
  tables and columns, and apply per-column type overrides limited to DecentDB
  native types
- select parsed SQL dump tables to import, rename target tables and columns,
  and apply per-column type overrides limited to DecentDB native types
- map representative SQLite affinities to DecentDB types, including boolean,
  decimal, blob, and timestamp-oriented cases
- infer representative Excel column types for integers, booleans, floats,
  timestamps, and safe text fallbacks
- parse representative SQL dump `CREATE TABLE` plus `INSERT ... VALUES`
  statements, infer DecentDB target types for common MySQL/MariaDB column
  types, and preserve unsupported statements as warnings
- preview sample SQLite rows before import and surface warnings for `STRICT`,
  `WITHOUT ROWID`, skipped composite indexes, and skipped foreign keys to
  unselected tables
- preview sample Excel rows before import and surface warnings for formula-text
  handling and unsupported legacy `.xls` workbooks
- preview sample SQL dump rows before import and surface warnings for skipped
  `SET`, `LOCK TABLES`, `ALTER TABLE`, and other unsupported statements
- execute SQLite imports in a background worker with progress updates and
  best-effort cancellation plus rollback-oriented summary messaging
- execute Excel imports in a background worker with progress updates and
  best-effort cancellation plus rollback-oriented summary messaging
- execute SQL dump imports in a background worker with progress updates and
  rollback-oriented summary messaging
- open the imported database or launch a starter query from the import summary
- inspect schema metadata loaded through the DecentDB adapter for tables, views,
  columns, indexes, and exposed constraint details
- harden native-library startup with deterministic runtime resolution order and
  actionable missing-library diagnostics
- stage the DecentDB native library into desktop bundles through a repeatable
  packaging helper for Linux, macOS, and Windows outputs
- run SQL in multiple editor tabs with per-tab positional parameters
- keep per-tab results, errors, and CSV export state isolated
- restore query tabs when reopening the same DecentDB file
- switch tabs and move between editor/results with keyboard shortcuts
- author SQL with schema-aware autocomplete for objects, columns, functions,
  keywords, and snippets
- manage user-editable SQL snippets with default DecentDB-oriented starters
- format selected SQL or whole documents deterministically while preserving
  comments and string literals
- page large result sets instead of materializing everything by default
- best-effort query cancellation
- export query results to CSV
- persist recent files, export defaults, editor settings, and SQL snippets in
  TOML
- persist workspace tab drafts separately from global config
- run broader unit, smoke, widget, and integration tests for the MVP workflow,
  including native-library resolution and larger paging/schema scenarios

### Not implemented yet

- JSON, Parquet, and Excel export
- legacy binary `.xls` workbook parsing

For the full planned product scope, read:

- [design/PRD.md](/home/steven/source/decent-bench/design/PRD.md)
- [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
- [design/IMPLEMENTATION_PHASES.md](/home/steven/source/decent-bench/design/IMPLEMENTATION_PHASES.md)

## Engine baseline

- Decent Bench tracks the **DecentDB `v1.6.x` compatibility line**.
- The official DecentDB SQL reference for that line is the normative SQL
  contract for the app.
- Patch upgrades inside `v1.6.x` do not require doc churn unless they change
  capability surface, validation expectations, or packaging assumptions.

## Repository layout

```text
apps/decent-bench/              Flutter desktop app
.github/workflows/              CI workflows
design/                         Product docs, roadmap, and ADRs
design/adr/                     Architecture Decision Records
THIRD_PARTY_NOTICES.md          Third-party attribution tracking
LICENSE                         Apache 2.0 license
AGENTS.md                       Repo workflow and guardrails
```

## Source of truth

- Product requirements: [design/PRD.md](/home/steven/source/decent-bench/design/PRD.md)
- Product specification: [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
- Delivery phases: [design/IMPLEMENTATION_PHASES.md](/home/steven/source/decent-bench/design/IMPLEMENTATION_PHASES.md)
- ADR policy and decisions: [design/adr/README.md](/home/steven/source/decent-bench/design/adr/README.md)
- Repo workflow and validation rules: [AGENTS.md](/home/steven/source/decent-bench/AGENTS.md)

## Developer onboarding

### Prerequisites

- Git
- Flutter stable with desktop tooling enabled for your OS
- the native toolchain required by Flutter desktop on your platform
- Nim, for building the local DecentDB native library
- a local DecentDB checkout placed as a sibling repo, or an equivalent update
  to the path dependency in `apps/decent-bench/pubspec.yaml`

### Expected checkout layout

The current Flutter app depends on the upstream Dart binding via a local path:

```text
decent-bench/apps/decent-bench/pubspec.yaml -> ../../../decentdb/bindings/dart/dart
```

The simplest layout is:

```text
/path/to/source/decent-bench
/path/to/source/decentdb
```

### Bootstrap

1. Build the DecentDB native library:

```bash
cd ../decentdb
nimble build_lib
```

2. Install Flutter dependencies:

```bash
cd ../decent-bench/apps/decent-bench
flutter pub get
```

### Validate

From `apps/decent-bench/`:

```bash
flutter analyze
DECENTDB_NATIVE_LIB=/path/to/decentdb/build/libc_api.so flutter test
DECENTDB_NATIVE_LIB=/path/to/decentdb/build/libc_api.so flutter test integration_test
```

If `flutter` is not on `PATH`, use its full path instead.

### Run locally

From `apps/decent-bench/`, pick the desktop target you want:

```bash
DECENTDB_NATIVE_LIB=/path/to/decentdb/build/libc_api.so flutter run -d linux
DECENTDB_NATIVE_LIB=/path/to/decentdb/build/libc_api.so flutter run -d macos
DECENTDB_NATIVE_LIB=/path/to/decentdb/build/libc_api.so flutter run -d windows
```

The app resolves the native DecentDB library in this order:

1. `DECENTDB_NATIVE_LIB`
2. a bundled desktop-runner location
3. a sibling `../decentdb/build/` checkout discovered from the app working
   directory

If the sibling build is present and resolves correctly, you can omit
`DECENTDB_NATIVE_LIB` when launching locally.

### Package desktop builds

Build the Flutter desktop bundle first, then stage the DecentDB native library
into the generated output:

```bash
cd apps/decent-bench
flutter build linux
dart run tool/stage_decentdb_native.dart --bundle build/linux/x64/release/bundle
dart run tool/stage_decentdb_native.dart --bundle build/linux/x64/release/bundle --verify-only
```

Equivalent bundle roots:

- macOS: `build/macos/Build/Products/Release/decent_bench.app`
- Windows: `build/windows/x64/runner/Release`

The staging helper uses the same resolution contract as the app. See
[design/adr/0009-desktop-native-library-packaging-and-resolution.md](/home/steven/source/decent-bench/design/adr/0009-desktop-native-library-packaging-and-resolution.md).

### Local config and workspace state

Global config is stored as TOML at:

- Linux: `~/.config/decent-bench/config.toml`
- macOS: `~/Library/Application Support/Decent Bench/config.toml`
- Windows: `%APPDATA%\Decent Bench\config.toml`

`config.toml` currently stores recent files, CSV defaults, editor settings, and
SQL snippets. See
[design/adr/0005-editor-config-and-snippet-persistence.md](/home/steven/source/decent-bench/design/adr/0005-editor-config-and-snippet-persistence.md).

Per-database workspace state is stored separately under:

- Linux: `~/.config/decent-bench/workspaces/`
- macOS: `~/Library/Application Support/Decent Bench/workspaces/`
- Windows: `%APPDATA%\Decent Bench\workspaces\`

That workspace-state store restores query tabs only when the same database is
opened again. See
[design/adr/0004-workspace-state-persistence.md](/home/steven/source/decent-bench/design/adr/0004-workspace-state-persistence.md).

## Manual Verification

Use this checklist before cutting or reviewing an MVP build:

- Large query paging:
  run a query that returns thousands of rows, load more pages, and confirm the
  window stays responsive while row counts and running/completed state stay
  accurate
- Cancellation:
  run a longer query, cancel it, and confirm the tab reports cancelled or
  partial results without blocking the next execution
- Long-running imports:
  run SQLite, Excel, and SQL dump imports with enough data to show progress,
  cancel at least one run, and confirm the summary reports rollback-oriented
  status clearly
- Export behavior:
  export CSV with headers on and off plus a custom delimiter, then confirm the
  file contents match the visible result shape
- Packaged startup:
  build a desktop bundle, run
  `dart run tool/stage_decentdb_native.dart --bundle <bundle-path> --verify-only`,
  then launch the packaged app without `DECENTDB_NATIVE_LIB` and confirm it
  resolves the bundled library path

### Contributing

Read these before making non-trivial changes:

1. [design/PRD.md](/home/steven/source/decent-bench/design/PRD.md)
2. [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
3. [design/IMPLEMENTATION_PHASES.md](/home/steven/source/decent-bench/design/IMPLEMENTATION_PHASES.md)
4. [AGENTS.md](/home/steven/source/decent-bench/AGENTS.md)

Important repo expectations:

- keep changes small and testable
- keep heavy work off the UI thread
- prefer paging/streaming over full materialization
- create an ADR for lasting architectural or product-impacting decisions
- only add Apache-2.0-compatible dependencies
- update `THIRD_PARTY_NOTICES.md` when required by a dependency license

Recent ADRs relevant to the current implementation:

- [design/adr/0004-workspace-state-persistence.md](/home/steven/source/decent-bench/design/adr/0004-workspace-state-persistence.md)
- [design/adr/0005-editor-config-and-snippet-persistence.md](/home/steven/source/decent-bench/design/adr/0005-editor-config-and-snippet-persistence.md)
- [design/adr/0006-sqlite-import-entry-and-worker-architecture.md](/home/steven/source/decent-bench/design/adr/0006-sqlite-import-entry-and-worker-architecture.md)
- [design/adr/0008-sql-dump-import-mvp-parser-and-warning-contract.md](/home/steven/source/decent-bench/design/adr/0008-sql-dump-import-mvp-parser-and-warning-contract.md)
- [design/adr/0009-desktop-native-library-packaging-and-resolution.md](/home/steven/source/decent-bench/design/adr/0009-desktop-native-library-packaging-and-resolution.md)
- [design/adr/0007-excel-import-parser-and-legacy-workbook-handling.md](/home/steven/source/decent-bench/design/adr/0007-excel-import-parser-and-legacy-workbook-handling.md)

## License

Decent Bench is licensed under the Apache License 2.0. See `LICENSE`.

## Third-party notices

See `THIRD_PARTY_NOTICES.md` for dependency attributions and license tracking.
