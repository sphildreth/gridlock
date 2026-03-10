# Decent Bench — Theme System Design

## Overview

Decent Bench should implement theming as a **first-class, file-based system** built around:

- a configured **themes directory**
- **one TOML file per theme**
- a typed **theme token model** in code
- a **theme loader + validator**
- built-in fallback themes
- compatibility metadata to ensure themes only load on supported Decent Bench versions
- full support for **SQL editor syntax theming**

The goal is to make themes:

- easy to install
- easy to share
- easy to validate
- resilient to app evolution
- powerful enough to style the entire application

This is especially important for Decent Bench because it is a **desktop workbench** where users are likely to prefer dense, classic, high-contrast, or highly personalized visual styles.

---

## Goals

The theme system should support:

1. **Full application theming**
   - menus
   - toolbars
   - status bar
   - side panels
   - properties/details views
   - SQL editor
   - results grid
   - dialogs/forms
   - buttons
   - borders, hover states, focus states, selection states

2. **Full SQL syntax theming**
   - keywords
   - strings
   - numbers
   - comments
   - functions
   - types
   - parameters
   - constants
   - identifiers
   - operators
   - errors
   - editor background/selection/cursor/gutter/current line

3. **Version compatibility**
   - theme version
   - minimum Decent Bench version
   - optional maximum Decent Bench version

4. **Safe fallback behavior**
   - invalid theme files do not break startup
   - missing keys fall back to built-in defaults
   - unknown keys are ignored with warnings

5. **User-extensible themes**
   - users can drop a `.toml` file into the configured themes directory
   - Decent Bench discovers it and offers it in the theme picker

---

## Configuration

The main application configuration should include appearance and theme discovery settings.

Example:

```toml
[appearance]
active_theme = "classic-dark"
themes_dir = "/home/steven/.config/decent-bench/themes"
```

### Behavior
- If `themes_dir` is set, Decent Bench scans that directory for `*.toml`.
- If `themes_dir` is not set, Decent Bench uses an OS-specific default theme folder:
  - Linux: `~/.config/decent-bench/themes`
  - Windows: `%AppData%/Decent Bench/themes`
  - macOS: `~/Library/Application Support/Decent Bench/themes`
- Built-in themes must always be available even if the external folder is missing or empty.

---

## One file per theme

Each theme should be defined as a **single TOML file** initially.

That keeps themes easy to:
- inspect
- diff
- version control
- share
- install manually

Recommended layout:

```text
themes/
  classic-dark.toml
  classic-light.toml
  purple-night.toml
```

Later, if Decent Bench needs theme previews or assets, the format can evolve toward a directory-based theme package. But single-file TOML is the right starting point.

---

## Theme metadata

Each theme file should include top-level metadata.

### Required
- `name`
- `id`
- `version`

### Recommended
- `author`
- `description`

Example:

```toml
name = "Classic Dark"
id = "classic-dark"
version = "1.0.0"
author = "Decent Bench"
description = "A dense, classic dark theme for desktop-heavy database work."
```

---

## Compatibility metadata

Each theme should define the Decent Bench versions it supports.

Example:

```toml
[compatibility]
min_decent_bench_version = "0.1.0"
max_decent_bench_version = "0.9.x"
```

### Recommended rules
- `min_decent_bench_version` should be required
- `max_decent_bench_version` should be optional
- If app version is below minimum: reject theme
- If app version is above maximum: warn or reject depending on policy
- If compatibility block is missing: warn and treat as incompatible or only allow for trusted/built-in themes

This prevents old themes from silently mis-styling newer UI elements.

---

## Theme token strategy

Do **not** let widgets read raw TOML keys directly.

Instead:

1. parse TOML into a typed theme model
2. expose **semantic tokens**
3. let widgets consume the semantic tokens

Example semantic token names in code:
- `windowBackground`
- `panelBackground`
- `menuTextColor`
- `statusBarBackground`
- `resultsGridHeaderBackground`
- `sqlKeywordColor`

This makes the theme system maintainable as the UI grows.

---

## Recommended theme sections

A practical first version should include these sections:

- metadata (top level)
- compatibility
- base
- colors
- menu
- toolbar
- status_bar
- sidebar
- properties
- editor
- results_grid
- dialog
- buttons
- sql_syntax
- fonts
- metrics

These are enough to fully style the app.

---

## Example theme file shape

```toml
name = "Classic Dark"
id = "classic-dark"
version = "1.0.0"
author = "Decent Bench"
description = "A dense, classic dark desktop theme inspired by traditional database tools."

[compatibility]
min_decent_bench_version = "0.1.0"
max_decent_bench_version = "0.9.x"

[base]
brightness = "dark"

[colors]
window_bg = "#1E1E1E"
panel_bg = "#252526"
panel_alt_bg = "#2D2D30"
surface_bg = "#2A2A2A"
overlay_bg = "#333337"
border = "#3F3F46"
border_strong = "#5A5A66"
text = "#E5E5E5"
text_muted = "#A8A8A8"
text_disabled = "#6E6E6E"
accent = "#7C5CFF"
accent_hover = "#947BFF"
accent_active = "#6246EA"
selection = "#3A3D41"
focus_ring = "#A78BFA"
error = "#E05A5A"
warning = "#D9A441"
success = "#57B36A"
info = "#4FA3D9"
```

---

## SQL syntax theming

Because Decent Bench is a SQL-first desktop workbench, syntax theming should be an explicit, dedicated section.

Recommended SQL syntax tokens:

- `keyword`
- `identifier`
- `string`
- `number`
- `comment`
- `operator`
- `function`
- `type`
- `parameter`
- `constant`
- `error`

Recommended editor-specific tokens:

- `editor.bg`
- `editor.text`
- `editor.gutter_bg`
- `editor.gutter_text`
- `editor.current_line_bg`
- `editor.selection_bg`
- `editor.cursor`
- `editor.whitespace`
- `editor.indent_guide`
- `editor.tab_active_bg`
- `editor.tab_inactive_bg`
- `editor.tab_hover_bg`
- `editor.tab_active_text`
- `editor.tab_inactive_text`

This makes the editor fully controllable without mixing SQL syntax colors into general UI colors.

---

## Fonts and density

Themes should not be limited to color.

The theme system should also support:

### Fonts
- UI font family
- editor font family
- UI font size
- editor font size
- line height

### Density / metrics
- border radius
- pane padding
- control height
- splitter thickness
- icon size

This allows themes like:
- Classic Dense
- Classic Light
- High Contrast
- Spacious Modern
- Retro Terminal-inspired

---

## Validation behavior

The theme loader should validate:

### Required metadata
- `name`
- `id`
- `version`
- `compatibility.min_decent_bench_version`

### Color formats
Accept:
- `#RRGGBB`
- `#AARRGGBB`

### Numeric values
Validate sane ranges for:
- font sizes
- line height
- border radius
- splitter thickness
- icon size

### Unknown keys
Ignore with warning.

### Missing keys
Fall back to built-in defaults.

### Invalid theme
Reject gracefully and load a fallback theme.

---

## Built-in fallback themes

Decent Bench should ship with at least:

- `Classic Dark`
- `Classic Light`

If the user-selected theme fails validation or compatibility checks:
- log the issue
- show a friendly warning in UI if appropriate
- fall back to a built-in theme

A theme must never prevent the app from launching.

---

## Suggested architecture

Recommended services/classes:

### AppConfig
Stores:
- active theme id
- themes directory path

### ThemeDiscoveryService
- scans theme directory
- discovers `.toml` files
- lists available theme candidates

### ThemeParser
- parses TOML
- maps file contents to typed theme model

### ThemeValidator
- validates required fields
- validates compatibility
- validates colors and numeric ranges

### DecentBenchTheme
- strongly typed in-memory theme model
- source of truth for widgets

### ThemeManager
- loads active theme
- falls back when needed
- exposes current theme to app
- persists selected theme

---

## Future enhancements

Not required for first release, but worth planning for:

- theme inheritance via `extends = "classic-dark"`
- theme preview thumbnails
- theme packages with asset folders
- icon theme packs
- live theme reloading
- in-app theme editor
- export current theme
- import theme bundle

---

## Recommendation

The theme system should be treated as a real subsystem, not a bag of colors.

The right approach is:

- configured themes directory
- one TOML file per theme
- semantic tokens
- compatibility metadata
- validator + fallback behavior
- full SQL syntax theming
- font + density support

This gives Decent Bench a sustainable, extensible, user-friendly theming foundation.
