import 'dart:convert';
import 'dart:typed_data';

import '../domain/import_models.dart';
import '../../workspace/domain/workspace_models.dart';

class TypeInferenceService {
  const TypeInferenceService();

  List<ImportColumnDraft> inferColumns(
    List<Map<String, Object?>> rows,
    Iterable<String> orderedKeys,
  ) {
    final columns = <ImportColumnDraft>[];
    for (final key in orderedKeys) {
      final values = rows.map((row) => row[key]).toList(growable: false);
      final containsNulls = values.any((value) => value == null);
      final inferred = inferTargetType(values);
      columns.add(
        ImportColumnDraft(
          sourceName: key,
          targetName: sanitizeIdentifier(key, fallbackPrefix: 'column'),
          inferredTargetType: inferred,
          targetType: inferred,
          containsNulls: containsNulls,
        ),
      );
    }
    return columns;
  }

  String inferTargetType(Iterable<Object?> values) {
    final nonNull = values
        .where((value) => value != null)
        .toList(growable: false);
    if (nonNull.isEmpty) {
      return 'TEXT';
    }
    if (nonNull.every((value) => value is bool || _looksLikeBool(value))) {
      return 'BOOLEAN';
    }
    if (nonNull.every(_isUuidLike)) {
      return 'UUID';
    }
    if (nonNull.every(_isIntegerLike)) {
      if (nonNull.any(_hasLeadingZeroString)) {
        return 'TEXT';
      }
      return 'INTEGER';
    }
    if (nonNull.every(_isDoubleLike)) {
      return 'FLOAT64';
    }
    if (nonNull.every(_isTimestampLike)) {
      return 'TIMESTAMP';
    }
    if (nonNull.every((value) => value is Uint8List)) {
      return 'BLOB';
    }
    return 'TEXT';
  }

  Object? coerceValue(Object? value, String targetType) {
    if (value == null) {
      return null;
    }
    if (targetType == 'TEXT') {
      if (value is Uint8List) {
        return formatCellValue(value);
      }
      if (value is List || value is Map) {
        return jsonEncode(value);
      }
      return '$value';
    }
    if (targetType == 'BOOLEAN') {
      if (value is bool) {
        return value;
      }
      if (value is num && (value == 0 || value == 1)) {
        return value == 1;
      }
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (const <String>{'true', '1', 'yes', 'y'}.contains(normalized)) {
          return true;
        }
        if (const <String>{'false', '0', 'no', 'n'}.contains(normalized)) {
          return false;
        }
      }
      return value;
    }
    if (targetType == 'INTEGER') {
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        return int.tryParse(value.trim()) ?? value;
      }
      return value;
    }
    if (targetType == 'FLOAT64') {
      if (value is double) {
        return value;
      }
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        return double.tryParse(value.trim()) ?? value;
      }
      return value;
    }
    if (targetType == 'BLOB') {
      if (value is Uint8List) {
        return value;
      }
      if (value is String) {
        return Uint8List.fromList(value.codeUnits);
      }
      return Uint8List.fromList(utf8.encode('$value'));
    }
    if (targetType == 'TIMESTAMP') {
      if (value is DateTime) {
        return value.toUtc();
      }
      if (value is String) {
        return DateTime.tryParse(value.trim())?.toUtc() ?? value;
      }
      return value;
    }
    if (isDecimalTargetType(targetType)) {
      if (value is num) {
        return value.toString();
      }
      return '$value';
    }
    if (isUuidTargetType(targetType)) {
      return '$value';
    }
    return value;
  }

  String sanitizeIdentifier(String raw, {required String fallbackPrefix}) {
    final trimmed = raw.trim();
    final normalized = trimmed
        .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) {
      return '${fallbackPrefix}_1';
    }
    final startsWithDigit = RegExp(r'^[0-9]').hasMatch(normalized);
    return startsWithDigit ? '${fallbackPrefix}_$normalized' : normalized;
  }

  List<String> distinctTargetNames(
    Iterable<String> rawNames, {
    required String fallbackPrefix,
  }) {
    final used = <String>{};
    final result = <String>[];
    for (final rawName in rawNames) {
      final base = sanitizeIdentifier(rawName, fallbackPrefix: fallbackPrefix);
      var candidate = base;
      var suffix = 2;
      while (used.contains(candidate)) {
        candidate = '${base}_$suffix';
        suffix++;
      }
      used.add(candidate);
      result.add(candidate);
    }
    return result;
  }

  bool _looksLikeBool(Object? value) {
    if (value is! String) {
      return false;
    }
    final normalized = value.trim().toLowerCase();
    return const <String>{
      'true',
      'false',
      'yes',
      'no',
      '1',
      '0',
      'y',
      'n',
    }.contains(normalized);
  }

  bool _isIntegerLike(Object? value) {
    if (value is int) {
      return true;
    }
    if (value is double) {
      return value == value.roundToDouble();
    }
    return value is String && int.tryParse(value.trim()) != null;
  }

  bool _hasLeadingZeroString(Object? value) {
    if (value is! String) {
      return false;
    }
    final trimmed = value.trim();
    return trimmed.length > 1 && trimmed.startsWith('0');
  }

  bool _isDoubleLike(Object? value) {
    if (value is num) {
      return true;
    }
    return value is String && double.tryParse(value.trim()) != null;
  }

  bool _isTimestampLike(Object? value) {
    if (value is DateTime) {
      return true;
    }
    return value is String && DateTime.tryParse(value.trim()) != null;
  }

  bool _isUuidLike(Object? value) {
    if (value is! String) {
      return false;
    }
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value.trim());
  }
}
