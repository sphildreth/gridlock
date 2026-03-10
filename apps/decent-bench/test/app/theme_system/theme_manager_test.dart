import 'dart:io';

import 'package:decent_bench/app/theme_system/theme_manager.dart';
import 'package:decent_bench/features/workspace/domain/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('built-in fallback theme loads when external theme fails', () async {
    final directory = await Directory.systemTemp.createTemp(
      'decent-bench-themes-invalid-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final file = File('${directory.path}/broken.toml');
    await file.writeAsString('''
name = "Broken"
id = "broken"
version = "1.0.0"

[compatibility]
min_decent_bench_version = "0.1.0"

[colors]
accent = "#12"
''');

    final manager = ThemeManager();
    addTearDown(manager.dispose);

    await manager.loadFromConfig(
      AppearanceSettings(activeTheme: 'broken', themesDir: directory.path),
    );

    expect(manager.currentTheme.id, 'classic-dark');
    expect(
      manager.availableThemes.any((theme) => theme.id == 'broken'),
      isFalse,
    );
  });
}
