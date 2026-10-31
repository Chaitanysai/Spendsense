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
  setUp(() => AppColors.applyPalette(AppPalette.emerald));
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  Future<ThemeProvider> loaded(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final provider = ThemeProvider();
    // Let the async _load() future settle.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return provider;
  }

  group('AppPalette', () {
    test('ships the 2026 premium set first and keeps the legacy palettes', () {
      expect(AppPalette.all, hasLength(13));
      expect(AppPalette.all.first, same(AppPalette.premiumBlue));
      expect(
        AppPalette.all.map((p) => p.label),
        containsAll([
          'Premium Blue',
        'Paper',
          'Deep Navy',
          'Soft Pastel Teal',
          'Plum & Blush',
          'Midnight',
          'Emerald',
          'Ocean Blue',
          'Warm Amber',
          'Forest Green',
          'Royal Purple',
          'Rose',
          'Teal',
        ]),
      );
    });

    test('every palette id is unique', () {
      final ids = AppPalette.all.map((p) => p.id).toSet();
      expect(ids, hasLength(AppPalette.all.length));
    });

    test('byId resolves known ids and falls back to Premium Blue', () {
      expect(AppPalette.byId('forest_green'), same(AppPalette.forestGreen));
      expect(AppPalette.byId('emerald'), same(AppPalette.emerald));
      expect(AppPalette.byId('premium_blue'), same(AppPalette.premiumBlue));
      expect(
        AppPalette.byId('does_not_exist'),
        same(AppPalette.premiumBlue),
      );
      expect(AppPalette.byId(null), same(AppPalette.premiumBlue));
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

    test('Emerald carries the green fintech brand ramp and lime accent', () {
      expect(AppPalette.emerald.brand, const Color(0xFF12A150));
      expect(AppPalette.emerald.deep, const Color(0xFF0B3B2C));
      expect(AppPalette.emerald.limeAccent, const Color(0xFFC6F432));
      expect(AppPalette.emerald.background, const Color(0xFFF7F9F8));
    });

    test('legacy palettes keep the true-black AMOLED canvas', () {
      expect(AppPalette.emerald.darkBackground, const Color(0xFF000000));
      expect(AppPalette.emerald.isAmoled, isTrue);

      for (final p in AppPalette.all.where((p) => p.isAmoled)) {
        expect(p.darkBackground, const Color(0xFF000000), reason: p.label);
      }

      // Only Midnight layers navy glass cards on that black canvas.
      expect(AppPalette.midnight.glass, isTrue);
      for (final p in AppPalette.all.where(
        (p) => p.isAmoled && p != AppPalette.midnight,
      )) {
        expect(p.glass, isFalse, reason: p.label);
      }
    });

    test('2026 premium palettes tint the dark canvas on purpose', () {
      final premium = [
        AppPalette.premiumBlue,
        AppPalette.deepNavy,
        AppPalette.softPastelTeal,
        AppPalette.plumBlush,
      ];
      for (final p in premium) {
        expect(p.isAmoled, isFalse, reason: p.label);
        expect(p.glass, isTrue, reason: p.label);
        expect(p.darkBackground, isNot(const Color(0xFF000000)),
            reason: p.label);
      }
      // Premium Blue is the default identity and the reset target.
      expect(AppPalette.defaultPalette, AppPalette.premiumBlue);
    });

    test('2026 palettes carry the supplied premium colours', () {
      expect(AppPalette.premiumBlue.brand, const Color(0xFF5483B3));
      expect(AppPalette.premiumBlue.deep, const Color(0xFF021024));
      expect(AppPalette.premiumBlue.background, const Color(0xFFF2F8FF));

      expect(AppPalette.deepNavy.brand, const Color(0xFF253745));
      expect(AppPalette.deepNavy.darkBackground, const Color(0xFF06141B));

      expect(AppPalette.softPastelTeal.brand, const Color(0xFF5D6B6B));
      expect(AppPalette.softPastelTeal.limeAccent, const Color(0xFFF7CBCA));
      expect(
        AppPalette.softPastelTeal.background,
        const Color(0xFFF1F7F7),
      );

      expect(AppPalette.plumBlush.brand, const Color(0xFF854F6C));
      expect(AppPalette.plumBlush.limeAccent, const Color(0xFFDFB6B2));
      expect(AppPalette.plumBlush.darkBackground, const Color(0xFF190019));
    });

    test('a palette without an explicit lime falls back to its accent', () {
      expect(AppPalette.oceanBlue.lime, isNull);
      expect(AppPalette.oceanBlue.limeAccent, AppPalette.oceanBlue.accent);
    });

    test('Ocean Blue still reproduces the shipped navy tokens exactly', () {
      expect(AppPalette.oceanBlue.brand, const Color(0xFF1B44C8));
      expect(AppPalette.oceanBlue.deep, const Color(0xFF071638));
      expect(AppPalette.oceanBlue.bright, const Color(0xFF2F6BFF));
      expect(AppPalette.oceanBlue.background, const Color(0xFFF3F6FD));
      expect(AppPalette.oceanBlue.darkBackground, const Color(0xFF000000));
    });

    test('the balance gradient runs its legible top stop into the deep stop',
        () {
      final colors = AppPalette.emerald.balanceGradient.colors;
      expect(colors, hasLength(2));
      expect(colors[0], AppPalette.emerald.balanceTop);
      expect(colors[1], AppPalette.emerald.deep);
    });

    test('a palettes bright mid stop is darkened for the balance card', () {
      // Ocean Blue's raw mid is ~2.8:1 against white, so the derived top stop
      // must be darker than it while still being a real blend of mid and deep.
      expect(_contrast(AppPalette.oceanBlue.mid, Colors.white), lessThan(4.5));
      expect(AppPalette.oceanBlue.balanceTop, isNot(AppPalette.oceanBlue.mid));
      expect(_contrast(AppPalette.oceanBlue.balanceTop, Colors.white),
          greaterThanOrEqualTo(4.5));

      // Emerald's mid already clears the threshold, so it is used unchanged.
      expect(AppPalette.emerald.balanceTop, AppPalette.emerald.mid);
    });

    test('every balance-gradient stop keeps white text at AA', () {
      // The balance card renders 11px supporting labels in white on this
      // gradient, so every stop — not just the average — has to clear 4.5:1.
      for (final palette in AppPalette.all) {
        for (final stop in palette.balanceGradient.colors) {
          final contrast = _contrast(stop, Colors.white);
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason: '${palette.label} stop $stop is only '
                '${contrast.toStringAsFixed(2)}:1 against white',
          );
        }
      }
    });

    test('the income gradient keeps white text on a debit-free surface', () {
      for (final stop in AppPalette.incomeGradient.colors) {
        expect(_contrast(stop, Colors.white), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('AppColors.applyPalette', () {
    test('rewrites the brand ramp and surfaces', () {
      AppColors.applyPalette(AppPalette.rose);
      expect(AppColors.brand, AppPalette.rose.brand);
      expect(AppColors.brandBright, AppPalette.rose.bright);
      expect(AppColors.navyDeep, AppPalette.rose.deep);
      expect(AppColors.background, AppPalette.rose.background);
      // The rose canvas comes from the palette; the dark card is the same
      // surface tinted toward rose rather than the neutral shipped token.
      expect(AppColors.darkBackground, AppPalette.rose.darkBackground);
      expect(AppColors.darkSurface, isNot(AppPalette.rose.darkSurface));
      expect(
        HSLColor.fromColor(AppColors.darkSurface).hue,
        closeTo(HSLColor.fromColor(AppPalette.rose.brand).hue, 60),
      );
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

    test('mirrors the lime accent and the AMOLED flag', () {
      AppColors.applyPalette(AppPalette.emerald);
      expect(AppColors.lime, AppPalette.emerald.limeAccent);
      expect(AppColors.isAmoledCanvas, isTrue);

      AppColors.applyPalette(AppPalette.oceanBlue);
      expect(AppColors.lime, AppPalette.oceanBlue.accent);
      expect(AppColors.isAmoledCanvas, isTrue);
    });
  });

  group('AMOLED dark foundation', () {
    test('legacy AMOLED palettes share neutral black surfaces and borders', () {
      for (final p in AppPalette.all.where(
        (p) => p.isAmoled && p != AppPalette.midnight,
      )) {
        expect(p.darkBackground, const Color(0xFF000000), reason: p.label);
        for (final c in [p.darkSurface, p.darkSurfaceAlt, p.borderDark]) {
          final r = (c.r * 255).round();
          final g = (c.g * 255).round();
          final b = (c.b * 255).round();
          expect(r == g && g == b, isTrue,
              reason: '${p.label} surface $c must be neutral grey, not tinted');
        }
        // Cards stay in the near-black band, never a coloured panel.
        expect(p.darkSurface.computeLuminance(), lessThan(0.02));
        expect(p.darkSurfaceAlt.computeLuminance(), lessThan(0.03));
      }
    });

    test('selected palette still controls accents in dark mode', () {
      AppColors.applyPalette(AppPalette.rose);
      expect(AppColors.darkBackground, const Color(0xFF000000));
      expect(AppColors.brand, AppPalette.rose.brand);
      final roseInk = AppColors.brandInkFor(true);
      expect(
        _contrast(roseInk, AppColors.darkSurfaceAlt),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        HSLColor.fromColor(roseInk).hue,
        closeTo(HSLColor.fromColor(AppPalette.rose.bright).hue, 12),
      );

      AppColors.applyPalette(AppPalette.royalPurple);
      expect(AppColors.darkBackground, const Color(0xFF000000));
      expect(AppColors.brand, AppPalette.royalPurple.brand);
      // Royal Purple's bright stop was 4.42:1 on dialogs, so its ink is the
      // same purple lightened slightly; it is still the palette's own accent.
      final ink = AppColors.brandInkFor(true);
      expect(ink, isNot(AppPalette.royalPurple.bright));
      expect(
        HSLColor.fromColor(ink).hue,
        closeTo(HSLColor.fromColor(AppPalette.royalPurple.bright).hue, 12),
      );
    });

    testWidgets('dark text tiers are neutral and readable on black',
        (tester) async {
      late Color primary, secondary, tertiary, fill, border;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Builder(builder: (c) {
          primary = AppColors.textPrimary(c);
          secondary = AppColors.textSecondary(c);
          tertiary = AppColors.textTertiary(c);
          fill = AppColors.glassFill(c);
          border = AppColors.glassBorder(c);
          return const SizedBox();
        }),
      ));
      const black = Color(0xFF000000);
      expect(_contrast(primary, black), greaterThanOrEqualTo(15));
      expect(_contrast(secondary, black), greaterThanOrEqualTo(7));
      expect(_contrast(tertiary, black), greaterThanOrEqualTo(4.5));
      for (final c in [primary, secondary, tertiary]) {
        expect((c.r - c.g).abs() < 0.01 && (c.g - c.b).abs() < 0.01, isTrue,
            reason: '$c must be neutral');
      }
      // The card is a dark surface with the palette tint, not a white wash.
      expect(fill.computeLuminance(), lessThan(0.12));
      expect(HSLColor.fromColor(border).saturation, greaterThan(0.08));
    });

    test('dark cards carry the active palette tint, never flat black', () {
      for (final p in AppPalette.all) {
        AppColors.applyPalette(p);
        final surface = HSLColor.fromColor(AppColors.darkSurface);
        final raised = HSLColor.fromColor(AppColors.darkSurfaceAlt);
        expect(surface.saturation, greaterThan(0.08), reason: p.label);
        expect(raised.saturation, greaterThan(0.10), reason: p.label);
        expect(AppColors.darkSurface.computeLuminance(), lessThan(0.20));
        expect(AppColors.darkSurfaceAlt.computeLuminance(), lessThan(0.25));
        expect(
          HSLColor.fromColor(AppColors.borderDark).saturation,
          greaterThan(0.10),
          reason: p.label,
        );
      }
    });
  });

  group('AppColors contrast helpers', () {
    test('brand ink deepens in light mode and brightens in dark mode', () {
      AppColors.applyPalette(AppPalette.emerald);

      final lightInk = AppColors.brandInkFor(false);
      final darkInk = AppColors.brandInkFor(true);

      // The raw brand green is too weak as small text on white, so light ink is
      // pulled toward the deep stop — measurably darker than the brand itself.
      expect(lightInk.computeLuminance(),
          lessThan(AppColors.brand.computeLuminance()));
      // Dark ink steps up to the bright stop — measurably lighter than brand.
      expect(darkInk.computeLuminance(),
          greaterThan(AppColors.brand.computeLuminance()));
    });

    test('light-mode brand ink clears the AA threshold on white', () {
      AppColors.applyPalette(AppPalette.emerald);
      final contrast = _contrastWithWhite(AppColors.brandInkFor(false));
      expect(contrast, greaterThanOrEqualTo(4.5));
    });

    test('dark-mode brand ink clears the AA threshold on black', () {
      AppColors.applyPalette(AppPalette.emerald);
      final contrast = _contrastWithBlack(AppColors.brandInkFor(true));
      expect(contrast, greaterThanOrEqualTo(4.5));
    });

    test('lime ink stays legible on every palette highlight', () {
      for (final p in AppPalette.all) {
        AppColors.applyPalette(p);
        final contrast = _contrast(
          AppColors.onLimeInk,
          p.limeAccent,
        );
        expect(contrast, greaterThanOrEqualTo(4.5), reason: p.label);
      }
    });

    // Paper's highlight is a saturated ultramarine, not a pastel: the default
    // "deep stop, else black" rule gave 2.7:1 there. This pins the explicit
    // white override so the bug cannot come back silently.
    test('Paper uses white ink on its saturated highlight', () {
      AppColors.applyPalette(AppPalette.paper);
      expect(AppColors.onLimeInk, Colors.white);
      expect(
        _contrast(AppColors.onLimeInk, AppPalette.paper.limeAccent),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('neutral text tiers keep AA on every light surface', () {
      for (final p in AppPalette.all) {
        AppColors.applyPalette(p);
        for (final surface in [p.background, p.surfaceMuted]) {
          expect(
            _contrast(AppColors.textPrimaryFor(false), surface),
            greaterThanOrEqualTo(7),
            reason: '${p.label} primary',
          );
          expect(
            _contrast(AppColors.textSecondaryFor(false), surface),
            greaterThanOrEqualTo(4.5),
            reason: '${p.label} secondary',
          );
          expect(
            _contrast(AppColors.textTertiaryFor(false), surface),
            greaterThanOrEqualTo(4.5),
            reason: '${p.label} tertiary',
          );
        }
      }
    });

    test('neutral text tiers keep AA on every dark surface', () {
      for (final p in AppPalette.all) {
        AppColors.applyPalette(p);
        expect(
          _contrast(AppColors.textPrimaryFor(true), p.darkSurfaceAlt),
          greaterThanOrEqualTo(7),
          reason: p.label,
        );
        expect(
          _contrast(AppColors.textSecondaryFor(true), p.darkSurfaceAlt),
          greaterThanOrEqualTo(7),
          reason: p.label,
        );
        expect(
          _contrast(AppColors.textTertiaryFor(true), p.darkSurfaceAlt),
          greaterThanOrEqualTo(4.5),
          reason: p.label,
        );
      }
    });
  });

  group('ThemeProvider', () {
    test('defaults to Premium Blue in light mode', () async {
      final provider = await loaded({});
      expect(provider.palette, same(AppPalette.premiumBlue));
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

    test('an unknown persisted id falls back to Premium Blue', () async {
      final provider = await loaded({'palette_id': 'chartreuse'});
      expect(provider.palette, same(AppPalette.premiumBlue));
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

    test('resetToDefaults restores Premium Blue and light mode', () async {
      final provider = await loaded({});
      await provider.setPalette(AppPalette.royalPurple);
      await provider.setThemeMode(ThemeMode.dark);

      await provider.resetToDefaults();

      expect(provider.palette, same(AppPalette.premiumBlue));
      expect(provider.themeMode, ThemeMode.light);
      expect(AppColors.brand, AppPalette.premiumBlue.brand);

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

/// WCAG relative-luminance contrast ratio between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

double _contrastWithWhite(Color c) => _contrast(c, Colors.white);

double _contrastWithBlack(Color c) => _contrast(c, Colors.black);
