import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/widgets/home_action_dock.dart';
import 'package:spendsense/widgets/quick_action_tile.dart';

/// Regression for the OTA review: the dock's icon+label stack shrink-wrapped
/// to the label, so the whole cluster sat at the left edge of its slot. The
/// icon and label must share the slot's centre line.
void main() {
  testWidgets('dock icons are centred over their labels and slots',
      (tester) async {
    final actions = <QuickAction>[
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
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: HomeActionDock(actions: actions),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final dock = find.byType(HomeActionDock);
    final dockLeft = tester.getTopLeft(dock).dx;
    final dockWidth = tester.getSize(dock).width;
    const slotWidth = 360 / 4;

    for (var i = 0; i < actions.length; i++) {
      final label = find.text(actions[i].label);
      final icon = find.byIcon(actions[i].icon);
      final labelCenter = tester.getCenter(label).dx;
      final iconCenter = tester.getCenter(icon).dx;

      expect(
        iconCenter,
        closeTo(labelCenter, 0.75),
        reason: '${actions[i].label}: icon must sit over its label',
      );
      final slotCenter = dockLeft + slotWidth * (i + 0.5);
      expect(
        iconCenter,
        closeTo(slotCenter, 6),
        reason: '${actions[i].label}: icon must sit in the slot centre',
      );
    }
    expect(dockWidth, 360);
  });
}
