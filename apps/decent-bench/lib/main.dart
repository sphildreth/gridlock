import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/startup_launch_options.dart';

void main(List<String> args) {
  final cliDecision = parseStartupCliDecision(args);
  if (cliDecision.shouldExit) {
    stdout.writeln(cliDecision.output ?? '');
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  runApp(DecentBenchApp(startupLaunchOptions: cliDecision.launchOptions));
}
