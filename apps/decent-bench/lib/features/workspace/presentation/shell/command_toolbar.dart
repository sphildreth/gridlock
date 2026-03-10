import 'package:flutter/material.dart';

import '../../application/menu_command_registry.dart';

class CommandToolbar extends StatelessWidget {
  const CommandToolbar({super.key, required this.registry});

  final MenuCommandRegistry registry;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            _toolbarButton('file_new'),
            _toolbarButton('file_open'),
            _toolbarButton('import_excel'),
            _toolbarButton('import_sqlite'),
            _toolbarButton('import_sql_dump'),
            _divider(context),
            _toolbarButton('tools_new_query_tab'),
            _toolbarButton('tools_run_query'),
            _toolbarButton('tools_stop_query'),
            _toolbarButton('tools_format_sql'),
            _divider(context),
            _toolbarButton('export_results_csv'),
          ],
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }

  Widget _toolbarButton(String commandId) {
    final command = registry[commandId];
    if (command == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton.icon(
        onPressed: command.enabled
            ? () {
                registry.invoke(commandId);
              }
            : null,
        icon: Icon(command.icon, size: 16),
        label: Text(command.label),
      ),
    );
  }
}
