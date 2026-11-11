import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/widgets/app_kpi_card.dart';

/// The KPI card is the first place a money figure meets a narrow column.
void main() {
  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 148, double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('a long amount scales down instead of losing digits',
      (tester) async {
    const value = '₹1,23,45,678';
    await pump(
      tester,
      const AppKpiCard(
          icon: Icons.north_east_rounded, label: 'Income', value: value),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    // Whole string still present (an ellipsis would shorten the painted text),
    // and it fits inside the card's 16dp padding.
    expect(find.text(value), findsOneWidget);
    final card = tester.getRect(find.byType(AppKpiCard));
    final text = tester.getRect(find.text(value));
    expect(text.right, lessThanOrEqualTo(card.right - 16 + 0.5));
  });

  testWidgets('trend colour follows meaning, not sign', (tester) async {
    AppColors.applyPalette(AppColors.palette);
    // Expenses rose: bad (red). Income rose: good (green).
    await pump(
      tester,
      const AppKpiCard(
        icon: Icons.south_west_rounded,
        label: 'Expenses',
        value: '₹10',
        trendValue: 12.5,
        trendGoodIsUp: false,
      ),
      width: 220,
    );
    final badColour = tester.widget<Text>(find.text('12.5%')).style!.color;
    expect(badColour, AppColors.expenseRed);

    await pump(
      tester,
      const AppKpiCard(
        icon: Icons.north_east_rounded,
        label: 'Income',
        value: '₹10',
        trendValue: 12.5,
        trendGoodIsUp: true,
      ),
      width: 220,
    );
    final goodColour = tester.widget<Text>(find.text('12.5%')).style!.color;
    expect(goodColour, AppColors.incomeGreen);
  });

  testWidgets('no previous period means no trend at all', (tester) async {
    await pump(
      tester,
      const AppKpiCard(
          icon: Icons.savings_outlined, label: 'Net', value: '₹10'),
    );
    expect(find.textContaining('from'), findsNothing);
    expect(find.byType(AppTrend), findsNothing);
  });

  testWidgets('the trend is announced with its direction in words',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      const AppKpiCard(
        icon: Icons.south_west_rounded,
        label: 'Expenses',
        value: '₹10',
        trendValue: -5.1,
        trendGoodIsUp: false,
      ),
      width: 220,
    );
    expect(find.bySemanticsLabel('Down 5.1 percent, from last period'),
        findsOneWidget);
    handle.dispose();
  });

  testWidgets(
      'the row shares the width when it fits, scrolls when it does not,'
      ' and stacks at large text', (tester) async {
    List<Widget> cards() => const [
          AppKpiCard(icon: Icons.add, label: 'A', value: '₹1'),
          AppKpiCard(icon: Icons.add, label: 'B', value: '₹2'),
          AppKpiCard(icon: Icons.add, label: 'C', value: '₹3'),
        ];
    // 360dp: three cards of about 109dp fit, so nothing scrolls.
    await pump(tester, AppKpiRow(cards: cards()), width: 360);
    expect(find.byType(SingleChildScrollView), findsNothing);
    // 280dp: they do not, so the row scrolls.
    await pump(tester, AppKpiRow(cards: cards()), width: 280);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // 2x text: stacked, whatever the width.
    await pump(tester, AppKpiRow(cards: cards()), width: 360, scale: 2);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
