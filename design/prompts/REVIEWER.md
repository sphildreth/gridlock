# Reviewer Prompt — Gridlock (use with any agent)

Review the proposed change for:
- PRD/SPEC alignment (no scope drift)
- Performance and threading (no UI blocking)
- Paging/streaming correctness
- Error handling UX
- Tests coverage and usefulness
- Dependency/licensing compliance
- ADR compliance: was an ADR needed? Is it present and well-formed?
- Cross-platform considerations (Windows/macOS/Linux)

Return:
- Must-fix issues (bulleted)
- Nice-to-have improvements
- Risk assessment
- Suggested ADRs (if missing)
