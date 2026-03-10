# 0013-external-toml-theme-system

- **Status:** Proposed
- **Date:** 2026-03-10
- **Decision owners:** Decent Bench maintainers
- **Related:** UI/UX shell, configuration system, appearance settings

## Decision

Decent Bench will implement theming as an **external TOML-based theme system** with:

- a configurable **themes directory**
- **one TOML file per theme**
- compatibility metadata
- semantic theme tokens
- built-in fallback themes

The theme system must support styling the **entire application**, including:

- menus
- toolbars
- status bar
- side panes
- results grids
- dialogs/forms
- buttons
- SQL editor surfaces
- SQL syntax colors

## Rationale

- Decent Bench is a desktop-first workbench where themes materially affect usability.
- A TOML-based system is readable, hand-editable, and fits the broader configuration direction of the project.
- External theme files make user customization and sharing straightforward.
- Semantic tokens provide a stable abstraction between theme files and Flutter widget implementation.
- Compatibility metadata allows the app to reject or warn on incompatible themes as the UI evolves.

## Alternatives considered

### 1. Hardcoded themes only
- Pros: simplest implementation
- Cons: poor user customization, difficult to share/import themes, not aligned with project goals

### 2. JSON or YAML theme files
- Pros: widely known serialization formats
- Cons: TOML is cleaner for human-edited configuration and matches project preference

### 3. Direct widget-level color config without semantic tokens
- Pros: quick to start
- Cons: brittle, hard to evolve, leaks implementation detail into theme files

### 4. Database-backed theme definitions
- Pros: central management
- Cons: unnecessary complexity for a desktop app; weak fit for theme sharing and file-based customization

## Trade-offs

- External TOML themes require validation and fallback logic.
- A wide token surface increases initial theme-model design effort.
- Maintaining backward compatibility for themes will require discipline as UI components evolve.

These trade-offs are acceptable because theming is expected to be a long-lived, user-visible capability.

## Implementation notes (non-normative)

### Config
Main config should include:
- active theme id
- themes directory

Example:

```toml
[appearance]
active_theme = "classic-dark"
themes_dir = "/home/user/.config/decent-bench/themes"
```

### Theme metadata
Each theme should include:
- `name`
- `id`
- `version`

### Compatibility
Each theme should include:
- `compatibility.min_decent_bench_version`
- optional `compatibility.max_decent_bench_version`

### Required behavior
- missing theme directory must not break startup
- invalid theme files must not break startup
- missing keys fall back to defaults
- unknown keys are ignored with warnings
- built-in themes are always available

### SQL editor theming
The theme model must explicitly support editor surfaces and SQL syntax tokens.

## References

- Decent Bench theme system design document
- Project TOML configuration direction
