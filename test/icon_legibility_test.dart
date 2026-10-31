import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Ink-legibility regressions for glyphs drawn on *tinted* surfaces.
///
/// The original bug: icons used `brandInk`, which is computed against the
/// canvas. On a 12–20% brand capsule the hue distance collapses, so in dark
/// mode the action-dock and settings icons measured ~2–3:1 and effectively
/// disappeared. These tests pin the capsule-aware helpers instead.
double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// Pumps [body] under an explicit brightness, asserting the theme really is the
/// requested one before the body runs.
Future<void> _underBrightness(
  WidgetTester tester,
  bool dark,
  void Function(BuildContext context) body,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppPalette.premiumBlue.brand,
          brightness: dark ? Brightness.dark : Brightness.light,
        ),
      ),
      home: Builder(
        builder: (context) {
          expect(
            AppColors.isDark(context),
            dark,
            reason: 'harness must produce the requested brightness',
          );
          body(context);
          return const SizedBox();
        },
      ),
    ),
  );
}

void main() {
  group('brandWellInk', () {
    testWidgets('every palette clears AA on the icon capsule (light)',
        (tester) async {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        await _underBrightness(tester, false, (context) {
          final capsule = Color.alphaBlend(
            AppColors.brand.withValues(alpha: AppColors.brandWellAlpha(false)),
            AppColors.surface,
          );
          expect(
            _contrast(AppColors.brandWellInk(context), capsule),
            greaterThanOrEqualTo(4.5),
            reason: palette.label,
          );
        });
      }
    });

    testWidgets('every palette clears AA on the icon capsule (dark)',
        (tester) async {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        await _underBrightness(tester, true, (context) {
          final capsule = Color.alphaBlend(
            AppColors.brand.withValues(alpha: AppColors.brandWellAlpha(true)),
            AppColors.darkSurface,
          );
          expect(
            _contrast(AppColors.brandWellInk(context), capsule),
            greaterThanOrEqualTo(4.5),
            reason: palette.label,
          );
        });
      }
    });
  });

  group('inkOn', () {
    test('lifts a glyph that would match its own tinted well', () {
      // Paper's ultramarine on a 12% ultramarine well is the worst case.
      final tint = AppPalette.paper.brand;
      final well = tint.withValues(alpha: 0.12);
      final blended = Color.alphaBlend(well, AppPalette.paper.darkSurface);
      final ink = AppColors.inkOn(tint, well, AppPalette.paper.darkSurface);
      expect(_contrast(ink, blended), greaterThanOrEqualTo(4.5));
    });

    test('keeps the tint when it already reads well', () {
      const tint = Color(0xFF12B76A);
      final well = tint.withValues(alpha: 0.12);
      final blended = Color.alphaBlend(well, Colors.white);
      final ink = AppColors.inkOn(tint, well, Colors.white);
      expect(_contrast(ink, blended), greaterThanOrEqualTo(4.5));
    });
  });

  group('dark surfaces are lit, not flat black', () {
    test('raised dark surface is lighter than the canvas', () {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        expect(
          AppColors.darkSurfaceAlt.computeLuminance(),
          greaterThan(AppColors.darkBackground.computeLuminance()),
          reason: palette.label,
        );
      }
    });

    test('Paper enables the glass path so dark mode has glassmorphism', () {
      expect(AppPalette.paper.glass, isTrue);
    });
  });
}
