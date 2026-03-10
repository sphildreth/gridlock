import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/workspace_shell_preferences.dart';

typedef PersistShellPreferences =
    Future<void> Function(
      WorkspaceShellPreferences preferences, {
      String? statusMessage,
    });

class WorkspaceShellController extends ChangeNotifier {
  WorkspaceShellController({
    required WorkspaceShellPreferences initialPreferences,
    required PersistShellPreferences onPersist,
  }) : _preferences = initialPreferences.normalized(),
       _onPersist = onPersist;

  final PersistShellPreferences _onPersist;
  WorkspaceShellPreferences _preferences;
  Timer? _persistDebounce;

  WorkspaceShellPreferences get preferences => _preferences;

  void replacePreferences(WorkspaceShellPreferences next) {
    _preferences = next.normalized();
    notifyListeners();
  }

  void setLeftColumnFraction(double value) {
    _setPreferences(
      _preferences.copyWith(leftColumnFraction: value),
      immediate: false,
    );
  }

  void setLeftTopFraction(double value) {
    _setPreferences(
      _preferences.copyWith(leftTopFraction: value),
      immediate: false,
    );
  }

  void setRightTopFraction(double value) {
    _setPreferences(
      _preferences.copyWith(rightTopFraction: value),
      immediate: false,
    );
  }

  void setSchemaExplorerVisible(bool value) {
    _setPreferences(_preferences.copyWith(showSchemaExplorer: value));
  }

  void setPropertiesPaneVisible(bool value) {
    _setPreferences(_preferences.copyWith(showPropertiesPane: value));
  }

  void setResultsPaneVisible(bool value) {
    _setPreferences(_preferences.copyWith(showResultsPane: value));
  }

  void setStatusBarVisible(bool value) {
    _setPreferences(_preferences.copyWith(showStatusBar: value));
  }

  void setActiveResultsTab(ResultsPaneTab tab) {
    _setPreferences(_preferences.copyWith(activeResultsTab: tab));
  }

  void zoomIn() {
    final next = _preferences.copyWith(
      editorZoom: _preferences.editorZoom + 0.1,
    );
    _setPreferences(
      next,
      statusMessage:
          'Zoom set to ${(next.editorZoom * 100).round().clamp(80, 140)}%.',
    );
  }

  void zoomOut() {
    final next = _preferences.copyWith(
      editorZoom: _preferences.editorZoom - 0.1,
    );
    _setPreferences(
      next,
      statusMessage:
          'Zoom set to ${(next.editorZoom * 100).round().clamp(80, 140)}%.',
    );
  }

  void resetZoom() {
    _setPreferences(
      _preferences.copyWith(editorZoom: 1.0),
      statusMessage: 'Zoom reset to 100%.',
    );
  }

  void resetLayout() {
    _setPreferences(
      WorkspaceShellPreferences.defaults(),
      statusMessage: 'Workspace layout reset.',
    );
  }

  String get zoomPercentLabel =>
      '${(_preferences.editorZoom * 100).round().clamp(80, 140)}%';

  Future<void> persistNow({String? statusMessage}) async {
    _persistDebounce?.cancel();
    await _onPersist(_preferences, statusMessage: statusMessage);
  }

  void _setPreferences(
    WorkspaceShellPreferences next, {
    bool immediate = true,
    String? statusMessage,
  }) {
    _preferences = next.normalized();
    notifyListeners();
    if (immediate || statusMessage != null) {
      unawaited(persistNow(statusMessage: statusMessage));
      return;
    }
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_onPersist(_preferences));
    });
  }

  @override
  void dispose() {
    _persistDebounce?.cancel();
    super.dispose();
  }
}
