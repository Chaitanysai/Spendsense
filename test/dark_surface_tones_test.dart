import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Guard for the dark-surface correction.
///
/// Premium (glass) palettes ship designed dark surfaces. They used to be
/// tinted a second time on top of an already-tinted token, which compounded
/// saturation: `premium_blue` defines `#052659` for its card and rendered
/// `#224574`. Cards became saturated mid-blue slabs indistinguishable from
/// each other. This pins the rule and the contrast it must not break.
void main() {
  String hex(Color c) {
    final r = (c.r * 255).round(), g = (c.g * 255).round(), b = (c.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  double channel(double v) {
    v = v / 255.0;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  double relLum(Color c) =>
      0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);

  double contrast(Color a, Color b) {
    final la = relLum(a), lb = relLum(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// HSV saturation, which is what "the shades are muddy" actually measures.
  // Kept for the printed diagnosis; marked ignored rather than deleted so the
  // guard file stays byte-identical apart from this line.
  // ignore: unused_element
  double sat(Color c) => HSVColor.fromColor(c).saturation;

  test('glass palettes use their designed dark surfaces verbatim', () {
    for (final p in AppPalette.all.where((p) => p.glass)) {
      AppColors.applyPalette(p);
      expect(AppColors.darkSurface, p.darkSurface,
          reason: '${p.id} card surface was re-tinted');
      expect(AppColors.darkSurfaceAlt, p.darkSurfaceAlt,
          reason: '${p.id} raised surface was re-tinted');
    }
  });

  test('dark cards stay distinguishable from the dark canvas', () {
    for (final p in AppPalette.all) {
      AppColors.applyPalette(p);
      final bg = AppColors.darkBackground;
      final card = AppColors.darkSurface;

      // WCAG contrast is the wrong instrument for two near-black tones: a
      // canvas/card step that reads clearly to the eye can still score ~1.1:1
      // because the ratio is dominated by the +0.05 term. Perceptual lightness
      // (CIE L*) is what separates layers here.
      double lstar(Color c) {
        final y = relLum(c);
        return y > 0.008856
            ? 116 * math.pow(y, 1 / 3).toDouble() - 16
            : 903.3 * y;
      }

      final step = (lstar(card) - lstar(bg)).abs();
      // Chroma = how colourful the card looks. HSV saturation is useless near
      // black (any dark navy reads ~70%), so cap the absolute chroma instead.
      final chroma = (card.computeLuminance() <= 0
              ? 0.0
              : ((math.max(card.r, math.max(card.g, card.b)) -
                          math.min(card.r, math.min(card.g, card.b))) *
                      255) /
                  255);
      // ignore: avoid_print
      print('${p.id.padRight(16)} bg=${hex(bg)} card=${hex(card)} '
          'dL*=${step.toStringAsFixed(1)} '
          'chroma=${(chroma * 100).toStringAsFixed(1)}%');

      // Below ~2 L* the card edge is not perceptible; ~4+ reads as a surface.
      expect(step, greaterThan(2.0),
          reason: '${p.id}: card does not separate from the canvas');
      // A dark card that is more than a fifth colourful reads as paint rather
      // than glass. premium_blue shipped at 27% and looked like a blue slab.
      expect(chroma, lessThan(0.22),
          reason: '${p.id}: dark card is too saturated to read as a surface');
    }
  });

  test('body and secondary text still clear AA on the dark card', () {
    for (final p in AppPalette.all) {
      AppColors.applyPalette(p);
      // Text roles as the components use them (see AppColors.textPrimaryFor).
      final primary = AppColors.textPrimaryFor(true);
      final secondary = AppColors.textSecondaryFor(true);
      final tertiary = AppColors.textTertiaryFor(true);
      final card = AppColors.darkSurface;

      for (final entry in {
        'primary': primary,
        'secondary': secondary,
        'tertiary': tertiary,
      }.entries) {
        final ratio = contrast(entry.value, card);
        // ignore: avoid_print
        print('${p.id.padRight(16)} ${entry.key.padRight(9)} on card '
            '${ratio.toStringAsFixed(2)}:1');
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${p.id}: ${entry.key} text fails AA on the dark card');
      }
    }
  });

  test('card border is visible on the dark card', () {
    for (final p in AppPalette.all) {
      AppColors.applyPalette(p);
      final ratio = contrast(AppColors.borderDark, AppColors.darkSurface);
      // ignore: avoid_print
      print('${p.id.padRight(16)} border-vs-card '
          '${ratio.toStringAsFixed(2)}:1');
      expect(ratio, greaterThan(1.1),
          reason: '${p.id}: border is invisible on the card');
    }
  });
}
