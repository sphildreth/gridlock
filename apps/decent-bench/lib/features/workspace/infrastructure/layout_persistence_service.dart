import '../domain/app_config.dart';
import '../domain/workspace_shell_preferences.dart';

class LayoutPersistenceService {
  const LayoutPersistenceService();

  WorkspaceShellPreferences load(AppConfig config) {
    return config.shellPreferences.normalized();
  }

  AppConfig save(AppConfig config, WorkspaceShellPreferences preferences) {
    return config.copyWith(shellPreferences: preferences.normalized());
  }
}
