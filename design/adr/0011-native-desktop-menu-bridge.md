## Native Desktop Menu Bridge
**Date:** 2026-03-10
**Status:** Accepted

### Decision
Decent Bench will keep a single Dart-side command registry and route it into native desktop menu implementations per platform:

- macOS: Flutter `PlatformMenuBar` using the built-in `flutter/menu` plugin.
- Windows: runner-owned `HMENU` plus accelerator table bridged over `flutter/menu`.
- Linux: runner-owned GTK menubar plus `GtkAccelGroup` bridged over `flutter/menu`.

The in-window Material `MenuBar` remains only as a fallback when the native menu bridge is unavailable, such as widget tests or unsupported environments.

### Rationale
The shell is explicitly desktop-first and should evaluate like a traditional SQL workbench. A native menu bar is a visible part of that interaction model, and it also keeps keyboard shortcuts, application lifecycle commands, and host conventions aligned with each desktop platform.

Keeping command definition and shortcut resolution in Dart avoids duplicating menu semantics across three hosts while still allowing each runner to render the menu natively.

### Alternatives Considered
- Keep the Material `MenuBar` everywhere.
- Use `PlatformMenuBar` only on macOS and accept non-native menus elsewhere.
- Build a fully custom platform channel and bypass `flutter/menu`.

### Trade-offs
- Windows and Linux runners now contain menu-specific host code that must be maintained alongside Flutter updates.
- Native desktop platforms do not have identical menu capabilities, so visual parity is approximate rather than exact.
- Tests need to tolerate both native and fallback menu hosts depending on environment.

### References
- `apps/decent-bench/lib/features/workspace/presentation/shell/app_menu_bar.dart`
- `apps/decent-bench/windows/runner/flutter_menu_plugin.cpp`
- `apps/decent-bench/linux/runner/flutter_menu_plugin.cc`
