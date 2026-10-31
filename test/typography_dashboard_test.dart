import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/screens/typography_screen.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/utils/app_text_styles.dart';
import 'package:spendsense/utils/app_typography.dart';
import 'package:spendsense/utils/dashboard_sections.dart';
import 'package:spendsense/widgets/quick_action_tile.dart';

Future<ThemeProvider> _loaded() async {
  final provider = ThemeProvider();
  // _load() is fire-and-forget in the constructor; wait until it completes.
  for (var i = 0; i < 50 && !provider.isLoaded; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(provider.isLoaded, isTrue);
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTypography.active = FontPreset.standard;
    AppTypography.debugSkipFontLoading = true;
  });

  tearDown(() => AppTypography.debugSkipFontLoading = false);

  group('font presets', () {
    test('five presets, unique ids, all open-licensed', () {
      expect(FontPreset.all, hasLength(5));
      expect({for (final p in FontPreset.all) p.id}, hasLength(5));
      for (final p in FontPreset.all) {
        expect(p.licence, contains('Open Font License'));
        expect(p.label, isNotEmpty);
      }
    });

    test('unknown or missing ids fall back to the default', () {
      expect(FontPreset.byId(null).id, FontPreset.standard.id);
      expect(FontPreset.byId('does_not_exist').id, FontPreset.standard.id);
      expect(FontPreset.byId('dot_matrix').id, FontPreset.dotMatrix.id);
    });

    test('dot-matrix display face is used only for large text', () {
      final big = AppTypography.resolve(
        preset: FontPreset.dotMatrix,
        fontSize: 32,
        fontWeight: FontWeight.w800,
      );
      final small = AppTypography.resolve(
        preset: FontPreset.dotMatrix,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      );
      expect(big.fontFamily, 'DotGothic16');
      expect(small.fontFamily, 'Space Grotesk');
      // Body text must never use the decorative face.
      expect(small.fontFamily, isNot('DotGothic16'));
    });

    test('an unknown family degrades to a usable style, not an exception', () {
      // Exercises the real font path, which fails synchronously for an
      // unknown family (no network is involved).
      AppTypography.debugSkipFontLoading = false;
      const broken = FontPreset(
        id: 'broken',
        label: 'Broken',
        description: '',
        displayFamily: 'No Such Font',
        bodyFamily: 'No Such Font',
      );
      final style = AppTypography.resolve(
        preset: broken,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      );
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w600);
      expect(
          AppTypography.textTheme(ThemeData.light().textTheme, preset: broken),
          isA<TextTheme>());
    });

    testWidgets('weights and tabular figures are preserved for amounts',
        (tester) async {
      AppTypography.active = FontPreset.cleanSans;
      late TextStyle style;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          style = AppText.amount(context, size: 24);
          return const SizedBox();
        }),
      ));
      expect(style.fontWeight, FontWeight.w800);
      expect(style.fontFeatures, isNotEmpty);
      expect(style.fontFamily, 'Inter');
    });
    test('font scale is clamped to the supported range', () {
      expect(FontScale.sanitize(null), 1.0);
      expect(FontScale.sanitize(double.nan), 1.0);
      expect(FontScale.sanitize(0.1), FontScale.min);
      expect(FontScale.sanitize(9), FontScale.max);
      expect(FontScale.sanitize(1.15), 1.15);
    });
  });

  group('ThemeProvider typography persistence', () {
    test('preset and scale persist across a restart', () async {
      final first = await _loaded();
      await first.setFontPreset(FontPreset.modernSans);
      await first.setFontScale(1.15);
      expect(AppTypography.active.id, FontPreset.modernSans.id);

      AppTypography.active = FontPreset.standard; // simulate a cold start
      final second = await _loaded();
      expect(second.fontPreset.id, FontPreset.modernSans.id);
      expect(second.fontScale, 1.15);
      expect(AppTypography.active.id, FontPreset.modernSans.id);
    });

    test('reset returns to the default face and scale', () async {
      final theme = await _loaded();
      await theme.setFontPreset(FontPreset.dotMatrix);
      await theme.setFontScale(1.3);
      await theme.resetTypography();
      expect(theme.fontPreset.id, FontPreset.standard.id);
      expect(theme.fontScale, 1.0);
      expect(AppTypography.active.id, FontPreset.standard.id);

      final reloaded = await _loaded();
      expect(reloaded.fontPreset.id, FontPreset.standard.id);
      expect(reloaded.fontScale, 1.0);
    });

    test('a corrupt stored preset or scale loads the defaults', () async {
      SharedPreferences.setMockInitialValues({
        'font_preset_id': 'zzz',
        'font_scale': 99.0,
      });
      final theme = await _loaded();
      expect(theme.fontPreset.id, FontPreset.standard.id);
      expect(theme.fontScale, FontScale.max);
    });

    test('dashboard sections can be hidden, persist, and ignore bad ids',
        () async {
      final theme = await _loaded();
      expect(theme.isSectionVisible(DashboardSection.weekly), isTrue);
      await theme.setSectionVisible(DashboardSection.weekly, false);
      await theme.setSectionVisible('not_a_section', false);
      expect(theme.hiddenSections, {DashboardSection.weekly});

      final reloaded = await _loaded();
      expect(reloaded.isSectionVisible(DashboardSection.weekly), isFalse);
      await reloaded.setSectionVisible(DashboardSection.weekly, true);
      expect(reloaded.hiddenSections, isEmpty);
    });
  });

  group('Typography screen', () {
    testWidgets('previews first, applies on request, and resets',
        (tester) async {
      late ThemeProvider theme;
      await tester.runAsync(() async => theme = await _loaded());
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>.value(
          value: theme,
          child: const MaterialApp(home: TypographyScreen()),
        ),
      );

      // Choosing a card only previews it.
      await tester.tap(find.text(FontPreset.dotMatrix.label));
      await tester.pump();
      expect(theme.fontPreset.id, FontPreset.standard.id);

      await tester.tap(find.textContaining('Apply'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(theme.fontPreset.id, FontPreset.dotMatrix.id);

      await tester.scrollUntilVisible(find.text('Reset'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Reset'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(theme.fontPreset.id, FontPreset.standard.id);
      expect(tester.takeException(), isNull);
    });
  });

  group('QuickActionGrid', () {
    List<QuickAction> actions() => [
          for (final label in [
            'Add expense',
            'Add income',
            'Sync SMS',
            'Activity',
          ])
            QuickAction(label: label, icon: Icons.add, onTap: () {}),
        ];

    test('column choice follows width and text scale, not device size', () {
      int cols(double w, double s) =>
          QuickActionGrid.columnsFor(width: w, textScale: s, count: 4);
      expect(cols(320, 1.0), 4); // phone
      expect(cols(280, 1.0), 2); // narrow
      expect(cols(320, 1.5), 2); // accessibility text
      expect(cols(900, 1.0), 4); // landscape / tablet
      expect(cols(900, 2.0), 2);
    });

    Future<List<Size>> pumpAndMeasure(
      WidgetTester tester, {
      required double width,
      required double textScale,
    }) async {
      tester.view.physicalSize = Size(width * 2, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: TextScaler.linear(textScale),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                child: QuickActionGrid(actions: actions()),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      return [
        for (final e in tester.widgetList(find.byType(QuickActionTile)))
          tester.getSize(find.byWidget(e)),
      ];
    }

    for (final scenario in const [
      (width: 360.0, scale: 1.0),
      (width: 320.0, scale: 1.0),
      (width: 360.0, scale: 1.3),
      (width: 360.0, scale: 2.0),
      (width: 800.0, scale: 1.0),
    ]) {
      testWidgets(
          'tiles are identical in size at ${scenario.width}dp / ${scenario.scale}x',
          (tester) async {
        final sizes = await pumpAndMeasure(
          tester,
          width: scenario.width,
          textScale: scenario.scale,
        );
        expect(sizes, hasLength(4));
        expect({for (final s in sizes) s.height.roundToDouble()}, hasLength(1),
            reason: 'equal heights: $sizes');
        expect({for (final s in sizes) s.width.roundToDouble()}, hasLength(1),
            reason: 'equal widths: $sizes');
        expect(
            sizes.first.height, greaterThanOrEqualTo(AppSpacing.tileMinHeight));
      });
    }
  });
}
