import 'dart:async';

import 'package:flutter/material.dart';

import 'app_metadata.dart';
import 'startup_launch_options.dart';
import 'theme_system/theme_manager.dart';
import '../features/workspace/application/workspace_controller.dart';
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
  });

  final WorkspaceController? controller;
  final AppLifecycleService appLifecycleService;
  final bool autoInitialize;
  final StartupLaunchOptions startupLaunchOptions;
  final ThemeManager? themeManager;

  @override
  State<DecentBenchApp> createState() => _DecentBenchAppState();
}

class _DecentBenchAppState extends State<DecentBenchApp> {
  late final WorkspaceController _controller =
      widget.controller ?? WorkspaceController();
  late final ThemeManager _themeManager = widget.themeManager ?? ThemeManager();

  String? _lastThemeId;
  String? _lastThemesDir;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
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
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleControllerChanged() {
    _syncThemeFromConfig();
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
            appLifecycleService: widget.appLifecycleService,
            startupLaunchOptions: widget.startupLaunchOptions,
          ),
        );
      },
    );
  }
}
