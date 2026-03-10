import 'package:flutter/material.dart';

import '../infrastructure/shortcut_config_service.dart';

typedef MenuCommandCallback = Future<void> Function();

class MenuCommand {
  const MenuCommand({
    required this.id,
    required this.label,
    required this.icon,
    required this.onInvoke,
    this.enabled = true,
    this.checked = false,
    this.shortcut,
    this.description = '',
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final bool enabled;
  final bool checked;
  final ShortcutBinding? shortcut;
  final MenuCommandCallback onInvoke;
}

class MenuCommandIntent extends Intent {
  const MenuCommandIntent(this.commandId);

  final String commandId;
}

class MenuCommandRegistry {
  MenuCommandRegistry({required Iterable<MenuCommand> commands})
    : _commands = <String, MenuCommand>{
        for (final command in commands) command.id: command,
      };

  final Map<String, MenuCommand> _commands;

  MenuCommand? operator [](String commandId) => _commands[commandId];

  Iterable<MenuCommand> get commands => _commands.values;

  Map<ShortcutActivator, Intent> buildShortcutMap() {
    final shortcuts = <ShortcutActivator, Intent>{};
    for (final command in _commands.values) {
      if (!command.enabled || command.shortcut == null) {
        continue;
      }
      shortcuts.putIfAbsent(
        command.shortcut!.activator,
        () => MenuCommandIntent(command.id),
      );
    }
    return shortcuts;
  }

  Future<void> invoke(String commandId) async {
    final command = _commands[commandId];
    if (command == null || !command.enabled) {
      return;
    }
    await command.onInvoke();
  }
}
