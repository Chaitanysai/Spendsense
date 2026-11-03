import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/screens/appearance_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// The Appearance screen groups nineteen palettes into sections. Grouping is a
/// presentation detail, but "every theme is reachable and nothing is listed
/// twice" is a product requirement, not a style choice: a palette that falls
/// through the grouping is a theme the user can never select.
void main() {
  setUp(() => AppColors.applyPalette(AppPalette.defaultPalette));
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  Future<ThemeProvider> pumpScreen(
    WidgetTester tester, {
    double textScale = 1.0,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final provider = ThemeProvider();

    // Pump straight away and let the fake clock advance through the async
    // load; awaiting a bare Future.delayed inside testWidgets deadlocks because
    // that timer only runs when the test clock is pumped.
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const MaterialApp(home: AppearanceScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    return provider;
  }

  testWidgets('every palette is listed exactly once', (tester) async {
    await pumpScreen(tester);

    // Appearance is one ListView whose children are all built eagerly, so every
    // row exists in the tree whether or not it is scrolled into view.
    final listed = <String, int>{};
    for (final palette in AppPalette.all) {
      listed[palette.id] = find.text(palette.label).evaluate().length;
    }

    final missing = listed.entries.where((e) => e.value == 0).toList();
    final duplicated = listed.entries.where((e) => e.value > 1).toList();
    expect(missing, isEmpty, reason: 'palettes never shown on Appearance');
    expect(duplicated, isEmpty, reason: 'palettes listed more than once');
    expect(listed, hasLength(AppPalette.all.length));
  });

  testWidgets('the three sections are present and labelled', (tester) async {
    await pumpScreen(tester);

    for (final heading in ['PREMIUM', 'ADDITIONAL', 'CLASSIC']) {
      expect(find.text(heading), findsOneWidget,
          reason: 'missing section "$heading"');
    }
  });

  testWidgets('tapping a supplied palette applies and persists it',
      (tester) async {
    final provider = await pumpScreen(tester);

    final target = AppPalette.all.firstWhere((p) => p.id == 'wine_sand');
    final finder = find.text(target.label);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();

    expect(provider.palette.id, 'wine_sand');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('palette_id'), 'wine_sand');
  });

  testWidgets('long names are fully visible, not truncated', (tester) async {
    await pumpScreen(tester);

    // Rendering a label with no clip is what "not ellipsised away" means. The
    // Text keeps `overflow: ellipsis` as a last-resort guard at extreme scales,
    // so assert on what the user sees rather than on the property.
    for (final id in ['midnight_indigo_vanilla', 'royal_blue_cream']) {
      final palette = AppPalette.all.firstWhere((p) => p.id == id);
      final text = tester.widget<Text>(find.text(palette.label));
      expect(text.maxLines, greaterThanOrEqualTo(2),
          reason: '${palette.label} is capped to one line');

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(AppearanceScreen),
          matching: find.text(palette.label),
        ),
      );
      expect(paragraph.didExceedMaxLines, isFalse,
          reason: '${palette.label} is clipped at text scale 1.0');
    }
  });

  testWidgets('the longest names still render at a common text scale',
      (tester) async {
    await pumpScreen(tester, textScale: 1.3);

    final palette =
        AppPalette.all.firstWhere((p) => p.id == 'midnight_indigo_vanilla');
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(AppearanceScreen),
        matching: find.text(palette.label),
      ),
    );
    expect(paragraph.didExceedMaxLines, isFalse,
        reason: '${palette.label} is clipped at text scale 1.3');
  });

  testWidgets('rows survive a large text scale without overflowing',
      (tester) async {
    await pumpScreen(tester, textScale: 1.6);

    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 24; i++) {
      await tester.drag(scrollable, const Offset(0, -260));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'overflowed at scroll step $i');
    }
  });
}
