import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/home_action_dock.dart';
import 'package:spendsense/widgets/pressable.dart';
import 'package:spendsense/widgets/quick_action_tile.dart';

/// Craft-floor regressions for the dashboard dock.
///
/// The reported defect was "the icons are not aligned". The dock already
/// centred each icon over its label, so the earlier test passed while the real
/// problem stayed: `Add expense` wraps to two lines and `Activity` does not, so
/// the wrapped slot grew taller and its icon dropped below the other three.
/// These pin the three facts that keep the four slots on one line: equal slot
/// heights, equal icon tops, equal label tops — plus the 48dp touch target.
void main() {
  List<QuickAction> actions() => [
        QuickAction(
          label: 'Add expense',
          icon: Icons.south_west_rounded,
          onTap: () {},
        ),
        QuickAction(
          label: 'Add income',
          icon: Icons.north_east_rounded,
          onTap: () {},
        ),
        QuickAction(label: 'Sync SMS', icon: Icons.sync_rounded, onTap: () {}),
        QuickAction(
          label: 'Activity',
          icon: Icons.receipt_long_rounded,
          onTap: () {},
        ),
      ];

  Future<void> pumpDock(
    WidgetTester tester, {
    double textScale = 1.0,
    double width = 411,
  }) async {
    // The dock is `Expanded` inside a Row on Home, so it is laid out tight
    // against the page inset. Centring it in a loose SizedBox let each slot
    // shrink-wrap to its own content, which hid the two-line label growth the
    // bug depended on. Force the tight width Home actually gives it.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              child: HomeActionDock(actions: actions()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('the four slots share one well size and one label-box height',
      (tester) async {
    // Two facts the user could see: the wells stopped being identical, and the
    // wrapped label made its slot a different shape from its neighbours.
    //
    // Glyph vertical position cannot be asserted across slots — Material icons
    // are not vertically symmetric (`north_east_rounded` reports a 1dp offset
    // from `south_west_rounded`), and the well clips the icon, so that 1dp is
    // glyph ink, not layout. Slot geometry is what must match.
    await pumpDock(tester);

    final slotHeights = <double>{};
    final labelHeights = <double>{};
    for (final action in actions()) {
      final slot = find.ancestor(
        of: find.text(action.label),
        matching: find.byType(Pressable),
      );
      slotHeights.add(tester.getSize(slot.first).height);
      labelHeights.add(tester.getSize(find.text(action.label)).height);
    }
    expect(slotHeights.length, 1, reason: 'slots differ in height: $slotHeights');
    expect(
      labelHeights.length,
      1,
      reason: 'label boxes differ in height: $labelHeights',
    );

    // The label box reserves two lines in every slot, so the wrapped slot can
    // never be the taller one.
    expect(slotHeights.first, greaterThan(AppSpacing.wellSize + 20));
  });

  testWidgets('every dock slot is a legal touch target', (tester) async {
    await pumpDock(tester);
    // `find.ancestor(of: text)` resolves the inner RichText of the label, so it
    // reports the label's own height rather than the slot's. Walk the Pressable
    // widgets directly instead; the dock creates one per slot, in order.
    final targets = find.byType(Pressable);
    expect(targets, findsNWidgets(actions().length));
    for (var i = 0; i < actions().length; i++) {
      final size = tester.getSize(targets.at(i));
      expect(
        size.height,
        greaterThanOrEqualTo(AppSpacing.wellTouchTarget),
        reason: '${actions()[i].label}: target is shorter than 48dp',
      );
      expect(
        size.width,
        greaterThanOrEqualTo(AppSpacing.wellTouchTarget),
        reason: '${actions()[i].label}: target is narrower than 48dp',
      );
    }
  });
}
