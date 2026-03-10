import 'package:flutter/material.dart';

import '../app_metadata.dart';
import 'decent_bench_theme.dart';

DecentBenchTheme buildEmergencyTheme({
  Brightness brightness = Brightness.dark,
  String id = 'classic-dark',
  String name = 'Classic Dark',
}) {
  final isDark = brightness == Brightness.dark;

  return DecentBenchTheme(
    metadata: ThemeMetadata(
      name: name,
      id: id,
      version: '1.0.0',
      author: 'Decent Bench',
      description: 'Emergency fallback theme bundled in code.',
    ),
    compatibility: const ThemeCompatibility(
      minDecentBenchVersion: kDecentBenchVersion,
    ),
    brightness: brightness,
    colors: ThemeColors(
      windowBg: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF3F3F5),
      panelBg: isDark ? const Color(0xFF252526) : const Color(0xFFFFFFFF),
      panelAltBg: isDark ? const Color(0xFF2D2D30) : const Color(0xFFF7F7F9),
      surfaceBg: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFFFFFFF),
      overlayBg: isDark ? const Color(0xFF333337) : const Color(0xFFF1F1F4),
      border: isDark ? const Color(0xFF3F3F46) : const Color(0xFFC9CBD2),
      borderStrong: isDark ? const Color(0xFF5A5A66) : const Color(0xFFAEB3BD),
      text: isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1F232A),
      textMuted: isDark ? const Color(0xFFA8A8A8) : const Color(0xFF5F6773),
      textDisabled: isDark ? const Color(0xFF6E6E6E) : const Color(0xFF9097A3),
      accent: isDark ? const Color(0xFF7C5CFF) : const Color(0xFF6B4DFF),
      accentHover: isDark ? const Color(0xFF947BFF) : const Color(0xFF7B63FF),
      accentActive: isDark ? const Color(0xFF6246EA) : const Color(0xFF5638E6),
      selection: isDark ? const Color(0xFF3A3D41) : const Color(0xFFD9E8FF),
      focusRing: isDark ? const Color(0xFFA78BFA) : const Color(0xFF8E7BFF),
      error: isDark ? const Color(0xFFE05A5A) : const Color(0xFFC64545),
      warning: isDark ? const Color(0xFFD9A441) : const Color(0xFFB57C18),
      success: isDark ? const Color(0xFF57B36A) : const Color(0xFF2E8B57),
      info: isDark ? const Color(0xFF4FA3D9) : const Color(0xFF2E78C7),
    ),
    menu: MenuThemeTokens(
      background: isDark ? const Color(0xFF2D2D30) : const Color(0xFFF7F7F9),
      text: isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1F232A),
      textMuted: isDark ? const Color(0xFFB8B8B8) : const Color(0xFF646C77),
      itemHoverBackground: isDark
          ? const Color(0xFF3A3D41)
          : const Color(0xFFE8ECF3),
      itemActiveBackground: isDark
          ? const Color(0xFF4A4D52)
          : const Color(0xFFDCE4F1),
      separator: isDark ? const Color(0xFF45454D) : const Color(0xFFD0D4DB),
      icon: isDark ? const Color(0xFFCFCFCF) : const Color(0xFF38414C),
      shortcut: isDark ? const Color(0xFF9E9E9E) : const Color(0xFF6A7280),
    ),
    toolbar: ToolbarThemeTokens(
      background: isDark ? const Color(0xFF2B2B2F) : const Color(0xFFF5F5F7),
      buttonBackground: isDark
          ? const Color(0xFF2F2F34)
          : const Color(0xFFFFFFFF),
      buttonHoverBackground: isDark
          ? const Color(0xFF3A3A40)
          : const Color(0xFFECEFF5),
      buttonActiveBackground: isDark
          ? const Color(0xFF45454C)
          : const Color(0xFFDEE5F0),
      buttonText: isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1F232A),
      buttonIcon: isDark ? const Color(0xFFD7D7D7) : const Color(0xFF38414C),
    ),
    statusBar: StatusBarThemeTokens(
      background: isDark ? const Color(0xFF2A2A2D) : const Color(0xFFF1F3F6),
      text: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF2B313A),
      borderTop: isDark ? const Color(0xFF3E3E44) : const Color(0xFFCCD1D9),
      success: isDark ? const Color(0xFF57B36A) : const Color(0xFF2E8B57),
      warning: isDark ? const Color(0xFFD9A441) : const Color(0xFFB57C18),
      error: isDark ? const Color(0xFFE05A5A) : const Color(0xFFC64545),
    ),
    sidebar: SidebarThemeTokens(
      background: isDark ? const Color(0xFF252526) : const Color(0xFFFFFFFF),
      headerBackground: isDark
          ? const Color(0xFF2D2D30)
          : const Color(0xFFF3F5F8),
      headerText: isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1F232A),
      itemText: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF2D333B),
      itemHoverBackground: isDark
          ? const Color(0xFF37373D)
          : const Color(0xFFEEF2F7),
      itemSelectedBackground: isDark
          ? const Color(0xFF3F3F46)
          : const Color(0xFFDCE7F8),
      itemSelectedText: isDark
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF111418),
      treeLine: isDark ? const Color(0xFF4A4A50) : const Color(0xFFC9CED8),
    ),
    properties: PropertiesThemeTokens(
      background: isDark ? const Color(0xFF252526) : const Color(0xFFFFFFFF),
      label: isDark ? const Color(0xFFBEBEBE) : const Color(0xFF5A6270),
      value: isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1F232A),
      sectionHeaderBackground: isDark
          ? const Color(0xFF2F2F34)
          : const Color(0xFFEEF2F7),
      sectionHeaderText: isDark
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF1B2027),
    ),
    editor: EditorThemeTokens(
      background: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF),
      text: isDark ? const Color(0xFFDCDCDC) : const Color(0xFF1F232A),
      gutterBackground: isDark
          ? const Color(0xFF252526)
          : const Color(0xFFF5F6F8),
      gutterText: isDark ? const Color(0xFF858585) : const Color(0xFF8A909A),
      currentLineBackground: isDark
          ? const Color(0xFF2A2D2E)
          : const Color(0xFFF4F8FF),
      selectionBackground: isDark
          ? const Color(0xFF264F78)
          : const Color(0xFFCFE3FF),
      cursor: isDark ? const Color(0xFFAEAFAD) : const Color(0xFF1F232A),
      whitespace: isDark ? const Color(0xFF404040) : const Color(0xFFD2D7DE),
      indentGuide: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD7DCE3),
      tabActiveBackground: isDark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFFFFFFF),
      tabInactiveBackground: isDark
          ? const Color(0xFF2D2D30)
          : const Color(0xFFECEFF4),
      tabHoverBackground: isDark
          ? const Color(0xFF37373D)
          : const Color(0xFFE2E8F2),
      tabActiveText: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF111418),
      tabInactiveText: isDark
          ? const Color(0xFFB8B8B8)
          : const Color(0xFF616A76),
    ),
    resultsGrid: ResultsGridThemeTokens(
      background: isDark ? const Color(0xFF1F1F22) : const Color(0xFFFFFFFF),
      headerBackground: isDark
          ? const Color(0xFF2D2D30)
          : const Color(0xFFF3F5F8),
      headerText: isDark ? const Color(0xFFF0F0F0) : const Color(0xFF161B22),
      rowBackground: isDark ? const Color(0xFF1F1F22) : const Color(0xFFFFFFFF),
      rowAltBackground: isDark
          ? const Color(0xFF252529)
          : const Color(0xFFF8FAFC),
      rowHoverBackground: isDark
          ? const Color(0xFF2F2F34)
          : const Color(0xFFEEF3FA),
      rowSelectedBackground: isDark
          ? const Color(0xFF3A3D41)
          : const Color(0xFFDCE7F8),
      rowSelectedText: isDark
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF111418),
      gridLine: isDark ? const Color(0xFF3D3D44) : const Color(0xFFD6DAE1),
      cellText: isDark ? const Color(0xFFE4E4E4) : const Color(0xFF1F232A),
      nullText: isDark ? const Color(0xFF8C8C8C) : const Color(0xFF8C929C),
    ),
    dialog: DialogThemeTokens(
      background: isDark ? const Color(0xFF252526) : const Color(0xFFFFFFFF),
      titleText: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF111418),
      bodyText: isDark ? const Color(0xFFD8D8D8) : const Color(0xFF2C333C),
      inputBackground: isDark
          ? const Color(0xFF1E1E1E)
          : const Color(0xFFFFFFFF),
      inputText: isDark ? const Color(0xFFEAEAEA) : const Color(0xFF1F232A),
      inputBorder: isDark ? const Color(0xFF4B4B52) : const Color(0xFFBFC6D1),
      inputFocusBorder: isDark
          ? const Color(0xFF8B7BFF)
          : const Color(0xFF7C67FF),
    ),
    buttons: ButtonThemeTokens(
      primaryBackground: isDark
          ? const Color(0xFF7C5CFF)
          : const Color(0xFF6B4DFF),
      primaryText: const Color(0xFFFFFFFF),
      primaryHoverBackground: isDark
          ? const Color(0xFF8A6CFF)
          : const Color(0xFF7A61FF),
      secondaryBackground: isDark
          ? const Color(0xFF34343A)
          : const Color(0xFFEEF1F6),
      secondaryText: isDark ? const Color(0xFFE5E5E5) : const Color(0xFF1F232A),
      secondaryHoverBackground: isDark
          ? const Color(0xFF404048)
          : const Color(0xFFE2E7EF),
      dangerBackground: isDark
          ? const Color(0xFFA94444)
          : const Color(0xFFC64545),
      dangerText: const Color(0xFFFFFFFF),
    ),
    sqlSyntax: SqlSyntaxThemeTokens(
      keyword: isDark ? const Color(0xFFC586C0) : const Color(0xFF8E24AA),
      identifier: isDark ? const Color(0xFF9CDCFE) : const Color(0xFF1565C0),
      string: isDark ? const Color(0xFFCE9178) : const Color(0xFFA15C2F),
      number: isDark ? const Color(0xFFB5CEA8) : const Color(0xFF558B2F),
      comment: isDark ? const Color(0xFF6A9955) : const Color(0xFF6A737D),
      operator: isDark ? const Color(0xFFD4D4D4) : const Color(0xFF1F232A),
      function: isDark ? const Color(0xFFDCDCAA) : const Color(0xFFAD7B00),
      type: isDark ? const Color(0xFF4EC9B0) : const Color(0xFF00897B),
      parameter: isDark ? const Color(0xFF9CDCFE) : const Color(0xFF1565C0),
      constant: isDark ? const Color(0xFF569CD6) : const Color(0xFF3949AB),
      error: isDark ? const Color(0xFFF44747) : const Color(0xFFD32F2F),
    ),
    fonts: const ThemeFontTokens(
      uiFamily: 'Inter',
      editorFamily: 'JetBrains Mono',
      uiSize: 13,
      editorSize: 13,
      lineHeight: 1.35,
    ),
    metrics: const ThemeMetricTokens(
      borderRadius: 4,
      panePadding: 6,
      controlHeight: 28,
      splitterThickness: 6,
      iconSize: 16,
    ),
    isBuiltIn: true,
    sourceLabel: 'emergency',
  );
}
