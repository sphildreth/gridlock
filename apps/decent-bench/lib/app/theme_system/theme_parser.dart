import 'dart:convert';

class ParsedThemeDocument {
  const ParsedThemeDocument({
    required this.sourceLabel,
    required this.topLevel,
    required this.sections,
    required this.warnings,
  });

  final String sourceLabel;
  final Map<String, Object?> topLevel;
  final Map<String, Map<String, Object?>> sections;
  final List<String> warnings;

  Map<String, Object?> section(String name) =>
      sections[name] ?? const <String, Object?>{};
}

class ThemeParseResult {
  const ThemeParseResult.success(ParsedThemeDocument this.document)
    : error = null;

  const ThemeParseResult.failure(String this.error) : document = null;

  final ParsedThemeDocument? document;
  final String? error;

  bool get isSuccess => document != null;
}

class ThemeParser {
  const ThemeParser();

  ThemeParseResult parse(String source, {required String sourceLabel}) {
    final topLevel = <String, Object?>{};
    final sections = <String, Map<String, Object?>>{};
    final warnings = <String>[];
    String? currentSection;

    final lines = const LineSplitter().convert(source);
    for (var index = 0; index < lines.length; index++) {
      final rawLine = lines[index];
      final line = _stripComment(rawLine).trim();
      if (line.isEmpty) {
        continue;
      }

      if (line.startsWith('[[')) {
        return ThemeParseResult.failure(
          '$sourceLabel:${index + 1} array tables are not supported in theme files.',
        );
      }

      if (line.startsWith('[')) {
        if (!line.endsWith(']')) {
          return ThemeParseResult.failure(
            '$sourceLabel:${index + 1} has an invalid table header.',
          );
        }
        currentSection = line.substring(1, line.length - 1).trim();
        if (currentSection.isEmpty) {
          return ThemeParseResult.failure(
            '$sourceLabel:${index + 1} has an empty table header.',
          );
        }
        sections.putIfAbsent(currentSection, () => <String, Object?>{});
        continue;
      }

      final separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) {
        return ThemeParseResult.failure(
          '$sourceLabel:${index + 1} is not a valid key/value pair.',
        );
      }

      final key = line.substring(0, separatorIndex).trim();
      final rawValue = line.substring(separatorIndex + 1).trim();
      if (key.isEmpty || rawValue.isEmpty) {
        return ThemeParseResult.failure(
          '$sourceLabel:${index + 1} is missing a key or value.',
        );
      }

      final parsedValue = _parseValue(rawValue);
      if (parsedValue == null) {
        return ThemeParseResult.failure(
          '$sourceLabel:${index + 1} uses an unsupported TOML value: $rawValue',
        );
      }

      final target = currentSection == null
          ? topLevel
          : sections.putIfAbsent(currentSection, () => <String, Object?>{});
      if (target.containsKey(key)) {
        warnings.add(
          'Duplicate key ${currentSection == null ? key : '$currentSection.$key'} in $sourceLabel; last value wins.',
        );
      }
      target[key] = parsedValue;
    }

    return ThemeParseResult.success(
      ParsedThemeDocument(
        sourceLabel: sourceLabel,
        topLevel: topLevel,
        sections: sections,
        warnings: warnings,
      ),
    );
  }

  Object? _parseValue(String rawValue) {
    if (rawValue.startsWith('"') && rawValue.endsWith('"')) {
      try {
        return jsonDecode(rawValue);
      } catch (_) {
        return null;
      }
    }
    if (rawValue == 'true') {
      return true;
    }
    if (rawValue == 'false') {
      return false;
    }
    final integer = int.tryParse(rawValue);
    if (integer != null) {
      return integer;
    }
    final decimal = double.tryParse(rawValue);
    if (decimal != null) {
      return decimal;
    }
    return null;
  }

  String _stripComment(String line) {
    var inString = false;
    var escaped = false;
    final buffer = StringBuffer();

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (!inString && char == '#') {
        break;
      }
      if (char == '"' && !escaped) {
        inString = !inString;
      }
      buffer.write(char);
      escaped = !escaped && char == '\\';
    }

    return buffer.toString();
  }
}
