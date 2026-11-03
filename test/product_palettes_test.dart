import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// The six palettes the product owner specified by name and colour.
///
/// The pairs below are the requirements, not a description of the code: a
/// Primary and a light neutral per theme. `brand` and `background` must equal
/// them byte for byte. Everything else in each palette is derived, so it is
/// left to the contrast suites to police — but these two values are the brief
/// and a drifted hex is a defect no contrast test would notice.
///
/// Names are asserted verbatim, including `WineRed, UnlightSand`, which reads
/// unusually but was supplied that way and must not be "corrected".
const _brief = <({String id, String label, Color brand, Color neutral})>[
  (
    id: 'royal_blue_cream',
    label: 'Royal Blue + Light Cream',
    brand: Color(0xFF014BAA),
    neutral: Color(0xFFF8F3F0),
  ),
  (
    id: 'wine_sand',
    label: 'WineRed, UnlightSand',
    brand: Color(0xFF7F011F),
    neutral: Color(0xFFF5EBD0),
  ),
  (
    id: 'orange_milk',
    label: 'Orange + milk',
    brand: Color(0xFFEC5E27),
    neutral: Color(0xFFFDFDF1),
  ),
  (
    id: 'plum_milk',
    label: 'Plum + milk',
    brand: Color(0xFF381932),
    neutral: Color(0xFFFFF3E6),
  ),
  (
    id: 'midnight_indigo_vanilla',
    label: 'Midnight, Indigo, Vanilla',
    brand: Color(0xFF282B4A),
    neutral: Color(0xFFEEEBDA),
  ),
  (
    id: 'cherry_alabaster',
    label: 'Cherry and alabaster',
    brand: Color(0xFF890149),
    neutral: Color(0xFFF3F3E7),
  ),
];

void main() {
  setUp(() => AppColors.applyPalette(AppPalette.defaultPalette));
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  group('product-owner palettes', () {
    for (final spec in _brief) {
      test('${spec.label}: exact name, primary and light neutral', () {
        final palette = AppPalette.all.firstWhere(
          (p) => p.id == spec.id,
          orElse: () => fail('palette "${spec.id}" is missing'),
        );
        expect(palette.label, spec.label);
        expect(palette.brand.toARGB32(), spec.brand.toARGB32(),
            reason: 'primary drifted from the supplied value');
        expect(palette.background.toARGB32(), spec.neutral.toARGB32(),
            reason: 'light neutral drifted from the supplied value');
      });

      test('${spec.label}: dark mode is a tinted glass canvas', () {
        final palette = AppPalette.all.firstWhere((p) => p.id == spec.id);
        // A glass palette ships designed dark surfaces; without the flag they
        // would be re-tinted on top, which is the saturation bug
        // dark_surface_tones_test.dart guards against.
        expect(palette.glass, isTrue);
        // Hue-tinted near-black rather than the shared AMOLED black, so the
        // theme is visible in dark mode and not just in light mode.
        expect(palette.isAmoled, isFalse,
            reason: 'dark canvas should carry the palette hue');
        expect(palette.darkBackground.computeLuminance(), lessThan(0.02),
            reason: 'dark canvas should stay dark');
      });
    }

    test('every brief palette is selectable and stored by id', () async {
      for (final spec in _brief) {
        SharedPreferences.setMockInitialValues({'palette_id': spec.id});
        final provider = ThemeProvider();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(provider.palette.id, spec.id,
            reason: '${spec.id} did not survive a restart');
        // The mirrored tokens must follow the palette, not the previous one.
        expect(AppColors.palette.id, spec.id);
        expect(AppColors.brand, provider.palette.brand);
        expect(AppColors.background, provider.palette.background);
      }
    });

    test('selecting a brief palette persists it for the next launch', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final target =
          AppPalette.all.firstWhere((p) => p.id == 'midnight_indigo_vanilla');
      await provider.setPalette(target);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('palette_id'), 'midnight_indigo_vanilla');

      // A fresh provider reads the same selection back.
      final reloaded = ThemeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(reloaded.palette.id, 'midnight_indigo_vanilla');
    });

    test('appearance mode does not disturb the selected palette', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await provider.setPalette(AppPalette.cherryAlabaster);

      for (final mode in ThemeMode.values) {
        await provider.setThemeMode(mode);
        expect(provider.palette.id, 'cherry_alabaster',
            reason: 'switching to $mode changed the palette');
      }
    });

    test('money semantics stay identical across the brief palettes', () {
      for (final spec in _brief) {
        final palette = AppPalette.all.firstWhere((p) => p.id == spec.id);
        expect(palette.chartPalette, contains(AppPalette.expenseRed));
        expect(palette.chartPalette, contains(AppPalette.incomeGreen));
      }
    });

    test('the default identity is unchanged by the additions', () {
      expect(AppPalette.defaultPalette.id, 'premium_blue');
      expect(AppPalette.byId(null).id, 'premium_blue');
      expect(AppPalette.byId('no_such_palette').id, 'premium_blue');
    });

    test('every brief palette id is unique across the whole set', () {
      final ids = AppPalette.all.map((p) => p.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
    });
  });
}
