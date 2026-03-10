import 'package:flutter/material.dart';

import '../../../../app/theme_system/decent_bench_theme_extension.dart';
import '../../application/menu_command_registry.dart';

class CommandToolbar extends StatelessWidget {
  const CommandToolbar({super.key, required this.registry});

  final MenuCommandRegistry registry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.decentBenchTheme;
    return Container(
      width: double.infinity,
      alignment: Alignment.centerLeft,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.toolbar.background,
        border: Border(bottom: BorderSide(color: tokens.colors.border)),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: context.decentBenchTheme.colors.border,
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
