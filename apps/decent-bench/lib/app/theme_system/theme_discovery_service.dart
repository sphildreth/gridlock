import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'built_in_theme_sources.dart';
import 'decent_bench_theme.dart';
import 'theme_parser.dart';
import 'theme_presets.dart';
import 'theme_validator.dart';

class ThemeDiscoveryResult {
  const ThemeDiscoveryResult({
    required this.availableThemesById,
    required this.builtInThemesById,
    required this.resolvedThemesDirectory,
    required this.logs,
  });

  final Map<String, DecentBenchTheme> availableThemesById;
  final Map<String, DecentBenchTheme> builtInThemesById;
  final String resolvedThemesDirectory;
  final List<String> logs;

  List<DecentBenchTheme> get availableThemes {
    final items = availableThemesById.values.toList();
    items.sort((left, right) {
      if (left.isBuiltIn != right.isBuiltIn) {
        return left.isBuiltIn ? -1 : 1;
      }
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });
    return items;
  }
}

class ThemeDiscoveryService {
  ThemeDiscoveryService({ThemeParser? parser, ThemeValidator? validator})
    : _parser = parser ?? const ThemeParser(),
      _validator = validator ?? const ThemeValidator();

  final ThemeParser _parser;
  final ThemeValidator _validator;

  Future<ThemeDiscoveryResult> discover({
    String? configuredThemesDirectory,
  }) async {
    final logs = <String>[];
    final resolvedThemesDirectory = resolveThemesDirectory(
      configuredThemesDirectory,
    );
    final builtInThemes = <String, DecentBenchTheme>{};
    final availableThemes = <String, DecentBenchTheme>{};

    _loadBuiltInTheme(
      sourceLabel: 'builtin:classic-dark',
      themeSource: kClassicDarkThemeSource,
      themeId: 'classic-dark',
      themeName: 'Classic Dark',
      builtInThemes: builtInThemes,
      availableThemes: availableThemes,
      logs: logs,
      brightness: Brightness.dark,
    );
    _loadBuiltInTheme(
      sourceLabel: 'builtin:classic-light',
      themeSource: kClassicLightThemeSource,
      themeId: 'classic-light',
      themeName: 'Classic Light',
      builtInThemes: builtInThemes,
      availableThemes: availableThemes,
      logs: logs,
      brightness: Brightness.light,
    );

    final directory = Directory(resolvedThemesDirectory);
    if (!await directory.exists()) {
      logs.add(
        'Themes directory $resolvedThemesDirectory does not exist; using built-in themes only.',
      );
      return ThemeDiscoveryResult(
        availableThemesById: availableThemes,
        builtInThemesById: builtInThemes,
        resolvedThemesDirectory: resolvedThemesDirectory,
        logs: logs,
      );
    }

    final files = await directory
        .list()
        .where(
          (entity) =>
              entity is File && entity.path.toLowerCase().endsWith('.toml'),
        )
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    logs.add(
      'Discovered ${files.length} external theme file${files.length == 1 ? '' : 's'} in $resolvedThemesDirectory.',
    );

    for (final file in files) {
      final parseResult = _parser.parse(
        await file.readAsString(),
        sourceLabel: file.path,
      );
      if (!parseResult.isSuccess) {
        logs.add('Skipping ${file.path}: ${parseResult.error}');
        continue;
      }

      final document = parseResult.document!;
      final fallbackTheme = _fallbackThemeFor(document, builtInThemes);
      final validation = _validator.validate(
        document,
        fallbackTheme: fallbackTheme,
        isBuiltIn: false,
      );
      for (final warning in validation.warnings) {
        logs.add('Theme warning (${file.path}): $warning');
      }
      if (!validation.isSuccess) {
        logs.add('Skipping ${file.path}: ${validation.error}');
        continue;
      }

      final theme = validation.theme!;
      if (availableThemes.containsKey(theme.id)) {
        logs.add(
          'Theme ${theme.id} from ${file.path} overrides an existing theme.',
        );
      }
      availableThemes[theme.id] = theme;
      logs.add('Loaded external theme ${theme.id} from ${file.path}.');
    }

    return ThemeDiscoveryResult(
      availableThemesById: availableThemes,
      builtInThemesById: builtInThemes,
      resolvedThemesDirectory: resolvedThemesDirectory,
      logs: logs,
    );
  }

  static String resolveThemesDirectory(String? configuredThemesDirectory) {
    final trimmed = configuredThemesDirectory?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }

    final home = Platform.environment['HOME'] ?? Directory.current.path;
    if (Platform.isLinux) {
      return p.join(
        Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config'),
        'decent-bench',
        'themes',
      );
    }
    if (Platform.isMacOS) {
      return p.join(
        home,
        'Library',
        'Application Support',
        'Decent Bench',
        'themes',
      );
    }
    if (Platform.isWindows) {
      return p.join(
        Platform.environment['APPDATA'] ?? p.join(home, 'AppData', 'Roaming'),
        'Decent Bench',
        'themes',
      );
    }
    return p.join(home, '.decent-bench', 'themes');
  }

  void _loadBuiltInTheme({
    required String sourceLabel,
    required String themeSource,
    required String themeId,
    required String themeName,
    required Map<String, DecentBenchTheme> builtInThemes,
    required Map<String, DecentBenchTheme> availableThemes,
    required List<String> logs,
    required Brightness brightness,
  }) {
    final emergencyTheme = buildEmergencyTheme(
      brightness: brightness,
      id: themeId,
      name: themeName,
    );
    final parseResult = _parser.parse(themeSource, sourceLabel: sourceLabel);
    if (!parseResult.isSuccess) {
      logs.add(
        'Failed to parse built-in theme $themeId; using emergency fallback. ${parseResult.error}',
      );
      builtInThemes[themeId] = emergencyTheme;
      availableThemes[themeId] = emergencyTheme;
      return;
    }

    final validation = _validator.validate(
      parseResult.document!,
      fallbackTheme: emergencyTheme,
      isBuiltIn: true,
    );
    for (final warning in validation.warnings) {
      logs.add('Theme warning ($sourceLabel): $warning');
    }
    if (!validation.isSuccess) {
      logs.add(
        'Built-in theme $themeId failed validation; using emergency fallback. ${validation.error}',
      );
      builtInThemes[themeId] = emergencyTheme;
      availableThemes[themeId] = emergencyTheme;
      return;
    }

    final theme = validation.theme!;
    builtInThemes[theme.id] = theme;
    availableThemes[theme.id] = theme;
    logs.add('Loaded built-in theme ${theme.id}.');
  }

  DecentBenchTheme _fallbackThemeFor(
    ParsedThemeDocument document,
    Map<String, DecentBenchTheme> builtInThemes,
  ) {
    final rawId = document.topLevel['id'];
    if (rawId is String && builtInThemes.containsKey(rawId.trim())) {
      return builtInThemes[rawId.trim()]!;
    }

    final brightness = document.section('base')['brightness'];
    if (brightness is String && brightness.trim().toLowerCase() == 'light') {
      return builtInThemes['classic-light'] ??
          buildEmergencyTheme(
            brightness: Brightness.light,
            id: 'classic-light',
            name: 'Classic Light',
          );
    }

    return builtInThemes['classic-dark'] ??
        buildEmergencyTheme(
          brightness: Brightness.dark,
          id: 'classic-dark',
          name: 'Classic Dark',
        );
  }
}
