# 0001-decentdb-flutter-binding-strategy

- **Status:** Accepted
- **Date:** 2026-02-27
- **Decision owners:** Gridlock maintainers
- **Related:** PRD/SPEC (DecentDB-first + performance + cross-platform desktop)

## Decision
Use **DecentDB’s official Dart FFI bindings** as the *only* supported integration mechanism between Gridlock (Flutter) and DecentDB.

Source of truth:
- Upstream-provided bindings can be downloaded from the DecentDB releases page.
- For local development, the bindings can also be used from a locally cloned DecentDB repo.

We will not build or maintain a custom C shim or any alternative binding layer unless the upstream Dart FFI bindings become insufficient for required features/performance.

## Rationale
- Flutter does not provide a native DB “driver” layer; high-performance embedded DB access is typically done via **Dart FFI**.
- FFI minimizes overhead vs platform channels and supports high-throughput calls (query paging, import bulk load).
- Using the upstream DecentDB Dart bindings reduces maintenance burden and keeps us aligned with the engine’s supported ABI surface.
- Packaging native libs alongside Flutter desktop builds is standard and repeatable.

## Alternatives considered
1. **Build/maintain a custom C shim**
   - Pros: complete control over ABI and packaging
   - Cons: ongoing maintenance surface; higher risk of drift from DecentDB behavior
2. **Platform channels (MethodChannel)**
   - Pros: simpler initial glue
   - Cons: higher overhead, more boilerplate per platform, awkward for high-frequency paging/streaming, harder cancellation semantics
3. **Pure Dart implementation**
   - Pros: single language
   - Cons: unrealistic for embedded DB engine performance/feature set; duplicates DecentDB
4. **Run DecentDB as a separate process**
   - Pros: isolation
   - Cons: complexity, packaging, IPC overhead, worse offline/local UX

## Trade-offs
- **FFI + native libs** increases build/packaging complexity (per-OS artifacts).
- Requires careful memory management and thread-safety across the boundary.
- Depending on upstream bindings means we must track DecentDB binding releases and pin versions for reproducible builds.

## Implementation notes (non-normative)
### Binding API surface
Gridlock will use the API exposed by the upstream DecentDB Dart bindings. If any required capability is missing (paging/streaming contract, cancellation, structured errors), we will first attempt to upstream changes rather than introducing a local shim.

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
- DecentDB Dart bindings (upstream)
