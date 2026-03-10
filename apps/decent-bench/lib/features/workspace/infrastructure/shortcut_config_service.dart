import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../domain/app_config.dart';

class ShortcutBinding {
  const ShortcutBinding({
    required this.commandId,
    required this.rawValue,
    required this.activator,
    required this.displayLabel,
  });

  final String commandId;
  final String rawValue;
  final SingleActivator activator;
  final String displayLabel;
}

class ShortcutConfigService {
  const ShortcutConfigService();

  Map<String, ShortcutBinding> load(AppConfig config) {
    final bindings = <String, ShortcutBinding>{};
    final defaults = AppConfig.defaultShortcutBindings();
    for (final entry in defaults.entries) {
      final rawValue = config.shortcutBindings[entry.key] ?? entry.value;
      final parsed = tryParseActivator(rawValue);
      final fallback = tryParseActivator(entry.value);
      final activator = parsed ?? fallback;
      if (activator == null) {
        continue;
      }
      final effectiveRawValue = parsed == null ? entry.value : rawValue;
      bindings[entry.key] = ShortcutBinding(
        commandId: entry.key,
        rawValue: effectiveRawValue,
        activator: activator,
        displayLabel: displayLabel(effectiveRawValue),
      );
    }
    return bindings;
  }

  SingleActivator? tryParseActivator(String rawValue) {
    final tokens = rawValue
        .split('+')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return null;
    }

    var control = false;
    var meta = false;
    var alt = false;
    var shift = false;
    LogicalKeyboardKey? triggerKey;

    for (final token in tokens) {
      final normalized = token.toLowerCase();
      switch (normalized) {
        case 'ctrl':
        case 'cmdorctrl':
        case 'primary':
          if (Platform.isMacOS) {
            meta = true;
          } else {
            control = true;
          }
          continue;
        case 'cmd':
        case 'meta':
          meta = true;
          continue;
        case 'alt':
        case 'option':
          alt = true;
          continue;
        case 'shift':
          shift = true;
          continue;
      }

      triggerKey = _parseKey(normalized);
      if (triggerKey == null) {
        return null;
      }
    }

    if (triggerKey == null) {
      return null;
    }

    return SingleActivator(
      triggerKey,
      control: control,
      meta: meta,
      alt: alt,
      shift: shift,
    );
  }

  String displayLabel(String rawValue) {
    final parts = rawValue
        .split('+')
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .map((token) {
          final normalized = token.toLowerCase();
          return switch (normalized) {
            'ctrl' ||
            'cmdorctrl' ||
            'primary' => Platform.isMacOS ? 'Cmd' : 'Ctrl',
            'cmd' || 'meta' => 'Cmd',
            'alt' => Platform.isMacOS ? 'Option' : 'Alt',
            'esc' => 'Esc',
            _ => token.length == 1 ? token.toUpperCase() : token,
          };
        });
    return parts.join('+');
  }

  LogicalKeyboardKey? _parseKey(String token) {
    final functionKeys = <String, LogicalKeyboardKey>{
      'f1': LogicalKeyboardKey.f1,
      'f2': LogicalKeyboardKey.f2,
      'f3': LogicalKeyboardKey.f3,
      'f4': LogicalKeyboardKey.f4,
      'f5': LogicalKeyboardKey.f5,
      'f6': LogicalKeyboardKey.f6,
      'f7': LogicalKeyboardKey.f7,
      'f8': LogicalKeyboardKey.f8,
      'f9': LogicalKeyboardKey.f9,
      'f10': LogicalKeyboardKey.f10,
      'f11': LogicalKeyboardKey.f11,
      'f12': LogicalKeyboardKey.f12,
    };
    final namedKeys = <String, LogicalKeyboardKey>{
      'enter': LogicalKeyboardKey.enter,
      'return': LogicalKeyboardKey.enter,
      'esc': LogicalKeyboardKey.escape,
      'escape': LogicalKeyboardKey.escape,
      'tab': LogicalKeyboardKey.tab,
      'space': LogicalKeyboardKey.space,
      'backspace': LogicalKeyboardKey.backspace,
      'delete': LogicalKeyboardKey.delete,
      '=': LogicalKeyboardKey.equal,
      '-': LogicalKeyboardKey.minus,
      '0': LogicalKeyboardKey.digit0,
      '1': LogicalKeyboardKey.digit1,
      '2': LogicalKeyboardKey.digit2,
      '3': LogicalKeyboardKey.digit3,
      '4': LogicalKeyboardKey.digit4,
      '5': LogicalKeyboardKey.digit5,
      '6': LogicalKeyboardKey.digit6,
      '7': LogicalKeyboardKey.digit7,
      '8': LogicalKeyboardKey.digit8,
      '9': LogicalKeyboardKey.digit9,
    };

    if (functionKeys.containsKey(token)) {
      return functionKeys[token];
    }
    if (namedKeys.containsKey(token)) {
      return namedKeys[token];
    }
    if (token.length == 1) {
      final codeUnit = token.codeUnitAt(0);
      if (codeUnit >= 97 && codeUnit <= 122) {
        return LogicalKeyboardKey.findKeyByKeyId(
          LogicalKeyboardKey.keyA.keyId + (codeUnit - 97),
        );
      }
    }
    return null;
  }
}
