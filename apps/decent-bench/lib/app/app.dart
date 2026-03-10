import 'package:flutter/material.dart';

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
  });

  final WorkspaceController? controller;
  final AppLifecycleService appLifecycleService;
  final bool autoInitialize;

  @override
  State<DecentBenchApp> createState() => _DecentBenchAppState();
}

class _DecentBenchAppState extends State<DecentBenchApp> {
  late final WorkspaceController _controller =
      widget.controller ?? WorkspaceController();

  @override
  void initState() {
    super.initState();
    if (widget.autoInitialize) {
      _controller.initialize();
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Decent Bench',
      debugShowCheckedModeBanner: false,
      theme: buildDecentBenchTheme(),
      home: WorkspaceScreen(
        controller: _controller,
        appLifecycleService: widget.appLifecycleService,
      ),
    );
  }
}
