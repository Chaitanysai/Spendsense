import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Measures the glyph against the *actual* surface it is composited onto.
///
/// The first version of this sweep blended the well onto `AppColors.surface`
/// in both themes, which under-lights the dark case: dark tiles sit on the
/// tinted `darkSurfaceAlt`, not on the light surface. That overstated the
/// problem and hid nothing, but the numbers were wrong, so they are computed
/// here against the real base.
double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('settings well ink sweep', () {
    var worstOverall = 99.0;
    for (final dark in [false, true]) {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        final Color base =
            dark ? AppColors.darkSurfaceAlt : AppColors.surface;
        final alpha = dark ? 0.22 : 0.12;

        final out = <String>[];
        final roles = <(String, Color)>[
          ('azure', AppColors.azure),
          ('brandBright', AppColors.brandBright),
          ('brand', AppColors.brand),
          ('danger', AppColors.danger),
          ('warning', AppColors.warning),
          ('incomeGreen', AppColors.incomeGreen),
        ];
        for (final role in roles) {
          final String name = role.$1;
          final Color tint = role.$2;
          final tinted = tint.withValues(alpha: alpha);
          final blended = Color.alphaBlend(tinted, base);
          final raw = _contrast(tint, blended);
          final fixed = _contrast(AppColors.inkOn(tint, tinted, base), blended);
          if (fixed < worstOverall) worstOverall = fixed;
          if (raw < 4.5) {
            out.add('$name ${raw.toStringAsFixed(2)}'
                '->${fixed.toStringAsFixed(2)}');
          }
        }
        if (out.isNotEmpty) {
          // ignore: avoid_print
          print('${dark ? "DARK " : "LIGHT"} '
              '${palette.id.padRight(17)} ${out.join("  ")}');
        }
      }
    }
    // ignore: avoid_print
    print('MINIMUM inkOn CONTRAST ACROSS ALL PALETTES/THEMES: '
        '${worstOverall.toStringAsFixed(2)}:1');
    expect(worstOverall, greaterThanOrEqualTo(4.5));
  });
}
