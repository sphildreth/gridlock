## Database-Backed Application Logging
**Date:** 2026-03-10
**Status:** Accepted

### Decision

Decent Bench will persist structured application logs into a dedicated
DecentDB database file named `decent-bench-log.ddb` in the app support/config
directory.

The logging subsystem will:

- create and maintain the log database on app startup
- write structured records into an `app_logs` table
- support configurable verbosity in `config.toml`
- keep logging failures non-fatal to normal app startup and workflows
- record SQL timing entries with database path, SQL text, returned row count,
  rows affected when relevant, and elapsed time in nanoseconds

### Rationale

The workbench now has multiple cross-cutting subsystems: theme discovery,
desktop shell state, workspace persistence, imports, exports, and SQL
execution. Troubleshooting those workflows is materially easier when the app has
a single durable, queryable log store instead of ad-hoc console messages.

Using a DecentDB log database fits the product direction and keeps operational
diagnostics inspectable with the same query tooling the app already centers.

### Alternatives Considered

- Console-only logging via `debugPrint`
- Flat-file text logs
- Per-workspace logs stored inside the active database

### Trade-offs

- Logging introduces another durable file in the app support directory
- Query timing logs for paged result sets are best-effort and represent the
  first page and final visible completion milestones available in the current
  cursor model
- The logger must remain defensive so log-write failures never block startup or
  user operations

### References

- `design/PRD.md`
- `design/SPEC.md`
- `apps/decent-bench/lib/app/logging/app_logger.dart`
- `apps/decent-bench/lib/app/app.dart`
- `apps/decent-bench/lib/features/workspace/application/workspace_controller.dart`
- `apps/decent-bench/lib/features/workspace/domain/app_config.dart`
