import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/utils/formatters.dart';
import 'package:spendsense/widgets/dashboard/balance_hero.dart';

TransactionModel _tx({
  required String id,
  required int amountMinor,
  TransactionType type = TransactionType.expense,
  String category = 'Food',
  DateTime? date,
  bool excluded = false,
}) {
  return TransactionModel(
    id: id,
    amountMinor: amountMinor,
    type: type,
    merchant: 'Test merchant',
    category: category,
    paymentMethod: 'UPI',
    date: date ?? DateTime(2026, 11, 10),
    time: '12:00',
    originalSms: '',
    isExcluded: excluded,
    source: 'Test',
  );
}

Future<void> _pumpHero(
  WidgetTester tester, {
  int incomeMinor = 500000,
  int expenseMinor = 125000,
  int? previousExpenseMinor,
}) async {
  var visible = true;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) {
              return BalanceHero(
                incomeMinor: incomeMinor,
                expenseMinor: expenseMinor,
                previousExpenseMinor: previousExpenseMinor,
                budgetMinor: 500000,
                periodLabel: '1 Nov – 30 Nov',
                periodEnd: DateTime(2026, 11, 30),
                visible: visible,
                onToggleVisibility: () => setState(() => visible = !visible),
                onSetBudget: () {},
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sms_scan_start_date': DateTime(2026, 10, 1).toIso8601String(),
    });
  });

  final period = DateTimeRange(
    start: DateTime(2026, 11, 1),
    end: DateTime(2026, 11, 30),
  );

  group('Spend Amount aggregation', () {
    test('uses the selected period expense total, not the all-time net', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(id: 'in-period', amountMinor: 100000),
        _tx(id: 'old-history', amountMinor: 900000, date: DateTime(2026, 8, 5)),
        _tx(id: 'income', amountMinor: 700000, type: TransactionType.income),
      ]);

      expect(provider.spendAmountForPeriod(period), 100000);
      expect(provider.availableBalance, -300000);
    });

    test('excludes income, transfers, and excluded rows', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(id: 'expense', amountMinor: 100000),
        _tx(id: 'transfer-title', amountMinor: 700000, category: 'Transfer'),
        _tx(id: 'transfer-lower', amountMinor: 200000, category: 'transfer'),
        _tx(
          id: 'transfer-plural',
          amountMinor: 150000,
          category: ' Transfers ',
        ),
        _tx(
          id: 'transfer-investment',
          amountMinor: 250000,
          category: 'Investment transfer',
        ),
        _tx(id: 'income', amountMinor: 900000, type: TransactionType.income),
        _tx(id: 'excluded', amountMinor: 300000, excluded: true),
      ]);

      expect(provider.spendAmountForPeriod(period), 100000);
    });

    test('empty history returns zero', () {
      final provider = TransactionProvider();
      provider.debugSeed([]);

      expect(provider.spendAmountForPeriod(period), 0);
    });

    test('canonical spend and instrument stats use the same transfer filter', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(id: 'expense', amountMinor: 100000),
        _tx(id: 'transfer', amountMinor: 500000, category: 'Transfer'),
      ]);

      final stats = provider.spendingStatsForPeriod(
        period,
        (t) => t.paymentMethod,
      );
      final statsTotal = stats.values.fold<int>(
        0,
        (sum, stat) => sum + stat.spent,
      );

      // The canonical figure, the alias and the roll-up agree by construction.
      expect(provider.spendAmountForPeriod(period), 100000);
      expect(provider.spendingTotalForPeriod(period), 100000);
      expect(statsTotal, 100000);
      expect(stats.values.fold<int>(0, (sum, stat) => sum + stat.count), 1);
    });

    test(
      'a negative expense reduces the period spend instead of being clamped',
      () {
        final provider = TransactionProvider();
        provider.debugSeed([
          _tx(id: 'spend', amountMinor: 100000),
          _tx(id: 'refund', amountMinor: -30000),
        ]);

        expect(provider.spendAmountForPeriod(period), 70000);
        expect(provider.spendingTotalForPeriod(period), 70000);
      },
    );

    test('the previous period applies the same transfer filter', () {
      final previous = DateTimeRange(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 31),
      );
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(
          id: 'previous-spend',
          amountMinor: 80000,
          date: DateTime(2026, 10, 10),
        ),
        _tx(
          id: 'previous-transfer',
          amountMinor: 500000,
          category: 'Transfer',
          date: DateTime(2026, 10, 11),
        ),
      ]);

      expect(provider.spendAmountForPeriod(previous), 80000);
      // The comparable window is what the hero's trend is built from.
      expect(provider.spendAmountForPeriod(period), 0);
    });
  });

  group('Budget surfaces', () {
    test('category budgets ignore transfers like the overall budget does', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(id: 'food', amountMinor: 100000),
        _tx(id: 'transfer', amountMinor: 500000, category: 'Transfer'),
      ]);

      final statuses = computeCategoryStatuses(
        {'Food': 200000, 'Transfer': 200000},
        provider.transactions,
        period,
      );

      expect(
        statuses.singleWhere((s) => s.category == 'Food').progress.spentMinor,
        100000,
      );
      // A transfer must not consume a budget, even one named "Transfer".
      expect(
        statuses
            .singleWhere((s) => s.category == 'Transfer')
            .progress
            .spentMinor,
        0,
      );
      // Per-category spent reconciles with the overall budget figure.
      final categoryTotal = statuses.fold<int>(
        0,
        (sum, s) => sum + s.progress.spentMinor,
      );
      expect(categoryTotal, provider.spendAmountForPeriod(period));
    });
  });

  group('Spend Amount card', () {
    testWidgets('shows Spend Amount and matches the Expenses KPI', (
      tester,
    ) async {
      await _pumpHero(tester);

      expect(find.text('Spend Amount'), findsOneWidget);
      expect(find.text('Available balance'), findsNothing);
      expect(find.text('Net across all transactions'), findsNothing);
      expect(find.text('1 Nov – 30 Nov'), findsWidgets);
      // Hero figure and the Expenses KPI use the same value.
      expect(find.text(Formatters.currency.format(125000)), findsNWidgets(2));
    });

    testWidgets('the eye toggle still masks the figure', (tester) async {
      await _pumpHero(tester);

      expect(find.text(Formatters.currency.format(125000)), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.text(Formatters.currency.format(125000)), findsNothing);
    });

    testWidgets('Net ignores an outgoing transfer', (tester) async {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(
          id: 'salary',
          amountMinor: 5000000,
          type: TransactionType.income,
          category: 'Income',
        ),
        _tx(id: 'food', amountMinor: 100000),
        _tx(id: 'move', amountMinor: 2000000, category: 'Transfer'),
      ]);

      // This is exactly what _HeroSection passes to the widget.
      await _pumpHero(
        tester,
        incomeMinor: provider.totalIncomeForPeriod(period),
        expenseMinor: provider.spendAmountForPeriod(period),
      );

      // ₹50,000 income − ₹1,000 spend = ₹49,000. The ₹20,000 transfer is not
      // spending, so it cannot push Net down.
      expect(find.text(Formatters.currency.format(4900000)), findsOneWidget);
      expect(find.text(Formatters.currency.format(2000000)), findsNothing);
    });

    testWidgets('shows the expense trend against the previous period', (
      tester,
    ) async {
      await _pumpHero(
        tester,
        expenseMinor: 125000,
        previousExpenseMinor: 100000,
      );

      // 125,000 vs 100,000 = 25.0% more spent, with no previous income to
      // compare, so exactly one trend is rendered.
      expect(find.text('25.0%'), findsOneWidget);
      expect(find.text('from last period'), findsOneWidget);
    });
  });
}
