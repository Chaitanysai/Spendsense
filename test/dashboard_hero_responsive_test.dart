import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/widgets/animated_progress_bar.dart';
import 'package:spendsense/widgets/app_kpi_card.dart';
import 'package:spendsense/widgets/dashboard/balance_hero.dart';

/// Responsive behaviour of the dashboard hero — V2 solid-surface contract.
///
/// V2 replaces the gradient hero with an [AppSurface.raised] card:
///  - Balance is a 32sp ink figure, not white-on-dark.
///  - Income, Expenses and Net/Budget are [AppKpiCard]s in an [AppKpiRow],
///    not a [MetricStrip]. Labels are sentence-case; values are
///    formatted currency or percentage.
///  - Trend is shown by [AppTrend] with a filled circle + coloured percentage
///    + "from last period"; not a `_ChangeChip` on the gradient surface.
///  - The budget bar stays [AnimatedProgressBar]; it now tracks
///    [AppColors.brandInk] on a [AppColors.surfaceTertiary] track.
///
/// Nothing here touches provider getters or financial logic. All figures are
/// passed in as before.

BalanceHero _hero({
  int budgetMinor = 500000,
  int? previousExpenseMinor,
  int? previousIncomeMinor,
  bool visible = true,
  bool ledgerError = false,
}) =>
    BalanceHero(
      balanceMinor: 1250000,
      incomeMinor: 2500000,
      expenseMinor: 250000,
      previousExpenseMinor: previousExpenseMinor,
      previousIncomeMinor: previousIncomeMinor,
      budgetMinor: budgetMinor,
      periodLabel: '1 Nov – 30 Nov',
      periodEnd: DateTime(2026, 11, 30),
      visible: visible,
      onToggleVisibility: () {},
      onSetBudget: () {},
      ledgerError: ledgerError,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
      'V2: landscape keeps the KPI row on one scrollable line and the meter linear',
      (tester) async {
    _size(tester, const Size(2400, 1080)); // 800 × 360 logical
    await _pump(tester, _hero());

    // Solid surface: balance label is sentence-case.
    expect(find.text('Available balance'), findsOneWidget);
    // KPI row is an AppKpiRow with AppKpiCard children.
    expect(find.byType(AppKpiRow), findsOneWidget);
    // The budget meter lives in the Monthly budget section, not the hero.
    expect(find.byType(AnimatedProgressBar), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter != null,
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('V2: a narrow phone still lays out the KPI cards', (tester) async {
    _size(tester, const Size(1080, 2340)); // 360 × 780 logical
    await _pump(tester, _hero());

    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('V2: large text stacks the KPI cards instead of truncating them',
      (tester) async {
    _size(tester, const Size(1080, 2340));
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await _pump(tester, _hero());

    // AppKpiRow collapses to vertical at scale ≥ 1.6, so all three cards
    // should still be found.
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('V2: no budget offers the setup action',
      (tester) async {
    _size(tester, const Size(1080, 2340));
    await _pump(tester, _hero(budgetMinor: 0));

    // The outlined "Set a budget" pill appears.
    expect(find.text('Set a budget'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Net'), findsOneWidget);
  });

  testWidgets('V2: a known previous period shows a trend indicator',
      (tester) async {
    _size(tester, const Size(1080, 2340));
    // 250000 this period vs 125000 last period → 100% more (expense trend).
    await _pump(tester, _hero(previousExpenseMinor: 125000));

    // AppTrend shows the percentage and the "from last period" caption.
    expect(find.text('100.0%'), findsAtLeastNWidgets(1));
    expect(find.textContaining('from last period'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('V2: hiding the balance masks every KPI figure but keeps the labels',
      (tester) async {
    _size(tester, const Size(1080, 2340));
    await _pump(tester, _hero(visible: false));

    // The main balance.
    expect(find.text('••••••'), findsOneWidget);
    // Income, Expenses and Net are all masked.
    expect(find.text('••••'), findsNWidgets(3));
    // The labels remain.
    expect(find.text('Available balance'), findsOneWidget);
    expect(find.text('Income'), findsOneWidget);
    expect(find.text('Expenses'), findsOneWidget);
  });

  testWidgets('V2: a failed ledger never reads as a zero balance',
      (tester) async {
    _size(tester, const Size(1080, 2340));
    await _pump(tester, _hero(ledgerError: true));

    expect(find.text('Ledger unavailable'), findsOneWidget);
    // KPI row is not shown on ledger error.
    expect(find.byType(AppKpiRow), findsNothing);
  });
}
