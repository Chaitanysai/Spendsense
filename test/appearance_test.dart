import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/screens/appearance_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Appearance is backed by mutable global tokens in [AppColors], so every test
/// restores the default palette to stay order-independent.
void main() {
  setUp(() => AppColors.applyPalette(AppPalette.oceanBlue));
  tearDown(() => AppColors.applyPalette(AppPalette.oceanBlue));

  Future<ThemeProvider> loaded(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final provider = ThemeProvider();
    // Let the async _load() future settle.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return provider;
  }

  group('AppPalette', () {
    test('ships the six curated palettes with Ocean Blue first', () {
      expect(AppPalette.all, hasLength(6));
      expect(AppPalette.all.first, same(AppPalette.oceanBlue));
      expect(
        AppPalette.all.map((p) => p.label),
        containsAll([
          'Ocean Blue',
          'Warm Amber',
          'Forest Green',
          'Royal Purple',
          'Rose',
          'Teal'
        ]),
      );
    });

    test('every palette id is unique', () {
      final ids = AppPalette.all.map((p) => p.id).toSet();
      expect(ids, hasLength(AppPalette.all.length));
    });

    test('byId resolves known ids and falls back to Ocean Blue', () {
      expect(AppPalette.byId('forest_green'), same(AppPalette.forestGreen));
      expect(AppPalette.byId('does_not_exist'), same(AppPalette.oceanBlue));
      expect(AppPalette.byId(null), same(AppPalette.oceanBlue));
    });

    test('money semantics are identical in every palette', () {
      // Red must always mean money out, whichever theme the user picks.
      for (final p in AppPalette.all) {
        expect(p.chartPalette, contains(AppPalette.expenseRed));
        expect(p.chartPalette, contains(AppPalette.incomeGreen));
      }
      expect(AppColors.expenseRed, AppPalette.expenseRed);
      expect(AppColors.incomeGreen, AppPalette.incomeGreen);
    });

    test('Ocean Blue reproduces the shipped navy tokens exactly', () {
      expect(AppPalette.oceanBlue.brand, const Color(0xFF1B44C8));
      expect(AppPalette.oceanBlue.deep, const Color(0xFF071638));
      expect(AppPalette.oceanBlue.bright, const Color(0xFF2F6BFF));
      expect(AppPalette.oceanBlue.background, const Color(0xFFF3F6FD));
      expect(AppPalette.oceanBlue.darkBackground, const Color(0xFF050D24));
    });
  });

  group('AppColors.applyPalette', () {
    test('rewrites the brand ramp and surfaces', () {
      AppColors.applyPalette(AppPalette.rose);
      expect(AppColors.brand, AppPalette.rose.brand);
      expect(AppColors.brandBright, AppPalette.rose.bright);
      expect(AppColors.navyDeep, AppPalette.rose.deep);
      expect(AppColors.background, AppPalette.rose.background);
      expect(AppColors.darkSurface, AppPalette.rose.darkSurface);
      expect(AppColors.palette, same(AppPalette.rose));
    });

    test('gradients track the active palette', () {
      AppColors.applyPalette(AppPalette.teal);
      expect(AppColors.heroGradient.colors.first, AppPalette.teal.brand);
      expect(AppColors.electricGradient.colors.last, AppPalette.teal.mid);
    });

    test('semantic colours never change', () {
      AppColors.applyPalette(AppPalette.royalPurple);
      expect(AppColors.expenseRed, AppPalette.expenseRed);
      expect(AppColors.incomeGreen, AppPalette.incomeGreen);
      expect(AppColors.danger, AppPalette.danger);
    });
  });

  group('ThemeProvider', () {
    test('defaults to Ocean Blue in light mode', () async {
      final provider = await loaded({});
      expect(provider.palette, same(AppPalette.oceanBlue));
      expect(provider.themeMode, ThemeMode.light);
    });

    test('setPalette applies tokens and persists the id', () async {
      final provider = await loaded({});
      await provider.setPalette(AppPalette.rose);

      expect(provider.palette, same(AppPalette.rose));
      expect(AppColors.brand, AppPalette.rose.brand);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('palette_id'), AppPalette.rose.id);
    });

    test('a new provider restores the persisted palette', () async {
      SharedPreferences.setMockInitialValues({});
      final first = ThemeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await first.setPalette(AppPalette.forestGreen);

      final second = ThemeProvider();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(second.palette, same(AppPalette.forestGreen));
    });

    test('an unknown persisted id falls back to Ocean Blue', () async {
      final provider = await loaded({'palette_id': 'chartreuse'});
      expect(provider.palette, same(AppPalette.oceanBlue));
    });

    test('setThemeMode persists light, dark and system', () async {
      final provider = await loaded({});
      for (final mode in ThemeMode.values) {
        await provider.setThemeMode(mode);
        expect(provider.themeMode, mode);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('theme_mode'), mode.name);
      }
    });

    test('a persisted themeMode is restored', () async {
      final provider = await loaded({'theme_mode': 'dark'});
      expect(provider.themeMode, ThemeMode.dark);
    });

    test('resetToDefaults restores Ocean Blue and light mode', () async {
      final provider = await loaded({});
      await provider.setPalette(AppPalette.royalPurple);
      await provider.setThemeMode(ThemeMode.dark);

      await provider.resetToDefaults();

      expect(provider.palette, same(AppPalette.oceanBlue));
      expect(provider.themeMode, ThemeMode.light);
      expect(AppColors.brand, AppPalette.oceanBlue.brand);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('palette_id'), isNull);
    });

    test('legacy setDarkMode still flips between light and dark', () async {
      final provider = await loaded({});
      await provider.setDarkMode(true);
      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.isDarkMode, isTrue);
      await provider.setDarkMode(false);
      expect(provider.themeMode, ThemeMode.light);
    });

    test('notifies listeners when the palette changes', () async {
      final provider = await loaded({});
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setPalette(AppPalette.rose);
      expect(notified, 1);

      // Selecting the already-active palette must not notify.
      await provider.setPalette(AppPalette.rose);
      expect(notified, 1);
    });
  });

  group('AppearanceScreen.modeLabel', () {
    test('names every mode', () {
      expect(AppearanceScreen.modeLabel(ThemeMode.system), 'System');
      expect(AppearanceScreen.modeLabel(ThemeMode.light), 'Light');
      expect(AppearanceScreen.modeLabel(ThemeMode.dark), 'Dark');
    });
  });
}
