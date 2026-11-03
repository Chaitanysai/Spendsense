import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/widgets/cycle_hero.dart';
import 'package:spendsense/widgets/cycle_ring.dart';
import 'package:spendsense/widgets/animated_progress_bar.dart';

void main() {
  testWidgets('dashboard hero uses linear progress in landscape',
      (tester) async {
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CycleHero(
            spentMinor: 250000,
            budgetMinor: 500000,
            transactionCount: 4,
            topCategory: 'Food',
            periodLabel: '1 Nov – 30 Nov',
            periodEnd: DateTime(2026, 11, 30),
            visible: true,
            onToggleVisibility: () {},
            onSetBudget: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CycleRing), findsNothing);
    expect(find.text('Total spent this cycle'), findsOneWidget);
    expect(find.byType(AnimatedProgressBar), findsOneWidget);
  });
}
