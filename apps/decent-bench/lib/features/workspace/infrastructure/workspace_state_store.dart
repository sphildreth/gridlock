import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/app_support_paths.dart';
import '../domain/workspace_state.dart';

abstract class WorkspaceStateStore {
  Future<PersistedWorkspaceState?> load(String databasePath);

  Future<void> save(String databasePath, PersistedWorkspaceState state);

  Future<void> clear(String databasePath);
}

class FileWorkspaceStateStore implements WorkspaceStateStore {
  FileWorkspaceStateStore({Directory? rootOverride})
    : _rootOverride = rootOverride;

  final Directory? _rootOverride;

  @override
  Future<PersistedWorkspaceState?> load(String databasePath) async {
    final file = _resolveFile(databasePath);
    if (!await file.exists()) {
      return null;
    }
    return PersistedWorkspaceState.decode(await file.readAsString());
  }

  @override
  Future<void> save(String databasePath, PersistedWorkspaceState state) async {
    final file = _resolveFile(databasePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(state.encode());
  }

  @override
  Future<void> clear(String databasePath) async {
    final file = _resolveFile(databasePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  File _resolveFile(String databasePath) {
    final root = _rootOverride ?? _defaultRootDirectory();
    final encoded = base64Url
        .encode(utf8.encode(databasePath))
        .replaceAll('=', '');
    return File(p.join(root.path, '$encoded.json'));
  }

  Directory _defaultRootDirectory() {
    return Directory(AppSupportPaths.resolveWorkspaceStateDirectoryPath());
  }
}
