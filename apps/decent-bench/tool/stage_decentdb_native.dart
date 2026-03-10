import 'dart:io';

import 'package:decent_bench/features/workspace/infrastructure/native_library_resolver.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  late final Map<String, String?> options;
  try {
    options = _parseArgs(args);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage(stderr);
    exitCode = 64;
    return;
  }
  final bundlePath = options['bundle']?.trim() ?? '';
  final sourcePath = options['source']?.trim();
  final verifyOnly = options.containsKey('verify-only');

  if (bundlePath.isEmpty) {
    _printUsage(stderr);
    exitCode = 64;
    return;
  }

  final resolver = NativeLibraryResolver();
  final destinationPath = p.join(
    bundlePath,
    resolver.bundleRelativeInstallPath,
  );
  final destinationFile = File(destinationPath);

  if (verifyOnly) {
    if (!destinationFile.existsSync()) {
      stderr.writeln(
        'Expected bundled DecentDB native library at $destinationPath, but no file was found.',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'Verified bundled DecentDB native library: $destinationPath',
    );
    return;
  }

  final sourceFile = File(
    sourcePath?.isNotEmpty == true
        ? sourcePath!
        : await resolver.resolvePackagingSource(),
  );
  if (!sourceFile.existsSync()) {
    stderr.writeln(
      'Resolved DecentDB native library source file does not exist: ${sourceFile.path}',
    );
    exitCode = 1;
    return;
  }

  await destinationFile.parent.create(recursive: true);
  await sourceFile.copy(destinationFile.path);
  stdout.writeln('Staged ${sourceFile.path} -> ${destinationFile.path}');
}

Map<String, String?> _parseArgs(List<String> args) {
  final options = <String, String?>{};
  for (var i = 0; i < args.length; i++) {
    final argument = args[i];
    switch (argument) {
      case '--bundle':
        if (i + 1 >= args.length) {
          throw const FormatException('--bundle requires a value.');
        }
        options['bundle'] = args[++i];
        break;
      case '--source':
        if (i + 1 >= args.length) {
          throw const FormatException('--source requires a value.');
        }
        options['source'] = args[++i];
        break;
      case '--verify-only':
        options['verify-only'] = 'true';
        break;
      case '--help':
      case '-h':
        _printUsage(stdout);
        exit(0);
      default:
        throw FormatException('Unknown argument: $argument');
    }
  }
  return options;
}

void _printUsage(IOSink sink) {
  sink.writeln(
    'Usage: dart run tool/stage_decentdb_native.dart --bundle <bundle-path> [--source <native-lib-path>] [--verify-only]',
  );
}
