import 'package:flutter/material.dart';

ThemeData buildDecentBenchTheme() {
  const background = Color(0xFFE6EBF0);
  const panel = Color(0xFFFDFEFE);
  const chrome = Color(0xFFD7DFE8);
  const ink = Color(0xFF1E2933);
  const accent = Color(0xFF2F5D7C);
  const accentAlt = Color(0xFF6F4E2E);

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        primary: accent,
        secondary: accentAlt,
        surface: panel,
      ).copyWith(
        surface: panel,
        surfaceContainerHighest: chrome,
        surfaceContainerHigh: const Color(0xFFE2E8EE),
        surfaceContainerLow: const Color(0xFFF1F4F7),
        surfaceContainerLowest: const Color(0xFFF8FAFC),
        outline: const Color(0xFF9FAABA),
        outlineVariant: const Color(0xFFBAC4D0),
        onSurface: ink,
        onSurfaceVariant: const Color(0xFF546270),
      );

  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(4)),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: background,
    splashFactory: NoSplash.splashFactory,
    textTheme: Typography.material2021().black.apply(
      bodyColor: ink,
      displayColor: ink,
    ),
    cardTheme: const CardThemeData(
      color: panel,
      shape: shape,
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colorScheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorScheme.surfaceContainerLowest,
      side: BorderSide(color: colorScheme.outlineVariant),
      shape: shape,
      labelStyle: const TextStyle(fontSize: 12),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
    ),
    menuBarTheme: MenuBarThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHighest,
        ),
        shape: const WidgetStatePropertyAll(shape),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(color: Colors.white),
    ),
  );
}
