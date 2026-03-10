## Desktop Native Library Packaging And Resolution
**Date:** 2026-03-10
**Status:** Accepted

### Decision

Decent Bench packages the DecentDB native library as an external desktop-bundle
artifact and uses a deterministic runtime resolution order.

The accepted contract is:

- runtime resolution order is:
  1. `DECENTDB_NATIVE_LIB`
  2. the platform-specific bundled desktop app location
  3. a sibling `../decentdb/build/` checkout for development
- Linux bundles expect `lib/libc_api.so`
- macOS bundles expect `Contents/Frameworks/libc_api.dylib`
- Windows bundles expect `c_api.dll` next to the executable
- the repository provides a packaging helper script to stage the native library
  into built bundles and verify its presence
- missing-library failures must be actionable and list the checked candidate
  paths

### Rationale

The upstream DecentDB Dart bindings remain the correct integration mechanism,
but the app still needs a stable startup contract for local development,
integration tests, and packaged desktop builds.

Relying only on `DECENTDB_NATIVE_LIB` keeps development workable, but it does
not produce repeatable packaged startup. Relying only on a sibling checkout
would also fail once the app is distributed or moved outside the repo layout.

The project therefore needs:

- a documented bundle layout per desktop platform
- deterministic runtime search order
- a repeatable staging step for packaging verification
- failure messages that help contributors fix startup quickly

### Alternatives Considered

- Require `DECENTDB_NATIVE_LIB` for all local and packaged startup
- Modify the upstream DecentDB Dart binding package to own app-bundle staging
- Keep sibling-checkout discovery only and treat packaged startup as post-MVP
- Introduce a new custom loader or wrapper binary around the DecentDB library

### Trade-offs

- A packaging helper is an extra build step, but it keeps the runtime contract
  explicit and testable without forking the upstream bindings
- Supporting bundle discovery and dev-checkout discovery at once adds some
  search-path complexity, but it improves local iteration and packaged startup
- The app still depends on the local DecentDB build artifact being available at
  packaging time; this is acceptable for MVP and is now documented instead of
  implicit

### References

- [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
- [design/IMPLEMENTATION_PHASES.md](/home/steven/source/decent-bench/design/IMPLEMENTATION_PHASES.md)
- [design/adr/0001-decentdb-flutter-binding-strategy.md](/home/steven/source/decent-bench/design/adr/0001-decentdb-flutter-binding-strategy.md)
