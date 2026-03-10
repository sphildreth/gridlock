import 'dart:convert';

import 'workspace_shell_preferences.dart';

class SqlSnippet {
  const SqlSnippet({
    required this.id,
    required this.name,
    required this.trigger,
    required this.body,
    this.description = '',
  });

  final String id;
  final String name;
  final String trigger;
  final String description;
  final String body;

  SqlSnippet copyWith({
    String? id,
    String? name,
    String? trigger,
    String? description,
    String? body,
  }) {
    return SqlSnippet(
      id: id ?? this.id,
      name: name ?? this.name,
      trigger: trigger ?? this.trigger,
      description: description ?? this.description,
      body: body ?? this.body,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'trigger': trigger,
      'description': description,
      'body': body,
    };
  }

  factory SqlSnippet.fromJson(Map<String, Object?> map) {
    return SqlSnippet(
      id: map['id']! as String,
      name: map['name']! as String,
      trigger: map['trigger']! as String,
      description: map['description'] as String? ?? '',
      body: map['body']! as String,
    );
  }
}

class EditorSettings {
  static const bool defaultAutocompleteEnabled = true;
  static const int defaultAutocompleteMaxSuggestions = 12;
  static const bool defaultFormatUppercaseKeywords = true;
  static const int defaultIndentSpaces = 2;

  const EditorSettings({
    required this.autocompleteEnabled,
    required this.autocompleteMaxSuggestions,
    required this.formatUppercaseKeywords,
    required this.indentSpaces,
  });

  final bool autocompleteEnabled;
  final int autocompleteMaxSuggestions;
  final bool formatUppercaseKeywords;
  final int indentSpaces;

  factory EditorSettings.defaults() {
    return const EditorSettings(
      autocompleteEnabled: defaultAutocompleteEnabled,
      autocompleteMaxSuggestions: defaultAutocompleteMaxSuggestions,
      formatUppercaseKeywords: defaultFormatUppercaseKeywords,
      indentSpaces: defaultIndentSpaces,
    );
  }

  EditorSettings copyWith({
    bool? autocompleteEnabled,
    int? autocompleteMaxSuggestions,
    bool? formatUppercaseKeywords,
    int? indentSpaces,
  }) {
    return EditorSettings(
      autocompleteEnabled: autocompleteEnabled ?? this.autocompleteEnabled,
      autocompleteMaxSuggestions:
          autocompleteMaxSuggestions ?? this.autocompleteMaxSuggestions,
      formatUppercaseKeywords:
          formatUppercaseKeywords ?? this.formatUppercaseKeywords,
      indentSpaces: indentSpaces ?? this.indentSpaces,
    );
  }
}

class AppearanceSettings {
  static const String defaultActiveTheme = 'classic-dark';
  static const Object _unset = Object();

  const AppearanceSettings({required this.activeTheme, this.themesDir});

  final String activeTheme;
  final String? themesDir;

  factory AppearanceSettings.defaults() {
    return const AppearanceSettings(activeTheme: defaultActiveTheme);
  }

  AppearanceSettings copyWith({
    String? activeTheme,
    Object? themesDir = _unset,
  }) {
    return AppearanceSettings(
      activeTheme: activeTheme ?? this.activeTheme,
      themesDir: themesDir == _unset ? this.themesDir : themesDir as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppearanceSettings &&
        other.activeTheme == activeTheme &&
        other.themesDir == themesDir;
  }

  @override
  int get hashCode => Object.hash(activeTheme, themesDir);
}

class AppConfig {
  static const int currentConfigVersion = 1;
  static const int defaultPageSizeValue = 1000;
  static const String defaultCsvDelimiter = ',';
  static const bool defaultCsvIncludeHeaders = true;
  static const int maxRecentFiles = 8;

  const AppConfig({
    required this.configVersion,
    required this.appearance,
    required this.recentFiles,
    required this.defaultPageSize,
    required this.csvDelimiter,
    required this.csvIncludeHeaders,
    required this.editorSettings,
    required this.shellPreferences,
    required this.shortcutBindings,
    required this.snippets,
  });

  final int configVersion;
  final AppearanceSettings appearance;
  final List<String> recentFiles;
  final int defaultPageSize;
  final String csvDelimiter;
  final bool csvIncludeHeaders;
  final EditorSettings editorSettings;
  final WorkspaceShellPreferences shellPreferences;
  final Map<String, String> shortcutBindings;
  final List<SqlSnippet> snippets;

  factory AppConfig.defaults() {
    return AppConfig(
      configVersion: currentConfigVersion,
      appearance: AppearanceSettings.defaults(),
      recentFiles: const <String>[],
      defaultPageSize: defaultPageSizeValue,
      csvDelimiter: defaultCsvDelimiter,
      csvIncludeHeaders: defaultCsvIncludeHeaders,
      editorSettings: EditorSettings.defaults(),
      shellPreferences: WorkspaceShellPreferences.defaults(),
      shortcutBindings: defaultShortcutBindings(),
      snippets: defaultSnippets(),
    );
  }

  AppConfig copyWith({
    int? configVersion,
    AppearanceSettings? appearance,
    List<String>? recentFiles,
    int? defaultPageSize,
    String? csvDelimiter,
    bool? csvIncludeHeaders,
    EditorSettings? editorSettings,
    WorkspaceShellPreferences? shellPreferences,
    Map<String, String>? shortcutBindings,
    List<SqlSnippet>? snippets,
  }) {
    return AppConfig(
      configVersion: configVersion ?? this.configVersion,
      appearance: appearance ?? this.appearance,
      recentFiles: recentFiles ?? this.recentFiles,
      defaultPageSize: defaultPageSize ?? this.defaultPageSize,
      csvDelimiter: csvDelimiter ?? this.csvDelimiter,
      csvIncludeHeaders: csvIncludeHeaders ?? this.csvIncludeHeaders,
      editorSettings: editorSettings ?? this.editorSettings,
      shellPreferences: shellPreferences ?? this.shellPreferences,
      shortcutBindings: shortcutBindings ?? this.shortcutBindings,
      snippets: snippets ?? this.snippets,
    );
  }

  AppConfig pushRecentFile(String path) {
    final updated = <String>[
      path,
      ...recentFiles.where((item) => item != path),
    ];
    return copyWith(recentFiles: updated.take(maxRecentFiles).toList());
  }

  AppConfig upsertSnippet(SqlSnippet snippet) {
    final existingIndex = snippets.indexWhere((item) => item.id == snippet.id);
    final updated = <SqlSnippet>[...snippets];
    if (existingIndex >= 0) {
      updated[existingIndex] = snippet;
    } else {
      updated.add(snippet);
    }
    updated.sort((left, right) => left.name.compareTo(right.name));
    return copyWith(snippets: updated);
  }

  AppConfig removeSnippet(String snippetId) {
    return copyWith(
      snippets: snippets.where((item) => item.id != snippetId).toList(),
    );
  }

  String toToml() {
    final layout = shellPreferences.normalized();
    final buffer = StringBuffer()
      ..writeln('# Decent Bench configuration')
      ..writeln('config_version = $configVersion')
      ..writeln('default_page_size = $defaultPageSize')
      ..writeln('csv_delimiter = ${jsonEncode(csvDelimiter)}')
      ..writeln('csv_include_headers = $csvIncludeHeaders')
      ..writeln('recent_files = ${jsonEncode(recentFiles)}')
      ..writeln(
        'editor_autocomplete_enabled = ${editorSettings.autocompleteEnabled}',
      )
      ..writeln(
        'editor_autocomplete_max_suggestions = ${editorSettings.autocompleteMaxSuggestions}',
      )
      ..writeln(
        'editor_format_uppercase_keywords = ${editorSettings.formatUppercaseKeywords}',
      )
      ..writeln('editor_indent_spaces = ${editorSettings.indentSpaces}')
      ..writeln('editor_snippet_count = ${snippets.length}')
      ..writeln()
      ..writeln('[appearance]')
      ..writeln('active_theme = ${jsonEncode(appearance.activeTheme)}');

    if (appearance.themesDir != null &&
        appearance.themesDir!.trim().isNotEmpty) {
      buffer.writeln('themes_dir = ${jsonEncode(appearance.themesDir)}');
    }

    buffer
      ..writeln()
      ..writeln('[layout]')
      ..writeln(
        'left_column_fraction = ${_formatDouble(layout.leftColumnFraction)}',
      )
      ..writeln('left_top_fraction = ${_formatDouble(layout.leftTopFraction)}')
      ..writeln(
        'right_top_fraction = ${_formatDouble(layout.rightTopFraction)}',
      )
      ..writeln('show_schema_explorer = ${layout.showSchemaExplorer}')
      ..writeln('show_properties_pane = ${layout.showPropertiesPane}')
      ..writeln('show_results_pane = ${layout.showResultsPane}')
      ..writeln('show_status_bar = ${layout.showStatusBar}')
      ..writeln('editor_zoom = ${_formatDouble(layout.editorZoom)}')
      ..writeln(
        'active_results_tab = ${jsonEncode(WorkspaceShellPreferences.encodeResultsTab(layout.activeResultsTab))}',
      )
      ..writeln()
      ..writeln('[shortcuts]');

    final sortedShortcutKeys = shortcutBindings.keys.toList()..sort();
    for (final key in sortedShortcutKeys) {
      buffer.writeln('$key = ${jsonEncode(shortcutBindings[key])}');
    }

    for (final snippet in snippets) {
      buffer
        ..writeln()
        ..writeln('[[editor_snippets]]')
        ..writeln('id = ${jsonEncode(snippet.id)}')
        ..writeln('name = ${jsonEncode(snippet.name)}')
        ..writeln('trigger = ${jsonEncode(snippet.trigger)}')
        ..writeln('description = ${jsonEncode(snippet.description)}')
        ..writeln('body = ${jsonEncode(snippet.body)}');
    }
    return buffer.toString();
  }

  static AppConfig fromToml(String source) {
    var config = AppConfig.defaults();
    final parsedSnippets = <SqlSnippet>[];
    Map<String, Object?>? pendingSnippet;
    int? declaredSnippetCount;
    String? currentTable;

    void flushSnippet() {
      if (pendingSnippet == null) {
        return;
      }
      try {
        parsedSnippets.add(SqlSnippet.fromJson(pendingSnippet!));
      } catch (_) {
        // Ignore malformed snippet entries and keep loading the rest.
      }
      pendingSnippet = null;
    }

    for (final rawLine in const LineSplitter().convert(source)) {
      final commentFree = _stripTomlComment(rawLine).trim();
      if (commentFree.isEmpty) {
        continue;
      }
      if (commentFree.startsWith('[[') && commentFree.endsWith(']]')) {
        flushSnippet();
        currentTable = commentFree.substring(2, commentFree.length - 2).trim();
        if (currentTable == 'editor_snippets') {
          pendingSnippet = <String, Object?>{};
        }
        continue;
      }
      if (commentFree.startsWith('[') && commentFree.endsWith(']')) {
        flushSnippet();
        currentTable = commentFree.substring(1, commentFree.length - 1).trim();
        continue;
      }
      if (!commentFree.contains('=')) {
        continue;
      }

      final separatorIndex = commentFree.indexOf('=');
      final key = commentFree.substring(0, separatorIndex).trim();
      final value = commentFree.substring(separatorIndex + 1).trim();

      if (pendingSnippet != null && currentTable == 'editor_snippets') {
        final parsed = _decodeJsonString(value);
        if (parsed != null &&
            const <String>{
              'id',
              'name',
              'trigger',
              'description',
              'body',
            }.contains(key)) {
          pendingSnippet![key] = parsed;
        }
        continue;
      }

      final qualifiedKey = currentTable == null ? key : '$currentTable.$key';
      switch (qualifiedKey) {
        case 'config_version':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed >= 0) {
            config = config.copyWith(configVersion: parsed);
          }
          break;
        case 'appearance.active_theme':
          final parsed = _decodeJsonString(value);
          if (parsed != null && parsed.trim().isNotEmpty) {
            config = config.copyWith(
              appearance: config.appearance.copyWith(
                activeTheme: parsed.trim(),
              ),
            );
          }
          break;
        case 'appearance.themes_dir':
          final parsed = _decodeJsonString(value);
          if (parsed != null) {
            config = config.copyWith(
              appearance: config.appearance.copyWith(
                themesDir: parsed.trim().isEmpty ? null : parsed.trim(),
              ),
            );
          }
          break;
        case 'default_page_size':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed > 0) {
            config = config.copyWith(defaultPageSize: parsed);
          }
          break;
        case 'csv_delimiter':
          final parsed = _decodeJsonString(value);
          if (parsed != null && parsed.isNotEmpty) {
            config = config.copyWith(csvDelimiter: parsed);
          }
          break;
        case 'csv_include_headers':
          final parsed = _parseBool(value);
          if (parsed != null) {
            config = config.copyWith(csvIncludeHeaders: parsed);
          }
          break;
        case 'recent_files':
          final parsed = _decodeStringList(value);
          if (parsed != null) {
            config = config.copyWith(
              recentFiles: parsed.take(maxRecentFiles).toList(),
            );
          }
          break;
        case 'editor_autocomplete_enabled':
          final parsed = _parseBool(value);
          if (parsed != null) {
            config = config.copyWith(
              editorSettings: config.editorSettings.copyWith(
                autocompleteEnabled: parsed,
              ),
            );
          }
          break;
        case 'editor_autocomplete_max_suggestions':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed > 0) {
            config = config.copyWith(
              editorSettings: config.editorSettings.copyWith(
                autocompleteMaxSuggestions: parsed,
              ),
            );
          }
          break;
        case 'editor_format_uppercase_keywords':
          final parsed = _parseBool(value);
          if (parsed != null) {
            config = config.copyWith(
              editorSettings: config.editorSettings.copyWith(
                formatUppercaseKeywords: parsed,
              ),
            );
          }
          break;
        case 'editor_indent_spaces':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed > 0) {
            config = config.copyWith(
              editorSettings: config.editorSettings.copyWith(
                indentSpaces: parsed,
              ),
            );
          }
          break;
        case 'editor_snippet_count':
          final parsed = int.tryParse(value);
          if (parsed != null && parsed >= 0) {
            declaredSnippetCount = parsed;
          }
          break;
        case 'editor_snippets':
          final parsed = _decodeSnippetList(value);
          if (parsed != null) {
            config = config.copyWith(snippets: parsed);
          }
          break;
        case 'layout.left_column_fraction':
          final parsed = double.tryParse(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                leftColumnFraction: parsed,
              ),
            );
          }
          break;
        case 'layout.left_top_fraction':
          final parsed = double.tryParse(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                leftTopFraction: parsed,
              ),
            );
          }
          break;
        case 'layout.right_top_fraction':
          final parsed = double.tryParse(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                rightTopFraction: parsed,
              ),
            );
          }
          break;
        case 'layout.show_schema_explorer':
          final parsed = _parseBool(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                showSchemaExplorer: parsed,
              ),
            );
          }
          break;
        case 'layout.show_properties_pane':
          final parsed = _parseBool(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                showPropertiesPane: parsed,
              ),
            );
          }
          break;
        case 'layout.show_results_pane':
          final parsed = _parseBool(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                showResultsPane: parsed,
              ),
            );
          }
          break;
        case 'layout.show_status_bar':
          final parsed = _parseBool(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                showStatusBar: parsed,
              ),
            );
          }
          break;
        case 'layout.editor_zoom':
          final parsed = double.tryParse(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                editorZoom: parsed,
              ),
            );
          }
          break;
        case 'layout.active_results_tab':
          final parsed = _decodeJsonString(value);
          if (parsed != null) {
            config = config.copyWith(
              shellPreferences: config.shellPreferences.copyWith(
                activeResultsTab: WorkspaceShellPreferences.parseResultsTab(
                  parsed,
                ),
              ),
            );
          }
          break;
        default:
          if (qualifiedKey.startsWith('shortcuts.')) {
            final parsed = _decodeJsonString(value);
            if (parsed != null && parsed.isNotEmpty) {
              final updated = <String, String>{
                ...config.shortcutBindings,
                key: parsed,
              };
              config = config.copyWith(shortcutBindings: updated);
            }
          }
          break;
      }
    }

    flushSnippet();
    if (declaredSnippetCount != null || parsedSnippets.isNotEmpty) {
      config = config.copyWith(snippets: parsedSnippets);
    }

    return config.copyWith(
      configVersion: config.configVersion == 0
          ? currentConfigVersion
          : config.configVersion,
      shellPreferences: config.shellPreferences.normalized(),
    );
  }

  static Map<String, String> defaultShortcutBindings() {
    return const <String, String>{
      'edit_copy': 'Ctrl+C',
      'edit_find': 'Ctrl+F',
      'edit_find_next': 'F3',
      'edit_paste': 'Ctrl+V',
      'edit_redo': 'Ctrl+Shift+Z',
      'edit_select_all': 'Ctrl+A',
      'edit_undo': 'Ctrl+Z',
      'export_results_csv': 'Ctrl+Shift+C',
      'file_new': 'Ctrl+N',
      'file_open': 'Ctrl+O',
      'file_save': 'Ctrl+S',
      'file_save_as': 'Ctrl+Shift+S',
      'file_exit': 'Ctrl+Q',
      'help_docs': 'F1',
      'import_open_wizard': 'Ctrl+Shift+I',
      'tools_format_sql': 'Ctrl+Shift+F',
      'tools_new_query_tab': 'Ctrl+T',
      'tools_run_query': 'Ctrl+Enter',
      'tools_stop_query': 'Esc',
      'view_reset_layout': 'Ctrl+Shift+R',
      'view_zoom_in': 'Ctrl+=',
      'view_zoom_out': 'Ctrl+-',
      'view_zoom_reset': 'Ctrl+0',
    };
  }

  static List<SqlSnippet> defaultSnippets() {
    return const <SqlSnippet>[
      SqlSnippet(
        id: 'cte',
        name: 'Recursive CTE',
        trigger: 'cte',
        description: 'Start a WITH RECURSIVE query.',
        body:
            'WITH RECURSIVE seed AS (\n'
            '  SELECT 1 AS id\n'
            '  UNION ALL\n'
            '  SELECT id + 1\n'
            '  FROM seed\n'
            '  WHERE id < 10\n'
            ')\n'
            'SELECT *\n'
            'FROM seed;',
      ),
      SqlSnippet(
        id: 'window',
        name: 'Window Function',
        trigger: 'window',
        description: 'Add a ROW_NUMBER window expression.',
        body:
            'SELECT\n'
            '  *,\n'
            '  ROW_NUMBER() OVER (PARTITION BY category ORDER BY id) AS row_num\n'
            'FROM your_table;',
      ),
      SqlSnippet(
        id: 'json_each',
        name: 'JSON Each',
        trigger: 'json',
        description: 'Use json_each as a table-valued function.',
        body:
            'SELECT entry.key, entry.value\n'
            'FROM json_each(\'{"name":"decent","type":"bench"}\') AS entry;',
      ),
      SqlSnippet(
        id: 'explain',
        name: 'Explain Analyze',
        trigger: 'explain',
        description: 'Profile a query plan.',
        body:
            'EXPLAIN ANALYZE\n'
            'SELECT *\n'
            'FROM your_table\n'
            'WHERE id = \$1;',
      ),
    ];
  }

  static String? _decodeJsonString(String raw) {
    try {
      final parsed = jsonDecode(raw);
      return parsed is String ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  static List<String>? _decodeStringList(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) {
        return null;
      }
      return parsed.whereType<String>().toList();
    } catch (_) {
      return null;
    }
  }

  static List<SqlSnippet>? _decodeSnippetList(String raw) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) {
        return null;
      }
      return parsed
          .whereType<Map>()
          .map(
            (item) => SqlSnippet.fromJson(
              item.map((key, value) => MapEntry(key as String, value)),
            ),
          )
          .toList();
    } catch (_) {
      return null;
    }
  }

  static bool? _parseBool(String raw) {
    if (raw == 'true') {
      return true;
    }
    if (raw == 'false') {
      return false;
    }
    return null;
  }

  static String _stripTomlComment(String rawLine) {
    final buffer = StringBuffer();
    var insideString = false;
    var escaping = false;
    for (var i = 0; i < rawLine.length; i++) {
      final char = rawLine[i];
      if (escaping) {
        buffer.write(char);
        escaping = false;
        continue;
      }
      if (char == r'\') {
        buffer.write(char);
        if (insideString) {
          escaping = true;
        }
        continue;
      }
      if (char == '"') {
        insideString = !insideString;
        buffer.write(char);
        continue;
      }
      if (char == '#' && !insideString) {
        break;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  static String _formatDouble(double value) {
    final formatted = value.toStringAsFixed(3);
    return formatted
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
