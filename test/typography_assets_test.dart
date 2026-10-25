import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_text_styles.dart';
import 'package:spendsense/utils/app_typography.dart';

TextStyle _style(BuildContext context, TextStyle Function(BuildContext) f) =>
    f(context);

void main() {
  tearDown(() => AppTypography.active = FontPreset.standard);

  group('bundled family resolution', () {
    test('the dot-matrix preset splits display and body faces', () {
      final display = AppTypography.resolve(
        preset: FontPreset.dotMatrix,
        fontSize: 28,
        fontWeight: FontWeight.w800,
      );
      final body = AppTypography.resolve(
        preset: FontPreset.dotMatrix,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      );
      expect(display.fontFamily, 'DotGothic16');
      expect(body.fontFamily, 'Space Grotesk');
    });

    test('variable families get a real weight axis', () {
      final style = AppTypography.resolve(
        preset: FontPreset.cleanSans,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );
      expect(style.fontFamily, 'Inter');
      expect(style.fontVariations, isNotNull);
      expect(style.fontVariations!.single.axis, 'wght');
      expect(style.fontVariations!.single.value, 600);
    });

    test('a static family carries no weight axis', () {
      final style = AppTypography.resolve(
        preset: FontPreset.standard,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );
      expect(style.fontFamily, 'Poppins');
      expect(style.fontVariations, isNull);
    });

    test('the text theme inherits the preset family', () {
      final theme = AppTypography.textTheme(
        ThemeData.light().textTheme,
        preset: FontPreset.cleanSans,
      );
      expect(theme.bodyMedium?.fontFamily, 'Inter');
      expect(theme.displayLarge?.fontFamily, 'Inter');
    });
  });

  group('money never uses the decorative display face', () {
    for (final size in [12.0, 16.0, 24.0, 40.0]) {
      testWidgets('amount at $size stays in the body face', (tester) async {
        AppTypography.active = FontPreset.dotMatrix;
        late TextStyle style;
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (context) {
            style = _style(context, (c) => AppText.amount(c, size: size));
            return const SizedBox();
          }),
        ));
        expect(style.fontFamily, 'Space Grotesk',
            reason: 'the rupee sign and lining figures must exist');
        expect(style.fontFamily, isNot('DotGothic16'));
        expect(style.fontFeatures, isNotEmpty);
      });
    }

    testWidgets('hero and display figures stay in the body face',
        (tester) async {
      AppTypography.active = FontPreset.dotMatrix;
      late TextStyle hero;
      late TextStyle display;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          hero = AppText.hero(context);
          display = AppText.display(context);
          return const SizedBox();
        }),
      ));
      expect(hero.fontFamily, 'Space Grotesk');
      expect(display.fontFamily, 'Space Grotesk');
    });

    testWidgets('headings still use the display face', (tester) async {
      AppTypography.active = FontPreset.dotMatrix;
      late TextStyle h1;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          h1 = AppText.h1(context);
          return const SizedBox();
        }),
      ));
      expect(h1.fontFamily, 'DotGothic16');
    });
  });

  group('long strings and large text', () {
    testWidgets('a long body string wraps without overflow at 1.4x',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.4),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(builder: (context) {
                return Text(
                  'A very long transaction description from a merchant with an '
                  'unusually verbose registered legal name and reference number',
                  style: AppText.body(context),
                );
              }),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large amount scales down instead of clipping', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 800)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Builder(builder: (context) {
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('₹9,87,65,432.10',
                      style: AppText.amount(context, size: 40)),
                );
              }),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
