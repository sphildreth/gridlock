import 'dart:io';

import 'package:path/path.dart' as p;

enum NativeLibraryPlatform { linux, macos, windows }

enum NativeLibraryResolutionMode { runtime, packagingSource }

class NativeLibraryResolution {
  const NativeLibraryResolution({
    required this.libraryFileName,
    required this.resolvedPath,
    required this.checkedPaths,
    required this.mode,
    this.requestedEnvPath,
  });

  final String libraryFileName;
  final String resolvedPath;
  final List<String> checkedPaths;
  final NativeLibraryResolutionMode mode;
  final String? requestedEnvPath;
}

class NativeLibraryResolutionFailure implements Exception {
  const NativeLibraryResolutionFailure({
    required this.libraryFileName,
    required this.checkedPaths,
    required this.mode,
    this.requestedEnvPath,
  });

  final String libraryFileName;
  final List<String> checkedPaths;
  final NativeLibraryResolutionMode mode;
  final String? requestedEnvPath;

  String toDisplayMessage() {
    final buffer = StringBuffer()
      ..writeln(
        'Unable to resolve the DecentDB native library ($libraryFileName).',
      );
    if (requestedEnvPath != null && requestedEnvPath!.trim().isNotEmpty) {
      buffer.writeln(
        'DECENTDB_NATIVE_LIB was set but no file was found at: $requestedEnvPath',
      );
    }
    if (checkedPaths.isNotEmpty) {
      buffer
        ..writeln('Checked candidate paths:')
        ..writeln(checkedPaths.map((path) => '- $path').join('\n'));
    }
    buffer.writeln(
      mode == NativeLibraryResolutionMode.runtime
          ? 'Set DECENTDB_NATIVE_LIB, bundle the native library with the desktop app, or build DecentDB under a sibling ../decentdb checkout.'
          : 'Set DECENTDB_NATIVE_LIB or build DecentDB under a sibling ../decentdb checkout before packaging.',
    );
    return buffer.toString().trimRight();
  }

  @override
  String toString() => toDisplayMessage();
}

class NativeLibraryResolver {
  NativeLibraryResolver({
    Map<String, String>? environment,
    String? currentDirectoryPath,
    String? scriptDirectoryPath,
    String? resolvedExecutablePath,
    bool Function(String path)? fileExists,
    NativeLibraryPlatform? platform,
  }) : _environment = environment ?? Platform.environment,
       _currentDirectoryPath = currentDirectoryPath ?? Directory.current.path,
       _scriptDirectoryPath =
           scriptDirectoryPath ??
           File(Platform.script.toFilePath()).parent.path,
       _resolvedExecutablePath =
           resolvedExecutablePath ?? Platform.resolvedExecutable,
       _fileExists = fileExists ?? ((path) => File(path).existsSync()),
       _platform = platform ?? _detectCurrentPlatform();

  final Map<String, String> _environment;
  final String _currentDirectoryPath;
  final String _scriptDirectoryPath;
  final String _resolvedExecutablePath;
  final bool Function(String path) _fileExists;
  final NativeLibraryPlatform _platform;

  Future<String> resolve() async {
    return (await resolveDetailed()).resolvedPath;
  }

  Future<String> resolvePackagingSource() async {
    return (await resolveDetailed(
      mode: NativeLibraryResolutionMode.packagingSource,
    )).resolvedPath;
  }

  Future<NativeLibraryResolution> resolveDetailed({
    NativeLibraryResolutionMode mode = NativeLibraryResolutionMode.runtime,
  }) async {
    final env = _environment['DECENTDB_NATIVE_LIB']?.trim();
    final checkedPaths = <String>[];

    if (env != null && env.isNotEmpty) {
      checkedPaths.add(env);
      if (_fileExists(env)) {
        return NativeLibraryResolution(
          libraryFileName: libraryFileName,
          resolvedPath: env,
          checkedPaths: checkedPaths,
          mode: mode,
          requestedEnvPath: env,
        );
      }
    }

    for (final candidate in candidatePaths(mode: mode)) {
      checkedPaths.add(candidate);
      if (_fileExists(candidate)) {
        return NativeLibraryResolution(
          libraryFileName: libraryFileName,
          resolvedPath: candidate,
          checkedPaths: checkedPaths,
          mode: mode,
          requestedEnvPath: env,
        );
      }
    }

    throw NativeLibraryResolutionFailure(
      libraryFileName: libraryFileName,
      checkedPaths: checkedPaths,
      mode: mode,
      requestedEnvPath: env,
    );
  }

  String get libraryFileName {
    switch (_platform) {
      case NativeLibraryPlatform.linux:
        return 'libc_api.so';
      case NativeLibraryPlatform.macos:
        return 'libc_api.dylib';
      case NativeLibraryPlatform.windows:
        return 'c_api.dll';
    }
  }

  String get bundleRelativeInstallPath {
    switch (_platform) {
      case NativeLibraryPlatform.linux:
        return p.join('lib', libraryFileName);
      case NativeLibraryPlatform.macos:
        return p.join('Contents', 'Frameworks', libraryFileName);
      case NativeLibraryPlatform.windows:
        return libraryFileName;
    }
  }

  List<String> candidatePaths({
    NativeLibraryResolutionMode mode = NativeLibraryResolutionMode.runtime,
  }) {
    final candidates = <String>[];
    if (mode == NativeLibraryResolutionMode.runtime) {
      candidates.addAll(_bundleCandidates());
    }
    candidates.addAll(_searchFrom(_currentDirectoryPath));
    candidates.addAll(_searchFrom(_scriptDirectoryPath));
    return _dedupePaths(candidates);
  }

  Iterable<String> _bundleCandidates() sync* {
    final executableDir = p.dirname(_resolvedExecutablePath);
    switch (_platform) {
      case NativeLibraryPlatform.linux:
        yield p.join(executableDir, 'lib', libraryFileName);
      case NativeLibraryPlatform.macos:
        yield p.join(executableDir, '..', 'Frameworks', libraryFileName);
      case NativeLibraryPlatform.windows:
        yield p.join(executableDir, libraryFileName);
    }
  }

  Iterable<String> _searchFrom(String startPath) sync* {
    var current = Directory(startPath).absolute;
    for (var i = 0; i < 8; i++) {
      yield p.join(current.path, 'native', libraryFileName);
      yield p.join(current.path, 'native', 'lib', libraryFileName);
      yield p.join(current.path, 'build', libraryFileName);
      yield p.join(current.path, '..', 'decentdb', 'build', libraryFileName);
      current = current.parent;
    }
  }

  List<String> _dedupePaths(Iterable<String> candidates) {
    final seen = <String>{};
    final unique = <String>[];
    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (seen.add(normalized)) {
        unique.add(normalized);
      }
    }
    return unique;
  }

  static NativeLibraryPlatform _detectCurrentPlatform() {
    if (Platform.isLinux) {
      return NativeLibraryPlatform.linux;
    }
    if (Platform.isMacOS) {
      return NativeLibraryPlatform.macos;
    }
    if (Platform.isWindows) {
      return NativeLibraryPlatform.windows;
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}
