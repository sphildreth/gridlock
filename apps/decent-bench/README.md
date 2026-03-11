# Decent Bench App

This directory contains the hand-authored Phase 7 Flutter app source for
Decent Bench.

## Current state

- `pubspec.yaml`, `lib/`, `test/`, and `integration_test/` are present
- the workspace controller, multi-tab UI, desktop bridge, autocomplete,
  snippets, formatter, drag-and-drop entry flow, shared import registry,
  generic import wizard, SQLite import wizard, Excel import wizard, and SQL
  dump import wizard are in place
- reopening the same DecentDB file restores persisted query tabs for that
  workspace
- editor settings and SQL snippets persist in `config.toml`
- SQLite, Excel, and SQL dump inspection plus import execution run off the UI
  thread
- CSV, TSV, generic delimited text, JSON, NDJSON/JSONL, XML, HTML tables, and
  ZIP/GZip wrapper routing now use the generic import preview/execution path
- desktop runner folders (`linux/`, `macos/`, `windows/`) are checked in
- the DecentDB Dart package is consumed from a local sibling checkout at
  `../../../decentdb/bindings/dart/dart`
- Excel import currently supports `.xlsx`; legacy `.xls` files route through
  the existing conversion/normalization path and remain explicitly partial
- SQL dump import currently targets the MVP-lite parser scope documented in
  `design/SPEC.md`: common MariaDB/MySQL-style `CREATE TABLE` plus
  `INSERT ... VALUES`, with unsupported statements surfaced as warnings rather
  than hard failures when possible
- `docs/IMPORT_FORMATS.md` summarizes the currently implemented, partial, and
  recognized-but-unimplemented import formats
- native-library resolution now prefers `DECENTDB_NATIVE_LIB`, then bundled
  desktop app locations, then a sibling `../decentdb/build/` checkout, with a
  packaging helper to stage the library into built bundles

## Validation

From `apps/decent-bench/`:

```bash
flutter pub get
flutter analyze
DECENTDB_NATIVE_LIB=/path/to/decentdb/build/libc_api.so flutter test
DECENTDB_NATIVE_LIB=/path/to/decentdb/build/libc_api.so flutter test integration_test
DECENTDB_NATIVE_LIB=/path/to/decentdb/build/libc_api.so flutter run -d linux
flutter build linux
dart run tool/stage_decentdb_native.dart --bundle build/linux/x64/release/bundle
dart run tool/stage_decentdb_native.dart --bundle build/linux/x64/release/bundle --verify-only
```

The app expects a compatible DecentDB v1.6.x native library to be available via:

1. `DECENTDB_NATIVE_LIB`
2. a bundled desktop runner path
3. a sibling `../decentdb/build/` checkout

Workspace tab drafts are stored separately from `config.toml` under the
platform-specific `workspaces/` directory documented in the root
[README.md](/home/steven/source/decent-bench/README.md).

For packaged builds on other platforms, use the same staging helper with the
platform bundle root:

- macOS: `build/macos/Build/Products/Release/decent_bench.app`
- Windows: `build/windows/x64/runner/Release`
