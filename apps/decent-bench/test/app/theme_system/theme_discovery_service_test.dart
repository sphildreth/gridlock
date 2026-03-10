import 'dart:io';

import 'package:decent_bench/app/theme_system/theme_discovery_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      expect(result.availableThemes.length, 2);
    },
  );
}
