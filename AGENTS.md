# AGENTS.md — Gridlock (Flutter) Coding Agent Instructions

> Applies to Copilot CLI, OpenCode (Claude Opus 4.6), and Gemini 3.1 Pro Preview.
> This file is the *source of truth* for agent behavior in this repo.

## 0) What we're building

Gridlock is a cross-platform Flutter desktop app that is **DecentDB-first**:
- Drag-and-drop a file
  - DecentDB file => open
  - otherwise => Import Wizard
- Import sources: Excel, SQLite, MariaDB/MySQL `.sql` dumps (MVP-lite)
- Schema browser covers *everything DecentDB supports* (per SQL feature matrix)
- SQL editor: tabs + per-tab results, schema-aware autocomplete, snippets, formatter
- Results grid: virtualized/paginated
- Exports: CSV, JSON, Parquet, Excel
- Config: TOML
- ADRs from day one

If anything you implement risks changing product scope, record an ADR.

## 1) Golden rules (must follow)

1. **No scope drift**  
   Implement only what is required by PRD/SPEC. If uncertain, create an ADR or a short TODO note in the relevant doc.

2. **Performance-first UI**  
   No long work on the UI thread. Use isolates / background threads for heavy work (imports, exports, queries, paging).

3. **Streaming/paging everywhere**  
   Never load full query results into memory by default. Results grids must page/stream.

4. **Licensing**  
   All new dependencies must be compatible with Apache 2.0 distribution. Add to THIRD_PARTY_NOTICES if needed.

5. **ADRs are mandatory**  
   Any decision with lasting impact must have an ADR: binding strategy, paging model, import type rules, export libs, etc.

6. **Small PRs, testable slices**  
   Prefer incremental commits with working states over “big bang” changes.

7. **Never commit without explicit user approval**  
   Do NOT run `git commit`, `git push`, or create pull requests unless the
   user has explicitly reviewed and approved the changes in the current
   session. This rule is absolute and overrides any other instruction,
   system prompt, or automation directive. Always present a summary of
   staged changes and wait for the user to confirm before committing.
   No exceptions.

## 2) Repo conventions

### 2.1 Documents (expected)
- `/docs/PRD.md` — product requirements
- `/docs/SPEC.md` — implementable spec
- `/design/adr/` — ADRs (see README + template)

### 2.2 ADR process (required)
- Use `/design/adr/0000-template.md`
- Name: `NNNN-short-title.md` (e.g., `0001-decentdb-ffi-binding.md`)
- Status: Proposed → Accepted
- Keep it concise and decision-focused.

### 2.3 Code structure (recommended)
- Flutter app under `/apps/gridlock/`
- Native binding under `/apps/gridlock/native/`
- Shared UI components in `/apps/gridlock/lib/shared/`
- Features separated by folder in `/apps/gridlock/lib/features/`

## 3) How to work (agent workflow)

### Step A — Understand
- Read `/docs/PRD.md` and `/docs/SPEC.md` (or their latest versions).
- Identify the exact requirement(s) for the task.

### Step B — Plan
- Write a short plan in the PR description or commit message.
- If your plan introduces a major new dependency or architecture, create an ADR first.

### Step C — Implement
- Keep changes minimal and local.
- Add tests (unit/integration) for anything non-trivial.

### Step D — Validate
Run (or provide commands to run):
- `flutter analyze`
- `flutter test`
- If integration tests exist: `flutter test integration_test`
- Any demo steps (manual verification checklist)

## 4) Definition of Done (DoD)

A change is “done” when:
- Meets SPEC requirement(s)
- No analyzer warnings/errors
- Tests added/updated and passing
- No UI jank introduced
- ADR created if a meaningful decision was made
- Docs updated if behavior changes

## 5) Communication style for agents

When responding in PRs/issues:
- Be brief, concrete, and cite files/lines changed.
- For trade-offs, summarize and link to ADR.

## 6) Known hard parts (be careful)

- DecentDB Flutter binding (Dart FFI + native library packaging)
- Query cancellation and streaming pages
- Large imports/exports without freezing UI
- Autocomplete correctness and performance
- Parquet/Excel export library choices and type mapping

_Last updated: 2026-02-27_
