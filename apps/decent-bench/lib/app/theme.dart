import 'package:flutter/material.dart';

import 'theme_system/decent_bench_theme.dart';
import 'theme_system/decent_bench_theme_extension.dart';
import 'theme_system/theme_presets.dart';

ThemeData buildDecentBenchTheme([DecentBenchTheme? theme]) {
  final tokens = theme ?? buildEmergencyTheme();
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
  );

  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: tokens.colors.accent,
        brightness: tokens.brightness,
        primary: tokens.colors.accent,
        secondary: tokens.colors.accentActive,
        surface: tokens.colors.surfaceBg,
      ).copyWith(
        surface: tokens.colors.surfaceBg,
        surfaceContainerHighest: tokens.colors.panelAltBg,
        surfaceContainerHigh: tokens.toolbar.background,
        surfaceContainerLow: tokens.colors.panelAltBg,
        surfaceContainerLowest: tokens.colors.panelBg,
        outline: tokens.colors.borderStrong,
        outlineVariant: tokens.colors.border,
        onSurface: tokens.colors.text,
        onSurfaceVariant: tokens.colors.textMuted,
        primary: tokens.colors.accent,
        onPrimary: tokens.buttons.primaryText,
        secondary: tokens.colors.accentActive,
        onSecondary: tokens.colors.text,
        error: tokens.colors.error,
        onError: tokens.buttons.dangerText,
        primaryContainer: tokens.buttons.primaryBackground,
        onPrimaryContainer: tokens.buttons.primaryText,
        secondaryContainer: tokens.colors.selection,
        onSecondaryContainer: tokens.colors.text,
        tertiary: tokens.colors.info,
        onTertiary: tokens.colors.panelBg,
        shadow: Colors.black,
        scrim: tokens.colors.overlayBg,
      );

  final baseTextTheme = tokens.brightness == Brightness.dark
      ? Typography.material2021().white
      : Typography.material2021().black;
  final textTheme = baseTextTheme
      .apply(
        fontFamily: tokens.fonts.uiFamily,
        bodyColor: tokens.colors.text,
        displayColor: tokens.colors.text,
      )
      .copyWith(
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          fontFamily: tokens.fonts.uiFamily,
          color: tokens.colors.textMuted,
          fontSize: tokens.fonts.uiSize - 1,
          height: tokens.fonts.lineHeight,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontFamily: tokens.fonts.uiFamily,
          color: tokens.colors.text,
          fontSize: tokens.fonts.uiSize,
          height: tokens.fonts.lineHeight,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          fontFamily: tokens.fonts.uiFamily,
          color: tokens.colors.textMuted,
          fontSize: tokens.fonts.uiSize - 1,
          height: tokens.fonts.lineHeight,
        ),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontFamily: tokens.fonts.uiFamily,
          color: tokens.colors.text,
          fontSize: tokens.fonts.uiSize,
          height: tokens.fonts.lineHeight,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          fontFamily: tokens.fonts.uiFamily,
          color: tokens.colors.text,
          fontSize: tokens.fonts.uiSize,
          height: 1.1,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontFamily: tokens.fonts.uiFamily,
          color: tokens.colors.text,
          fontSize: tokens.fonts.uiSize + 1,
          height: 1.2,
        ),
      );

  final menuStateBackground = WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.selected)) {
      return tokens.menu.itemActiveBackground;
    }
    if (states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.focused)) {
      return tokens.menu.itemHoverBackground;
    }
    return tokens.menu.background;
  });

  return ThemeData(
    useMaterial3: true,
    brightness: tokens.brightness,
    colorScheme: colorScheme,
    extensions: <ThemeExtension<dynamic>>[DecentBenchThemeExtension(tokens)],
    scaffoldBackgroundColor: tokens.colors.windowBg,
    canvasColor: tokens.colors.panelBg,
    splashFactory: NoSplash.splashFactory,
    hoverColor: tokens.colors.selection,
    focusColor: tokens.colors.focusRing.withValues(alpha: 0.25),
    highlightColor: tokens.colors.selection.withValues(alpha: 0.2),
    dividerColor: tokens.colors.border,
    textTheme: textTheme,
    iconTheme: IconThemeData(
      color: tokens.colors.textMuted,
      size: tokens.metrics.iconSize,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.colors.accent,
    ),
    dividerTheme: DividerThemeData(color: tokens.colors.border, space: 1),
    cardTheme: CardThemeData(
      color: tokens.colors.panelBg,
      shape: shape,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.dialog.background,
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: tokens.dialog.titleText,
      ),
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: tokens.dialog.bodyText,
      ),
      shape: shape,
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: tokens.dialog.inputBackground,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: (tokens.metrics.controlHeight - 18).clamp(8, 16),
      ),
      hintStyle: textTheme.bodySmall?.copyWith(color: tokens.colors.textMuted),
      labelStyle: textTheme.bodySmall?.copyWith(color: tokens.colors.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
        borderSide: BorderSide(color: tokens.dialog.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
        borderSide: BorderSide(
          color: tokens.dialog.inputFocusBorder,
          width: 1.2,
        ),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: tokens.editor.selectionBackground,
      cursorColor: tokens.editor.cursor,
      selectionHandleColor: tokens.colors.accent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(0, tokens.metrics.controlHeight),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
        foregroundColor: WidgetStatePropertyAll<Color>(
          tokens.buttons.primaryText,
        ),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.colors.textDisabled.withValues(alpha: 0.25);
          }
          if (states.contains(WidgetState.hovered)) {
            return tokens.buttons.primaryHoverBackground;
          }
          return tokens.buttons.primaryBackground;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll<Size>(
          Size(0, tokens.metrics.controlHeight),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: tokens.colors.border),
        ),
        foregroundColor: WidgetStatePropertyAll<Color>(
          tokens.buttons.secondaryText,
        ),
        backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.disabled)) {
            return tokens.colors.textDisabled.withValues(alpha: 0.12);
          }
          if (states.contains(WidgetState.hovered)) {
            return tokens.buttons.secondaryHoverBackground;
          }
          return tokens.buttons.secondaryBackground;
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: tokens.colors.accent,
        shape: shape,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.colors.panelAltBg,
      side: BorderSide(color: tokens.colors.border),
      shape: shape,
      labelStyle: textTheme.labelSmall,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      iconColor: tokens.colors.textMuted,
      textColor: tokens.colors.text,
    ),
    menuBarTheme: MenuBarThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(tokens.menu.background),
        shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: tokens.menu.separator),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
        backgroundColor: menuStateBackground,
        foregroundColor: WidgetStatePropertyAll<Color>(tokens.menu.text),
        iconColor: WidgetStatePropertyAll<Color>(tokens.menu.icon),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.menu.background,
      textStyle: textTheme.bodyMedium?.copyWith(color: tokens.menu.text),
      shape: shape,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.colors.overlayBg,
        borderRadius: BorderRadius.circular(tokens.metrics.borderRadius),
      ),
      textStyle: textTheme.bodySmall?.copyWith(color: tokens.colors.text),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(tokens.colors.borderStrong),
      trackColor: WidgetStatePropertyAll(tokens.colors.panelAltBg),
      radius: Radius.circular(tokens.metrics.borderRadius),
    ),
  );
}
