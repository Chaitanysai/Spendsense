import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/formatters.dart';
import 'package:spendsense/widgets/app_kpi_card.dart';
import 'package:spendsense/widgets/dashboard/balance_hero.dart';

/// No Overview figure may be clipped or misleading.
///
/// At 390dp the third card ("Net") used to start 16dp inside the page margin, so
/// the margin cut it flat and a ₹1,106 net showed as "₹1". The cards were a
/// fixed 148dp wide; three of them cannot fit in 358dp, and a clipped digit
/// reads as a different amount.
///
/// What is asserted, from painted rectangles with Inter loaded:
///
/// * a figure is either wholly inside the row's viewport or wholly outside it,
///   never partly cut (checked at rest);
/// * at 360dp and wider all three are inside, with nothing to scroll;
/// * on a narrower row the first two are inside, the third is reachable, and
///   after scrolling to it, it is wholly inside;
/// * a figure that does not fit its card is scaled down, not cut, and never
///   below 0.7 of its size;
/// * the figures are the ones the provider computed (₹4,500, ₹3,394, ₹1,106).
void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await inter.load();
  });

  BalanceHero hero({int income = 450000, int expense = 339400}) => BalanceHero(
        balanceMinor: 110600,
        incomeMinor: income,
        expenseMinor: expense,
        previousExpenseMinor: 300000,
        previousIncomeMinor: 400000,
        budgetMinor: 2000000,
        periodLabel: '1 Nov – 30 Nov',
        periodEnd: DateTime(2026, 11, 30),
        visible: true,
        onToggleVisibility: () {},
        onSetBudget: () {},
      );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required double width,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 3, 1800);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
  }

  /// Painted rectangle of the text [value] inside the Overview row, including
  /// the scale a FittedBox applied, and that scale.
  ({Rect rect, double scale}) painted(WidgetTester tester, String value) {
    final finder = find.descendant(
      of: find.byType(AppKpiRow),
      matching: find.text(value),
    );
    expect(finder, findsOneWidget, reason: 'no "$value" in the Overview row');
    final ro = tester.renderObject<RenderParagraph>(finder);
    final m = ro.getTransformTo(null);
    return (
      rect: MatrixUtils.transformRect(m, Offset.zero & ro.size),
      scale: m.getMaxScaleOnAxis(),
    );
  }

  /// The visible window of the row: its scroll viewport if it scrolls, else the
  /// row itself.
  Rect viewport(WidgetTester tester) {
    final scrollers = find.descendant(
      of: find.byType(AppKpiRow),
      matching: find.byType(SingleChildScrollView),
    );
    return tester.getRect(
      scrollers.evaluate().isEmpty ? find.byType(AppKpiRow) : scrollers,
    );
  }

  bool inside(Rect r, Rect v) =>
      r.left >= v.left - 0.5 && r.right <= v.right + 0.5;
  bool outside(Rect r, Rect v) => r.left >= v.right - 0.5 || r.right <= v.left;

  final income = Formatters.currency.format(450000 ~/ 1);
  final expenses = Formatters.currency.format(339400 ~/ 1);
  final net = Formatters.currency.format(110600 ~/ 1);

  test('the figures are the provider\'s own, formatted', () {
    expect(income, '₹4,500');
    expect(expenses, '₹3,394');
    expect(net, '₹1,106');
  });

  for (final (width, scale) in const <(double, double)>[
    (390.0, 1.0),
    (411.0, 1.0),
    (360.0, 1.0),
    (360.0, 1.3),
  ]) {
    testWidgets('all three Overview figures are whole at ${width}dp, ${scale}x',
        (tester) async {
      await pump(tester, hero(), width: width, scale: scale);
      final v = viewport(tester);
      expect(
          find.descendant(
            of: find.byType(AppKpiRow),
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
          reason: 'three cards fit at ${width}dp: nothing to scroll');
      for (final value in [income, expenses, net]) {
        final p = painted(tester, value);
        expect(inside(p.rect, v), isTrue,
            reason: '$value ${p.rect} is not wholly inside the row $v');
        expect(p.scale, greaterThanOrEqualTo(0.7),
            reason: '$value is scaled to ${p.scale.toStringAsFixed(2)}');
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in const [1.0, 1.3]) {
    testWidgets('320dp, ${scale}x: no figure is half-cut, Net is reachable',
        (tester) async {
      await pump(tester, hero(), width: 320, scale: scale);
      final v = viewport(tester);
      final scroller = find.descendant(
        of: find.byType(AppKpiRow),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scroller, findsOneWidget, reason: 'a 288dp row must scroll');

      // At rest: Income and Expenses whole; Net wholly off screen, not sliced.
      expect(inside(painted(tester, income).rect, v), isTrue);
      expect(inside(painted(tester, expenses).rect, v), isTrue);
      final restNet = painted(tester, net).rect;
      expect(outside(restNet, v), isTrue,
          reason: 'Net $restNet is partly visible in $v: a sliced figure');

      // Scrolled to the end: Net is whole.
      final position = tester
          .state<ScrollableState>(find.descendant(
            of: scroller,
            matching: find.byType(Scrollable),
          ))
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump(const Duration(milliseconds: 300));
      expect(inside(painted(tester, net).rect, v), isTrue,
          reason: 'Net is not whole after scrolling to the end');
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in const [320.0, 390.0]) {
    testWidgets('a large figure scales down instead of clipping at ${width}dp',
        (tester) async {
      // ₹12,34,567 income, ₹9,87,654 expenses -> net ₹2,46,913.
      await pump(
        tester,
        hero(income: 123456700, expense: 98765400),
        width: width,
      );
      final v = viewport(tester);
      final big = Formatters.currency.format(123456700);
      final p = painted(tester, big);
      if (width >= 360) {
        expect(inside(p.rect, v), isTrue, reason: '$big ${p.rect} in $v');
      } else {
        // Scrolling row: Income is the first card, so it must be whole.
        expect(inside(p.rect, v), isTrue, reason: '$big ${p.rect} in $v');
      }
      expect(p.scale, greaterThanOrEqualTo(0.7),
          reason: '$big is scaled to ${p.scale.toStringAsFixed(2)}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the trend stays readable in a narrow card', (tester) async {
    await pump(tester, hero(), width: 390);
    final caption = find.descendant(
      of: find.byType(AppKpiRow),
      matching: find.textContaining('from last period'),
    );
    expect(caption, findsNWidgets(2), reason: 'income and expenses trends');
    for (final e in caption.evaluate()) {
      final ro = e.renderObject! as RenderParagraph;
      final scale = ro.getTransformTo(null).getMaxScaleOnAxis();
      expect(scale, greaterThanOrEqualTo(0.8),
          reason: 'the trend caption is scaled to ${scale.toStringAsFixed(2)}');
    }
  });
}
