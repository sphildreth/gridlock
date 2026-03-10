import 'package:flutter/foundation.dart';

import '../../features/workspace/domain/app_config.dart';
import 'decent_bench_theme.dart';
import 'theme_discovery_service.dart';
import 'theme_presets.dart';

class ThemeManager extends ChangeNotifier {
  ThemeManager({ThemeDiscoveryService? discoveryService})
    : _discoveryService = discoveryService ?? ThemeDiscoveryService(),
      _currentTheme = buildEmergencyTheme();

  final ThemeDiscoveryService _discoveryService;

  DecentBenchTheme _currentTheme;
  List<DecentBenchTheme> _availableThemes = <DecentBenchTheme>[
    buildEmergencyTheme(),
  ];
  String _resolvedThemesDirectory =
      ThemeDiscoveryService.resolveThemesDirectory(null);
  AppearanceSettings _lastAppearance = AppearanceSettings.defaults();

  DecentBenchTheme get currentTheme => _currentTheme;
  List<DecentBenchTheme> get availableThemes =>
      List<DecentBenchTheme>.unmodifiable(_availableThemes);
  String get resolvedThemesDirectory => _resolvedThemesDirectory;

  Future<void> loadFromConfig(AppearanceSettings appearance) async {
    _lastAppearance = appearance;
    final discovery = await _discoveryService.discover(
      configuredThemesDirectory: appearance.themesDir,
    );
    _resolvedThemesDirectory = discovery.resolvedThemesDirectory;
    _availableThemes = discovery.availableThemes;
    for (final log in discovery.logs) {
      debugPrint('[theme] $log');
    }

    final selected = discovery.availableThemesById[appearance.activeTheme];
    if (selected != null) {
      _currentTheme = selected;
      notifyListeners();
      return;
    }

    debugPrint(
      '[theme] Failed to activate "${appearance.activeTheme}". Falling back to built-in classic-dark.',
    );
    _currentTheme =
        discovery.builtInThemesById['classic-dark'] ?? buildEmergencyTheme();
    notifyListeners();
  }

  Future<void> switchTheme(String themeId) async {
    for (final theme in _availableThemes) {
      if (theme.id == themeId) {
        _currentTheme = theme;
        notifyListeners();
        return;
      }
    }

    debugPrint(
      '[theme] Requested theme "$themeId" is not available. Keeping ${_currentTheme.id}.',
    );
  }

  Future<void> reload() => loadFromConfig(_lastAppearance);
}
