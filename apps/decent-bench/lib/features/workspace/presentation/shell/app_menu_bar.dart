import 'package:flutter/material.dart';

import '../../application/menu_command_registry.dart';

class NativeAppMenuHost extends StatelessWidget {
  const NativeAppMenuHost({
    super.key,
    required this.registry,
    required this.recentFiles,
    required this.onOpenRecent,
    required this.child,
  });

  final MenuCommandRegistry registry;
  final List<String> recentFiles;
  final ValueChanged<String> onOpenRecent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PlatformMenuBar(menus: _buildPlatformMenus(), child: child);
  }

  List<PlatformMenuItem> _buildPlatformMenus() {
    return <PlatformMenuItem>[
      PlatformMenu(
        label: 'File',
        menus: <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('file_new'),
              _platformCommandItem('file_open'),
              PlatformMenu(
                label: 'Open Recent',
                menus: recentFiles.isEmpty
                    ? <PlatformMenuItem>[
                        const PlatformMenuItem(label: 'No recent workspaces'),
                      ]
                    : <PlatformMenuItem>[
                        for (final path in recentFiles)
                          PlatformMenuItem(
                            label: path,
                            onSelected: () => onOpenRecent(path),
                          ),
                      ],
              ),
              _platformCommandItem('file_save'),
              _platformCommandItem('file_save_as'),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('file_close'),
              _platformCommandItem('file_exit'),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Edit',
        menus: <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('edit_undo'),
              _platformCommandItem('edit_redo'),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('edit_cut'),
              _platformCommandItem('edit_copy'),
              _platformCommandItem('edit_paste'),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('edit_find'),
              _platformCommandItem('edit_find_next'),
              _platformCommandItem('edit_select_all'),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Import',
        menus: <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('import_excel'),
              _platformCommandItem('import_sqlite'),
              _platformCommandItem('import_sql_dump'),
              _platformCommandItem('import_from_database'),
              _platformCommandItem('import_rerun_last'),
              _platformCommandItem('import_open_wizard'),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Export',
        menus: <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('export_results_csv'),
              _platformCommandItem('export_results_json'),
              _platformCommandItem('export_results_parquet'),
              _platformCommandItem('export_results_excel'),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('export_table'),
              _platformCommandItem('export_schema'),
              _platformCommandItem('export_rerun_last'),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'View',
        menus: <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('view_reset_layout'),
              _platformCommandItem('view_toggle_schema'),
              _platformCommandItem('view_toggle_properties'),
              _platformCommandItem('view_toggle_results'),
              _platformCommandItem('view_toggle_status_bar'),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('view_zoom_in'),
              _platformCommandItem('view_zoom_out'),
              _platformCommandItem('view_zoom_reset'),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Tools',
        menus: <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('tools_run_query'),
              _platformCommandItem('tools_stop_query'),
              _platformCommandItem('tools_format_sql'),
              _platformCommandItem('tools_new_query_tab'),
            ],
          ),
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('tools_query_history'),
              _platformCommandItem('tools_snippets'),
              _platformCommandItem('tools_manage_connections'),
              _platformCommandItem('tools_options'),
            ],
          ),
        ],
      ),
      PlatformMenu(
        label: 'Help',
        menus: <PlatformMenuItem>[
          PlatformMenuItemGroup(
            members: <PlatformMenuItem>[
              _platformCommandItem('help_docs'),
              _platformCommandItem('help_keyboard_shortcuts'),
              _platformCommandItem('help_about'),
            ],
          ),
        ],
      ),
    ];
  }

  PlatformMenuItem _platformCommandItem(String commandId) {
    final command = registry[commandId];
    if (command == null) {
      return const PlatformMenuItem(label: 'Missing');
    }
    return PlatformMenuItem(
      label: command.checked ? '✓ ${command.label}' : command.label,
      shortcut: command.shortcut?.activator,
      onSelected: command.enabled ? () => registry.invoke(commandId) : null,
    );
  }
}

class AppMenuBar extends StatelessWidget {
  const AppMenuBar({
    super.key,
    required this.registry,
    required this.recentFiles,
    required this.onOpenRecent,
  });

  final MenuCommandRegistry registry;
  final List<String> recentFiles;
  final ValueChanged<String> onOpenRecent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: MenuBar(
        style: MenuStyle(
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 2),
          ),
          backgroundColor: WidgetStatePropertyAll(
            Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
        ),
        children: <Widget>[
          SubmenuButton(
            menuChildren: <Widget>[
              _commandItem('file_new'),
              _commandItem('file_open'),
              SubmenuButton(
                menuChildren: recentFiles.isEmpty
                    ? <Widget>[
                        const MenuItemButton(
                          onPressed: null,
                          child: Text('No recent workspaces'),
                        ),
                      ]
                    : <Widget>[
                        for (final path in recentFiles)
                          MenuItemButton(
                            leadingIcon: const Icon(Icons.history, size: 18),
                            onPressed: () {
                              onOpenRecent(path);
                            },
                            child: Text(
                              path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                child: const Text('Open Recent'),
              ),
              _commandItem('file_save'),
              _commandItem('file_save_as'),
              const Divider(height: 1),
              _commandItem('file_close'),
              const Divider(height: 1),
              _commandItem('file_exit'),
            ],
            child: const Text('File'),
          ),
          SubmenuButton(
            menuChildren: <Widget>[
              _commandItem('edit_undo'),
              _commandItem('edit_redo'),
              const Divider(height: 1),
              _commandItem('edit_cut'),
              _commandItem('edit_copy'),
              _commandItem('edit_paste'),
              const Divider(height: 1),
              _commandItem('edit_find'),
              _commandItem('edit_find_next'),
              _commandItem('edit_select_all'),
            ],
            child: const Text('Edit'),
          ),
          SubmenuButton(
            menuChildren: <Widget>[
              _commandItem('import_excel'),
              _commandItem('import_sqlite'),
              _commandItem('import_sql_dump'),
              _commandItem('import_from_database'),
              _commandItem('import_rerun_last'),
              const Divider(height: 1),
              _commandItem('import_open_wizard'),
            ],
            child: const Text('Import'),
          ),
          SubmenuButton(
            menuChildren: <Widget>[
              _commandItem('export_results_csv'),
              _commandItem('export_results_json'),
              _commandItem('export_results_parquet'),
              _commandItem('export_results_excel'),
              const Divider(height: 1),
              _commandItem('export_table'),
              _commandItem('export_schema'),
              _commandItem('export_rerun_last'),
            ],
            child: const Text('Export'),
          ),
          SubmenuButton(
            menuChildren: <Widget>[
              _commandItem('view_reset_layout'),
              const Divider(height: 1),
              _commandItem('view_toggle_schema'),
              _commandItem('view_toggle_properties'),
              _commandItem('view_toggle_results'),
              _commandItem('view_toggle_status_bar'),
              const Divider(height: 1),
              _commandItem('view_zoom_in'),
              _commandItem('view_zoom_out'),
              _commandItem('view_zoom_reset'),
            ],
            child: const Text('View'),
          ),
          SubmenuButton(
            menuChildren: <Widget>[
              _commandItem('tools_run_query'),
              _commandItem('tools_stop_query'),
              _commandItem('tools_format_sql'),
              _commandItem('tools_new_query_tab'),
              const Divider(height: 1),
              _commandItem('tools_query_history'),
              _commandItem('tools_snippets'),
              _commandItem('tools_manage_connections'),
              _commandItem('tools_options'),
            ],
            child: const Text('Tools'),
          ),
          SubmenuButton(
            menuChildren: <Widget>[
              _commandItem('help_docs'),
              _commandItem('help_keyboard_shortcuts'),
              _commandItem('help_about'),
            ],
            child: const Text('Help'),
          ),
        ],
      ),
    );
  }

  MenuItemButton _commandItem(String commandId) {
    final command = registry[commandId];
    if (command == null) {
      return const MenuItemButton(onPressed: null, child: Text('Missing'));
    }
    return MenuItemButton(
      leadingIcon: Icon(command.icon, size: 18),
      trailingIcon: command.checked
          ? const Icon(Icons.check, size: 16)
          : const SizedBox.shrink(),
      shortcut: command.shortcut?.activator,
      onPressed: command.enabled
          ? () {
              registry.invoke(commandId);
            }
          : null,
      child: Text(command.label),
    );
  }
}
