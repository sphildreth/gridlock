# Flutter Instructions — Gridlock

## Goals
- Desktop-first Flutter app (Windows/macOS/Linux)
- Fast, responsive UX with heavy work off the UI thread
- Clean architecture: feature modules, testable services

## Technical constraints
- Apache 2.0 compatible dependencies only
- Prefer Riverpod for state management (or document alternative via ADR)
- Results must be paginated/virtualized; never load full datasets into memory by default
- Configuration stored in TOML

## Required features to implement (MVP)
- Drag-and-drop file open/import (single-file drop)
- Import Wizard (Excel, SQLite, `.sql` dump MVP-lite) with transforms:
  - rename columns, computed columns, type overrides (DecentDB native types)
- Schema browser matches DecentDB-supported objects
- SQL editor:
  - multi tabs + per-tab results
  - schema-aware autocomplete
  - snippets
  - SQL formatter
- Results grid with paging/virtualization
- Export: CSV, JSON, Parquet, Excel
- ADR process enforced

## Flutter implementation guidance
### Threading / async
- Use isolates for parsing large files and exporting large result sets.
- For native DecentDB calls, prefer running queries on a background isolate with message passing.
- Never block build/layout with synchronous work.

### UI composition
- Keep widgets dumb; push logic into controllers/providers.
- Use separate controllers for:
  - WorkspaceController
  - ImportWizardController
  - QueryTabController
  - SchemaBrowserController
  - ExportController

### State management
- Riverpod recommended:
  - Providers for engine instance, workspace state, schema cache
  - AsyncNotifier for long-running actions with cancellation tokens

### Error handling
- Surface errors in UX:
  - Inline validation in wizard
  - Error panel in result tab
  - Toast/snackbar for transient errors
- Always include a “Copy error details” action.

### Testing
- Unit test all import mapping and transform logic.
- Golden tests for SQL formatting.
- Integration tests for: drop -> wizard -> import -> query -> export.

## ADR triggers
Create an ADR if you:
- Choose a specific grid/editor widget package
- Choose the SQL formatter/autocomplete engine
- Choose export libraries (Parquet/Excel)
- Lock in binding strategy (FFI details)
