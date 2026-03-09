# Decent Bench

> The GUI for DecentDB — Because perfection is overrated.

Decent Bench is a cross-platform desktop app (Flutter) for power users who need
to **open DecentDB files**, **import data into DecentDB**, **inspect schema**,
run fast **SELECT-style queries**, and **export shaped results**.

## Project status

**Pre-alpha / docs-first.** This repository currently contains the product
requirements, specification, ADRs, and an initial placeholder app directory.
The Flutter app folder exists under `apps/decent-bench/`, but there is **not
yet a runnable Flutter project scaffold**.

Current source-of-truth documents:

- Product requirements: `docs/PRD.md`
- Product specification: `docs/SPEC.md`
- Engineering plan: `design/IMPLEMENTATION_PHASES.md`
- Architecture decisions: `design/adr/`
- Repo workflow and constraints: `AGENTS.md`

If you want to contribute right now, the highest-value work is usually:

- tightening MVP requirements in `docs/SPEC.md`
- creating or refining ADRs in `design/adr/`
- landing the first runnable Flutter + DecentDB scaffold
- adding CI for `flutter analyze` and `flutter test`

## MVP at a glance

The current MVP is intentionally narrower than the long-term product vision.

### MVP includes

- Drag-and-drop a file:
  - DecentDB file → open immediately
  - supported import source → open Import Wizard
- Open/create a local DecentDB file
- Import sources:
  - Excel (`.xls`, `.xlsx`)
  - SQLite (`.db`, `.sqlite`, `.sqlite3`)
  - MariaDB/MySQL-style `.sql` dumps (**MVP-lite**)
- Import transforms before commit:
  - rename columns
  - type overrides
  - basic computed columns
- Schema browser for the **pinned DecentDB feature surface required by MVP**
- SQL editor with:
  - multiple tabs
  - per-tab results
  - run/stop query
  - schema-aware autocomplete
  - snippets
  - deterministic formatter
- Results grid backed by paging/streaming
- Export query results to:
  - CSV (**required MVP format**)
- TOML configuration
- ADR-driven architecture decisions from day one

### Explicitly not MVP

- Postgres custom-format backup import
- External databases as first-class query targets
- Collaboration or multi-user features
- Full migration tooling
- Multiple DecentDB workspaces open simultaneously

### Planned after MVP

- Additional export formats such as JSON, Parquet, and Excel
- Additional import connectors
- Richer workflow and workspace features

## Repository layout

```text
apps/decent-bench/              Flutter desktop app (placeholder today)
docs/                           Product docs (PRD, SPEC)
design/adr/                     Architecture Decision Records
design/IMPLEMENTATION_PHASES.md Delivery sequencing and milestones
THIRD_PARTY_NOTICES.md          Third-party attribution tracking
LICENSE                         Apache 2.0 license
AGENTS.md                       Repo workflow and guardrails
```

## Architecture direction

At a high level, Decent Bench is expected to consist of:

1. **Flutter desktop UI shell**
2. **DecentDB integration via Dart FFI**
3. **Import pipeline** for supported source formats
4. **Results paging/streaming pipeline**
5. **Export pipeline**
6. **Config + secrets handling**
7. **ADR-governed technical decisions**

See:

- `docs/SPEC.md` for behavior and structure
- `design/adr/0001-decentdb-flutter-binding-strategy.md`
- `design/adr/0002-results-paging-and-streaming-contract.md`

## Onboarding for contributors

### Prerequisites

- Flutter (stable) with desktop tooling enabled for your OS
- Git

> Note: until the Flutter scaffold lands in `apps/decent-bench/`, you will not
> be able to run `flutter pub get`, `flutter analyze`, or `flutter test` in the
> app directory.

### Read first

1. `docs/PRD.md` — what we are building and why
2. `docs/SPEC.md` — implementable behavior and scope
3. `design/IMPLEMENTATION_PHASES.md` — sequencing and near-term milestones
4. `AGENTS.md` — repo rules, especially performance and scope control

### ADR workflow

We require ADRs for lasting architectural or product-impacting choices.

Typical ADR topics include:

- DecentDB binding strategy
- paging and streaming behavior
- import type mapping rules
- export library selection
- credential storage strategy

To create an ADR:

1. Read `design/adr/README.md`
2. Copy `design/adr/0000-template.md`
3. Save the next numbered file in `design/adr/`

## Development workflow

Once the app scaffold exists, expected commands from `apps/decent-bench/` are:

```bash
flutter --version
flutter doctor -v

flutter pub get
flutter analyze
flutter test
flutter test integration_test

# Run on desktop (pick one)
flutter run -d linux
flutter run -d macos
flutter run -d windows
```

## Contribution guidance

Until the first runnable app scaffold is merged, contributions are especially
welcome in:

- clarifying MVP behavior in `docs/SPEC.md`
- aligning `docs/PRD.md` and `docs/SPEC.md`
- writing and accepting ADRs
- adding the initial Flutter project scaffold
- adding CI that runs analysis and tests

When submitting changes:

- keep changes small and testable
- avoid UI-thread-heavy work
- prefer paging/streaming over full materialization
- do not add dependencies that are incompatible with Apache 2.0 distribution
- update `THIRD_PARTY_NOTICES.md` when required

## License

Decent Bench is licensed under the Apache License 2.0. See `LICENSE`.

## Third-party notices

See `THIRD_PARTY_NOTICES.md` for dependency attributions and license tracking.