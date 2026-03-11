import 'dart:io';

import 'package:path/path.dart' as p;

class AppSupportPaths {
  const AppSupportPaths._();

  static String resolveConfigDirectoryPath() {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    if (Platform.isLinux) {
      return p.join(
        Platform.environment['XDG_CONFIG_HOME'] ?? p.join(home, '.config'),
        'decent-bench',
      );
    }
    if (Platform.isMacOS) {
      return p.join(home, 'Library', 'Application Support', 'Decent Bench');
    }
    if (Platform.isWindows) {
      return p.join(
        Platform.environment['APPDATA'] ?? p.join(home, 'AppData', 'Roaming'),
        'Decent Bench',
      );
    }
    return p.join(home, '.decent-bench');
  }

  static String resolveConfigFilePath() {
    return p.join(resolveConfigDirectoryPath(), 'config.toml');
  }

  static String resolveWorkspaceStateDirectoryPath() {
    return p.join(resolveConfigDirectoryPath(), 'workspaces');
  }

  static String resolveThemesDirectoryPath() {
    return p.join(resolveConfigDirectoryPath(), 'themes');
  }

  static String resolveLogDatabasePath() {
    return p.join(resolveConfigDirectoryPath(), 'decent-bench-log.ddb');
  }
}
