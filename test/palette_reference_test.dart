import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/main.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/utils/app_typography.dart';
import 'package:spendsense/widgets/app_background.dart';

/// The four reference palettes must keep their exact anchor shades: the brand
/// ramp feeds every gradient, chip and chart tone, so a silent drift would
/// change the identity without any other test noticing.
double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _app(Widget child, {required bool dark}) => MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(body: child),
    );

const _black = Color(0xFF000000);
const _greenInk = Color(0xFF0B3B2C);

void main() {
  setUpAll(() => AppTypography.debugSkipFontLoading = true);
  setUp(() => AppColors.applyPalette(AppPalette.defaultPalette));
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  group('reference palettes', () {
    test('Azure is the default and ships the blue anchors', () {
      expect(AppPalette.defaultPalette.id, 'azure');
      final p = AppPalette.byId('azure');
      expect(p.label, 'Azure');
      expect(p.deep, const Color(0xFF021024));
      expect(p.brand, const Color(0xFF052659));
      expect(p.mid, const Color(0xFF5483B3));
      expect(p.bright, const Color(0xFF7DA0CA));
      expect(p.accent, const Color(0xFFC1E8FF));
      expect(p.borderLight, const Color(0xFFC1E8FF));
      expect(p.darkBackground, const Color(0xFF021024));
      expect(p.darkSurface, const Color(0xFF052659));
      expect(p.glass, isTrue);
    });

    test('Slate ships the navy-grey anchors', () {
      final p = AppPalette.byId('slate');
      expect(p.label, 'Slate');
      expect(p.deep, const Color(0xFF06141B));
      expect(p.brand, const Color(0xFF253745));
      expect(p.mid, const Color(0xFF4A5C6A));
      expect(p.bright, const Color(0xFF9BA8AB));
      expect(p.accent, const Color(0xFFCCD0CF));
      expect(p.borderLight, const Color(0xFFCCD0CF));
      expect(p.darkBackground, const Color(0xFF06141B));
      expect(p.darkSurface, const Color(0xFF11212D));
      expect(p.glass, isTrue);
    });

    test('Plum ships the purple anchors', () {
      final p = AppPalette.byId('plum');
      expect(p.label, 'Plum');
      expect(p.deep, const Color(0xFF190019));
      expect(p.brand, const Color(0xFF522B5B));
      expect(p.mid, const Color(0xFF854F6C));
      expect(p.bright, const Color(0xFFDFB6B2));
      expect(p.accent, const Color(0xFFFBE4D8));
      expect(p.borderLight, const Color(0xFFDFB6B2));
      expect(p.darkBackground, const Color(0xFF190019));
      expect(p.darkSurface, const Color(0xFF2B124C));
      expect(p.glass, isTrue);
    });

    test('Blush ships the pink and mint anchors', () {
      final p = AppPalette.byId('blush');
      expect(p.label, 'Blush');
      expect(p.deep, const Color(0xFF2F3B3A));
      expect(p.brand, const Color(0xFF5D6B6B));
      expect(p.mid, const Color(0xFFB0D7D8));
      expect(p.bright, const Color(0xFFD5E5E5));
      expect(p.accent, const Color(0xFFF7CBCA));
      expect(p.background, const Color(0xFFF1F7F7));
      expect(p.surfaceMuted, const Color(0xFFD5E5E5));
      expect(p.borderLight, const Color(0xFFDDD3D3));
      expect(p.darkBackground, const Color(0xFF101616));
      expect(p.glass, isTrue);
    });

    test('the four new palettes lead the picker with unique ids', () {
      expect(
        AppPalette.all.take(4).map((p) => p.id),
        ['azure', 'slate', 'plum', 'blush'],
      );
      expect(AppPalette.all, hasLength(12));
      expect(
        AppPalette.all.map((p) => p.id).toSet(),
        hasLength(AppPalette.all.length),
      );
    });
  });

  group('tinted dark canvases', () {
    for (final id in ['azure', 'slate', 'plum', 'blush']) {
      test('$id paints its own deep canvas instead of pure black', () {
        final p = AppPalette.byId(id);
        expect(p.isAmoled, isFalse, reason: id);
        expect(p.darkBackground, isNot(_black), reason: id);
        expect(
          p.darkBackground.computeLuminance(),
          lessThan(p.darkSurface.computeLuminance()),
          reason: '$id canvas must sit below its cards',
        );
      });
    }

    testWidgets('a tinted palette keeps its canvas and ambient glow',
        (tester) async {
      AppColors.applyPalette(AppPalette.byId('plum'));
      await tester.pumpWidget(_app(
        const AppBackground(child: SizedBox.expand()),
        dark: true,
      ));
      await tester.pumpAndSettle();

      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AppBackground),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((box.decoration as BoxDecoration).color,
          AppPalette.byId('plum').darkBackground);
      final radial = find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).gradient is RadialGradient);
      expect(radial, findsWidgets,
          reason: 'tinted themes keep the soft glow black themes skip');
    });
  });

  group('palette-pure tokens', () {
    testWidgets('lime ink is the palette deep colour, not a fixed green',
        (tester) async {
      AppColors.applyPalette(AppPalette.byId('azure'));
      late Color ink;
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          ink = AppColors.onLime(context);
          return const SizedBox();
        }),
        dark: false,
      ));
      expect(ink, AppPalette.byId('azure').deep);
      expect(ink, isNot(_greenInk));
    });

    test('the light snackbar is palette-tinted, not always deep green', () {
      for (final id in ['azure', 'slate', 'plum', 'blush']) {
        final p = AppPalette.byId(id);
        AppColors.applyPalette(p);
        final theme = const SpendSenseApp()
            .themeFor(Brightness.light, FontPreset.standard);
        expect(theme.snackBarTheme.backgroundColor, p.deep, reason: id);
        expect(theme.snackBarTheme.backgroundColor, isNot(_greenInk),
            reason: id);
      }
    });

    testWidgets(
        'light text tiers stay neutral and readable on every new palette',
        (tester) async {
      for (final id in ['azure', 'slate', 'plum', 'blush']) {
        final p = AppPalette.byId(id);
        AppColors.applyPalette(p);
        late Color primary, secondary, tertiary;
        await tester.pumpWidget(_app(
          Builder(builder: (context) {
            primary = AppColors.textPrimary(context);
            secondary = AppColors.textSecondary(context);
            tertiary = AppColors.textTertiary(context);
            return const SizedBox();
          }),
          dark: false,
        ));
        final tiers = {
          'primary': primary,
          'secondary': secondary,
          'tertiary': tertiary,
        };
        tiers.forEach((name, color) {
          final r = (color.r * 255).round();
          final g = (color.g * 255).round();
          final b = (color.b * 255).round();
          expect((r - g).abs() <= 12 && (g - b).abs() <= 12, isTrue,
              reason: '$id $name $color must be neutral, not green-tinted');
          expect(_contrast(color, p.background), greaterThanOrEqualTo(4.5),
              reason: '$id $name $color on ${p.background}');
        });
      }
    });
  });

  group('soft palettes keep charts visible', () {
    for (final id in ['azure', 'slate', 'plum', 'blush']) {
      test('$id chart tones clear 3:1 on a white card', () {
        final p = AppPalette.byId(id);
        for (final color in p.chartPalette) {
          if (color == AppPalette.expenseRed ||
              color == AppPalette.incomeGreen) {
            continue;
          }
          expect(_contrast(color, Colors.white), greaterThanOrEqualTo(3.0),
              reason: '$id chart tone $color is too pale on white');
        }
      });
    }
  });
}
