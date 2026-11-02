import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/utils/category_style.dart';
import 'package:spendsense/widgets/icon_well.dart';

/// Contrast contract for the semantic tokens, measured on the colours that are
/// really on screen (composited), for every palette in both brightnesses.
double _contrast(Color a, Color b) => AppColors.contrastRatio(a, b);

/// Opaque result of painting [fg] (which may be translucent) over [bg].
Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  for (final palette in AppPalette.all) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      test('${palette.label} · $mode: text, icons and nav keep their contrast',
          () {
        AppColors.applyPalette(palette);
        final t = AppTokens.forBrightness(dark);
        final canvas = dark ? AppColors.darkBackground : AppColors.background;
        final glass = AppColors.glassBase(dark);
        final surface = _over(t.surface, canvas);
        final failures = <String>[];

        void expectAtLeast(String name, Color fg, Color bg, double min) {
          final ratio = _contrast(_over(fg, bg), bg);
          if (ratio < min) {
            failures.add('$name ${ratio.toStringAsFixed(2)} < $min');
          }
        }

        // Text: 4.5:1 on the plain surface and on the composited glass card.
        for (final bg in {'surface': surface, 'glass': glass}.entries) {
          expectAtLeast('textPrimary/${bg.key}', t.textPrimary, bg.value, 4.5);
          expectAtLeast(
              'textSecondary/${bg.key}', t.textSecondary, bg.value, 4.5);
          // Icons: 3:1 non-text minimum.
          expectAtLeast('iconPrimary/${bg.key}', t.iconPrimary, bg.value, 3);
          expectAtLeast('iconSecondary/${bg.key}', t.iconSecondary, bg.value, 3);
        }

        // Navigation: the bar fill sits over the canvas, the selected container
        // over the bar fill.
        final bar = AppColors.navBackdropFor(dark);
        final selectedBackdrop = AppColors.navSelectedBackdropFor(dark);
        expectAtLeast(
            'nav unselected', AppColors.navIdleInkFor(dark), bar, 3);
        expectAtLeast(
            'nav selected', AppColors.navSelectedInkFor(dark), selectedBackdrop, 3);
        // The selected state must also be distinguishable from the bar itself.
        final lift = _contrast(selectedBackdrop, bar);
        if (lift < 1.08) {
          failures.add('nav selected container barely visible '
              '${lift.toStringAsFixed(2)}');
        }
        // Accent roles on their containers.
        expectAtLeast('onAccentContainer', t.onAccentContainer,
            _over(t.accentContainer, glass), 4.5);

        expect(failures, isEmpty, reason: '${palette.label} $mode');
      });
    }
  }

  group('lane B roles hold in every palette and brightness', () {
    for (final palette in AppPalette.all) {
      for (final dark in [false, true]) {
        final mode = dark ? 'dark' : 'light';

        test('${palette.label} · $mode: switch, add button, panels', () {
          AppColors.applyPalette(palette);
          final failures = <String>[];
          void atLeast(String name, double actual, double min) {
            if (actual < min) {
              failures.add('$name ${actual.toStringAsFixed(2)} < $min');
            }
          }

          // Switch: the "on" thumb must stand out from its own track and from
          // the card, and the track must separate from the card. Deep Navy's
          // raw brand used to fail all three.
          final card = dark ? AppColors.darkSurface : AppColors.surface;
          final track = AppColors.switchTrackOnBackdropFor(dark);
          final thumb = AppColors.switchThumbOnFor(dark);
          atLeast('switch thumb/track', _contrast(thumb, track), 3);
          atLeast('switch thumb/card', _contrast(thumb, card), 3);
          atLeast('switch track/card', _contrast(track, card), 1.2);

          // Add button: glyph on its own translucent fill.
          atLeast(
            'fab glyph',
            _contrast(
                AppColors.fabInkFor(dark), AppColors.fabBackdropFor(dark)),
            4.5,
          );

          // Resolved inks always reach AA on their fill.
          atLeast('onBrand', _contrast(AppColors.onBrand, palette.brand), 4.5);
          atLeast('onDanger', _contrast(AppColors.onDanger, AppColors.danger),
              4.5);

          // Icon wells: a plate is visible against the card and its glyph
          // holds AA, for every role Settings paints with.
          for (final role in {
            'brand': AppColors.brand,
            'azure': AppColors.azure,
            'brandBright': AppColors.brandBright,
          }.entries) {
            final base = AppColors.glassBase(dark);
            final tint = IconWell.plateTint(role.value, dark);
            final plate = Color.alphaBlend(IconWell.fill(tint, dark), base);
            atLeast('well plate/${role.key}', _contrast(plate, base),
                IconWell.minPlateContrast(dark));
            atLeast(
              'well glyph/${role.key}',
              _contrast(
                AppColors.inkOn(tint, IconWell.fill(tint, dark), base),
                plate,
              ),
              4.5,
            );
          }

          expect(failures, isEmpty, reason: '${palette.label} $mode');
        });
      }
    }

    for (final palette in AppPalette.all) {
      testWidgets('${palette.label}: accent hero gradient holds white text',
          (tester) async {
        AppColors.applyPalette(palette);
        for (final dark in [false, true]) {
          late LinearGradient g;
          late LinearGradient success;
          late Color onHero;
          late LinearGradient hero;
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Builder(builder: (context) {
              g = AppColors.accentHeroGradient(context);
              success = AppColors.successHeroGradient(context);
              hero = AppColors.heroSurfaceGradient(context);
              onHero = AppColors.onHero(context);
              return const SizedBox();
            }),
          ));
          for (final stop in [...g.colors, ...success.colors]) {
            expect(_contrast(Colors.white, stop), greaterThanOrEqualTo(4.5),
                reason: '${palette.label} dark=$dark stop $stop');
          }
          // The hero ink is measured, so it holds on every hero stop even if
          // a palette ships a pale deep stop.
          for (final stop in hero.colors) {
            expect(_contrast(onHero, stop), greaterThanOrEqualTo(4.5),
                reason: '${palette.label} dark=$dark hero ink on $stop');
            // Hero text is drawn with AppText.onGradient, which is always
            // white, so white itself has to hold, not just the resolved ink.
            expect(_contrast(Colors.white, stop), greaterThanOrEqualTo(4.5),
                reason: '${palette.label} dark=$dark white text on hero $stop');
          }
        }
      });
    }
  });

  group('washes, bubbles and chips (audit follow-up)', () {
    // Every colour that is ever drawn as a tinted wash with a same-hue glyph or
    // label on it: category hues, status hues and the three money colours.
    final tones = <String, Color>{
      for (final c in const [
        'Food', 'Shopping', 'Fuel', 'Travel', 'Bills', 'Transfer', 'Cash',
        'Entertainment', 'Health', 'Investment', 'UPI', 'Other', 'Income',
      ])
        'category/$c': CategoryStyle.color(c),
      'warning': AppColors.warning,
      'expense': AppColors.expenseRed,
      'income': AppColors.incomeGreen,
      'danger': AppColors.danger,
    };

    for (final palette in AppPalette.all) {
      for (final dark in [false, true]) {
        test('${palette.label} · ${dark ? 'dark' : 'light'}: wash ink', () {
          AppColors.applyPalette(palette);
          final base = AppColors.glassBase(dark);
          final failures = <String>[];
          for (final e in tones.entries) {
            for (final alpha in const [null, 0.18, 0.20, 0.32]) {
              final a = alpha ?? AppColors.washAlphaFor(dark);
              final plate = Color.alphaBlend(e.value.withValues(alpha: a), base);
              final ink = AppColors.inkOnWashFor(dark, e.value, alpha: alpha);
              final ratio = _contrast(ink, plate);
              if (ratio < 4.5) {
                failures.add('${e.key}@$a ${ratio.toStringAsFixed(2)}');
              }
            }
          }
          expect(failures, isEmpty);
        });
      }
    }

    testWidgets('hero chip fill keeps hero ink at AA on every stop',
        (tester) async {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        for (final dark in [false, true]) {
          late LinearGradient hero;
          late LinearGradient accent;
          late LinearGradient success;
          late Color chip;
          late Color accentChip;
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Builder(builder: (context) {
              hero = AppColors.heroSurfaceGradient(context);
              accent = AppColors.accentHeroGradient(context);
              success = AppColors.successHeroGradient(context);
              chip = AppColors.heroChipFill(context);
              accentChip = AppColors.heroChipFill(context, gradient: accent);
              return const SizedBox();
            }),
          ));
          for (final (g, fill) in [(hero, chip), (accent, accentChip)]) {
            final ink = AppColors.inkOnGradient(g);
            for (final stop in g.colors) {
              expect(
                _contrast(ink, Color.alphaBlend(fill, stop)),
                greaterThanOrEqualTo(4.5),
                reason: '${palette.label} dark=$dark chip on $stop',
              );
            }
          }
          // The success card shares the accent construction, so its stops must
          // hold the same ink.
          final ink = AppColors.inkOnGradient(success);
          for (final stop in success.colors) {
            expect(_contrast(ink, stop), greaterThanOrEqualTo(4.5),
                reason: '${palette.label} dark=$dark success $stop');
          }
        }
      }
    });

    test('value bubble pairing holds in every palette', () {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        for (final dark in [false, true]) {
          // Mirrors _ValueBubble: white bubble in dark, deep stop in light.
          final bubble = dark ? Colors.white : AppColors.navyDeep;
          final ink = AppColors.resolveInk(
              dark ? AppColors.navyDeep : Colors.white, bubble);
          expect(_contrast(ink, bubble), greaterThanOrEqualTo(4.5),
              reason: '${palette.label} dark=$dark value bubble');
        }
        // The selected-weekday pill: lime fill with its resolved ink.
        expect(_contrast(AppColors.onLimeInk, AppColors.lime),
            greaterThanOrEqualTo(4.5),
            reason: '${palette.label} weekday pill');
      }
    });
  });

  test('nav fill stays see-through in every palette', () {
    for (final palette in AppPalette.all) {
      AppColors.applyPalette(palette);
      for (final dark in [false, true]) {
        final fill = AppColors.navFillFor(dark);
        expect(fill.a, inInclusiveRange(0.45, 0.60),
            reason: '${palette.label} dark=$dark');
      }
    }
  });

  test('switching palettes leaves no stale token', () {
    Map<String, Color> snapshot(bool dark) => {
          ...AppTokens.forBrightness(dark).toMap(),
          'navFill': AppColors.navFillFor(dark),
          'navSelectedFill': AppColors.navSelectedFillFor(dark),
          'navSelectedInk': AppColors.navSelectedInkFor(dark),
          'navIdleInk': AppColors.navIdleInkFor(dark),
          'glassFill': AppColors.glassFillFor(dark),
          'glassBorder': AppColors.glassBorderFor(dark),
        };

    for (final a in AppPalette.all) {
      for (final b in AppPalette.all) {
        for (final dark in [false, true]) {
          AppColors.applyPalette(b);
          final fresh = snapshot(dark);
          AppColors.applyPalette(a);
          AppColors.applyPalette(b);
          final switched = snapshot(dark);
          expect(switched, fresh,
              reason: '${a.id} -> ${b.id} dark=$dark left a stale token');
        }
      }
    }
  });

  test('palettes are actually distinct where it matters', () {
    AppColors.applyPalette(AppPalette.midnight);
    final midnight = AppTokens.forBrightness(true).accentPrimary;
    AppColors.applyPalette(AppPalette.emerald);
    final emerald = AppTokens.forBrightness(true).accentPrimary;
    AppColors.applyPalette(AppPalette.deepNavy);
    final navy = AppTokens.forBrightness(true).accentPrimary;
    expect(midnight, isNot(emerald));
    expect(midnight, isNot(navy));
    // Deep Navy's accent must carry a blue hue, not the old neutral grey.
    final hsl = HSLColor.fromColor(navy);
    expect(hsl.hue, inInclusiveRange(185, 225));
    expect(hsl.saturation, greaterThan(0.25));
  });
}
