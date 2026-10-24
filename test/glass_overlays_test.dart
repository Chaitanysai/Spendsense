import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/main.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_typography.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/app_background.dart';
import 'package:spendsense/widgets/app_sheet.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';
import 'package:spendsense/widgets/glass_card.dart';
import 'package:spendsense/widgets/gradient_hero_card.dart';
import 'package:spendsense/widgets/transaction_type_toggle.dart';

Widget _app(Widget child, {bool dark = false, bool reduceMotion = false}) {
  return MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          padding: const EdgeInsets.only(bottom: 24),
          viewPadding: const EdgeInsets.only(bottom: 24),
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
}

int _blurCount(WidgetTester tester) =>
    tester.widgetList(find.byType(BackdropFilter)).length;

void main() {
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  group('glass hierarchy', () {
    testWidgets('near-opaque cards skip the blur layer', (tester) async {
      AppColors.applyPalette(AppPalette.emerald);
      for (final dark in [false, true]) {
        await tester.pumpWidget(_app(
          const GlassCard(child: Text('card')),
          dark: dark,
        ));
        expect(_blurCount(tester), 0, reason: 'dark=$dark');
      }
    });

    testWidgets('translucent navy glass cards keep a single blur',
        (tester) async {
      AppColors.applyPalette(AppPalette.midnight);
      await tester.pumpWidget(_app(
        const GlassCard(child: Text('card')),
        dark: true,
      ));
      expect(_blurCount(tester), 1);
      final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(filter.filter, isA<ImageFilter>());
    });

    testWidgets('hero cards get a hairline on navy glass and none in light',
        (tester) async {
      AppColors.applyPalette(AppPalette.midnight);
      Border? heroBorder() => (tester
              .widget<Container>(find
                  .descendant(
                      of: find.byType(GradientHeroCard),
                      matching: find.byType(Container))
                  .first)
              .decoration as BoxDecoration)
          .border as Border?;

      await tester.pumpWidget(
          _app(const GradientHeroCard(child: Text('hero')), dark: true));
      expect(heroBorder(), isNotNull);

      await tester
          .pumpWidget(_app(const GradientHeroCard(child: Text('hero'))));
      await tester.pumpAndSettle(); // let the theme cross-fade finish
      expect(heroBorder(), isNull);
    });

    testWidgets('navy hero stops keep white figures legible', (tester) async {
      AppColors.applyPalette(AppPalette.midnight);
      late LinearGradient g;
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          g = AppColors.heroSurfaceGradient(context);
          return const SizedBox();
        }),
        dark: true,
      ));
      for (final c in g.colors) {
        final contrast = 1.05 / (c.computeLuminance() + 0.05);
        expect(contrast, greaterThan(7), reason: '$c');
      }
    });
  });

  group('pitch-black canvas', () {
    const black = Color(0xFF000000);

    BoxDecoration backgroundDecoration(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AppBackground),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return box.decoration as BoxDecoration;
    }

    testWidgets('dark AppBackground is #000000 with no glow for every palette',
        (tester) async {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        await tester.pumpWidget(
          _app(const AppBackground(child: SizedBox.expand()), dark: true),
        );
        await tester.pumpAndSettle();
        final decoration = backgroundDecoration(tester);
        expect(decoration.color, black, reason: palette.label);
        expect(decoration.gradient, isNull, reason: palette.label);
        // No radial glow lights up the canvas.
        final radial = find.byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).gradient is RadialGradient);
        expect(radial, findsNothing, reason: palette.label);
      }
    });

    testWidgets('light mode keeps its own canvas and glow', (tester) async {
      AppColors.applyPalette(AppPalette.midnight);
      await tester.pumpWidget(
        _app(const AppBackground(child: SizedBox.expand())),
      );
      await tester.pumpAndSettle();
      expect(backgroundDecoration(tester).color, isNot(black));
    });

    testWidgets('Midnight keeps navy glass on the black canvas',
        (tester) async {
      AppColors.applyPalette(AppPalette.midnight);
      late Color fill;
      late Color border;
      late LinearGradient hero;
      late Color canvas;
      await tester.pumpWidget(_app(
        Builder(builder: (context) {
          fill = AppColors.glassFill(context);
          border = AppColors.glassBorder(context);
          hero = AppColors.heroSurfaceGradient(context);
          canvas = AppColors.scaffold(context);
          return const SizedBox();
        }),
        dark: true,
      ));
      expect(canvas, black);
      // Cards: translucent navy, not black and not opaque.
      expect(fill.a, lessThan(0.9));
      expect(fill.b, greaterThan(fill.r), reason: 'navy-tinted card');
      expect(fill, isNot(black));
      // Hero: blue-lit gradient, brighter than the surface it sits on.
      expect(hero.colors.first.b, greaterThan(hero.colors.first.r));
      expect(hero.colors.first.computeLuminance(),
          greaterThan(AppColors.darkSurface.computeLuminance()));
      // Borders stay a light hairline.
      expect(border.a, lessThan(0.2));
    });
  });
  group('dialog actions', () {
    double contrast(Color a, Color b) {
      final l1 = a.computeLuminance();
      final l2 = b.computeLuminance();
      final hi = l1 > l2 ? l1 : l2;
      final lo = l1 > l2 ? l2 : l1;
      return (hi + 0.05) / (lo + 0.05);
    }

    // Regression (found on a OnePlus 7T): Cancel/Save in a navy dialog used the
    // raw blue brand fill, which measures under 3:1 on the navy surface. Every
    // palette is asserted in both modes. Ocean Blue (4.16:1) and Royal Purple
    // (4.42:1) were under the bar in *dark* mode; their light-mode ink was
    // already above 11:1.
    setUp(() => AppTypography.debugSkipFontLoading = true);
    tearDown(() {
      AppTypography.debugSkipFontLoading = false;
      AppColors.applyPalette(AppPalette.defaultPalette);
    });

    for (final palette in AppPalette.all) {
      test('${palette.label}: text and outlined buttons stay readable', () {
        AppColors.applyPalette(palette);
        for (final brightness in Brightness.values) {
          final theme =
              const SpendSenseApp().themeFor(brightness, FontPreset.standard);
          final surface = theme.dialogTheme.backgroundColor!;
          final text = theme.textButtonTheme.style!.foregroundColor!
              .resolve(<WidgetState>{})!;
          final outlined = theme.outlinedButtonTheme.style!.foregroundColor!
              .resolve(<WidgetState>{})!;
          expect(contrast(text, surface), greaterThanOrEqualTo(4.5),
              reason: '${palette.label} $brightness text button');
          expect(contrast(outlined, surface), greaterThanOrEqualTo(4.5),
              reason: '${palette.label} $brightness outlined button');
        }
      });
    }

    for (final palette in [AppPalette.oceanBlue, AppPalette.royalPurple]) {
      test(
          '${palette.label}: dark ink keeps its hue and light mode is untouched',
          () {
        AppColors.applyPalette(palette);
        final dark = AppColors.brandInkFor(true);
        // Still the palette's own colour family, only lighter.
        expect(HSLColor.fromColor(dark).hue,
            closeTo(HSLColor.fromColor(palette.bright).hue, 12));
        expect(dark.computeLuminance(),
            greaterThan(palette.bright.computeLuminance()));
        expect(
            contrast(dark, palette.darkSurfaceAlt), greaterThanOrEqualTo(4.5));
        expect(AppColors.brandInkFor(false),
            Color.lerp(palette.brand, palette.deep, 0.45));
      });
    }

    test('palettes already above 4.5:1 keep their bright stop unchanged', () {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        if (contrast(palette.bright, palette.darkSurfaceAlt) >= 4.5) {
          expect(AppColors.brandInkFor(true), palette.bright,
              reason: palette.label);
        }
      }
    });
  });
  group('navigation', () {
    const items = [
      NavItem(Icons.home_rounded, 'Home'),
      NavItem(Icons.receipt_long_rounded, 'Activity'),
    ];

    testWidgets('selected slot is a lit chip with a white glyph on navy glass',
        (tester) async {
      AppColors.applyPalette(AppPalette.midnight);
      await tester.pumpWidget(_app(
        FloatingNavBar(items: items, currentIndex: 0, onTap: (_) {}),
        dark: true,
      ));
      await tester.pumpAndSettle();
      final home = tester.widget<Icon>(find.byIcon(Icons.home_rounded));
      final idle = tester.widget<Icon>(find.byIcon(Icons.receipt_long_rounded));
      expect(home.color, Colors.white);
      expect(idle.color, isNot(Colors.white));
    });
  });

  group('sheets', () {
    Future<void> open(WidgetTester tester, {bool reduceMotion = false}) async {
      // The sheet route sits above the app's own MediaQuery, so the system
      // inset must come from the view itself.
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context: context,
              builder: (_) => const SizedBox(
                height: 120,
                child: Center(child: Text('sheet body')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        reduceMotion: reduceMotion,
      ));
      await tester.tap(find.text('open'));
    }

    testWidgets('content clears the system navigation bar', (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      final bodyBottom = tester.getBottomLeft(find.text('sheet body')).dy;
      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      // 120 high box centred, plus the 24dp bottom inset below it.
      expect(screen - bodyBottom, greaterThanOrEqualTo(24 + 50));
    });

    testWidgets(
        'a sheet that paints its own surface reaches the bottom of the screen',
        (tester) async {
      // Regression (found on a OnePlus 7T): wrapping a transparent-background
      // sheet in a SafeArea left a see-through strip under it, so the page
      // behind showed through below the sheet.
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => Container(
                key: const Key('own-surface'),
                height: 120,
                color: Colors.blue,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final bottom =
          tester.getBottomLeft(find.byKey(const Key('own-surface'))).dy;
      expect(bottom, tester.view.physicalSize.height);
    });
    testWidgets('tapping the barrier dismisses with the reverse transition',
        (tester) async {
      await open(tester);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      // Still on screen mid-exit, gone once the reverse animation finishes.
      expect(find.text('sheet body'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('sheet body'), findsNothing);
    });

    testWidgets('reduced motion shows the sheet without a transition',
        (tester) async {
      await open(tester, reduceMotion: true);
      await tester.pump();
      await tester.pump();
      final route = ModalRoute.of(tester.element(find.text('sheet body')))!;
      expect(route.animation!.value, 1.0);
    });
  });

  group('type toggle', () {
    testWidgets('reports the tapped side and marks the selection',
        (tester) async {
      TransactionType? picked;
      await tester.pumpWidget(_app(TransactionTypeToggle(
        isIncome: false,
        onSelect: (t) => picked = t,
      )));
      await tester.tap(find.text('Income'));
      expect(picked, TransactionType.income);

      final expense = tester.getSemantics(find.bySemanticsLabel('Expense'));
      expect(expense, isSemantics(label: 'Expense', isSelected: true));
    });
  });
}
