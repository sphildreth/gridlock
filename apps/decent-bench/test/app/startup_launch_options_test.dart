import 'package:decent_bench/app/startup_launch_options.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns a help decision for --help', () {
    final decision = parseStartupCliDecision(<String>['--help']);

    expect(decision.behavior, StartupCliBehavior.printHelp);
    expect(decision.shouldExit, isTrue);
    expect(decision.output, contains('Usage:'));
    expect(decision.output, contains('dbench /path/to/workspace.ddb'));
    expect(decision.output, contains('--import <path>'));
    expect(decision.output, contains('--version'));
  });

  test('returns a version decision for --version', () {
    final decision = parseStartupCliDecision(<String>['--version']);

    expect(decision.behavior, StartupCliBehavior.printVersion);
    expect(decision.shouldExit, isTrue);
    expect(decision.output, contains('Decent Bench'));
  });

  test('parses --import filename form', () {
    final options = parseStartupLaunchOptions(<String>[
      '--import',
      '/tmp/source.xlsx',
    ]);

    expect(options.openDatabasePath, isNull);
    expect(options.importSourcePath, '/tmp/source.xlsx');
    expect(options.startupNotice, isNull);
  });

  test('parses a positional .ddb path for direct open', () {
    final options = parseStartupLaunchOptions(<String>['/tmp/workspace.ddb']);

    expect(options.openDatabasePath, '/tmp/workspace.ddb');
    expect(options.importSourcePath, isNull);
    expect(options.startupNotice, isNull);
  });

  test('parses --import=filename form', () {
    final options = parseStartupLaunchOptions(<String>[
      '--import=/tmp/source.sqlite',
    ]);

    expect(options.openDatabasePath, isNull);
    expect(options.importSourcePath, '/tmp/source.sqlite');
    expect(options.startupNotice, isNull);
  });

  test('reports a notice when --import is missing a filename', () {
    final options = parseStartupLaunchOptions(<String>['--import']);

    expect(options.openDatabasePath, isNull);
    expect(options.importSourcePath, isNull);
    expect(options.startupNotice, '`--import` expects a filename.');
  });

  test('dispatches a positional .ddb path to direct open', () async {
    String? openedPath;
    String? importedPath;
    String? noticeTitle;
    String? noticeMessage;

    await applyStartupLaunchOptions(
      const StartupLaunchOptions(openDatabasePath: '/tmp/workspace.ddb'),
      showNotice: (title, message) async {
        noticeTitle = title;
        noticeMessage = message;
      },
      openDatabase: (path) async {
        openedPath = path;
      },
      startImport: (path) async {
        importedPath = path;
      },
    );

    expect(openedPath, '/tmp/workspace.ddb');
    expect(importedPath, isNull);
    expect(noticeTitle, isNull);
    expect(noticeMessage, isNull);
  });

  test('dispatches --import paths to the import flow', () async {
    String? openedPath;
    String? importedPath;

    await applyStartupLaunchOptions(
      const StartupLaunchOptions(importSourcePath: '/tmp/source.xlsx'),
      showNotice: (ignoredTitle, ignoredMessage) async {},
      openDatabase: (path) async {
        openedPath = path;
      },
      startImport: (path) async {
        importedPath = path;
      },
    );

    expect(openedPath, isNull);
    expect(importedPath, '/tmp/source.xlsx');
  });

  test('dispatches startup notices before open/import actions', () async {
    String? openedPath;
    String? importedPath;
    String? noticeTitle;
    String? noticeMessage;

    await applyStartupLaunchOptions(
      const StartupLaunchOptions(
        openDatabasePath: '/tmp/workspace.ddb',
        importSourcePath: '/tmp/source.xlsx',
        startupNotice: '`--import` expects a filename.',
      ),
      showNotice: (title, message) async {
        noticeTitle = title;
        noticeMessage = message;
      },
      openDatabase: (path) async {
        openedPath = path;
      },
      startImport: (path) async {
        importedPath = path;
      },
    );

    expect(noticeTitle, 'Command-line import');
    expect(noticeMessage, '`--import` expects a filename.');
    expect(openedPath, isNull);
    expect(importedPath, isNull);
  });
}
