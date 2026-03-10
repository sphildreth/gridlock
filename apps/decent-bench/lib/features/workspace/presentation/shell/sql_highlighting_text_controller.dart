import 'package:flutter/material.dart';

import '../../../../app/theme_system/decent_bench_theme_extension.dart';
import '../../domain/sql_vocabulary.dart';

class SqlHighlightingTextEditingController extends TextEditingController {
  SqlHighlightingTextEditingController({super.text});

  static final Set<String> _keywordSet = decentDbSqlKeywords
      .map((keyword) => keyword.toLowerCase())
      .toSet();
  static final Set<String> _functionSet = decentDbSqlFunctions
      .map((functionName) => functionName.toLowerCase())
      .toSet();
  static const Set<String> _constantSet = <String>{
    'true',
    'false',
    'null',
    'current_timestamp',
    'current_date',
    'current_time',
  };
  static const Set<String> _typeSet = <String>{
    'any',
    'blob',
    'boolean',
    'date',
    'datetime',
    'decimal',
    'double',
    'float',
    'integer',
    'int',
    'numeric',
    'real',
    'text',
    'time',
    'timestamp',
    'varchar',
  };
  static const Set<String> _operatorChars = <String>{
    '+',
    '-',
    '*',
    '/',
    '%',
    '=',
    '<',
    '>',
    '!',
    '|',
    '&',
    '^',
    '~',
    '.',
    ',',
    ';',
    '(',
    ')',
    '[',
    ']',
  };

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final theme = context.decentBenchTheme;
    final baseStyle = (style ?? const TextStyle()).copyWith(
      color: theme.sqlSyntax.identifier,
      fontFamily: theme.fonts.editorFamily,
      fontSize: theme.fonts.editorSize,
      height: theme.fonts.lineHeight,
    );
    final spans = <InlineSpan>[];
    final source = text;
    var index = 0;

    while (index < source.length) {
      final current = source[index];

      if (current == '-' &&
          index + 1 < source.length &&
          source[index + 1] == '-') {
        final end = _scanLineComment(source, index + 2);
        spans.add(
          TextSpan(
            text: source.substring(index, end),
            style: baseStyle.copyWith(color: theme.sqlSyntax.comment),
          ),
        );
        index = end;
        continue;
      }

      if (current == '/' &&
          index + 1 < source.length &&
          source[index + 1] == '*') {
        final end = _scanBlockComment(source, index + 2);
        final isClosed = end < source.length || source.endsWith('*/');
        spans.add(
          TextSpan(
            text: source.substring(index, end),
            style: baseStyle.copyWith(
              color: isClosed ? theme.sqlSyntax.comment : theme.sqlSyntax.error,
            ),
          ),
        );
        index = end;
        continue;
      }

      if (current == '\'') {
        final scan = _scanSingleQuotedString(source, index + 1);
        spans.add(
          TextSpan(
            text: source.substring(index, scan.end),
            style: baseStyle.copyWith(
              color: scan.terminated
                  ? theme.sqlSyntax.string
                  : theme.sqlSyntax.error,
            ),
          ),
        );
        index = scan.end;
        continue;
      }

      if (current == '"') {
        final scan = _scanDoubleQuotedIdentifier(source, index + 1);
        spans.add(
          TextSpan(
            text: source.substring(index, scan.end),
            style: baseStyle.copyWith(
              color: scan.terminated
                  ? theme.sqlSyntax.identifier
                  : theme.sqlSyntax.error,
            ),
          ),
        );
        index = scan.end;
        continue;
      }

      if (_isParameterStart(source, index)) {
        final end = _scanParameter(source, index + 1);
        spans.add(
          TextSpan(
            text: source.substring(index, end),
            style: baseStyle.copyWith(color: theme.sqlSyntax.parameter),
          ),
        );
        index = end;
        continue;
      }

      if (_isDigit(current)) {
        final end = _scanNumber(source, index + 1);
        spans.add(
          TextSpan(
            text: source.substring(index, end),
            style: baseStyle.copyWith(color: theme.sqlSyntax.number),
          ),
        );
        index = end;
        continue;
      }

      if (_isIdentifierStart(current)) {
        final end = _scanIdentifier(source, index + 1);
        final lexeme = source.substring(index, end);
        final lower = lexeme.toLowerCase();
        final nextNonWhitespace = _nextNonWhitespace(source, end);
        final tokenStyle = switch (true) {
          _ when _constantSet.contains(lower) => baseStyle.copyWith(
            color: theme.sqlSyntax.constant,
            fontWeight: FontWeight.w700,
          ),
          _ when _functionSet.contains(lower) && nextNonWhitespace == '(' =>
            baseStyle.copyWith(color: theme.sqlSyntax.function),
          _ when _typeSet.contains(lower) => baseStyle.copyWith(
            color: theme.sqlSyntax.type,
          ),
          _ when _keywordSet.contains(lower) => baseStyle.copyWith(
            color: theme.sqlSyntax.keyword,
            fontWeight: FontWeight.w700,
          ),
          _ => baseStyle.copyWith(color: theme.sqlSyntax.identifier),
        };
        spans.add(TextSpan(text: lexeme, style: tokenStyle));
        index = end;
        continue;
      }

      if (_operatorChars.contains(current)) {
        spans.add(
          TextSpan(
            text: current,
            style: baseStyle.copyWith(color: theme.sqlSyntax.operator),
          ),
        );
        index++;
        continue;
      }

      spans.add(TextSpan(text: current, style: baseStyle));
      index++;
    }

    return TextSpan(style: baseStyle, children: spans);
  }

  static int _scanLineComment(String source, int index) {
    while (index < source.length && source[index] != '\n') {
      index++;
    }
    return index;
  }

  static int _scanBlockComment(String source, int index) {
    while (index < source.length - 1) {
      if (source[index] == '*' && source[index + 1] == '/') {
        return index + 2;
      }
      index++;
    }
    return source.length;
  }

  static _StringScanResult _scanSingleQuotedString(String source, int index) {
    while (index < source.length) {
      if (source[index] == '\'') {
        if (index + 1 < source.length && source[index + 1] == '\'') {
          index += 2;
          continue;
        }
        return _StringScanResult(end: index + 1, terminated: true);
      }
      index++;
    }
    return _StringScanResult(end: source.length, terminated: false);
  }

  static _StringScanResult _scanDoubleQuotedIdentifier(
    String source,
    int index,
  ) {
    while (index < source.length) {
      if (source[index] == '"') {
        if (index + 1 < source.length && source[index + 1] == '"') {
          index += 2;
          continue;
        }
        return _StringScanResult(end: index + 1, terminated: true);
      }
      index++;
    }
    return _StringScanResult(end: source.length, terminated: false);
  }

  static int _scanNumber(String source, int index) {
    while (index < source.length) {
      final current = source[index];
      if (!_isDigit(current) && current != '.') {
        return index;
      }
      index++;
    }
    return source.length;
  }

  static int _scanIdentifier(String source, int index) {
    while (index < source.length && _isIdentifierPart(source[index])) {
      index++;
    }
    return index;
  }

  static bool _isParameterStart(String source, int index) {
    final current = source[index];
    if (current == '?') {
      return true;
    }
    if ((current == ':' || current == '@') &&
        index + 1 < source.length &&
        _isIdentifierStart(source[index + 1])) {
      return true;
    }
    if (current == r'$' &&
        index + 1 < source.length &&
        (_isIdentifierStart(source[index + 1]) ||
            _isDigit(source[index + 1]))) {
      return true;
    }
    return false;
  }

  static int _scanParameter(String source, int index) {
    while (index < source.length && _isIdentifierPart(source[index])) {
      index++;
    }
    return index;
  }

  static String? _nextNonWhitespace(String source, int index) {
    while (index < source.length) {
      final current = source[index];
      if (current.trim().isNotEmpty) {
        return current;
      }
      index++;
    }
    return null;
  }

  static bool _isDigit(String value) {
    final codeUnit = value.codeUnitAt(0);
    return codeUnit >= 48 && codeUnit <= 57;
  }

  static bool _isIdentifierStart(String value) {
    final codeUnit = value.codeUnitAt(0);
    return (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122) ||
        value == '_';
  }

  static bool _isIdentifierPart(String value) {
    return _isIdentifierStart(value) || _isDigit(value);
  }
}

class _StringScanResult {
  const _StringScanResult({required this.end, required this.terminated});

  final int end;
  final bool terminated;
}
