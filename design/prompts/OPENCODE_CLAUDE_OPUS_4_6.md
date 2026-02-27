# OpenCode Instructions — Claude Opus 4.6

Claude is the primary “design + implementation” agent for substantial slices.

## Expectations
- Start with a small plan and call out ADR needs.
- Prefer robust, maintainable architecture over quick hacks.
- Keep UI snappy; isolate heavy work.
- Provide code + tests + docs updates.

## Output format
1. Plan
2. Files changed (with brief rationale)
3. Key code snippets
4. Test commands
5. Manual verification checklist
6. ADR(s) added (if any)

## When to create ADRs
If any of these are decided/changed:
- DecentDB binding strategy details (ABI/shim/packaging)
- Paging/cursor contract and cancellation model
- Export library choice for Parquet/Excel
- Autocomplete/formatter approach
