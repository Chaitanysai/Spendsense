import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/utils/category_style.dart';
import 'package:spendsense/widgets/category_chip_picker.dart';

/// The category picker: one chosen chip, everything else neutral.
void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await inter.load();
  });
  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  Future<void> pump(WidgetTester tester, String selected,
      {bool dark = false,
      double scale = 1,
      ValueChanged<String>? onSelect}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CategoryChipPicker(
                selected: selected, onSelect: onSelect ?? (_) {}),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Border borderOf(WidgetTester tester, String label) {
    final box = tester.widget<AnimatedContainer>(find.ancestor(
        of: find.text(label), matching: find.byType(AnimatedContainer)));
    return (box.decoration! as BoxDecoration).border! as Border;
  }

  testWidgets('only the chosen chip wears its category hue', (tester) async {
    await pump(tester, 'Food');
    final chosen = borderOf(tester, 'Food').top;
    expect(chosen.color, CategoryStyle.color('Food'));
    expect(chosen.width, 1.5);
    for (final c in CategoryStyle.pickerCategories.where((c) => c != 'Food')) {
      final side = borderOf(tester, c).top;
      expect(side.width, 1, reason: c);
      expect(side.color, isNot(CategoryStyle.color(c)),
          reason: '$c shows its hue while not chosen');
    }
  });

  testWidgets('the chosen chip shows a check instead of its glyph',
      (tester) async {
    await pump(tester, 'Travel');
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(CategoryStyle.icon('Travel')), findsNothing);
    expect(find.byIcon(CategoryStyle.icon('Food')), findsOneWidget);
  });

  testWidgets('selection is announced, and tapping reports the category',
      (tester) async {
    final handle = tester.ensureSemantics();
    String? picked;
    await pump(tester, 'Food', onSelect: (c) => picked = c);
    expect(
      tester.getSemantics(find.text('Food')),
      isSemantics(
          label: 'Food',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true),
    );
    await tester.tap(find.text('Health'));
    expect(picked, 'Health');
    handle.dispose();
  });

  testWidgets('a screen reader can activate a chip, not only read it',
      (tester) async {
    final handle = tester.ensureSemantics();
    String? picked;
    await pump(tester, 'Food', onSelect: (c) => picked = c);
    tester.semantics.tap(find.semantics.byLabel('Travel'));
    await tester.pump();
    expect(picked, 'Travel',
        reason: 'the tap action must be exposed to assistive technology');
    handle.dispose();
  });

  for (final palette in AppPalette.all) {
    for (final dark in [false, true]) {
      testWidgets(
          'chosen label is readable: ${palette.id} ${dark ? 'dark' : 'light'}',
          (tester) async {
        AppColors.applyPalette(palette);
        await pump(tester, 'Food', dark: dark);
        final label = tester.widget<Text>(find.text('Food'));
        final tinted = Color.alphaBlend(
          CategoryStyle.color('Food').withValues(alpha: dark ? 0.22 : 0.16),
          AppColors.glassBase(dark),
        );
        // The chosen label is primary ink on the tinted chip.
        final ratio = AppColors.contrastRatio(label.style!.color!, tinted);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '${palette.label} dark=$dark chosen label contrast');
      });
    }
  }

  testWidgets('every chip is at least 48dp tall and fits at 2x',
      (tester) async {
    await pump(tester, 'Food', scale: 2);
    for (final c in CategoryStyle.pickerCategories) {
      final size = tester.getSize(find.ancestor(
          of: find.text(c), matching: find.byType(AnimatedContainer)));
      expect(size.height, greaterThanOrEqualTo(48), reason: c);
    }
    expect(tester.takeException(), isNull);
  });
}
