import 'package:flutter/material.dart';

class ThemeMetadata {
  const ThemeMetadata({
    required this.name,
    required this.id,
    required this.version,
    this.author = '',
    this.description = '',
  });

  final String name;
  final String id;
  final String version;
  final String author;
  final String description;
}

class ThemeCompatibility {
  const ThemeCompatibility({
    required this.minDecentBenchVersion,
    this.maxDecentBenchVersion,
  });

  final String minDecentBenchVersion;
  final String? maxDecentBenchVersion;
}

class ThemeColors {
  const ThemeColors({
    required this.windowBg,
    required this.panelBg,
    required this.panelAltBg,
    required this.surfaceBg,
    required this.overlayBg,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textDisabled,
    required this.accent,
    required this.accentHover,
    required this.accentActive,
    required this.selection,
    required this.focusRing,
    required this.error,
    required this.warning,
    required this.success,
    required this.info,
  });

  final Color windowBg;
  final Color panelBg;
  final Color panelAltBg;
  final Color surfaceBg;
  final Color overlayBg;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textMuted;
  final Color textDisabled;
  final Color accent;
  final Color accentHover;
  final Color accentActive;
  final Color selection;
  final Color focusRing;
  final Color error;
  final Color warning;
  final Color success;
  final Color info;
}

class MenuThemeTokens {
  const MenuThemeTokens({
    required this.background,
    required this.text,
    required this.textMuted,
    required this.itemHoverBackground,
    required this.itemActiveBackground,
    required this.separator,
    required this.icon,
    required this.shortcut,
  });

  final Color background;
  final Color text;
  final Color textMuted;
  final Color itemHoverBackground;
  final Color itemActiveBackground;
  final Color separator;
  final Color icon;
  final Color shortcut;
}

class ToolbarThemeTokens {
  const ToolbarThemeTokens({
    required this.background,
    required this.buttonBackground,
    required this.buttonHoverBackground,
    required this.buttonActiveBackground,
    required this.buttonText,
    required this.buttonIcon,
  });

  final Color background;
  final Color buttonBackground;
  final Color buttonHoverBackground;
  final Color buttonActiveBackground;
  final Color buttonText;
  final Color buttonIcon;
}

class StatusBarThemeTokens {
  const StatusBarThemeTokens({
    required this.background,
    required this.text,
    required this.borderTop,
    required this.success,
    required this.warning,
    required this.error,
  });

  final Color background;
  final Color text;
  final Color borderTop;
  final Color success;
  final Color warning;
  final Color error;
}

class SidebarThemeTokens {
  const SidebarThemeTokens({
    required this.background,
    required this.headerBackground,
    required this.headerText,
    required this.itemText,
    required this.itemHoverBackground,
    required this.itemSelectedBackground,
    required this.itemSelectedText,
    required this.treeLine,
  });

  final Color background;
  final Color headerBackground;
  final Color headerText;
  final Color itemText;
  final Color itemHoverBackground;
  final Color itemSelectedBackground;
  final Color itemSelectedText;
  final Color treeLine;
}

class PropertiesThemeTokens {
  const PropertiesThemeTokens({
    required this.background,
    required this.label,
    required this.value,
    required this.sectionHeaderBackground,
    required this.sectionHeaderText,
  });

  final Color background;
  final Color label;
  final Color value;
  final Color sectionHeaderBackground;
  final Color sectionHeaderText;
}

class EditorThemeTokens {
  const EditorThemeTokens({
    required this.background,
    required this.text,
    required this.gutterBackground,
    required this.gutterText,
    required this.currentLineBackground,
    required this.selectionBackground,
    required this.cursor,
    required this.whitespace,
    required this.indentGuide,
    required this.tabActiveBackground,
    required this.tabInactiveBackground,
    required this.tabHoverBackground,
    required this.tabActiveText,
    required this.tabInactiveText,
  });

  final Color background;
  final Color text;
  final Color gutterBackground;
  final Color gutterText;
  final Color currentLineBackground;
  final Color selectionBackground;
  final Color cursor;
  final Color whitespace;
  final Color indentGuide;
  final Color tabActiveBackground;
  final Color tabInactiveBackground;
  final Color tabHoverBackground;
  final Color tabActiveText;
  final Color tabInactiveText;
}

class ResultsGridThemeTokens {
  const ResultsGridThemeTokens({
    required this.background,
    required this.headerBackground,
    required this.headerText,
    required this.rowBackground,
    required this.rowAltBackground,
    required this.rowHoverBackground,
    required this.rowSelectedBackground,
    required this.rowSelectedText,
    required this.gridLine,
    required this.cellText,
    required this.nullText,
  });

  final Color background;
  final Color headerBackground;
  final Color headerText;
  final Color rowBackground;
  final Color rowAltBackground;
  final Color rowHoverBackground;
  final Color rowSelectedBackground;
  final Color rowSelectedText;
  final Color gridLine;
  final Color cellText;
  final Color nullText;
}

class DialogThemeTokens {
  const DialogThemeTokens({
    required this.background,
    required this.titleText,
    required this.bodyText,
    required this.inputBackground,
    required this.inputText,
    required this.inputBorder,
    required this.inputFocusBorder,
  });

  final Color background;
  final Color titleText;
  final Color bodyText;
  final Color inputBackground;
  final Color inputText;
  final Color inputBorder;
  final Color inputFocusBorder;
}

class ButtonThemeTokens {
  const ButtonThemeTokens({
    required this.primaryBackground,
    required this.primaryText,
    required this.primaryHoverBackground,
    required this.secondaryBackground,
    required this.secondaryText,
    required this.secondaryHoverBackground,
    required this.dangerBackground,
    required this.dangerText,
  });

  final Color primaryBackground;
  final Color primaryText;
  final Color primaryHoverBackground;
  final Color secondaryBackground;
  final Color secondaryText;
  final Color secondaryHoverBackground;
  final Color dangerBackground;
  final Color dangerText;
}

class SqlSyntaxThemeTokens {
  const SqlSyntaxThemeTokens({
    required this.keyword,
    required this.identifier,
    required this.string,
    required this.number,
    required this.comment,
    required this.operator,
    required this.function,
    required this.type,
    required this.parameter,
    required this.constant,
    required this.error,
  });

  final Color keyword;
  final Color identifier;
  final Color string;
  final Color number;
  final Color comment;
  final Color operator;
  final Color function;
  final Color type;
  final Color parameter;
  final Color constant;
  final Color error;
}

class ThemeFontTokens {
  const ThemeFontTokens({
    required this.uiFamily,
    required this.editorFamily,
    required this.uiSize,
    required this.editorSize,
    required this.lineHeight,
  });

  final String uiFamily;
  final String editorFamily;
  final double uiSize;
  final double editorSize;
  final double lineHeight;
}

class ThemeMetricTokens {
  const ThemeMetricTokens({
    required this.borderRadius,
    required this.panePadding,
    required this.controlHeight,
    required this.splitterThickness,
    required this.iconSize,
  });

  final double borderRadius;
  final double panePadding;
  final double controlHeight;
  final double splitterThickness;
  final double iconSize;
}

class DecentBenchTheme {
  const DecentBenchTheme({
    required this.metadata,
    required this.compatibility,
    required this.brightness,
    required this.colors,
    required this.menu,
    required this.toolbar,
    required this.statusBar,
    required this.sidebar,
    required this.properties,
    required this.editor,
    required this.resultsGrid,
    required this.dialog,
    required this.buttons,
    required this.sqlSyntax,
    required this.fonts,
    required this.metrics,
    required this.isBuiltIn,
    required this.sourceLabel,
  });

  final ThemeMetadata metadata;
  final ThemeCompatibility compatibility;
  final Brightness brightness;
  final ThemeColors colors;
  final MenuThemeTokens menu;
  final ToolbarThemeTokens toolbar;
  final StatusBarThemeTokens statusBar;
  final SidebarThemeTokens sidebar;
  final PropertiesThemeTokens properties;
  final EditorThemeTokens editor;
  final ResultsGridThemeTokens resultsGrid;
  final DialogThemeTokens dialog;
  final ButtonThemeTokens buttons;
  final SqlSyntaxThemeTokens sqlSyntax;
  final ThemeFontTokens fonts;
  final ThemeMetricTokens metrics;
  final bool isBuiltIn;
  final String sourceLabel;

  String get id => metadata.id;
  String get name => metadata.name;
}
