import 'package:decent_bench/app/theme_system/built_in_theme_assets.dart';
import 'package:decent_bench/app/theme_system/theme_parser.dart';
import 'package:decent_bench/app/theme_system/theme_presets.dart';
import 'package:decent_bench/app/theme_system/theme_validator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const parser = ThemeParser();
  const validator = ThemeValidator();

  test('valid theme TOML loads successfully', () async {
    final themeSource = await rootBundle.loadString(
      'assets/themes/classic-dark.toml',
    );
    final parsed = parser.parse(themeSource, sourceLabel: 'classic-dark.toml');

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

  test('all built-in theme TOML assets load successfully', () async {
    for (final asset in kBuiltInThemeAssets) {
      final themeSource = await rootBundle.loadString(asset.assetPath);
      final parsed = parser.parse(themeSource, sourceLabel: asset.assetPath);

      expect(parsed.isSuccess, isTrue, reason: asset.assetPath);
      final result = validator.validate(
        parsed.document!,
        fallbackTheme: buildEmergencyTheme(
          brightness: asset.brightness,
          id: asset.id,
          name: asset.name,
        ),
        isBuiltIn: true,
      );

      expect(result.isSuccess, isTrue, reason: asset.assetPath);
      expect(result.theme!.id, asset.id, reason: asset.assetPath);
    }
  });

  test('invalid color format is rejected', () async {
    final themeSource = await rootBundle.loadString(
      'assets/themes/classic-dark.toml',
    );
    final parsed = parser.parse(
      themeSource.replaceFirst('#7C5CFF', '#12345'),
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
