import 'dart:io';

import 'package:decent_bench/app/theme_system/built_in_theme_assets.dart';
import 'package:decent_bench/app/theme_system/theme_discovery_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'theme discovery returns built-in themes even with empty external directory',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'decent-bench-themes-empty-',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final service = ThemeDiscoveryService();
      final result = await service.discover(
        configuredThemesDirectory: directory.path,
      );

      expect(result.availableThemesById.containsKey('classic-dark'), isTrue);
      expect(result.availableThemesById.containsKey('classic-light'), isTrue);
      expect(result.availableThemes.length, kBuiltInThemeAssets.length);
      expect(
        result.availableThemesById['classic-dark']!.metadata.description,
        'A dense, classic dark desktop theme inspired by traditional database tools.',
      );
      expect(
        result.availableThemesById['classic-light']!.metadata.description,
        'A dense, classic light desktop theme for practical database work.',
      );
    },
  );

  test('built-in theme assets stay in sync with repo theme files', () async {
    for (final asset in kBuiltInThemeAssets) {
      final assetSource = await rootBundle.loadString(asset.assetPath);
      final repoSource = await File(
        '../../themes/${asset.id}.toml',
      ).readAsString();

      expect(assetSource, repoSource, reason: asset.id);
    }
  });
}
