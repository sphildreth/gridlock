import 'package:flutter/material.dart';

import 'decent_bench_theme.dart';
import 'theme_presets.dart';

class DecentBenchThemeExtension
    extends ThemeExtension<DecentBenchThemeExtension> {
  const DecentBenchThemeExtension(this.theme);

  final DecentBenchTheme theme;

  @override
  ThemeExtension<DecentBenchThemeExtension> copyWith({
    DecentBenchTheme? theme,
  }) {
    return DecentBenchThemeExtension(theme ?? this.theme);
  }

  @override
  ThemeExtension<DecentBenchThemeExtension> lerp(
    covariant ThemeExtension<DecentBenchThemeExtension>? other,
    double t,
  ) {
    return t < 0.5 ? this : (other ?? this);
  }
}

extension DecentBenchThemeContext on BuildContext {
  DecentBenchTheme get decentBenchTheme {
    return Theme.of(this).extension<DecentBenchThemeExtension>()?.theme ??
        buildEmergencyTheme();
  }
}
