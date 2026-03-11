## Custom SQL Editor Surface Rendering
**Date:** 2026-03-10
**Status:** Accepted

### Decision

Decent Bench will render the SQL editor through a dedicated `SqlCodeEditor`
widget built on `EditableText` plus custom painting instead of relying on a
plain `TextField`.

The editor surface will:

- keep the existing Flutter text-input stack for selection, IME, clipboard, and
  undo behavior
- use the syntax-highlighting controller to provide themed token spans
- paint theme-driven editor affordances behind the text, including current-line
  highlight, whitespace markers, and indent guides
- keep scroll ownership in Dart so the existing line-number gutter,
  autocomplete popup positioning, and workspace shell layout continue to work

### Rationale

The theme system now exposes explicit editor-surface tokens such as
`current_line_bg`, `whitespace`, and `indent_guide`. A plain `TextField` can
apply text color and cursor color, but it cannot cleanly render the full editor
surface contract without ad hoc overlays and duplicated state.

`EditableText` preserves Flutter-native editing behavior while allowing the app
to render the visual workbench affordances that a desktop SQL editor needs.

### Alternatives Considered

- Keep the plain `TextField` and only theme text/cursor colors
- Add more overlay widgets around `TextField` without changing the editor core
- Introduce a third-party code-editor package
- Build a fully custom RenderObject editor immediately

### Trade-offs

- The first custom-painted editor still uses monospaced layout assumptions for
  guide placement instead of a full code-editor engine
- More of the editor rendering logic now lives in app code and requires widget
  coverage
- `EditableText` is lower-level than `TextField`, so decoration and layout must
  be owned explicitly by the shell

These trade-offs are acceptable because they unlock the documented theme
surface without adding a new dependency or replacing Flutter's text input
behavior.

### References

- `design/THEME_SYSTEM.md`
- `design/adr/0013-external-toml-theme-system.md`
- `design/adr/0014-desktop-editor-and-context-workflows.md`
- `apps/decent-bench/lib/features/workspace/presentation/shell/sql_editor_pane.dart`
