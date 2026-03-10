## Desktop Editor And Context Workflows
**Date:** 2026-03-10
**Status:** Accepted

### Decision

Decent Bench will treat the SQL editor, results grid, and schema explorer as a
desktop-style work surface instead of a form-and-drawer UI:

- SQL autocomplete appears inside the editor surface as a suggestion popup and
  is accepted with `Tab`
- snippet management lives under `Tools -> Manage Snippets` and opens the
  snippet section of `Options / Preferences`
- when the app reopens the most recent DecentDB workspace on startup, it reruns
  the most recent saved query for that workspace; if no saved query exists, it
  runs `SELECT * FROM <first table> LIMIT <page size>`
- results-grid cell `Copy`, `Paste`, and `Set To Null` actions are shell-local
  edits exposed from a right-click context menu
- schema-explorer right-click actions generate concrete SQL templates or run a
  safe refresh/data-preview action instead of silently executing destructive DDL

### Rationale

The desktop shell proof is being evaluated against classic database clients.
Detached autocomplete trays, toolbar-local snippet management, and inert
right-click behavior made the shell feel closer to a web form than a workbench.
Startup restore also felt incomplete because reopening a real database did not
repopulate the results pane.

These decisions keep the UX dense and keyboard-driven without committing the app
to premature backend mutation flows.

### Alternatives Considered

- Keep autocomplete in a separate panel under the editor
- Keep snippet management in the SQL editor toolbar
- Reopen the last workspace without rerunning any SQL
- Make context-menu actions placeholders only
- Execute rename/delete/index/view DDL directly from the context menu

### Trade-offs

- The in-editor autocomplete popup uses approximate caret positioning rather
  than a full code-editor engine
- startup fallback uses a first-table preview query instead of plain `ANALYZE`
  because the preview must populate the results grid and `ANALYZE` may not
  return rows
- results-grid paste/null actions are local proof-of-concept overrides, not
  persisted row updates
- schema context actions that generate SQL still require the user to review and
  run the statement

### References

- `design/SPEC.md`
- `apps/decent-bench/lib/features/workspace/presentation/workspace_screen.dart`
- `apps/decent-bench/lib/features/workspace/presentation/shell/sql_editor_pane.dart`
- `apps/decent-bench/lib/features/workspace/application/workspace_controller.dart`
