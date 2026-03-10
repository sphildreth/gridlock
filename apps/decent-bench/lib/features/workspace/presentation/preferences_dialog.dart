import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/app_config.dart';
import '../domain/workspace_shell_preferences.dart';
import '../infrastructure/shortcut_config_service.dart';

typedef SavePreferencesDraft = Future<String?> Function(AppConfig config);

enum PreferencesDialogSection {
  general,
  export,
  editor,
  layout,
  shortcuts,
  snippets,
  toml,
}

class PreferencesDialog extends StatefulWidget {
  const PreferencesDialog({
    super.key,
    required this.initialConfig,
    required this.configFilePath,
    required this.shortcutConfigService,
    required this.createSnippetId,
    required this.onSave,
    this.initialSection = PreferencesDialogSection.general,
  });

  final AppConfig initialConfig;
  final String configFilePath;
  final ShortcutConfigService shortcutConfigService;
  final String Function() createSnippetId;
  final SavePreferencesDraft onSave;
  final PreferencesDialogSection initialSection;

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  static const Map<String, String> _shortcutLabels = <String, String>{
    'edit_copy': 'Copy',
    'edit_find': 'Find',
    'edit_find_next': 'Find Next',
    'edit_paste': 'Paste',
    'edit_redo': 'Redo',
    'edit_select_all': 'Select All',
    'edit_undo': 'Undo',
    'export_results_csv': 'Export Results as CSV',
    'file_new': 'New',
    'file_open': 'Open',
    'file_save': 'Save',
    'file_save_as': 'Save As',
    'file_exit': 'Exit',
    'help_docs': 'Documentation',
    'import_open_wizard': 'Open Import Wizard',
    'tools_format_sql': 'Format SQL',
    'tools_new_query_tab': 'New Query Tab',
    'tools_run_query': 'Run Query',
    'tools_stop_query': 'Stop Query',
    'view_reset_layout': 'Reset Layout',
    'view_zoom_in': 'Zoom In',
    'view_zoom_out': 'Zoom Out',
    'view_zoom_reset': 'Reset Zoom',
  };

  late final TextEditingController _pageSizeController;
  late final TextEditingController _csvDelimiterController;
  late final TextEditingController _autocompleteMaxController;
  late final TextEditingController _indentSpacesController;
  late WorkspaceShellPreferences _shellPreferences;
  late bool _csvIncludeHeaders;
  late bool _autocompleteEnabled;
  late bool _uppercaseKeywords;
  late List<String> _recentFiles;
  late final Map<String, TextEditingController> _shortcutControllers;
  late List<_SnippetDraft> _snippetDrafts;
  late PreferencesDialogSection _section;
  String? _errorMessage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig;
    _pageSizeController = TextEditingController(
      text: initial.defaultPageSize.toString(),
    );
    _csvDelimiterController = TextEditingController(text: initial.csvDelimiter);
    _autocompleteMaxController = TextEditingController(
      text: initial.editorSettings.autocompleteMaxSuggestions.toString(),
    );
    _indentSpacesController = TextEditingController(
      text: initial.editorSettings.indentSpaces.toString(),
    );
    _shellPreferences = initial.shellPreferences.normalized();
    _csvIncludeHeaders = initial.csvIncludeHeaders;
    _autocompleteEnabled = initial.editorSettings.autocompleteEnabled;
    _uppercaseKeywords = initial.editorSettings.formatUppercaseKeywords;
    _recentFiles = <String>[...initial.recentFiles];
    _section = widget.initialSection;
    final defaults = AppConfig.defaultShortcutBindings();
    _shortcutControllers = <String, TextEditingController>{
      for (final commandId in defaults.keys.toList()..sort())
        commandId: TextEditingController(
          text: initial.shortcutBindings[commandId] ?? defaults[commandId]!,
        ),
    };
    _snippetDrafts = _buildSnippetDrafts(initial.snippets);
  }

  @override
  void dispose() {
    _pageSizeController.dispose();
    _csvDelimiterController.dispose();
    _autocompleteMaxController.dispose();
    _indentSpacesController.dispose();
    for (final controller in _shortcutControllers.values) {
      controller.dispose();
    }
    for (final draft in _snippetDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _buildDraft();
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      title: Row(
        children: <Widget>[
          const Icon(Icons.tune_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Options / Preferences',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  'Editing ${widget.configFilePath}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 1080,
        height: 700,
        child: Row(
          children: <Widget>[
            _buildNavigation(context),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: Column(
                children: <Widget>[
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.errorContainer,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Text(
                        _errorMessage!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: switch (_section) {
                        PreferencesDialogSection.general =>
                          _buildGeneralSection(),
                        PreferencesDialogSection.export =>
                          _buildExportSection(),
                        PreferencesDialogSection.editor =>
                          _buildEditorSection(),
                        PreferencesDialogSection.layout =>
                          _buildLayoutSection(),
                        PreferencesDialogSection.shortcuts =>
                          _buildShortcutsSection(),
                        PreferencesDialogSection.snippets =>
                          _buildSnippetsSection(),
                        PreferencesDialogSection.toml => _buildTomlSection(
                          preview.error,
                          preview.config,
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: <Widget>[
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const ValueKey<String>('preferences.save'),
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: const Text('Save Preferences'),
        ),
      ],
    );
  }

  Widget _buildNavigation(BuildContext context) {
    return NavigationRail(
      selectedIndex: _section.index,
      onDestinationSelected: (index) {
        setState(() {
          _errorMessage = null;
          _section = PreferencesDialogSection.values[index];
        });
      },
      labelType: NavigationRailLabelType.all,
      minWidth: 88,
      minExtendedWidth: 180,
      destinations: const <NavigationRailDestination>[
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          label: Text(
            'General',
            key: ValueKey<String>('preferences.section.general'),
          ),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.file_upload_outlined),
          label: Text(
            'Export',
            key: ValueKey<String>('preferences.section.export'),
          ),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.code_outlined),
          label: Text(
            'Editor',
            key: ValueKey<String>('preferences.section.editor'),
          ),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          label: Text(
            'Layout',
            key: ValueKey<String>('preferences.section.layout'),
          ),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.keyboard_outlined),
          label: Text(
            'Shortcuts',
            key: ValueKey<String>('preferences.section.shortcuts'),
          ),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.snippet_folder_outlined),
          label: Text(
            'Snippets',
            key: ValueKey<String>('preferences.section.snippets'),
          ),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.article_outlined),
          label: Text(
            'TOML',
            key: ValueKey<String>('preferences.section.toml'),
          ),
        ),
      ],
    );
  }

  Widget _buildGeneralSection() {
    return _SectionPanel(
      title: 'General',
      description:
          'These values are loaded from the application TOML file before the dialog opens. Saving writes the updated structure back to disk.',
      child: ListView(
        children: <Widget>[
          _SettingsCard(
            title: 'Configuration File',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Path', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                SelectableText(
                  widget.configFilePath,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Config version ${AppConfig.currentConfigVersion}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Recent Workspaces',
            trailing: TextButton(
              onPressed: _recentFiles.isEmpty
                  ? null
                  : () => setState(() {
                      _recentFiles = <String>[];
                      _errorMessage = null;
                    }),
              child: const Text('Clear List'),
            ),
            child: _recentFiles.isEmpty
                ? const Text(
                    'No recent workspaces are currently stored in the application configuration.',
                  )
                : Column(
                    children: <Widget>[
                      for (final entry in _recentFiles)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.dns_outlined, size: 18),
                          title: Text(
                            entry,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove recent file',
                            onPressed: () => setState(() {
                              _recentFiles.remove(entry);
                              _errorMessage = null;
                            }),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    return _SectionPanel(
      title: 'Export Defaults',
      description:
          'These defaults are used for paged result retrieval and CSV export flows.',
      child: ListView(
        children: <Widget>[
          _SettingsCard(
            title: 'Query Paging',
            child: TextField(
              key: const ValueKey<String>('preferences.default_page_size'),
              controller: _pageSizeController,
              onChanged: (_) => _handleDraftChanged(),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Default page size',
                helperText: 'Rows fetched per page when opening a cursor.',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'CSV Export',
            child: Column(
              children: <Widget>[
                TextField(
                  key: const ValueKey<String>('preferences.csv_delimiter'),
                  controller: _csvDelimiterController,
                  onChanged: (_) => _handleDraftChanged(),
                  decoration: const InputDecoration(
                    labelText: 'CSV delimiter',
                    helperText: 'Use a delimiter such as "," or ";".',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _csvIncludeHeaders,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include headers in CSV exports'),
                  subtitle: const Text(
                    'Writes the column header row before result data.',
                  ),
                  onChanged: (value) => setState(() {
                    _csvIncludeHeaders = value;
                    _errorMessage = null;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorSection() {
    return _SectionPanel(
      title: 'Editor',
      description:
          'Autocomplete, formatting, and indentation settings are shared across editor tabs.',
      child: ListView(
        children: <Widget>[
          _SettingsCard(
            title: 'Autocomplete',
            child: Column(
              children: <Widget>[
                SwitchListTile.adaptive(
                  value: _autocompleteEnabled,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable SQL autocomplete'),
                  subtitle: const Text(
                    'Suggest schema objects and SQL keywords while typing.',
                  ),
                  onChanged: (value) => setState(() {
                    _autocompleteEnabled = value;
                    _errorMessage = null;
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey<String>(
                    'preferences.autocomplete_max_suggestions',
                  ),
                  controller: _autocompleteMaxController,
                  onChanged: (_) => _handleDraftChanged(),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Maximum suggestions',
                    helperText: 'Upper bound for each autocomplete request.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Formatting',
            child: Column(
              children: <Widget>[
                SwitchListTile.adaptive(
                  value: _uppercaseKeywords,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Uppercase SQL keywords'),
                  subtitle: const Text(
                    'Applies when the Format SQL command rewrites the current statement.',
                  ),
                  onChanged: (value) => setState(() {
                    _uppercaseKeywords = value;
                    _errorMessage = null;
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey<String>('preferences.indent_spaces'),
                  controller: _indentSpacesController,
                  onChanged: (_) => _handleDraftChanged(),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Indent spaces',
                    helperText: 'Spaces inserted per indentation level.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutSection() {
    return _SectionPanel(
      title: 'Layout',
      description:
          'These values control the default shell proportions, visible panes, and editor zoom restored from TOML on startup.',
      child: ListView(
        children: <Widget>[
          _SettingsCard(
            title: 'Pane Visibility',
            trailing: TextButton(
              onPressed: () => setState(() {
                _shellPreferences = _shellPreferences.copyWith(
                  showSchemaExplorer: true,
                  showPropertiesPane: true,
                  showResultsPane: true,
                  showStatusBar: true,
                );
                _errorMessage = null;
              }),
              child: const Text('Show All'),
            ),
            child: Column(
              children: <Widget>[
                _buildPaneSwitch(
                  'Schema Explorer',
                  _shellPreferences.showSchemaExplorer,
                  (value) => _shellPreferences = _shellPreferences.copyWith(
                    showSchemaExplorer: value,
                  ),
                ),
                _buildPaneSwitch(
                  'Properties / Details',
                  _shellPreferences.showPropertiesPane,
                  (value) => _shellPreferences = _shellPreferences.copyWith(
                    showPropertiesPane: value,
                  ),
                ),
                _buildPaneSwitch(
                  'Results Window',
                  _shellPreferences.showResultsPane,
                  (value) => _shellPreferences = _shellPreferences.copyWith(
                    showResultsPane: value,
                  ),
                ),
                _buildPaneSwitch(
                  'Status Bar',
                  _shellPreferences.showStatusBar,
                  (value) => _shellPreferences = _shellPreferences.copyWith(
                    showStatusBar: value,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Editor Zoom',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${(_shellPreferences.editorZoom * 100).round()}%',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  value: _shellPreferences.editorZoom,
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  label: '${(_shellPreferences.editorZoom * 100).round()}%',
                  onChanged: (value) => setState(() {
                    _shellPreferences = _shellPreferences.copyWith(
                      editorZoom: value,
                    );
                    _errorMessage = null;
                  }),
                ),
                DropdownButtonFormField<ResultsPaneTab>(
                  initialValue: _shellPreferences.activeResultsTab,
                  decoration: const InputDecoration(
                    labelText: 'Default lower-right tab',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<ResultsPaneTab>>[
                    DropdownMenuItem(
                      value: ResultsPaneTab.results,
                      child: Text('Results'),
                    ),
                    DropdownMenuItem(
                      value: ResultsPaneTab.messages,
                      child: Text('Messages'),
                    ),
                    DropdownMenuItem(
                      value: ResultsPaneTab.executionPlan,
                      child: Text('Execution Plan'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _shellPreferences = _shellPreferences.copyWith(
                        activeResultsTab: value,
                      );
                      _errorMessage = null;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsCard(
            title: 'Splitter Defaults',
            trailing: TextButton(
              onPressed: () => setState(() {
                _shellPreferences = WorkspaceShellPreferences.defaults();
                _errorMessage = null;
              }),
              child: const Text('Reset Layout'),
            ),
            child: Column(
              children: <Widget>[
                _FractionSlider(
                  label: 'Left vs right column width',
                  value: _shellPreferences.leftColumnFraction,
                  onChanged: (value) => setState(() {
                    _shellPreferences = _shellPreferences.copyWith(
                      leftColumnFraction: value,
                    );
                    _errorMessage = null;
                  }),
                ),
                _FractionSlider(
                  label: 'Schema Explorer height',
                  value: _shellPreferences.leftTopFraction,
                  onChanged: (value) => setState(() {
                    _shellPreferences = _shellPreferences.copyWith(
                      leftTopFraction: value,
                    );
                    _errorMessage = null;
                  }),
                ),
                _FractionSlider(
                  label: 'SQL Editor height',
                  value: _shellPreferences.rightTopFraction,
                  onChanged: (value) => setState(() {
                    _shellPreferences = _shellPreferences.copyWith(
                      rightTopFraction: value,
                    );
                    _errorMessage = null;
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutsSection() {
    final defaults = AppConfig.defaultShortcutBindings();
    return _SectionPanel(
      title: 'Keyboard Shortcuts',
      description:
          'Each shortcut is persisted in the [shortcuts] table of config.toml. Invalid combinations are rejected before saving.',
      child: ListView(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() {
                for (final entry in defaults.entries) {
                  _shortcutControllers[entry.key]!.text = entry.value;
                }
                _errorMessage = null;
              }),
              icon: const Icon(Icons.restart_alt_outlined),
              label: const Text('Restore Default Shortcuts'),
            ),
          ),
          const SizedBox(height: 8),
          for (final commandId in defaults.keys.toList()..sort())
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ShortcutEditorRow(
                commandId: commandId,
                label: _shortcutLabels[commandId] ?? commandId,
                controller: _shortcutControllers[commandId]!,
                defaultValue: defaults[commandId]!,
                shortcutConfigService: widget.shortcutConfigService,
                onChanged: _handleDraftChanged,
                onReset: () => setState(() {
                  _shortcutControllers[commandId]!.text = defaults[commandId]!;
                  _errorMessage = null;
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSnippetsSection() {
    return _SectionPanel(
      title: 'SQL Snippets',
      description:
          'Snippets are stored in repeated [[editor_snippets]] TOML records and used by the SQL editor shortcut menus.',
      child: ListView(
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => setState(() {
                  _snippetDrafts.add(
                    _SnippetDraft.empty(widget.createSnippetId()),
                  );
                  _errorMessage = null;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Add Snippet'),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _replaceSnippetDrafts(AppConfig.defaultSnippets());
                  _errorMessage = null;
                }),
                icon: const Icon(Icons.restart_alt_outlined),
                label: const Text('Restore Default Snippets'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_snippetDrafts.isEmpty)
            const _SettingsCard(
              title: 'No Snippets',
              child: Text(
                'No snippet definitions are currently stored. Add one to seed the SQL editor menu.',
              ),
            ),
          for (
            var index = 0;
            index < _snippetDrafts.length;
            index++
          ) ...<Widget>[
            _SnippetEditorCard(
              draft: _snippetDrafts[index],
              index: index,
              onChanged: _handleDraftChanged,
              onDelete: () => setState(() {
                final removed = _snippetDrafts.removeAt(index);
                removed.dispose();
                _errorMessage = null;
              }),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildTomlSection(String? error, AppConfig? config) {
    return _SectionPanel(
      title: 'TOML Preview',
      description:
          'This preview is generated from the current draft. Saving writes exactly this structure to the application configuration file.',
      child: _SettingsCard(
        title: 'config.toml',
        child: error != null
            ? Text(error)
            : Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  child: SelectableText(
                    config!.toToml(),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPaneSwitch(
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile.adaptive(
      value: value,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      onChanged: (next) => setState(() {
        onChanged(next);
        _errorMessage = null;
      }),
    );
  }

  void _replaceSnippetDrafts(List<SqlSnippet> snippets) {
    for (final draft in _snippetDrafts) {
      draft.dispose();
    }
    _snippetDrafts = _buildSnippetDrafts(snippets);
  }

  List<_SnippetDraft> _buildSnippetDrafts(List<SqlSnippet> snippets) {
    return <_SnippetDraft>[
      for (final snippet in snippets) _SnippetDraft.fromSnippet(snippet),
    ];
  }

  _DraftBuildResult _buildDraft() {
    final pageSize = int.tryParse(_pageSizeController.text.trim());
    if (pageSize == null || pageSize <= 0) {
      return const _DraftBuildResult.failure(
        'Default page size must be a positive integer.',
      );
    }

    final csvDelimiter = _csvDelimiterController.text;
    if (csvDelimiter.isEmpty) {
      return const _DraftBuildResult.failure('CSV delimiter cannot be empty.');
    }

    final autocompleteMax = int.tryParse(
      _autocompleteMaxController.text.trim(),
    );
    if (autocompleteMax == null || autocompleteMax <= 0) {
      return const _DraftBuildResult.failure(
        'Autocomplete suggestions must be a positive integer.',
      );
    }

    final indentSpaces = int.tryParse(_indentSpacesController.text.trim());
    if (indentSpaces == null || indentSpaces <= 0) {
      return const _DraftBuildResult.failure(
        'Indent spaces must be a positive integer.',
      );
    }

    final shortcutBindings = <String, String>{};
    for (final entry in _shortcutControllers.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) {
        return _DraftBuildResult.failure(
          'Shortcut "${_shortcutLabels[entry.key] ?? entry.key}" cannot be empty.',
        );
      }
      if (widget.shortcutConfigService.tryParseActivator(raw) == null) {
        return _DraftBuildResult.failure(
          'Shortcut "$raw" for "${_shortcutLabels[entry.key] ?? entry.key}" is not valid.',
        );
      }
      shortcutBindings[entry.key] = raw;
    }

    final snippetIds = <String>{};
    final snippetTriggers = <String>{};
    final snippets = <SqlSnippet>[];
    for (final draft in _snippetDrafts) {
      final snippet = draft.toSnippet();
      if (snippet == null) {
        return const _DraftBuildResult.failure(
          'Every snippet must have a name, trigger, and body.',
        );
      }
      if (!snippetIds.add(snippet.id)) {
        return const _DraftBuildResult.failure(
          'Snippet identifiers must be unique.',
        );
      }
      if (!snippetTriggers.add(snippet.trigger.toLowerCase())) {
        return _DraftBuildResult.failure(
          'Snippet trigger "${snippet.trigger}" is duplicated.',
        );
      }
      snippets.add(snippet);
    }

    return _DraftBuildResult.success(
      widget.initialConfig.copyWith(
        configVersion: AppConfig.currentConfigVersion,
        recentFiles: _recentFiles
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty)
            .toList(),
        defaultPageSize: pageSize,
        csvDelimiter: csvDelimiter,
        csvIncludeHeaders: _csvIncludeHeaders,
        editorSettings: EditorSettings(
          autocompleteEnabled: _autocompleteEnabled,
          autocompleteMaxSuggestions: autocompleteMax,
          formatUppercaseKeywords: _uppercaseKeywords,
          indentSpaces: indentSpaces,
        ),
        shellPreferences: _shellPreferences.normalized(),
        shortcutBindings: shortcutBindings,
        snippets: snippets,
      ),
    );
  }

  void _handleDraftChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _errorMessage = null;
    });
  }

  Future<void> _save() async {
    final draftResult = _buildDraft();
    if (draftResult.config == null) {
      setState(() {
        _errorMessage = draftResult.error;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final saveError = await widget.onSave(draftResult.config!);
    if (!mounted) {
      return;
    }
    if (saveError != null) {
      setState(() {
        _isSaving = false;
        _errorMessage = saveError;
      });
      return;
    }
    Navigator.of(context).pop();
  }
}

class _DraftBuildResult {
  const _DraftBuildResult.success(this.config) : error = null;

  const _DraftBuildResult.failure(this.error) : config = null;

  final AppConfig? config;
  final String? error;
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidgets = trailing == null ? null : <Widget>[trailing!];
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ...?trailingWidgets,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 20),
        Expanded(child: child),
      ],
    );
  }
}

class _FractionSlider extends StatelessWidget {
  const _FractionSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$label (${(value * 100).round()}%)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Slider(
            value: value,
            min: 0.2,
            max: 0.8,
            divisions: 60,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ShortcutEditorRow extends StatelessWidget {
  const _ShortcutEditorRow({
    required this.commandId,
    required this.label,
    required this.controller,
    required this.defaultValue,
    required this.shortcutConfigService,
    required this.onChanged,
    required this.onReset,
  });

  final String commandId;
  final String label;
  final TextEditingController controller;
  final String defaultValue;
  final ShortcutConfigService shortcutConfigService;
  final VoidCallback onChanged;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final raw = controller.text.trim();
    final parsed = shortcutConfigService.tryParseActivator(raw);
    final isValid = raw.isNotEmpty && parsed != null;
    final effectiveLabel = isValid
        ? shortcutConfigService.displayLabel(raw)
        : 'Invalid shortcut';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    commandId,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    effectiveLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isValid
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 220,
              child: TextField(
                key: ValueKey<String>('preferences.shortcut.$commandId'),
                controller: controller,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  labelText: 'Binding',
                  helperText: 'Default: $defaultValue',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Reset shortcut',
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnippetDraft {
  _SnippetDraft({
    required this.id,
    required String name,
    required String trigger,
    required String description,
    required String body,
  }) : nameController = TextEditingController(text: name),
       triggerController = TextEditingController(text: trigger),
       descriptionController = TextEditingController(text: description),
       bodyController = TextEditingController(text: body);

  factory _SnippetDraft.empty(String id) {
    return _SnippetDraft(
      id: id,
      name: '',
      trigger: '',
      description: '',
      body: '',
    );
  }

  factory _SnippetDraft.fromSnippet(SqlSnippet snippet) {
    return _SnippetDraft(
      id: snippet.id,
      name: snippet.name,
      trigger: snippet.trigger,
      description: snippet.description,
      body: snippet.body,
    );
  }

  final String id;
  final TextEditingController nameController;
  final TextEditingController triggerController;
  final TextEditingController descriptionController;
  final TextEditingController bodyController;

  SqlSnippet? toSnippet() {
    final name = nameController.text.trim();
    final trigger = triggerController.text.trim();
    final description = descriptionController.text.trim();
    final body = bodyController.text.trimRight();
    if (id.trim().isEmpty ||
        name.isEmpty ||
        trigger.isEmpty ||
        body.trim().isEmpty) {
      return null;
    }
    return SqlSnippet(
      id: id.trim(),
      name: name,
      trigger: trigger,
      description: description,
      body: body,
    );
  }

  void dispose() {
    nameController.dispose();
    triggerController.dispose();
    descriptionController.dispose();
    bodyController.dispose();
  }
}

class _SnippetEditorCard extends StatelessWidget {
  const _SnippetEditorCard({
    required this.draft,
    required this.index,
    required this.onChanged,
    required this.onDelete,
  });

  final _SnippetDraft draft;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Snippet ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SelectableText(
                  draft.id,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                ),
                IconButton(
                  tooltip: 'Delete snippet',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: draft.nameController,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: draft.triggerController,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Trigger',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: draft.descriptionController,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: draft.bodyController,
              onChanged: (_) => onChanged(),
              minLines: 6,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'SQL body',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ),
      ),
    );
  }
}
