# Copilot CLI Instructions — Gridlock

Use Copilot CLI for fast incremental coding tasks and refactors.

## How to run tasks
- Prefer small diffs; finish in < ~300 LOC per PR unless necessary.
- Always include:
  - What you changed
  - How to run tests
  - Manual verification steps

## Prompts style
- Reference specific files and acceptance criteria.
- Ask Copilot CLI to produce:
  - Implementation + tests
  - A short checklist
  - Any new dependencies with license note

## Example
“Implement drag-and-drop handler on desktop and launch Import Wizard for .xlsx files. Add unit tests for file type detection and an integration test that verifies wizard opens.”
