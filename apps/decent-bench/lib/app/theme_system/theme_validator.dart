import 'package:flutter/material.dart';

import '../app_metadata.dart';
import 'decent_bench_theme.dart';
import 'theme_parser.dart';
import 'theme_utils.dart';

class ThemeValidationResult {
  const ThemeValidationResult._({
    required this.theme,
    required this.warnings,
    required this.error,
  });

  const ThemeValidationResult.success(
    DecentBenchTheme theme,
    List<String> warnings,
  ) : this._(theme: theme, warnings: warnings, error: null);

  const ThemeValidationResult.failure(String error, List<String> warnings)
    : this._(theme: null, warnings: warnings, error: error);

  final DecentBenchTheme? theme;
  final List<String> warnings;
  final String? error;

  bool get isSuccess => theme != null;
}

class ThemeValidator {
  const ThemeValidator({this.appVersion = kDecentBenchVersion});

  static const Set<String> _topLevelKeys = <String>{
    'name',
    'id',
    'version',
    'author',
    'description',
  };

  static const Map<String, Set<String>> _sectionKeys = <String, Set<String>>{
    'compatibility': <String>{
      'min_decent_bench_version',
      'max_decent_bench_version',
    },
    'base': <String>{'brightness'},
    'colors': <String>{
      'window_bg',
      'panel_bg',
      'panel_alt_bg',
      'surface_bg',
      'overlay_bg',
      'border',
      'border_strong',
      'text',
      'text_muted',
      'text_disabled',
      'accent',
      'accent_hover',
      'accent_active',
      'selection',
      'focus_ring',
      'error',
      'warning',
      'success',
      'info',
    },
    'menu': <String>{
      'bg',
      'text',
      'text_muted',
      'item_hover_bg',
      'item_active_bg',
      'separator',
      'icon',
      'shortcut',
    },
    'toolbar': <String>{
      'bg',
      'button_bg',
      'button_hover_bg',
      'button_active_bg',
      'button_text',
      'button_icon',
    },
    'status_bar': <String>{
      'bg',
      'text',
      'border_top',
      'success',
      'warning',
      'error',
    },
    'sidebar': <String>{
      'bg',
      'header_bg',
      'header_text',
      'item_text',
      'item_hover_bg',
      'item_selected_bg',
      'item_selected_text',
      'tree_line',
    },
    'properties': <String>{
      'bg',
      'label',
      'value',
      'section_header_bg',
      'section_header_text',
    },
    'editor': <String>{
      'bg',
      'text',
      'gutter_bg',
      'gutter_text',
      'current_line_bg',
      'selection_bg',
      'cursor',
      'whitespace',
      'indent_guide',
      'tab_active_bg',
      'tab_inactive_bg',
      'tab_hover_bg',
      'tab_active_text',
      'tab_inactive_text',
    },
    'results_grid': <String>{
      'bg',
      'header_bg',
      'header_text',
      'row_bg',
      'row_alt_bg',
      'row_hover_bg',
      'row_selected_bg',
      'row_selected_text',
      'grid_line',
      'cell_text',
      'null_text',
    },
    'dialog': <String>{
      'bg',
      'title_text',
      'body_text',
      'input_bg',
      'input_text',
      'input_border',
      'input_focus_border',
    },
    'buttons': <String>{
      'primary_bg',
      'primary_text',
      'primary_hover_bg',
      'secondary_bg',
      'secondary_text',
      'secondary_hover_bg',
      'danger_bg',
      'danger_text',
    },
    'sql_syntax': <String>{
      'keyword',
      'identifier',
      'string',
      'number',
      'comment',
      'operator',
      'function',
      'type',
      'parameter',
      'constant',
      'error',
    },
    'fonts': <String>{
      'ui_family',
      'editor_family',
      'ui_size',
      'editor_size',
      'line_height',
    },
    'metrics': <String>{
      'border_radius',
      'pane_padding',
      'control_height',
      'splitter_thickness',
      'icon_size',
    },
  };

  final String appVersion;

  ThemeValidationResult validate(
    ParsedThemeDocument document, {
    required DecentBenchTheme fallbackTheme,
    required bool isBuiltIn,
  }) {
    final warnings = <String>[...document.warnings];
    try {
      _warnOnUnknownKeys(document, warnings);

      final name = _requiredString(document.topLevel, 'name');
      final id = _requiredString(document.topLevel, 'id');
      final version = _requiredString(document.topLevel, 'version');
      if (SemanticVersion.parse(version) == null) {
        return ThemeValidationResult.failure(
          'Theme $id has an invalid version: $version',
          warnings,
        );
      }

      final compatibilitySection = document.sections['compatibility'];
      if (compatibilitySection == null) {
        if (!isBuiltIn) {
          return ThemeValidationResult.failure(
            'Theme $id is missing [compatibility].',
            warnings,
          );
        }
        warnings.add(
          'Built-in theme $id is missing [compatibility]; using fallback compatibility.',
        );
      }

      final compatibility = _resolveCompatibility(
        compatibilitySection,
        fallbackTheme.compatibility,
        themeId: id,
        isBuiltIn: isBuiltIn,
      );
      if (compatibility == null) {
        return ThemeValidationResult.failure(
          'Theme $id has invalid compatibility metadata.',
          warnings,
        );
      }

      final appSemver = SemanticVersion.parse(appVersion);
      final minSemver = SemanticVersion.parse(
        compatibility.minDecentBenchVersion,
      );
      final maxSemver = compatibility.maxDecentBenchVersion == null
          ? null
          : SemanticVersionPattern.parse(compatibility.maxDecentBenchVersion!);
      if (appSemver == null || minSemver == null) {
        return ThemeValidationResult.failure(
          'Theme $id could not be checked against app version $appVersion.',
          warnings,
        );
      }

      if (appSemver.compareTo(minSemver) < 0) {
        return ThemeValidationResult.failure(
          'Theme $id requires Decent Bench ${compatibility.minDecentBenchVersion} or newer.',
          warnings,
        );
      }
      if (maxSemver == null &&
          compatibility.maxDecentBenchVersion != null &&
          compatibility.maxDecentBenchVersion!.isNotEmpty) {
        return ThemeValidationResult.failure(
          'Theme $id has an invalid max_decent_bench_version value.',
          warnings,
        );
      }
      if (maxSemver != null && !maxSemver.contains(appSemver)) {
        return ThemeValidationResult.failure(
          'Theme $id is incompatible with Decent Bench $appVersion.',
          warnings,
        );
      }

      final brightness = _resolveBrightness(
        document.section('base'),
        fallbackTheme.brightness,
        warnings,
      );
      final colors = _buildColors(
        document.section('colors'),
        fallbackTheme.colors,
      );
      final menu = _buildMenu(document.section('menu'), fallbackTheme.menu);
      final toolbar = _buildToolbar(
        document.section('toolbar'),
        fallbackTheme.toolbar,
      );
      final statusBar = _buildStatusBar(
        document.section('status_bar'),
        fallbackTheme.statusBar,
      );
      final sidebar = _buildSidebar(
        document.section('sidebar'),
        fallbackTheme.sidebar,
      );
      final properties = _buildProperties(
        document.section('properties'),
        fallbackTheme.properties,
      );
      final editor = _buildEditor(
        document.section('editor'),
        fallbackTheme.editor,
      );
      final resultsGrid = _buildResultsGrid(
        document.section('results_grid'),
        fallbackTheme.resultsGrid,
      );
      final dialog = _buildDialog(
        document.section('dialog'),
        fallbackTheme.dialog,
      );
      final buttons = _buildButtons(
        document.section('buttons'),
        fallbackTheme.buttons,
      );
      final sqlSyntax = _buildSqlSyntax(
        document.section('sql_syntax'),
        fallbackTheme.sqlSyntax,
      );
      final fonts = _buildFonts(
        document.section('fonts'),
        fallbackTheme.fonts,
        warnings,
      );
      final metrics = _buildMetrics(
        document.section('metrics'),
        fallbackTheme.metrics,
        warnings,
      );

      return ThemeValidationResult.success(
        DecentBenchTheme(
          metadata: ThemeMetadata(
            name: name,
            id: id,
            version: version,
            author: _optionalString(document.topLevel, 'author') ?? '',
            description:
                _optionalString(document.topLevel, 'description') ?? '',
          ),
          compatibility: compatibility,
          brightness: brightness,
          colors: colors,
          menu: menu,
          toolbar: toolbar,
          statusBar: statusBar,
          sidebar: sidebar,
          properties: properties,
          editor: editor,
          resultsGrid: resultsGrid,
          dialog: dialog,
          buttons: buttons,
          sqlSyntax: sqlSyntax,
          fonts: fonts,
          metrics: metrics,
          isBuiltIn: isBuiltIn,
          sourceLabel: document.sourceLabel,
        ),
        warnings,
      );
    } on _ThemeValidationError catch (error) {
      return ThemeValidationResult.failure(error.message, warnings);
    }
  }

  void _warnOnUnknownKeys(ParsedThemeDocument document, List<String> warnings) {
    for (final key in document.topLevel.keys) {
      if (!_topLevelKeys.contains(key)) {
        warnings.add(
          'Ignoring unknown top-level key "$key" in ${document.sourceLabel}.',
        );
      }
    }

    for (final entry in document.sections.entries) {
      final allowedKeys = _sectionKeys[entry.key];
      if (allowedKeys == null) {
        warnings.add(
          'Ignoring unknown section [${entry.key}] in ${document.sourceLabel}.',
        );
        continue;
      }
      for (final key in entry.value.keys) {
        if (!allowedKeys.contains(key)) {
          warnings.add(
            'Ignoring unknown key ${entry.key}.$key in ${document.sourceLabel}.',
          );
        }
      }
    }
  }

  ThemeCompatibility? _resolveCompatibility(
    Map<String, Object?>? section,
    ThemeCompatibility fallback, {
    required String themeId,
    required bool isBuiltIn,
  }) {
    if (section == null) {
      return isBuiltIn ? fallback : null;
    }

    final minVersion = _requiredString(
      section,
      'min_decent_bench_version',
      sectionName: 'compatibility',
    );
    if (SemanticVersion.parse(minVersion) == null) {
      return null;
    }

    final maxVersion = _optionalString(section, 'max_decent_bench_version');
    if (maxVersion != null &&
        SemanticVersionPattern.parse(maxVersion) == null) {
      return null;
    }

    return ThemeCompatibility(
      minDecentBenchVersion: minVersion,
      maxDecentBenchVersion: maxVersion,
    );
  }

  Brightness _resolveBrightness(
    Map<String, Object?> section,
    Brightness fallback,
    List<String> warnings,
  ) {
    final raw = section['brightness'];
    if (raw == null) {
      return fallback;
    }
    if (raw is! String) {
      warnings.add('base.brightness must be a string; using fallback.');
      return fallback;
    }
    return switch (raw.trim().toLowerCase()) {
      'dark' => Brightness.dark,
      'light' => Brightness.light,
      _ => fallback,
    };
  }

  ThemeColors _buildColors(Map<String, Object?> section, ThemeColors fallback) {
    return ThemeColors(
      windowBg: _color(section, 'window_bg', fallback.windowBg),
      panelBg: _color(section, 'panel_bg', fallback.panelBg),
      panelAltBg: _color(section, 'panel_alt_bg', fallback.panelAltBg),
      surfaceBg: _color(section, 'surface_bg', fallback.surfaceBg),
      overlayBg: _color(section, 'overlay_bg', fallback.overlayBg),
      border: _color(section, 'border', fallback.border),
      borderStrong: _color(section, 'border_strong', fallback.borderStrong),
      text: _color(section, 'text', fallback.text),
      textMuted: _color(section, 'text_muted', fallback.textMuted),
      textDisabled: _color(section, 'text_disabled', fallback.textDisabled),
      accent: _color(section, 'accent', fallback.accent),
      accentHover: _color(section, 'accent_hover', fallback.accentHover),
      accentActive: _color(section, 'accent_active', fallback.accentActive),
      selection: _color(section, 'selection', fallback.selection),
      focusRing: _color(section, 'focus_ring', fallback.focusRing),
      error: _color(section, 'error', fallback.error),
      warning: _color(section, 'warning', fallback.warning),
      success: _color(section, 'success', fallback.success),
      info: _color(section, 'info', fallback.info),
    );
  }

  MenuThemeTokens _buildMenu(
    Map<String, Object?> section,
    MenuThemeTokens fallback,
  ) {
    return MenuThemeTokens(
      background: _color(section, 'bg', fallback.background),
      text: _color(section, 'text', fallback.text),
      textMuted: _color(section, 'text_muted', fallback.textMuted),
      itemHoverBackground: _color(
        section,
        'item_hover_bg',
        fallback.itemHoverBackground,
      ),
      itemActiveBackground: _color(
        section,
        'item_active_bg',
        fallback.itemActiveBackground,
      ),
      separator: _color(section, 'separator', fallback.separator),
      icon: _color(section, 'icon', fallback.icon),
      shortcut: _color(section, 'shortcut', fallback.shortcut),
    );
  }

  ToolbarThemeTokens _buildToolbar(
    Map<String, Object?> section,
    ToolbarThemeTokens fallback,
  ) {
    return ToolbarThemeTokens(
      background: _color(section, 'bg', fallback.background),
      buttonBackground: _color(section, 'button_bg', fallback.buttonBackground),
      buttonHoverBackground: _color(
        section,
        'button_hover_bg',
        fallback.buttonHoverBackground,
      ),
      buttonActiveBackground: _color(
        section,
        'button_active_bg',
        fallback.buttonActiveBackground,
      ),
      buttonText: _color(section, 'button_text', fallback.buttonText),
      buttonIcon: _color(section, 'button_icon', fallback.buttonIcon),
    );
  }

  StatusBarThemeTokens _buildStatusBar(
    Map<String, Object?> section,
    StatusBarThemeTokens fallback,
  ) {
    return StatusBarThemeTokens(
      background: _color(section, 'bg', fallback.background),
      text: _color(section, 'text', fallback.text),
      borderTop: _color(section, 'border_top', fallback.borderTop),
      success: _color(section, 'success', fallback.success),
      warning: _color(section, 'warning', fallback.warning),
      error: _color(section, 'error', fallback.error),
    );
  }

  SidebarThemeTokens _buildSidebar(
    Map<String, Object?> section,
    SidebarThemeTokens fallback,
  ) {
    return SidebarThemeTokens(
      background: _color(section, 'bg', fallback.background),
      headerBackground: _color(section, 'header_bg', fallback.headerBackground),
      headerText: _color(section, 'header_text', fallback.headerText),
      itemText: _color(section, 'item_text', fallback.itemText),
      itemHoverBackground: _color(
        section,
        'item_hover_bg',
        fallback.itemHoverBackground,
      ),
      itemSelectedBackground: _color(
        section,
        'item_selected_bg',
        fallback.itemSelectedBackground,
      ),
      itemSelectedText: _color(
        section,
        'item_selected_text',
        fallback.itemSelectedText,
      ),
      treeLine: _color(section, 'tree_line', fallback.treeLine),
    );
  }

  PropertiesThemeTokens _buildProperties(
    Map<String, Object?> section,
    PropertiesThemeTokens fallback,
  ) {
    return PropertiesThemeTokens(
      background: _color(section, 'bg', fallback.background),
      label: _color(section, 'label', fallback.label),
      value: _color(section, 'value', fallback.value),
      sectionHeaderBackground: _color(
        section,
        'section_header_bg',
        fallback.sectionHeaderBackground,
      ),
      sectionHeaderText: _color(
        section,
        'section_header_text',
        fallback.sectionHeaderText,
      ),
    );
  }

  EditorThemeTokens _buildEditor(
    Map<String, Object?> section,
    EditorThemeTokens fallback,
  ) {
    return EditorThemeTokens(
      background: _color(section, 'bg', fallback.background),
      text: _color(section, 'text', fallback.text),
      gutterBackground: _color(section, 'gutter_bg', fallback.gutterBackground),
      gutterText: _color(section, 'gutter_text', fallback.gutterText),
      currentLineBackground: _color(
        section,
        'current_line_bg',
        fallback.currentLineBackground,
      ),
      selectionBackground: _color(
        section,
        'selection_bg',
        fallback.selectionBackground,
      ),
      cursor: _color(section, 'cursor', fallback.cursor),
      whitespace: _color(section, 'whitespace', fallback.whitespace),
      indentGuide: _color(section, 'indent_guide', fallback.indentGuide),
      tabActiveBackground: _color(
        section,
        'tab_active_bg',
        fallback.tabActiveBackground,
      ),
      tabInactiveBackground: _color(
        section,
        'tab_inactive_bg',
        fallback.tabInactiveBackground,
      ),
      tabHoverBackground: _color(
        section,
        'tab_hover_bg',
        fallback.tabHoverBackground,
      ),
      tabActiveText: _color(section, 'tab_active_text', fallback.tabActiveText),
      tabInactiveText: _color(
        section,
        'tab_inactive_text',
        fallback.tabInactiveText,
      ),
    );
  }

  ResultsGridThemeTokens _buildResultsGrid(
    Map<String, Object?> section,
    ResultsGridThemeTokens fallback,
  ) {
    return ResultsGridThemeTokens(
      background: _color(section, 'bg', fallback.background),
      headerBackground: _color(section, 'header_bg', fallback.headerBackground),
      headerText: _color(section, 'header_text', fallback.headerText),
      rowBackground: _color(section, 'row_bg', fallback.rowBackground),
      rowAltBackground: _color(
        section,
        'row_alt_bg',
        fallback.rowAltBackground,
      ),
      rowHoverBackground: _color(
        section,
        'row_hover_bg',
        fallback.rowHoverBackground,
      ),
      rowSelectedBackground: _color(
        section,
        'row_selected_bg',
        fallback.rowSelectedBackground,
      ),
      rowSelectedText: _color(
        section,
        'row_selected_text',
        fallback.rowSelectedText,
      ),
      gridLine: _color(section, 'grid_line', fallback.gridLine),
      cellText: _color(section, 'cell_text', fallback.cellText),
      nullText: _color(section, 'null_text', fallback.nullText),
    );
  }

  DialogThemeTokens _buildDialog(
    Map<String, Object?> section,
    DialogThemeTokens fallback,
  ) {
    return DialogThemeTokens(
      background: _color(section, 'bg', fallback.background),
      titleText: _color(section, 'title_text', fallback.titleText),
      bodyText: _color(section, 'body_text', fallback.bodyText),
      inputBackground: _color(section, 'input_bg', fallback.inputBackground),
      inputText: _color(section, 'input_text', fallback.inputText),
      inputBorder: _color(section, 'input_border', fallback.inputBorder),
      inputFocusBorder: _color(
        section,
        'input_focus_border',
        fallback.inputFocusBorder,
      ),
    );
  }

  ButtonThemeTokens _buildButtons(
    Map<String, Object?> section,
    ButtonThemeTokens fallback,
  ) {
    return ButtonThemeTokens(
      primaryBackground: _color(
        section,
        'primary_bg',
        fallback.primaryBackground,
      ),
      primaryText: _color(section, 'primary_text', fallback.primaryText),
      primaryHoverBackground: _color(
        section,
        'primary_hover_bg',
        fallback.primaryHoverBackground,
      ),
      secondaryBackground: _color(
        section,
        'secondary_bg',
        fallback.secondaryBackground,
      ),
      secondaryText: _color(section, 'secondary_text', fallback.secondaryText),
      secondaryHoverBackground: _color(
        section,
        'secondary_hover_bg',
        fallback.secondaryHoverBackground,
      ),
      dangerBackground: _color(section, 'danger_bg', fallback.dangerBackground),
      dangerText: _color(section, 'danger_text', fallback.dangerText),
    );
  }

  SqlSyntaxThemeTokens _buildSqlSyntax(
    Map<String, Object?> section,
    SqlSyntaxThemeTokens fallback,
  ) {
    return SqlSyntaxThemeTokens(
      keyword: _color(section, 'keyword', fallback.keyword),
      identifier: _color(section, 'identifier', fallback.identifier),
      string: _color(section, 'string', fallback.string),
      number: _color(section, 'number', fallback.number),
      comment: _color(section, 'comment', fallback.comment),
      operator: _color(section, 'operator', fallback.operator),
      function: _color(section, 'function', fallback.function),
      type: _color(section, 'type', fallback.type),
      parameter: _color(section, 'parameter', fallback.parameter),
      constant: _color(section, 'constant', fallback.constant),
      error: _color(section, 'error', fallback.error),
    );
  }

  ThemeFontTokens _buildFonts(
    Map<String, Object?> section,
    ThemeFontTokens fallback,
    List<String> warnings,
  ) {
    return ThemeFontTokens(
      uiFamily: _resolveString(
        section,
        'ui_family',
        fallback.uiFamily,
        warnings,
      ),
      editorFamily: _resolveString(
        section,
        'editor_family',
        fallback.editorFamily,
        warnings,
      ),
      uiSize: _resolveDouble(
        section,
        'ui_size',
        fallback.uiSize,
        warnings,
        min: 8,
        max: 28,
      ),
      editorSize: _resolveDouble(
        section,
        'editor_size',
        fallback.editorSize,
        warnings,
        min: 8,
        max: 32,
      ),
      lineHeight: _resolveDouble(
        section,
        'line_height',
        fallback.lineHeight,
        warnings,
        min: 1.0,
        max: 2.0,
      ),
    );
  }

  ThemeMetricTokens _buildMetrics(
    Map<String, Object?> section,
    ThemeMetricTokens fallback,
    List<String> warnings,
  ) {
    return ThemeMetricTokens(
      borderRadius: _resolveDouble(
        section,
        'border_radius',
        fallback.borderRadius,
        warnings,
        min: 0,
        max: 24,
      ),
      panePadding: _resolveDouble(
        section,
        'pane_padding',
        fallback.panePadding,
        warnings,
        min: 0,
        max: 32,
      ),
      controlHeight: _resolveDouble(
        section,
        'control_height',
        fallback.controlHeight,
        warnings,
        min: 20,
        max: 80,
      ),
      splitterThickness: _resolveDouble(
        section,
        'splitter_thickness',
        fallback.splitterThickness,
        warnings,
        min: 2,
        max: 24,
      ),
      iconSize: _resolveDouble(
        section,
        'icon_size',
        fallback.iconSize,
        warnings,
        min: 10,
        max: 32,
      ),
    );
  }

  Color _color(Map<String, Object?> values, String key, Color fallback) {
    final raw = values[key];
    if (raw == null) {
      return fallback;
    }
    if (raw is! String) {
      throw _ThemeValidationError('$key must be a quoted color value.');
    }
    final color = parseThemeColor(raw);
    if (color == null) {
      throw _ThemeValidationError('Invalid color "$raw" for $key.');
    }
    return color;
  }

  String _requiredString(
    Map<String, Object?> values,
    String key, {
    String? sectionName,
  }) {
    final value = values[key];
    if (value is! String || value.trim().isEmpty) {
      throw _ThemeValidationError(
        '${sectionName == null ? key : '$sectionName.$key'} is required.',
      );
    }
    return value.trim();
  }

  String? _optionalString(Map<String, Object?> values, String key) {
    final value = values[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw _ThemeValidationError('$key must be a string.');
    }
    return value;
  }

  String _resolveString(
    Map<String, Object?> values,
    String key,
    String fallback,
    List<String> warnings,
  ) {
    final value = values[key];
    if (value == null) {
      return fallback;
    }
    if (value is! String || value.trim().isEmpty) {
      warnings.add('$key must be a non-empty string; using fallback.');
      return fallback;
    }
    return value.trim();
  }

  double _resolveDouble(
    Map<String, Object?> values,
    String key,
    double fallback,
    List<String> warnings, {
    required double min,
    required double max,
  }) {
    final value = values[key];
    if (value == null) {
      return fallback;
    }
    if (value is! num) {
      warnings.add('$key must be numeric; using fallback.');
      return fallback;
    }
    final resolved = value.toDouble();
    if (resolved < min || resolved > max) {
      warnings.add('$key is out of range; using fallback.');
      return fallback;
    }
    return resolved;
  }
}

class _ThemeValidationError implements Exception {
  const _ThemeValidationError(this.message);

  final String message;
}
