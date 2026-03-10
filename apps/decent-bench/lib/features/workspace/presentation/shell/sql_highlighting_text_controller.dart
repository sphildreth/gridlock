import 'package:flutter/material.dart';

import '../../domain/sql_vocabulary.dart';

class SqlHighlightingTextEditingController extends TextEditingController {
  SqlHighlightingTextEditingController({super.text});

  static final Set<String> _keywordSet = decentDbSqlKeywords
      .map((keyword) => keyword.toLowerCase())
      .toSet();
  static final Set<String> _functionSet = decentDbSqlFunctions
      .map((functionName) => functionName.toLowerCase())
      .toSet();

  static const Color _commentColor = Color(0xFF5F7B4A);
  static const Color _stringColor = Color(0xFF9E2A2B);
  static const Color _numberColor = Color(0xFF0F5D75);
  static const Color _keywordColor = Color(0xFF0B4F8C);
  static const Color _functionColor = Color(0xFF7A4B10);
  static const Color _identifierColor = Color(0xFF111111);
  static const Color _quotedIdentifierColor = Color(0xFF444444);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseStyle = (style ?? const TextStyle()).copyWith(
      color: _identifierColor,
      fontFamily: 'monospace',
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
            style: baseStyle.copyWith(color: _commentColor),
          ),
        );
        index = end;
        continue;
      }

      if (current == '/' &&
          index + 1 < source.length &&
          source[index + 1] == '*') {
        final end = _scanBlockComment(source, index + 2);
        spans.add(
          TextSpan(
            text: source.substring(index, end),
            style: baseStyle.copyWith(color: _commentColor),
          ),
        );
        index = end;
        continue;
      }

      if (current == '\'') {
        final end = _scanSingleQuotedString(source, index + 1);
        spans.add(
          TextSpan(
            text: source.substring(index, end),
            style: baseStyle.copyWith(color: _stringColor),
          ),
        );
        index = end;
        continue;
      }

      if (current == '"') {
        final end = _scanDoubleQuotedIdentifier(source, index + 1);
        spans.add(
          TextSpan(
            text: source.substring(index, end),
            style: baseStyle.copyWith(color: _quotedIdentifierColor),
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
            style: baseStyle.copyWith(color: _numberColor),
          ),
        );
        index = end;
        continue;
      }

      if (_isIdentifierStart(current)) {
        final end = _scanIdentifier(source, index + 1);
        final lexeme = source.substring(index, end);
        final lower = lexeme.toLowerCase();
        final tokenStyle = switch (true) {
          _ when _keywordSet.contains(lower) => baseStyle.copyWith(
            color: _keywordColor,
            fontWeight: FontWeight.w700,
          ),
          _ when _functionSet.contains(lower) => baseStyle.copyWith(
            color: _functionColor,
          ),
          _ => baseStyle,
        };
        spans.add(TextSpan(text: lexeme, style: tokenStyle));
        index = end;
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

  static int _scanSingleQuotedString(String source, int index) {
    while (index < source.length) {
      if (source[index] == '\'') {
        if (index + 1 < source.length && source[index + 1] == '\'') {
          index += 2;
          continue;
        }
        return index + 1;
      }
      index++;
    }
    return source.length;
  }

  static int _scanDoubleQuotedIdentifier(String source, int index) {
    while (index < source.length) {
      if (source[index] == '"') {
        if (index + 1 < source.length && source[index + 1] == '"') {
          index += 2;
          continue;
        }
        return index + 1;
      }
      index++;
    }
    return source.length;
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
