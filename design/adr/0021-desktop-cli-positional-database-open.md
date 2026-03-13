## Desktop CLI Positional Database Open
**Date:** 2026-03-13
**Status:** Accepted

### Decision

Decent Bench desktop builds accept a positional DecentDB database path:

- `dbench /path/to/workspace.ddb`

This launches the desktop UI and opens the specified `.ddb` workspace during
startup initialization.

This behavior is separate from the existing `dbench --import <path>` workflow:

- positional `.ddb` paths open an existing DecentDB workspace
- `--import <path>` remains the startup entry point for non-DecentDB import
  sources

### Rationale

Users expect desktop database tools to support opening a database directly from
the command line, especially for launcher integrations, shell scripts, and file
association workflows.

Keeping positional startup limited to `.ddb` files preserves the narrower,
predictable meaning of `--import` while still making the primary workspace type
easy to open.

### Alternatives Considered

- Keep command-line startup limited to `--import`
- Treat any positional path as a generic "open or import" request
- Add a separate `--open <path>` flag instead of positional support

### Trade-offs

- CLI startup now has two entry forms that must stay documented together.
- Positional startup remains intentionally narrow; non-`.ddb` files still use
  `--import` instead of implicit wizard launch.
- Native desktop runners must keep the packaged `--help` text in sync with the
  Dart-side parser behavior.

### References

- [design/adr/0013-desktop-cli-import-launch-and-binary-name.md](/home/steven/source/decent-bench/design/adr/0013-desktop-cli-import-launch-and-binary-name.md)
- [apps/decent-bench/lib/app/startup_launch_options.dart](/home/steven/source/decent-bench/apps/decent-bench/lib/app/startup_launch_options.dart)
- [apps/decent-bench/lib/features/workspace/presentation/workspace_screen.dart](/home/steven/source/decent-bench/apps/decent-bench/lib/features/workspace/presentation/workspace_screen.dart)
- [apps/decent-bench/linux/runner/main.cc](/home/steven/source/decent-bench/apps/decent-bench/linux/runner/main.cc)
