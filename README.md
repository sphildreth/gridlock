# Gridlock

> The GUI for DecentDB — Because perfection is overrated.

Gridlock is a cross-platform desktop app (Flutter) that helps power users
**import data into DecentDB**, **inspect schema**, run fast **SELECT-style
queries**, and **export shaped results**.

## Project status

**Pre-alpha / docs-first.** Today this repository contains the product
requirements/specification and initial ADRs. The Flutter app folder exists
under `apps/gridlock/`, but it is currently a placeholder (no runnable Flutter
project scaffold yet).

- Product docs: `docs/PRD.md`, `docs/SPEC.md`
- Engineering plan: `design/IMPLEMENTATION_PHASES.md`
- ADRs: `design/adr/`

If you want to contribute right now, the highest-value work is usually:
improving the SPEC, adding/accepting ADRs, and landing the first runnable
Flutter + native binding scaffold.

## Goals (MVP)

From the PRD/SPEC, Gridlock’s MVP targets:

- Drag-and-drop a file:
	- DecentDB file → open
	- otherwise → Import Wizard
- Import sources: Excel, SQLite, MariaDB/MySQL-style `.sql` dumps (MVP-lite)
- Schema browser reflecting everything DecentDB supports
- SQL editor with tabs + per-tab results
- Results grid backed by paging/streaming (no full materialization by default)
- Export results: CSV, JSON, Parquet, Excel
- TOML configuration

## Repository layout

```
apps/gridlock/          Flutter desktop app (placeholder today)
docs/                   Product docs (PRD, SPEC)
design/adr/             Architecture Decision Records
design/IMPLEMENTATION_PHASES.md
THIRD_PARTY_NOTICES.md
LICENSE
```

## Onboarding (contributors)

### Prerequisites

- Flutter (stable) with desktop tooling enabled for your OS
- Git

> Note: until the Flutter project scaffold lands in `apps/gridlock/`, you won’t
> be able to run `flutter pub get`, `flutter analyze`, or `flutter test`.

### Read first

1. `docs/PRD.md` — what we’re building and why
2. `docs/SPEC.md` — implementable requirements (source of truth for behavior)
3. `AGENTS.md` — repo rules (performance-first, ADRs, no scope drift)

### How decisions get made (ADRs)

We require ADRs for lasting/architectural choices (binding strategy, paging
contract, import type mapping, exporter libraries, etc.).

- Read: `design/adr/README.md`
- Create: copy `design/adr/0000-template.md` to the next numbered ADR

### Development workflow (once app scaffold exists)

From `apps/gridlock/`:

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

## Contributing

Until the first runnable app scaffold is merged, contributions are especially
welcome in:

- Tightening up `docs/SPEC.md` into clear, testable requirements
- Writing/accepting ADRs in `design/adr/`
- Adding the initial Flutter project scaffold under `apps/gridlock/`
- Adding CI that runs `flutter analyze` + `flutter test`

When submitting code changes:

- Keep PRs small and testable.
- Don’t introduce UI-thread-heavy work; use isolates/background threads.
- Don’t add dependencies that aren’t Apache-2.0 compatible; update
	`THIRD_PARTY_NOTICES.md` when you add any.

## License

Gridlock is licensed under the Apache License 2.0. See `LICENSE`.

## Third-party notices

See `THIRD_PARTY_NOTICES.md` for dependency attributions.
