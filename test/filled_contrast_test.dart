import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/main.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/utils/app_typography.dart';

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUp(() => AppTypography.debugSkipFontLoading = true);
  tearDown(() {
    AppTypography.debugSkipFontLoading = false;
    AppColors.applyPalette(AppPalette.defaultPalette);
  });

  group('filled-button white-on-brand contrast (Task 1)', () {
    for (final palette in AppPalette.all) {
      test('${palette.label}: FilledButton white label >=4.5:1', () {
        AppColors.applyPalette(palette);
        // Filled/Elevated use the derived filledBrand + white foreground.
        final filled = palette.filledBrand;
        expect(_contrast(filled, Colors.white), greaterThanOrEqualTo(4.5),
            reason: '${palette.label} filled $filled vs white');
      });

      test('${palette.label}: filledBrand keeps hue, only darkens toward deep',
          () {
        AppColors.applyPalette(palette);
        if (_rawBrandAlreadyPasses(palette)) {
          // palettes that already cleared keep raw brand
          expect(palette.filledBrand, palette.brand, reason: palette.label);
        } else {
          // the two that needed darkening keep the same hue family
          final hOrig = HSLColor.fromColor(palette.brand).hue;
          final hFilled = HSLColor.fromColor(palette.filledBrand).hue;
          // circular hue distance
          double diff = (hFilled - hOrig).abs();
          if (diff > 180) diff = 360 - diff;
          expect(diff, lessThanOrEqualTo(8), reason: palette.label);
          expect(palette.filledBrand.computeLuminance(),
              lessThan(palette.brand.computeLuminance()),
              reason: '${palette.label} must darken, not lighten');
        }
      });

      test('${palette.label}: actionGradient lightest stop >=4.5:1 on white',
          () {
        AppColors.applyPalette(palette);
        final top = palette.actionTop;
        expect(_contrast(top, Colors.white), greaterThanOrEqualTo(4.5),
            reason: '${palette.label} actionTop $top');
      });

      test('${palette.label}: theme FilledButton background == filledBrand',
          () {
        AppColors.applyPalette(palette);
        for (final brightness in Brightness.values) {
          final theme =
              const SpendSenseApp().themeFor(brightness, FontPreset.standard);
          final bg = theme.filledButtonTheme.style!.backgroundColor!
              .resolve(<WidgetState>{})!;
          expect(bg, palette.filledBrand,
              reason: '${palette.label} $brightness filled theme');
          expect(_contrast(bg, Colors.white), greaterThanOrEqualTo(4.5));
          final elevatedBg = theme.elevatedButtonTheme.style!.backgroundColor!
              .resolve(<WidgetState>{})!;
          expect(elevatedBg, palette.filledBrand);
        }
      });
    }

    test('spot: Emerald before would be 3.37, after >=4.5 (regression guard)',
        () {
      // Raw emerald brand vs white is the reported failure value.
      const rawEmeraldBrand = Color(0xFF12A150);
      expect(_contrast(rawEmeraldBrand, Colors.white), lessThan(4.5));
      expect(_contrast(const Color(0xFF12A150), Colors.white),
          closeTo(3.37, 0.08));
      // Derived filledBrand must pass.
      expect(_contrast(AppPalette.emerald.filledBrand, Colors.white),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(AppPalette.teal.filledBrand, Colors.white),
          greaterThanOrEqualTo(4.5));
    });
  });
}

bool _rawBrandAlreadyPasses(AppPalette p) {
  // raw brand already >=4.5 vs white
  final l = p.brand.computeLuminance();
  final c = 1.05 / (l + 0.05);
  return c >= 4.5;
}
