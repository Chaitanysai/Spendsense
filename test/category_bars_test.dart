import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/widgets/animated_progress_bar.dart';
import 'package:spendsense/widgets/category_spending_bars.dart';

Widget _host(
  Map<String, int> totals, {
  int maxRows = 6,
  double width = 360,
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: CategorySpendingBars(
                totalsMinor: totals,
                maxRows: maxRows,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('orders rows by amount and shows amount and share',
      (tester) async {
    await tester.pumpWidget(_host({
      'Food': 5000,
      'Travel': 3000,
      'Shopping': 2000,
    }));
    await tester.pump(const Duration(seconds: 1));

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .toList();

    expect(texts.indexOf('Food'), lessThan(texts.indexOf('Travel')));
    expect(texts.indexOf('Travel'), lessThan(texts.indexOf('Shopping')));
    final fractions = tester
        .widgetList<AnimatedProgressBar>(find.byType(AnimatedProgressBar))
        .map((w) => w.fraction)
        .toList();
    expect(fractions, [closeTo(0.5, 1e-9), closeTo(0.3, 1e-9), closeTo(0.2, 1e-9)]);
  });

  testWidgets('bar fractions are shares of the category total', (tester) async {
    await tester.pumpWidget(_host({
      'Food': 6000,
      'Travel': 2000,
      'Bills': 2000,
    }));
    await tester.pump(const Duration(seconds: 1));

    final fractions = tester
        .widgetList<AnimatedProgressBar>(find.byType(AnimatedProgressBar))
        .map((w) => w.fraction)
        .toList();

    expect(fractions, [closeTo(0.6, 1e-9), closeTo(0.2, 1e-9), closeTo(0.2, 1e-9)]);
    expect(fractions.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
  });

  testWidgets('zero and negative totals fall back to the empty state',
      (tester) async {
    await tester.pumpWidget(_host({'Food': 0, 'Travel': -500}));
    await tester.pump();

    expect(find.text('No spending to chart yet'), findsOneWidget);
    expect(find.byType(AnimatedProgressBar), findsNothing);
  });

  testWidgets('many categories are capped and summarised', (tester) async {
    final totals = {
      for (var i = 0; i < 9; i++) 'Category $i': (9 - i) * 100,
    };
    await tester.pumpWidget(_host(totals, maxRows: 6));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(AnimatedProgressBar), findsNWidgets(6));
    expect(find.text('+3 more categories'), findsOneWidget);
  });

  testWidgets('a single category is 100 percent and fills the bar',
      (tester) async {
    await tester.pumpWidget(_host({'Food': 12345}));
    await tester.pump(const Duration(seconds: 1));

    final bar = tester.widget<AnimatedProgressBar>(
      find.byType(AnimatedProgressBar),
    );
    expect(bar.fraction, 1.0);
  });

  testWidgets('no overflow on a narrow screen with very large amounts',
      (tester) async {
    await tester.pumpWidget(_host(
      {
        'Food': 98765432100,
        'A very long category name that should ellipsize': 50000000000,
      },
      width: 280,
      textScale: 1.3,
    ));
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
  });

  testWidgets('each row carries an accessible label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host({'Food': 5000, 'Travel': 5000}));
    await tester.pump(const Duration(seconds: 1));

    expect(find.bySemanticsLabel('Food, 50 percent of spending'), findsOneWidget);
    expect(
        find.bySemanticsLabel('Travel, 50 percent of spending'), findsOneWidget);
    handle.dispose();
  });
}
