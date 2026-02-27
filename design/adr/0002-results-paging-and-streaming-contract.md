# 0002-results-paging-and-streaming-contract

- **Status:** Proposed
- **Date:** 2026-02-27
- **Decision owners:** Gridlock maintainers
- **Related:** ADR-0001 (binding strategy), SPEC (results grid + paging)

## Decision
Gridlock will use a **cursor-based paging/streaming** model for query results:

- Opening a query returns a **cursor handle**.
- The UI fetches results in **pages** (batches) of rows.
- The results grid consumes pages incrementally and virtualizes display.
- A global default **page size** is configurable (TOML), and can be overridden per-tab.
- Query cancellation is **best-effort** and must immediately update UI state even if engine cancellation is delayed.

## Rationale
- Prevents memory blowups on large result sets.
- Enables responsive UI: show first rows quickly and keep scrolling smooth.
- Aligns with “non-annoying” performance goal and desktop expectations.
- Works naturally with Flutter isolates/background threads.

## Alternatives considered
1. **Load-all results into memory**
   - Simple but fails for large datasets; unacceptable for “power user” workloads.
2. **Server-side pagination only (OFFSET/LIMIT rewrite)**
   - Requires query rewriting; can be incorrect/slow for complex queries.
   - Still needs streaming to avoid blocking on first page in some cases.
3. **Reactive streaming row-by-row**
   - Fine-grained but higher overhead; paging is usually more efficient for UI rendering.

## Trade-offs
- Cursor lifecycle must be managed carefully (close cursors, release memory).
- Some exports may need to iterate all pages; must be done off UI thread.
- Total row count may be unknown; UX should not depend on knowing total.

## Contract (normative)
### Cursor lifecycle
1. `query_open(sql, options) -> cursor`
2. Repeat:
   - `query_next(cursor, page_size) -> {columns, rows, done}`
3. `query_close(cursor)` always called on completion or error.

### Page size
- Default: 1,000 rows (tunable).
- UI may adapt page size based on column count and row width (optional).
- “Max rows” guard exists to prevent accidental huge exports in interactive mode (configurable).

### Cancellation
- UI “Stop” immediately:
  - sets tab state to “cancelling…”
  - prevents additional paging calls
  - closes cursor when possible
- Engine cancellation:
  - best-effort request via binding
  - if engine cannot cancel, the UI must still regain responsiveness and allow the user to continue working (open a new tab, etc.)

### Error model
- Errors returned with:
  - message
  - optional SQL location
  - engine error code (if available)
- UI must provide “Copy error details.”

## Implementation notes (non-normative)
- Execute query/paging in a background isolate; post pages back to UI via streams.
- Grid should request next page on scroll threshold (prefetch).
- Export should consume cursor pages directly (no intermediate full materialization).

## References
- SPEC v0.1 sections: SQL editor, results grid, export
- ADR-0001 binding strategy
