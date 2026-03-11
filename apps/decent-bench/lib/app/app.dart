import 'dart:async';

import 'package:flutter/material.dart';

import 'app_metadata.dart';
import 'logging/app_logger.dart';
import 'startup_launch_options.dart';
import 'theme_system/theme_manager.dart';
import '../features/workspace/application/workspace_controller.dart';
import '../features/workspace/domain/app_config.dart';
import '../features/workspace/infrastructure/app_lifecycle_service.dart';
import '../features/workspace/presentation/workspace_screen.dart';
import 'theme.dart';

class DecentBenchApp extends StatefulWidget {
  const DecentBenchApp({
    super.key,
    this.controller,
    this.appLifecycleService = const FlutterAppLifecycleService(),
    this.autoInitialize = true,
    this.startupLaunchOptions = const StartupLaunchOptions(),
    this.themeManager,
    this.logger,
  });

  final WorkspaceController? controller;
  final AppLifecycleService appLifecycleService;
  final bool autoInitialize;
  final StartupLaunchOptions startupLaunchOptions;
  final ThemeManager? themeManager;
  final AppLogger? logger;

  @override
  State<DecentBenchApp> createState() => _DecentBenchAppState();
}

class _DecentBenchAppState extends State<DecentBenchApp> {
  late final AppLogger _logger = widget.logger ?? DecentBenchLogger();
  late final WorkspaceController _controller =
      widget.controller ?? WorkspaceController(logger: _logger);
  late final ThemeManager _themeManager =
      widget.themeManager ?? ThemeManager(logger: _logger);

  String? _lastThemeId;
  String? _lastThemesDir;
  LogVerbosity? _lastLogVerbosity;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
    unawaited(
      _logger.initialize(minimumLevel: _controller.config.logging.verbosity),
    );
    _syncLoggingFromConfig();
    _syncThemeFromConfig();
    if (widget.autoInitialize) {
      unawaited(_controller.initialize());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    if (widget.themeManager == null) {
      _themeManager.dispose();
    }
    if (widget.logger == null) {
      unawaited(_logger.dispose());
    }
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleControllerChanged() {
    _syncLoggingFromConfig();
    _syncThemeFromConfig();
  }

  void _syncLoggingFromConfig() {
    final verbosity = _controller.config.logging.verbosity;
    if (_lastLogVerbosity == verbosity) {
      return;
    }
    _lastLogVerbosity = verbosity;
    _logger.updateMinimumLevel(verbosity);
  }

  void _syncThemeFromConfig() {
    final appearance = _controller.config.appearance;
    if (_lastThemeId == appearance.activeTheme &&
        _lastThemesDir == appearance.themesDir) {
      return;
    }
    _lastThemeId = appearance.activeTheme;
    _lastThemesDir = appearance.themesDir;
    unawaited(_themeManager.loadFromConfig(appearance));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _themeManager,
      builder: (context, _) {
        return MaterialApp(
          title: kDecentBenchDisplayName,
          debugShowCheckedModeBanner: false,
          theme: buildDecentBenchTheme(_themeManager.currentTheme),
          home: WorkspaceScreen(
            controller: _controller,
            themeManager: _themeManager,
            appLifecycleService: widget.appLifecycleService,
            startupLaunchOptions: widget.startupLaunchOptions,
          ),
        );
      },
    );
  }
}
