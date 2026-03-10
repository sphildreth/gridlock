import 'dart:convert';

import 'workspace_models.dart';

class WorkspaceTabDraft {
  const WorkspaceTabDraft({
    required this.id,
    required this.title,
    required this.sql,
    required this.parameterJson,
    required this.exportPath,
    this.messageHistory = const <QueryMessageEntry>[],
    this.queryHistory = const <QueryHistoryEntry>[],
  });

  final String id;
  final String title;
  final String sql;
  final String parameterJson;
  final String exportPath;
  final List<QueryMessageEntry> messageHistory;
  final List<QueryHistoryEntry> queryHistory;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'sql': sql,
      'parameterJson': parameterJson,
      'exportPath': exportPath,
      'messageHistory': <Map<String, Object?>>[
        for (final entry in messageHistory) entry.toJson(),
      ],
      'queryHistory': <Map<String, Object?>>[
        for (final entry in queryHistory) entry.toJson(),
      ],
    };
  }

  factory WorkspaceTabDraft.fromJson(Map<String, Object?> map) {
    return WorkspaceTabDraft(
      id: map['id']! as String,
      title: map['title']! as String,
      sql: map['sql']! as String,
      parameterJson: map['parameterJson']! as String,
      exportPath: map['exportPath'] as String? ?? '',
      messageHistory: ((map['messageHistory'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (entry) => QueryMessageEntry.fromJson(
              entry.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
      queryHistory: ((map['queryHistory'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (entry) => QueryHistoryEntry.fromJson(
              entry.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
    );
  }
}

class PersistedWorkspaceState {
  const PersistedWorkspaceState({
    required this.schemaVersion,
    required this.activeTabId,
    required this.tabs,
  });

  static const int currentSchemaVersion = 2;

  final int schemaVersion;
  final String? activeTabId;
  final List<WorkspaceTabDraft> tabs;

  factory PersistedWorkspaceState.empty() {
    return const PersistedWorkspaceState(
      schemaVersion: currentSchemaVersion,
      activeTabId: null,
      tabs: <WorkspaceTabDraft>[],
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'activeTabId': activeTabId,
      'tabs': <Map<String, Object?>>[for (final tab in tabs) tab.toJson()],
    };
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory PersistedWorkspaceState.decode(String source) {
    final decoded = jsonDecode(source) as Map<String, Object?>;
    return PersistedWorkspaceState.fromJson(decoded);
  }

  factory PersistedWorkspaceState.fromJson(Map<String, Object?> map) {
    return PersistedWorkspaceState(
      schemaVersion: map['schemaVersion'] as int? ?? currentSchemaVersion,
      activeTabId: map['activeTabId'] as String?,
      tabs: ((map['tabs'] as List?) ?? const <Object?>[])
          .cast<Map<Object?, Object?>>()
          .map(
            (tab) => WorkspaceTabDraft.fromJson(
              tab.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList(),
    );
  }
}
