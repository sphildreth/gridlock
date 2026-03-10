import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/app_config.dart';

abstract class WorkspaceConfigStore {
  Future<AppConfig> load();

  Future<void> save(AppConfig config);

  String describeLocation();
}

class AppConfigStore implements WorkspaceConfigStore {
  AppConfigStore({File? fileOverride}) : _fileOverride = fileOverride;

  final File? _fileOverride;

  @override
  Future<AppConfig> load() async {
    final file = _resolveFile();
    if (!await file.exists()) {
      return AppConfig.defaults();
    }
    return AppConfig.fromToml(await file.readAsString());
  }

  @override
  Future<void> save(AppConfig config) async {
    final file = _resolveFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(config.toToml());
  }

  @override
  String describeLocation() => _resolveFile().path;

  File _resolveFile() {
    if (_fileOverride != null) {
      return _fileOverride;
    }

    final home = Platform.environment['HOME'] ?? Directory.current.path;
    if (Platform.isLinux) {
      return File(
        p.join(
          Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config'),
          'decent-bench',
          'config.toml',
        ),
      );
    }
    if (Platform.isMacOS) {
      return File(
        p.join(
          home,
          'Library',
          'Application Support',
          'Decent Bench',
          'config.toml',
        ),
      );
    }
    if (Platform.isWindows) {
      return File(
        p.join(
          Platform.environment['APPDATA'] ?? p.join(home, 'AppData', 'Roaming'),
          'Decent Bench',
          'config.toml',
        ),
      );
    }
    return File(p.join(home, '.decent-bench', 'config.toml'));
  }
}
