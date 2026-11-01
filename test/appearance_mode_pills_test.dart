import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/screens/appearance_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/glass_card.dart';

/// The System / Light / Dark pills must be one shape, three labels.
///
/// They regressed into three different boxes: the container shrink-wrapped its
/// content, so "System" and "Light" (which carry y/g descenders) came out
/// taller than "Dark", the labels sat on different baselines, and the selected
/// pill overflowed the card once the system text scale grew.
///
/// The first version of this test asserted the rect of the *nearest ancestor*
/// `Pressable`, which returns pills[0] for all three labels — it compared one
/// rect against itself and passed even with the bug reinstated. It now scopes
/// the descendant search to each labelled pill, then measures the pill's own
/// painted container.
void main() {
  setUp(() => AppColors.applyPalette(AppPalette.emerald));
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  Future<void> pumpAppearance(
    WidgetTester tester, {
    required double textScale,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final theme = ThemeProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>.value(
        value: theme,
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const MaterialApp(home: AppearanceScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// The painted box of one mode pill — the *inner* container that draws the
  /// selected border, which is the nearest `Container` ancestor of the label.
  /// Each label yields a distinct rect; the further ancestor is the card.
  Rect pillRect(WidgetTester tester, String label) {
    final containers = find
        .ancestor(of: find.text(label), matching: find.byType(Container))
        .evaluate()
        .toList();
    final pill = containers.first.renderObject! as RenderBox;
    return pill.localToGlobal(Offset.zero) & pill.size;
  }

  const labels = ['System', 'Light', 'Dark'];

  for (final scale in [1.0, 1.3]) {
    testWidgets('mode pills are one box at text scale $scale',
        (tester) async {
      await pumpAppearance(tester, textScale: scale);
      final rects = [for (final l in labels) pillRect(tester, l)];

      // The three must be distinct regions, not one rect reported thrice.
      expect(rects[0].left, lessThan(rects[1].left));
      expect(rects[1].left, lessThan(rects[2].left));

      for (final r in rects.skip(1)) {
        expect(r.width, moreOrLessEquals(rects.first.width, epsilon: 1.0),
            reason: 'pill widths differ');
        expect(r.height, moreOrLessEquals(rects.first.height, epsilon: 1.0),
            reason: 'pill heights differ — a descender decided the box');
        expect(r.top, moreOrLessEquals(rects.first.top, epsilon: 1.0),
            reason: 'pill tops are not on one line');
        expect(r.bottom, moreOrLessEquals(rects.first.bottom, epsilon: 1.0),
            reason: 'pill bottoms are not on one line');
      }
    });
  }

  testWidgets('no mode pill overflows its card at large text',
      (tester) async {
    await pumpAppearance(tester, textScale: 1.3);
    final card = tester.getRect(find.byType(GlassCard).first);
    for (final label in labels) {
      final r = pillRect(tester, label);
      expect(r.top, greaterThanOrEqualTo(card.top - 0.5),
          reason: '$label overflows the card top');
      expect(r.bottom, lessThanOrEqualTo(card.bottom + 0.5),
          reason: '$label overflows the card bottom');
    }
  });

  testWidgets('palette name and DEFAULT chip do not collide',
      (tester) async {
    await pumpAppearance(tester, textScale: 1.0);
    expect(find.text('Premium Blue'), findsOneWidget,
        reason: 'the default palette name should not be ellipsised away');
    final name = tester.getRect(find.text('Premium Blue'));
    final chip = tester.getRect(find.text('DEFAULT'));
    expect(name.right, lessThanOrEqualTo(chip.left + 0.5),
        reason: 'the palette name overlaps the DEFAULT chip');
  });
}
