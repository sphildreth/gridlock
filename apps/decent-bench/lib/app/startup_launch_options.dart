import 'app_metadata.dart';

typedef StartupNoticeHandler =
    Future<void> Function(String title, String message);
typedef StartupOpenDatabaseHandler = Future<void> Function(String path);
typedef StartupStartImportHandler = Future<void> Function(String path);

class StartupLaunchOptions {
  const StartupLaunchOptions({
    this.openDatabasePath,
    this.importSourcePath,
    this.startupNotice,
  });

  final String? openDatabasePath;
  final String? importSourcePath;
  final String? startupNotice;

  bool get hasPendingAction =>
      (openDatabasePath != null && openDatabasePath!.trim().isNotEmpty) ||
      (importSourcePath != null && importSourcePath!.trim().isNotEmpty) ||
      (startupNotice != null && startupNotice!.trim().isNotEmpty);
}

enum StartupCliBehavior { launchApp, printHelp, printVersion }

class StartupCliDecision {
  const StartupCliDecision._({
    required this.behavior,
    this.launchOptions = const StartupLaunchOptions(),
    this.output,
  });

  const StartupCliDecision.launch(StartupLaunchOptions launchOptions)
    : this._(
        behavior: StartupCliBehavior.launchApp,
        launchOptions: launchOptions,
      );

  const StartupCliDecision.printHelp(String output)
    : this._(behavior: StartupCliBehavior.printHelp, output: output);

  const StartupCliDecision.printVersion(String output)
    : this._(behavior: StartupCliBehavior.printVersion, output: output);

  final StartupCliBehavior behavior;
  final StartupLaunchOptions launchOptions;
  final String? output;

  bool get shouldExit => behavior != StartupCliBehavior.launchApp;
}

StartupCliDecision parseStartupCliDecision(List<String> rawArgs) {
  for (final rawArg in rawArgs) {
    final argument = rawArg.trim();
    if (argument.isEmpty) {
      continue;
    }
    if (argument == '--help' || argument == '-h') {
      return StartupCliDecision.printHelp(buildStartupHelpText());
    }
    if (argument == '--version' || argument == '-v') {
      return StartupCliDecision.printVersion(
        '$kDecentBenchDisplayName $kDecentBenchVersion',
      );
    }
  }

  return StartupCliDecision.launch(parseStartupLaunchOptions(rawArgs));
}

StartupLaunchOptions parseStartupLaunchOptions(List<String> rawArgs) {
  String? openDatabasePath;
  String? importSourcePath;
  String? startupNotice;

  for (var index = 0; index < rawArgs.length; index++) {
    final argument = rawArgs[index].trim();
    if (argument.isEmpty) {
      continue;
    }

    if (argument == '--import') {
      final nextIndex = index + 1;
      if (nextIndex >= rawArgs.length) {
        startupNotice ??= '`--import` expects a filename.';
        continue;
      }

      final value = rawArgs[nextIndex].trim();
      if (value.isEmpty || value.startsWith('--')) {
        startupNotice ??= '`--import` expects a filename.';
        continue;
      }

      importSourcePath ??= value;
      index = nextIndex;
      continue;
    }

    if (argument.startsWith('--import=')) {
      final value = argument.substring('--import='.length).trim();
      if (value.isEmpty) {
        startupNotice ??= '`--import` expects a filename.';
        continue;
      }
      importSourcePath ??= value;
      continue;
    }

    if (!argument.startsWith('-')) {
      if (_looksLikeDecentDbPath(argument)) {
        openDatabasePath ??= argument;
      }
    }
  }

  return StartupLaunchOptions(
    openDatabasePath: openDatabasePath,
    importSourcePath: importSourcePath,
    startupNotice: startupNotice,
  );
}

Future<void> applyStartupLaunchOptions(
  StartupLaunchOptions launchOptions, {
  required StartupNoticeHandler showNotice,
  required StartupOpenDatabaseHandler openDatabase,
  required StartupStartImportHandler startImport,
}) async {
  final startupNotice = launchOptions.startupNotice?.trim();
  if (startupNotice != null && startupNotice.isNotEmpty) {
    await showNotice('Command-line import', startupNotice);
    return;
  }

  final openDatabasePath = launchOptions.openDatabasePath?.trim();
  if (openDatabasePath != null && openDatabasePath.isNotEmpty) {
    await openDatabase(openDatabasePath);
    return;
  }

  final importSourcePath = launchOptions.importSourcePath?.trim();
  if (importSourcePath == null || importSourcePath.isEmpty) {
    return;
  }

  await startImport(importSourcePath);
}

String buildStartupHelpText() {
  return '$kDecentBenchDisplayName $kDecentBenchVersion\n'
      '\n'
      'Usage:\n'
      '  dbench [options]\n'
      '\n'
      'Options:\n'
      '  -h, --help\n'
      '      Show this help text and exit.\n'
      '  -v, --version\n'
      '      Show the application version and exit.\n'
      '  --import <path>\n'
      '      Open the import flow for <path> at startup.\n'
      '  --import=<path>\n'
      '      Same as above, using the inline form.\n'
      '\n'
      'Examples:\n'
      '  dbench\n'
      '  dbench /path/to/workspace.ddb\n'
      '  dbench --import /path/to/source.sqlite\n'
      '  dbench --import=/path/to/report.xlsx\n'
      '\n'
      'Notes:\n'
      '  Passing a .ddb path opens that database in the desktop UI.\n'
      '  If <path> is a .ddb database, Decent Bench opens it directly.\n'
      '  Otherwise Decent Bench starts the import workflow for the detected source format.';
}

bool _looksLikeDecentDbPath(String value) {
  return value.trim().toLowerCase().endsWith('.ddb');
}
