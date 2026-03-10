import 'dart:ui' as ui;

import 'package:flutter/services.dart';

abstract class AppLifecycleService {
  Future<void> requestExit();
}

class FlutterAppLifecycleService implements AppLifecycleService {
  const FlutterAppLifecycleService();

  @override
  Future<void> requestExit() async {
    await ServicesBinding.instance.exitApplication(ui.AppExitType.required);
  }
}
