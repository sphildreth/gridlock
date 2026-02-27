# 0001-decentdb-flutter-binding-strategy

- **Status:** Proposed
- **Date:** 2026-02-27
- **Decision owners:** Gridlock maintainers
- **Related:** PRD/SPEC (DecentDB-first + performance + cross-platform desktop)

## Decision
Adopt **Dart FFI** as the primary integration mechanism between Gridlock (Flutter) and DecentDB, using a **stable C-compatible ABI** exposed to Dart.

Select one of:
- **A. Use an official DecentDB C ABI** (preferred if available/stable)
- **B. Build a thin C shim** that wraps the existing DecentDB Nim API into a stable C ABI (preferred if Nim API is canonical and no C ABI exists yet)

For MVP we will implement **Option B** unless an official DecentDB C ABI exists that meets stability/performance needs.

## Rationale
- Flutter does not provide a native DB “driver” layer; high-performance embedded DB access is typically done via **Dart FFI**.
- FFI minimizes overhead vs platform channels and supports high-throughput calls (query paging, import bulk load).
- A C-compatible ABI is the most practical bridge target for Dart; direct Nim calls from Dart are not feasible.
- Packaging native libs alongside Flutter desktop builds is standard and repeatable.

## Alternatives considered
1. **Platform channels (MethodChannel)**
   - Pros: simpler initial glue
   - Cons: higher overhead, more boilerplate per platform, awkward for high-frequency paging/streaming, harder cancellation semantics
2. **Pure Dart implementation**
   - Pros: single language
   - Cons: unrealistic for embedded DB engine performance/feature set; duplicates DecentDB
3. **Run DecentDB as a separate process**
   - Pros: isolation
   - Cons: complexity, packaging, IPC overhead, worse offline/local UX

## Trade-offs
- **FFI + native libs** increases build/packaging complexity (per-OS artifacts).
- Requires careful memory management and thread-safety across the boundary.
- A shim introduces an additional maintenance surface; mitigate by keeping shim minimal and well-tested.

## Implementation notes (non-normative)
### Required MVP ABI surface (minimum)
- `db_open(path, flags) -> handle`
- `db_close(handle)`
- `db_exec(handle, sql) -> status/error`
- `db_query_open(handle, sql, options) -> cursor_handle`
- `db_query_next(cursor_handle, page_size) -> row_batch + metadata`
- `db_query_close(cursor_handle)`
- `db_cancel(handle_or_cursor)` (best-effort)
- `db_last_error(...)` or structured error return

### Packaging
- Bundle dynamic libraries with desktop apps:
  - Windows: `.dll`
  - macOS: `.dylib` (or `.framework`)
  - Linux: `.so`
- Provide a deterministic lookup strategy in app startup.

### Tests
- Integration tests that run `SELECT 1` and a paging query on each platform build.

## References
- Flutter/Dart FFI platform integration docs
- DecentDB Nim API reference (for shim mapping)
