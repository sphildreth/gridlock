import 'package:flutter/material.dart';

Color? parseThemeColor(String raw) {
  final normalized = raw.trim();
  final hex = normalized.startsWith('#') ? normalized.substring(1) : normalized;
  if (hex.length != 6 && hex.length != 8) {
    return null;
  }
  final value = int.tryParse(hex, radix: 16);
  if (value == null) {
    return null;
  }
  return Color(hex.length == 6 ? (0xFF000000 | value) : value);
}

class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static SemanticVersion? parse(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 3) {
      return null;
    }

    final major = int.tryParse(parts[0]);
    final minor = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (major == null || minor == null || patch == null) {
      return null;
    }

    return SemanticVersion(major, minor, patch);
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }
}

class SemanticVersionPattern {
  const SemanticVersionPattern(this.major, this.minor, this.patch);

  final int? major;
  final int? minor;
  final int? patch;

  static SemanticVersionPattern? parse(String raw) {
    final parts = raw.trim().split('.');
    if (parts.length != 3) {
      return null;
    }

    int? parsePart(String value) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'x' || normalized == '*') {
        return null;
      }
      return int.tryParse(normalized);
    }

    final major = parsePart(parts[0]);
    final minor = parsePart(parts[1]);
    final patch = parsePart(parts[2]);

    if ((major == null &&
            parts[0].trim().toLowerCase() != 'x' &&
            parts[0].trim() != '*') ||
        (minor == null &&
            parts[1].trim().toLowerCase() != 'x' &&
            parts[1].trim() != '*') ||
        (patch == null &&
            parts[2].trim().toLowerCase() != 'x' &&
            parts[2].trim() != '*')) {
      return null;
    }

    return SemanticVersionPattern(major, minor, patch);
  }

  bool contains(SemanticVersion version) {
    if (major != null) {
      if (version.major > major!) {
        return false;
      }
      if (version.major < major!) {
        return true;
      }
    } else {
      return true;
    }

    if (minor != null) {
      if (version.minor > minor!) {
        return false;
      }
      if (version.minor < minor!) {
        return true;
      }
    } else {
      return true;
    }

    if (patch != null) {
      return version.patch <= patch!;
    }
    return true;
  }
}
