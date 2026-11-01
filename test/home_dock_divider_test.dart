import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/home_action_dock.dart';
import 'package:spendsense/widgets/quick_action_tile.dart';

/// The dock's separator rules must not be drawn over the glyph plates.
///
/// `VerticalDivider` sat *between* the slots in the Row, and Row paints its
/// children in order, so the rule landed on top of the neighbouring plate: in the
/// 2x2 layout used at large text scale the lines appeared to slice through the
/// circles. The rule is now the bottom-most child of each slot's own stack.
void main() {
  setUp(() => AppColors.applyPalette(AppPalette.premiumBlue));
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  Future<void> pump(WidgetTester tester, {required double scale}) async {
    tester.view.physicalSize = const Size(411, 914) * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: MaterialApp(
          home: Scaffold(
            body: HomeActionDock(
              actions: [
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
                QuickAction(
                  label: 'Sync SMS',
                  icon: Icons.sync_rounded,
                  onTap: () {},
                ),
                QuickAction(
                  label: 'Activity',
                  icon: Icons.receipt_long_rounded,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no VerticalDivider is painted over a plate', (tester) async {
    await pump(tester, scale: 1.3);
    // The regression was a `VerticalDivider` sibling in the Row. Its absence is
    // the invariant: separators now live inside each slot, behind its content.
    expect(find.byType(VerticalDivider), findsNothing);
  });

  testWidgets('each slot stacks its rule under the plate', (tester) async {
    await pump(tester, scale: 1.3);
    final stacks = find.byType(Stack);
    expect(stacks, findsWidgets);
    // A slot's Stack must place the rule before the plate so paint order puts
    // the plate on top.
    for (final element in stacks.evaluate()) {
      final stack = element.widget as Stack;
      if (stack.children.length < 2) continue;
      final first = stack.children.first;
      expect(first, isA<Positioned>(),
          reason: 'rule must be the first (bottom-most) child of a slot stack');
    }
  });

  testWidgets('all four slots are present at both scales', (tester) async {
    for (final scale in [1.0, 1.3]) {
      await pump(tester, scale: scale);
      for (final label in [
        'Add expense',
        'Add income',
        'Sync SMS',
        'Activity',
      ]) {
        expect(find.text(label), findsOneWidget,
            reason: '$label missing at ${scale}x');
      }
    }
  });
}
