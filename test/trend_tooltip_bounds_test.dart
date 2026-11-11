import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/widgets/dashboard/spending_trend_card.dart';

/// The value tooltip must stay inside the card at every text size.
///
/// The bubble is centred on the selected point and the point for "today" sits at
/// the right edge of the plot. The old placement clamped the bubble's *centre*
/// 34dp from the edge, which assumes a bubble no wider than 68dp, so a wider one
/// had its right end cut flat by the card's clip. Found by zooming a 360dp / 1.3x
/// dark capture, not by any test: nothing asserted where the bubble ends.
///
/// Inter is loaded so the bubble has the width it has on a phone.
void main() {
  setUpAll(() async {
    // Real glyph metrics. Without this, widget tests draw text in the blocky
    // Ahem font (1em per glyph), which is far wider than Inter and inflates
    // every overflow. The capture harness loads it the same way.
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await inter.load();
  });

  TransactionModel tx(DateTime date, int minor) => TransactionModel(
        id: 'tx-${date.millisecondsSinceEpoch}',
        amountMinor: minor,
        type: TransactionType.expense,
        merchant: 'Merchant',
        category: 'Food',
        paymentMethod: 'UPI',
        date: date,
        time: '10:00',
        originalSms: '',
        isExcluded: false,
      );

  for (final scale in [1.0, 1.3, 2.0]) {
    for (final width in [320.0, 360.0, 411.0]) {
      testWidgets('tooltip stays inside the card at ${width}dp, ${scale}x text',
          (tester) async {
        tester.view.physicalSize = Size(width * 3, 2000);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day, 12);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SpendingTrendCard(
                    expenses: [
                      tx(today, 123456789),
                      tx(today.subtract(const Duration(days: 3)), 4000),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));

        final bubble = tester.getRect(find.textContaining(' · ₹'));
        final card = tester.getRect(find.byType(SpendingTrendCard));
        expect(bubble.right, lessThanOrEqualTo(card.right),
            reason: 'bubble $bubble runs past the card $card');
        expect(bubble.left, greaterThanOrEqualTo(card.left),
            reason: 'bubble $bubble starts left of the card $card');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('selecting the first day keeps the tooltip inside the card too',
      (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 2000);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SpendingTrendCard(
                expenses: [
                  tx(today.subtract(const Duration(days: 6)), 99999999),
                  tx(today, 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    final chart = tester.getRect(find.byKey(const Key('spending-trend-chart')));
    await tester.tapAt(Offset(chart.left + 4, chart.center.dy));
    await tester.pump(const Duration(milliseconds: 400));

    final bubble = tester.getRect(find.textContaining(' · ₹'));
    final card = tester.getRect(find.byType(SpendingTrendCard));
    expect(bubble.left, greaterThanOrEqualTo(card.left));
    expect(bubble.right, lessThanOrEqualTo(card.right));
  });
}
