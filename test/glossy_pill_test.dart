import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';
import 'package:spendsense/widgets/glossy_pill.dart';
import 'package:spendsense/widgets/pressable.dart';

/// Pins the glossy pill's two states in both themes, and the nav bar's use of
/// them. These assert the *treatment* rather than pixels: the selected state
/// owns the gradient, luminous edge and glow, and a bare control paints nothing
/// until it is chosen.
BoxDecoration _pillDecoration(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(find.descendant(
    of: find.byType(GlossyPill),
    matching: find.byType(AnimatedContainer),
  ));
  return container.decoration! as BoxDecoration;
}

Future<void> _pumpPill(
  WidgetTester tester, {
  required bool selected,
  required Brightness brightness,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Center(
          child: GlossyPill(
            selected: selected,
            bareWhenUnselected: true,
            child: const Text('Chip'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpNav(WidgetTester tester,
    {required Brightness brightness}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        bottomNavigationBar: FloatingNavBar(
          items: const [
            NavItem(Icons.home_rounded, 'HOME'),
            NavItem(Icons.receipt_long_rounded, 'ACTIVITY'),
          ],
          currentIndex: 1,
          onTap: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final label = brightness == Brightness.light ? 'light' : 'dark';

    testWidgets('$label: the selected pill carries gradient, edge and glow',
        (tester) async {
      await _pumpPill(tester, selected: true, brightness: brightness);

      final decoration = _pillDecoration(tester);
      expect(decoration.gradient, isNotNull,
          reason: 'the selected pill rides the brand gradient');
      expect(decoration.border, isNotNull,
          reason: 'the luminous edge belongs to the selected state');
      expect(decoration.boxShadow, isNotNull,
          reason: 'the glow belongs to the selected state');
    });

    testWidgets('$label: a bare unselected pill paints nothing',
        (tester) async {
      await _pumpPill(tester, selected: false, brightness: brightness);

      final decoration = _pillDecoration(tester);
      expect(decoration.gradient, isNull);
      expect(decoration.border, isNull,
          reason: 'inactive controls must stay understated');
      expect(decoration.boxShadow, isNull);
      expect(decoration.color, Colors.transparent);
    });

    testWidgets('$label: only the active nav slot is glossy', (tester) async {
      await _pumpNav(tester, brightness: brightness);

      final pills = tester.widgetList<GlossyPill>(find.byType(GlossyPill));
      expect(pills, hasLength(2));
      expect(pills.first.selected, isFalse, reason: 'HOME is not the tab');
      expect(pills.last.selected, isTrue, reason: 'ACTIVITY is the tab');
      expect(pills.every((p) => p.bareWhenUnselected), isTrue,
          reason: 'the inactive slot must stay bare, not frosted');

      // The selected icon sits on the gradient, so it has to be the
      // on-gradient white; the label below stays on the translucent bar.
      final activeIcon = tester.widget<Icon>(find.descendant(
        of: find.byType(GlossyPill).last,
        matching: find.byType(Icon),
      ));
      expect(activeIcon.color, Colors.white);

      // Qoder's press feedback is the whole slot, not the badge.
      expect(find.byType(Pressable), findsNWidgets(2));
    });
  }

  testWidgets('reduced motion zeroes the pill transition', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await _pumpPill(tester, selected: true, brightness: Brightness.light);

    final container = tester.widget<AnimatedContainer>(find.descendant(
      of: find.byType(GlossyPill),
      matching: find.byType(AnimatedContainer),
    ));
    expect(
        container.duration,
        AppMotion.respect(
          tester.element(find.byType(GlossyPill)),
          AppMotion.fast,
        ));
    expect(container.duration, Duration.zero);
  });
}
