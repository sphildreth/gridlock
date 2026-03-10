## Desktop Shell Layout And Shortcut Configuration
**Date:** 2026-03-10
**Status:** Accepted

### Decision

Decent Bench adopts a classic desktop workbench shell for the main workspace.

- The primary shell is a 2x2 split layout:
  - Schema Explorer / Properties on the left
  - SQL Editor / Results on the right
- The left-right split and both vertical splits are user-resizable and persist
  in the global `config.toml` file.
- View visibility toggles and editor zoom also persist in `config.toml`.
- Keyboard shortcuts are defined in a `[shortcuts]` TOML table with fallback
  defaults in code.
- Menu commands are modeled separately from the screen widget so the same
  command identities can drive the top menu bar, toolbar buttons, and keyboard
  shortcuts.

Per-database query tabs and the active tab remain in the separate workspace
state store defined by ADR 0004.

### Rationale

The shell proof is meant to validate whether Decent Bench should feel like a
traditional database client rather than a mobile/web-styled dashboard. That
decision affects window structure, affordances for power users, and how future
features plug into the shell.

Persisting layout and shortcut preferences in `config.toml` keeps the shell
behavior durable across launches without mixing global UI preferences into
per-database workspace state.

Separating command registration from widget composition also makes it practical
to wire future functionality once import/export/query actions move from shell
proof to production behavior.

### Alternatives Considered

- Keep the existing single-screen, card-based layout and add more controls to it
- Store pane layout in per-workspace state instead of global config
- Hardcode keyboard shortcuts in widget trees without TOML-backed overrides
- Use platform-native menubar integration before proving the shell interaction
  model inside Flutter

### Trade-offs

- A command registry and shell controller add more structure than a single
  widget file, but the shell is now easier to extend safely.
- Persisting layout globally means the same docking defaults apply across
  databases, which is simpler for now but may not fit every future workflow.
- Shortcuts still fall back to code defaults, so malformed TOML entries do not
  fail the app, but the parser must stay disciplined and well-tested.
- The proof uses some placeholder menu actions to validate IA and affordances
  before every backend workflow is wired.

### References

- [design/PRD.md](/home/steven/source/decent-bench/design/PRD.md)
- [design/SPEC.md](/home/steven/source/decent-bench/design/SPEC.md)
- [design/adr/0004-workspace-state-persistence.md](/home/steven/source/decent-bench/design/adr/0004-workspace-state-persistence.md)
- [design/adr/0005-editor-config-and-snippet-persistence.md](/home/steven/source/decent-bench/design/adr/0005-editor-config-and-snippet-persistence.md)
- [AGENTS.md](/home/steven/source/decent-bench/AGENTS.md)
