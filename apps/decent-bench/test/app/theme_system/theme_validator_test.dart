import 'package:decent_bench/app/theme_system/built_in_theme_sources.dart';
import 'package:decent_bench/app/theme_system/theme_parser.dart';
import 'package:decent_bench/app/theme_system/theme_presets.dart';
import 'package:decent_bench/app/theme_system/theme_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ThemeParser();
  const validator = ThemeValidator();

  test('valid theme TOML loads successfully', () {
    final parsed = parser.parse(
      kClassicDarkThemeSource,
      sourceLabel: 'classic-dark.toml',
    );

    expect(parsed.isSuccess, isTrue);
    final result = validator.validate(
      parsed.document!,
      fallbackTheme: buildEmergencyTheme(),
      isBuiltIn: true,
    );

    expect(result.isSuccess, isTrue);
    expect(result.theme!.id, 'classic-dark');
    expect(result.theme!.editor.background, const Color(0xFF1E1E1E));
    expect(result.theme!.sqlSyntax.keyword, const Color(0xFFC586C0));
  });

  test('invalid color format is rejected', () {
    final parsed = parser.parse(
      kClassicDarkThemeSource.replaceFirst('#7C5CFF', '#12345'),
      sourceLabel: 'broken.toml',
    );
    final result = validator.validate(
      parsed.document!,
      fallbackTheme: buildEmergencyTheme(),
      isBuiltIn: false,
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('Invalid color'));
  });

  test('missing optional keys fall back correctly', () {
    const partialTheme = '''
name = "Partial"
id = "partial"
version = "1.0.0"

[compatibility]
min_decent_bench_version = "0.1.0"

[base]
brightness = "dark"

[colors]
accent = "#AA66FF"
''';

    final parsed = parser.parse(partialTheme, sourceLabel: 'partial.toml');
    final fallback = buildEmergencyTheme();
    final result = validator.validate(
      parsed.document!,
      fallbackTheme: fallback,
      isBuiltIn: false,
    );

    expect(result.isSuccess, isTrue);
    expect(result.theme!.colors.accent, const Color(0xFFAA66FF));
    expect(result.theme!.menu.background, fallback.menu.background);
    expect(result.theme!.fonts.editorFamily, fallback.fonts.editorFamily);
  });

  test('incompatible version is rejected', () {
    const incompatibleTheme = '''
name = "Future"
id = "future"
version = "1.0.0"

[compatibility]
min_decent_bench_version = "9.0.0"
''';

    final parsed = parser.parse(incompatibleTheme, sourceLabel: 'future.toml');
    final result = validator.validate(
      parsed.document!,
      fallbackTheme: buildEmergencyTheme(),
      isBuiltIn: false,
    );

    expect(result.isSuccess, isFalse);
    expect(result.error, contains('requires Decent Bench 9.0.0 or newer'));
  });

  test('unknown keys do not crash parsing', () {
    const futureFriendlyTheme = '''
name = "Unknown Keys"
id = "unknown-keys"
version = "1.0.0"
author = "Tester"

[compatibility]
min_decent_bench_version = "0.1.0"

[colors]
accent = "#AA66FF"
future_token = "#FFFFFF"

[future_section]
surprise = "value"
''';

    final parsed = parser.parse(
      futureFriendlyTheme,
      sourceLabel: 'unknown-keys.toml',
    );
    final result = validator.validate(
      parsed.document!,
      fallbackTheme: buildEmergencyTheme(),
      isBuiltIn: false,
    );

    expect(result.isSuccess, isTrue);
    expect(result.warnings, isNotEmpty);
    expect(
      result.warnings.any((warning) => warning.contains('future_section')),
      isTrue,
    );
  });
}
