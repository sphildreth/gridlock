# 0002-results-paging-and-streaming-contract

- **Status:** Accepted
- **Date:** 2026-02-27
- **Decision owners:** Decent Bench maintainers
- **Related:** ADR-0001 (binding strategy), SPEC (results grid + paging)

## Decision
Decent Bench will use a **cursor-based paging/streaming** model for query
results:

- Opening a query returns a **cursor handle**.
- The UI fetches results in **pages** (batches) of rows.
- The results grid consumes pages incrementally and virtualizes display.
- A global default **page size** is configurable (TOML), and can be
  overridden per-tab.
- Query cancellation is **best-effort** and must immediately update UI state
  even if engine cancellation is delayed.

## Rationale
- Prevents memory blowups on large result sets.
- Enables responsive UI: show first rows quickly and keep scrolling smooth.
- Aligns with the “non-annoying” performance goal and desktop expectations.
- Works naturally with Flutter isolates/background threads.
- Supports export pipelines that iterate over results without full
  materialization.

## Alternatives considered
1. **Load-all results into memory**
   - Simple but fails for large datasets; unacceptable for power-user
     workloads.
2. **Server-side pagination only (OFFSET/LIMIT rewrite)**
   - Requires query rewriting; can be incorrect or slow for complex queries.
   - Still needs streaming to avoid blocking on first page in some cases.
3. **Reactive streaming row-by-row**
   - Fine-grained but higher overhead; paging is usually more efficient for UI
     rendering and export throughput.

## Trade-offs
- Cursor lifecycle must be managed carefully to avoid leaked handles or stale
  buffers.
- Some exports must iterate all pages and therefore must run off the UI thread.
- Total row count may be unknown; UX cannot depend on always knowing it.
- Cancellation may not stop engine work immediately, so the app must separate
  UI responsiveness from engine termination timing.

## Contract (normative)

### Cursor lifecycle
1. `query_open(sql, options) -> cursor`
2. Repeat:
   - `query_next(cursor, page_size) -> {columns, rows, done}`
3. `query_close(cursor)` is always called on completion, cancellation, or
   error.

### Page size
- Default: **1,000 rows**.
- Configurable globally in TOML.
- Overridable per-tab/query.
- UI may adapt page size based on row width and column count as an
  implementation detail.

### Cancellation
- When the user presses **Stop**, the UI immediately:
  - sets the tab state to `cancelling`
  - disables additional paging requests for that execution
  - ignores late-arriving pages for that execution
  - attempts cursor close / engine cancellation through the binding
- If engine cancellation is delayed or unsupported:
  - the tab must still return control to the user
  - the user must be able to switch tabs, open a new tab, and continue working
  - the cancelled execution must not block unrelated work in the UI

### Error model
Errors returned from query open or page fetch should include:
- message
- optional SQL location
- engine error code (if available)

The UI must support **Copy error details**.

### Result ownership
- A tab owns the cursor and all state for its active execution.
- Starting a new execution in the same tab invalidates any previous active
  cursor for that tab.
- Export should consume pages through the same paging contract, but must not
  require full in-memory materialization.

## Implementation notes (non-normative)
- Execute query open and paging in a background isolate or native background
  thread.
- Post page results back to the UI through a stream or equivalent async event
  channel.
- Grid should prefetch the next page when scroll position reaches a threshold.
- Exports should read directly from cursor pages where possible.
- Late events from cancelled or superseded executions should be discarded using
  an execution token or generation counter.

## Consequences
- The results grid, export pipeline, and query controller can share a single
  paging mental model.
- The binding layer must expose cursor lifecycle, page fetch, structured
  errors, and best-effort cancellation.
- Product UX must tolerate unknown total row counts and delayed cancellation.

## References
- SPEC v0.1 sections: SQL editor, results grid, export
- ADR-0001 binding strategy