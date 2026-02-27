# Gridlock — Implementation Phases (Plan) v0.1
_Last updated: 2026-02-27_

This plan is optimized for coding agents (Copilot CLI + OpenCode/Claude Opus 4.6 + Gemini 3.1 Pro Preview) and for producing early, testable vertical slices while forcing the biggest architectural decisions into ADRs up front.

---

## Phase 0 — Repo bootstrap + governance (Day 0)
**Outcome:** A clean repo with docs, ADR workflow, CI, and agent instructions so implementation can proceed safely.

### Work items
1. **Repository structure**
   - Add directories:
     - `apps/gridlock/` (Flutter app)
     - `docs/` (PRD/SPEC)
     - `design/adr/` (ADRs)
     - `prompts/` (optional, agent prompts)
2. **Docs**
   - Add `docs/PRD.md` (from Gridlock_PRD_v0_4.md)
   - Add `docs/SPEC.md` (from Gridlock_SPEC_v0_1.md)
3. **ADRs & Templates (must-have)**
   - Add `design/adr/README.md` and `design/adr/0000-template.md`
   - Add PR template with “ADR needed?” checkbox
   - Add Issue templates (`.github/ISSUE_TEMPLATE/`) for bugs, features, and ADR proposals
4. **CI (minimum)**
   - `flutter --version`
   - `flutter pub get`
   - `flutter analyze`
   - `flutter test`
5. **Quality gates**
   - Add formatting/lint rules (Dart/Flutter defaults acceptable)
   - Add `THIRD_PARTY_NOTICES.md` placeholder for dependency/license tracking
   - Add `CODEOWNERS` to enforce reviews on critical paths (e.g., `design/adr/`)
6. **Community & Project Governance**
   - Add `LICENSE` (Apache 2.0 based on distribution requirements)
   - Add `CONTRIBUTING.md` (developer workflow, branching strategy)
   - Add `CODE_OF_CONDUCT.md`
   - Add `SECURITY.md` (vulnerability reporting policy)
   - Add `CHANGELOG.md` (versioning and release notes)

### Acceptance (Phase 0)
- CI runs on PR and main branch.
- ADR policy exists and is referenced by PR template.
- Docs are present and referenced by AGENTS.md.
- Key governance files (LICENSE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CHANGELOG, CODEOWNERS, Issue Templates) are present.

---

## Phase 1 — ADRs + core architecture “spikes” (must do before feature coding)
**Outcome:** The hard decisions are documented and a minimal engine path is proven on desktop.

### Work items
1. **ADR-0001: DecentDB Flutter binding strategy**
   - Decide: FFI + (C ABI vs C shim around Nim API) + packaging approach
2. **ADR-0002: Results paging/streaming contract**
   - Decide: cursor/page APIs, default page sizes, cancellation semantics
3. **Spike: “Hello DecentDB”**
   - Implement minimal binding scaffold (no UI polish needed):
     - open DB
     - execute SQL
     - query with paging (even if stubbed)
     - error propagation
4. **Spike: Cross-platform packaging check**
   - Validate dynamic library discovery on:
     - Windows
     - macOS
     - Linux

### Acceptance (Phase 1)
- ADR-0001 and ADR-0002 are **Accepted** (or at least Proposed with clear next steps).
- A minimal CLI/test harness (or Flutter integration test) can run `SELECT 1` against DecentDB on each OS target.

---

## Phase 2 — Primary UX loop: Drag-drop → Wizard scaffold
**Outcome:** The app demonstrates the primary user journey end-to-end with mocked import execution (if needed).

### Work items
1. Desktop drag-and-drop handler (single-file for MVP)
2. File type detection by extension
3. Wizard scaffold with stepper:
   - Source → Target DecentDB → Preview → Transforms → Execute → Summary
4. Wizard state machine/controller + validation
5. Manual test checklist + integration test: drop `.xlsx` → wizard opens

### Acceptance (Phase 2)
- Dropping:
  - DecentDB file opens workspace
  - Excel/SQLite/SQL dump launches wizard
- Multi-drop shows warning and uses first file.

---

## Phase 3 — Query tabs + results grid (real engine path)
**Outcome:** Real query execution with paging into a responsive results grid.

### Work items
1. Multi-tab editor with per-tab results pane
2. Query run/stop with immediate running state
3. Paging-backed results data source
4. Virtualized grid integration
5. Export scaffold (CSV first, others stubbed behind flags)

### Acceptance (Phase 3)
- Run `SELECT ...` and see first page quickly; scroll loads more.
- No UI freeze for large results.
- Errors show in an error panel with “copy details.”

---

## Phase 4 — First import end-to-end (SQLite priority)
**Outcome:** Real import from SQLite into DecentDB with transforms.

### Work items
1. SQLite reader and schema extraction
2. Type mapping to DecentDB native types + override UI
3. Rename columns + computed columns (MVP “basic”)
4. Transactional import + summary report
5. Fixture-based integration test: import sample SQLite → row counts match

### Acceptance (Phase 4)
- Drop SQLite file → wizard → import → schema browser shows tables → query → export.

---

## Phase 5 — Excel import end-to-end
Same structure as Phase 4 but for Excel (streaming + inference edge cases).

---

## Phase 6 — Must-have SQL experience features
**Outcome:** Autocomplete, snippets, formatter are production-ready.

### Work items
1. Schema-aware autocomplete (context aware)
2. Snippets stored in TOML + UI to insert
3. Deterministic SQL formatter + golden tests

---

## Phase 7 — Export formats (JSON, Parquet, Excel)
**Outcome:** Export pipeline supports all MVP formats with correct type mapping and performance.

---

## Phase 8 — Optional MVP-lite SQL dump import
**Outcome:** MariaDB/MySQL-style `.sql` dump import for common patterns, with clear warnings for skipped statements.

---

## Notes
- Keep slices small; each phase can be broken into multiple PRs.
- Create ADRs whenever choosing a major library (grid/editor/parquet/excel/formatter/autocomplete).
