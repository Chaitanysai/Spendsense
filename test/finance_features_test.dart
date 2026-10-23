import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/models/recurring_plan.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/services/financial_summary.dart';
import 'package:spendsense/services/spending_insights.dart';
import 'package:spendsense/utils/transaction_filter.dart';

TransactionModel tx(
  String id,
  int amountMinor,
  DateTime date, {
  TransactionType type = TransactionType.expense,
  String merchant = 'Merchant',
  String category = 'Food',
  bool excluded = false,
}) =>
    TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: 'SECRET SMS BODY',
      isExcluded: excluded,
      account: 'XX1234',
      reference: 'REF999',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransactionFilter', () {
    final all = [
      tx('a', 23950, DateTime(2026, 10, 5), merchant: 'Swiggy'),
      tx('b', 100000, DateTime(2026, 10, 10),
          merchant: 'Salary', category: 'Income', type: TransactionType.income),
      tx('c', 5000, DateTime(2026, 9, 30),
          merchant: 'Uber', category: 'Travel'),
      tx('d', 123456, DateTime(2026, 10, 20),
          merchant: 'Rent', category: 'Bills'),
    ];

    test('no filter returns everything and is inactive', () {
      expect(TransactionFilter.none.isActive, isFalse);
      expect(TransactionFilter.none.apply(all), hasLength(4));
    });

    test('searches merchant and category, case-insensitively', () {
      expect(const TransactionFilter(query: 'swig').apply(all).single.id, 'a');
      expect(
          const TransactionFilter(query: 'TRAVEL').apply(all).single.id, 'c');
    });

    test('searches amounts in rupees, with or without symbols and commas', () {
      expect(const TransactionFilter(query: '239.5').apply(all).single.id, 'a');
      expect(
          const TransactionFilter(query: '₹239.50').apply(all).single.id, 'a');
      expect(
          const TransactionFilter(query: '1,234.56').apply(all).single.id, 'd');
      // Raw paise digits no longer match by accident.
      expect(const TransactionFilter(query: '23950').apply(all), isEmpty);
    });

    test('amount bounds are exact, inclusive, integer paise', () {
      final f = const TransactionFilter(
          minAmountMinor: 23950, maxAmountMinor: 100000);
      expect(f.apply(all).map((t) => t.id).toSet(), {'a', 'b'});
      expect(
          const TransactionFilter(minAmountMinor: 23951)
              .apply(all)
              .map((t) => t.id)
              .toSet(),
          {'b', 'd'});
      expect(
          const TransactionFilter(maxAmountMinor: 23949).apply(all).single.id,
          'c');
    });

    test('type, category and inclusive date range combine', () {
      final range = DateTimeRange(
          start: DateTime(2026, 10, 5), end: DateTime(2026, 10, 10));
      final f = TransactionFilter(dateRange: range);
      expect(f.apply(all).map((t) => t.id).toSet(), {'a', 'b'});
      expect(
          TransactionFilter(dateRange: range, type: TransactionType.income)
              .apply(all)
              .single
              .id,
          'b');
      expect(
          const TransactionFilter(category: 'Bills').apply(all).single.id, 'd');
    });

    test('clearing filters restores the complete list', () {
      final narrowed = const TransactionFilter(
        query: 'x',
        category: 'Food',
        type: TransactionType.expense,
        minAmountMinor: 1,
      );
      expect(narrowed.isActive, isTrue);
      expect(narrowed.apply(all), isEmpty);
      expect(TransactionFilter.none.apply(all), hasLength(all.length));
      final cleared = narrowed.copyWith(
        query: '',
        clearCategory: true,
        clearType: true,
        clearAmountRange: true,
      );
      expect(cleared.isActive, isFalse);
      expect(cleared.apply(all), hasLength(all.length));
    });
  });

  group('SpendingInsights', () {
    // Wednesday 14 Oct 2026.
    final now = DateTime(2026, 10, 14, 15);

    test('week-over-week compares the same elapsed days', () {
      final data = [
        tx('mon', 1000, DateTime(2026, 10, 12)),
        tx('tue', 2000, DateTime(2026, 10, 13)),
        tx('wed', 3000, DateTime(2026, 10, 14)),
        tx('pmon', 2000, DateTime(2026, 10, 5)),
        tx('ptue', 1000, DateTime(2026, 10, 6)),
        tx('pwed', 3000, DateTime(2026, 10, 7)),
        // After last Wednesday: outside the comparable window.
        tx('pthu', 99900, DateTime(2026, 10, 8)),
      ];
      final c = SpendingInsights.weekOverWeek(data, now);
      expect(c.currentMinor, 6000);
      expect(c.previousMinor, 6000);
      expect(c.changeTenthsOfPercent, 0);
    });

    test('month-over-month, rounding and no previous period', () {
      final data = [
        tx('a', 15000, DateTime(2026, 10, 3)),
        tx('b', 10000, DateTime(2026, 9, 3)),
        tx('c', 5000, DateTime(2026, 9, 20)), // beyond the 14th: excluded
      ];
      final c = SpendingInsights.monthOverMonth(data, now);
      expect(c.currentMinor, 15000);
      expect(c.previousMinor, 10000);
      expect(c.changeTenthsOfPercent, 500); // +50.0%

      final tiny = SpendingInsights.monthOverMonth([
        tx('x', 10001, DateTime(2026, 10, 3)),
        tx('y', 30000, DateTime(2026, 9, 3)),
      ], now);
      expect(tiny.changeTenthsOfPercent, -667); // -66.67% -> -66.7%

      final none = SpendingInsights.monthOverMonth(
          [tx('z', 100, DateTime(2026, 10, 2))], now);
      expect(none.hasPrevious, isFalse);
      expect(none.changeTenthsOfPercent, isNull);
    });

    test('month comparison clamps to a shorter previous month', () {
      final c =
          SpendingInsights.monthOverMonth(const [], DateTime(2026, 3, 31));
      expect(c.previous.end, DateTime(2026, 2, 28));
    });

    test('excluded and income rows never count as spending', () {
      final data = [
        tx('a', 1000, DateTime(2026, 10, 3)),
        tx('b', 9999, DateTime(2026, 10, 3), excluded: true),
        tx('c', 5000, DateTime(2026, 10, 3), type: TransactionType.income),
      ];
      expect(SpendingInsights.monthOverMonth(data, now).currentMinor, 1000);
    });

    test('category breakdown shares are integer tenths and ordered', () {
      final data = [
        tx('a', 3000, DateTime(2026, 10, 3), category: 'Food'),
        tx('b', 1000, DateTime(2026, 10, 4), category: 'Fuel'),
        tx('c', 2000, DateTime(2026, 10, 5), category: 'Food'),
      ];
      final shares = SpendingInsights.categoryBreakdown(
          data,
          DateTimeRange(
              start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31)));
      expect(shares.map((s) => s.category), ['Food', 'Fuel']);
      expect(shares.first.amountMinor, 5000);
      expect(shares.first.shareTenths, 833); // 83.3%
      expect(shares.last.shareTenths, 167);
    });

    test('largest expenses, trend and empty data', () {
      final range = DateTimeRange(
          start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31));
      final data = [
        for (var i = 1; i <= 7; i++) tx('t$i', i * 1000, DateTime(2026, 10, i)),
        tx('old', 777, DateTime(2026, 8, 3)),
      ];
      final top = SpendingInsights.largestExpenses(data, range, limit: 3);
      expect(top.map((t) => t.amountMinor), [7000, 6000, 5000]);

      final trend = SpendingInsights.monthlyTrend(data, now);
      expect(trend, hasLength(6));
      expect(trend.last.isPartial, isTrue);
      expect(trend.last.amountMinor, 28000);
      expect(trend.firstWhere((m) => m.month.month == 8).amountMinor, 777);

      expect(SpendingInsights.largestExpenses(const [], range), isEmpty);
      expect(SpendingInsights.categoryBreakdown(const [], range), isEmpty);
      expect(
          SpendingInsights.monthlyTrend(const [], now)
              .every((m) => m.amountMinor == 0),
          isTrue);
    });
  });

  group('FinancialSummary', () {
    final range = DateTimeRange(
        start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31));

    test('income, spend, net flow and budget status in integer paise', () {
      final s = FinancialSummary.compute(
        periodLabel: 'October',
        range: range,
        monthlyBudgetMinor: 100000,
        categoryBudgets: const {'Food': 5000, 'Fuel': 90000},
        transactions: [
          tx('i', 500000, DateTime(2026, 10, 1),
              type: TransactionType.income, category: 'Salary'),
          tx('a', 23950, DateTime(2026, 10, 3), category: 'Food'),
          tx('b', 90000, DateTime(2026, 10, 4), category: 'Fuel'),
          tx('x', 777777, DateTime(2026, 10, 5), excluded: true),
          tx('out', 55555, DateTime(2026, 9, 30)),
        ],
      );
      expect(s.incomeMinor, 500000);
      expect(s.expenseMinor, 113950);
      expect(s.netMinor, 386050);
      expect(s.transactionCount, 3);
      expect(s.budget.isOver, isTrue);
      expect(s.budget.overMinor, 13950);
      expect(s.overBudgetCategories, ['Food']);
      expect(s.topCategories.first.category, 'Fuel');
    });

    test('net can be negative and empty periods are valid', () {
      final s = FinancialSummary.compute(
        periodLabel: 'x',
        range: range,
        monthlyBudgetMinor: 0,
        transactions: [tx('a', 100, DateTime(2026, 10, 3))],
      );
      expect(s.netMinor, -100);
      final empty = FinancialSummary.compute(
          periodLabel: 'x',
          range: range,
          monthlyBudgetMinor: 0,
          transactions: const []);
      expect(empty.netMinor, 0);
      expect(empty.topCategories, isEmpty);
    });

    test('the saved text never contains merchants, accounts or SMS text', () {
      final text = FinancialSummary.compute(
        periodLabel: 'Oct',
        range: range,
        monthlyBudgetMinor: 100000,
        transactions: [
          tx('a', 23950, DateTime(2026, 10, 3), merchant: 'Swiggy')
        ],
      ).toText();
      expect(text, contains('₹239.50'));
      for (final secret in ['Swiggy', 'SECRET SMS BODY', 'XX1234', 'REF999']) {
        expect(text, isNot(contains(secret)));
      }
    });
  });

  group('RecurringPlan', () {
    test('monthly equivalents round to the nearest paise', () {
      expect(PlanFrequency.monthly.monthlyEquivalentMinor(10000), 10000);
      expect(
          PlanFrequency.weekly.monthlyEquivalentMinor(10000), 43333); // 433.33
      expect(PlanFrequency.weekly.monthlyEquivalentMinor(1), 4); // 4.33 -> 4
      expect(PlanFrequency.biWeekly.monthlyEquivalentMinor(10000),
          21667); // 216.67
      expect(PlanFrequency.quarterly.monthlyEquivalentMinor(10000), 3333);
      expect(PlanFrequency.quarterly.monthlyEquivalentMinor(10001),
          3334); // .67 up
      expect(PlanFrequency.yearly.monthlyEquivalentMinor(120000), 10000);
      expect(PlanFrequency.yearly.monthlyEquivalentMinor(6), 1); // .5 rounds up
    });

    RecurringPlan plan(DateTime due, PlanFrequency f) => RecurringPlan.create(
        id: 'p',
        title: 'Rent',
        category: 'Bills',
        amountMinor: 100,
        frequency: f,
        nextDue: due);

    test('month-end anchor returns to the 31st after a short month', () {
      var p = plan(DateTime(2026, 1, 31), PlanFrequency.monthly);
      p = p.advanced();
      expect(p.nextDue, DateTime(2026, 2, 28));
      p = p.advanced();
      expect(p.nextDue, DateTime(2026, 3, 31));
      expect(
          plan(DateTime(2024, 2, 29), PlanFrequency.yearly).advanced().nextDue,
          DateTime(2025, 2, 28));
    });

    test('weekly, bi-weekly and quarterly schedules', () {
      expect(
          plan(DateTime(2026, 12, 28), PlanFrequency.weekly).advanced().nextDue,
          DateTime(2027, 1, 4));
      expect(
          plan(DateTime(2026, 10, 1), PlanFrequency.biWeekly)
              .advanced()
              .nextDue,
          DateTime(2026, 10, 15));
      expect(
          plan(DateTime(2026, 11, 30), PlanFrequency.quarterly)
              .advanced()
              .nextDue,
          DateTime(2027, 2, 28));
    });

    test('rolled forward lands on or after today and terminates', () {
      final rolled = plan(DateTime(2026, 1, 15), PlanFrequency.monthly)
          .rolledForwardTo(DateTime(2026, 10, 14));
      expect(rolled.nextDue, DateTime(2026, 10, 15));
    });

    test('daysUntilDue counts calendar days, negative when overdue', () {
      final p = plan(DateTime(2026, 10, 20), PlanFrequency.monthly);
      expect(p.daysUntilDue(DateTime(2026, 10, 14, 23, 59)), 6);
      expect(p.daysUntilDue(DateTime(2026, 10, 20)), 0);
      expect(p.daysUntilDue(DateTime(2026, 10, 22)), -2);
    });

    test('strict decoding rejects bad data instead of guessing', () {
      final good = plan(DateTime(2026, 10, 20), PlanFrequency.monthly).toJson();
      expect(RecurringPlan.fromJson(good).amountMinor, 100);
      for (final bad in [
        {...good, 'amountMinor': 12.5},
        {...good, 'amountMinor': 0},
        {...good, 'frequency': 'fortnightly'},
        {...good, 'nextDue': 'soon'},
        {...good, 'title': ''},
        {...good}..remove('id'),
      ]) {
        expect(() => RecurringPlan.fromJson(bad), throwsFormatException);
      }
    });
  });

  group('PlannerProvider (encrypted storage)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<PlannerProvider> open() async {
      final p = PlannerProvider();
      await p.ready;
      return p;
    }

    test('budgets and plans persist, and are never stored as plaintext',
        () async {
      final first = await open();
      await first.setCategoryBudget('Food', 500050);
      await first.addPlan(RecurringPlan.create(
        id: 'plan_1',
        title: 'Netflix Subscription',
        category: 'Entertainment',
        amountMinor: 64900,
        frequency: PlanFrequency.monthly,
        nextDue: DateTime(2026, 11, 3),
      ));

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getKeys().map(prefs.get).join('|');
      for (final secret in [
        'Food',
        '500050',
        'Netflix',
        '64900',
        'Entertainment'
      ]) {
        expect(stored, isNot(contains(secret)),
            reason: 'plaintext leak: $secret');
      }
      expect(stored, contains('AES-256-GCM'));

      final second = await open();
      expect(second.hasLoadError, isFalse);
      expect(second.categoryBudgets, {'Food': 500050});
      expect(second.plans.single.title, 'Netflix Subscription');
      expect(second.plannedMonthlyCommitmentMinor, 64900);
    });

    test(
        'tampered ciphertext fails closed: error set, writes refused, data kept',
        () async {
      final first = await open();
      await first.setCategoryBudget('Food', 10000);
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getKeys().firstWhere((k) => k.contains('budgets'));
      final envelope =
          jsonDecode(prefs.getString(key)!) as Map<String, dynamic>;
      final bytes = base64Url.decode(envelope['ciphertext'] as String);
      bytes[0] ^= 0x01;
      envelope['ciphertext'] = base64Url.encode(bytes);
      final tampered = jsonEncode(envelope);
      await prefs.setString(key, tampered);

      final second = await open();
      expect(second.hasLoadError, isTrue);
      expect(second.categoryBudgets, isEmpty);
      await expectLater(
          second.setCategoryBudget('Fuel', 5000), throwsA(isA<StateError>()));
      // The unreadable record was not overwritten.
      expect(prefs.getString(key), tampered);
    });

    test('a record moved to another slot is rejected (record binding)',
        () async {
      final first = await open();
      await first.setCategoryBudget('Food', 10000);
      final prefs = await SharedPreferences.getInstance();
      final budgetsKey =
          prefs.getKeys().firstWhere((k) => k.contains('budgets'));
      final plansKey =
          budgetsKey.replaceAll('category_budgets', 'recurring_plans');
      await prefs.setString(plansKey, prefs.getString(budgetsKey)!);
      final second = await open();
      expect(second.hasLoadError, isTrue);
    });

    test('invalid budgets and plans are rejected and change nothing', () async {
      final p = await open();
      await expectLater(p.setCategoryBudget('Food', 0), throwsArgumentError);
      await expectLater(p.setCategoryBudget('  ', 100), throwsArgumentError);
      await expectLater(
          p.setCategoryBudget('Food', PlannerProvider.maxBudgetMinor + 1),
          throwsArgumentError);
      expect(p.categoryBudgets, isEmpty);
    });

    test('marking a plan paid only reschedules it', () async {
      final p = await open();
      await p.addPlan(RecurringPlan.create(
        id: 'rent',
        title: 'Rent',
        category: 'Bills',
        amountMinor: 1500000,
        frequency: PlanFrequency.monthly,
        nextDue: DateTime(2026, 10, 31),
      ));
      await p.markPlanPaid('rent');
      final plan = p.plans.single;
      expect(plan.nextDue, DateTime(2026, 11, 30));
      expect(plan.amountMinor, 1500000);
      await p.removePlan('rent');
      expect(p.plans, isEmpty);
    });

    test('upcoming order, due-soon window and thresholds', () async {
      final p = await open();
      for (final (id, day) in [('b', 20), ('a', 5), ('c', 30)]) {
        await p.addPlan(RecurringPlan.create(
          id: id,
          title: id,
          category: 'Bills',
          amountMinor: 100,
          frequency: PlanFrequency.monthly,
          nextDue: DateTime(2026, 10, day),
        ));
      }
      expect(p.upcomingPlans.map((e) => e.id), ['a', 'b', 'c']);
      expect(p.dueWithin(DateTime(2026, 10, 14), 5).map((e) => e.id), ['a']);
      expect(
          p.dueWithin(DateTime(2026, 10, 14), 7).map((e) => e.id), ['a', 'b']);
      expect(
          p.dueWithin(DateTime(2026, 10, 14), 10).map((e) => e.id), ['a', 'b']);

      await p.setThresholds([100, 80, 80, 33]);
      expect(p.thresholds, [80, 100]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('budget_alert_thresholds'), ['80', '100']);
      expect((await open()).thresholds, [80, 100]);
    });

    test('category statuses use the period, skip excluded, include zero spend',
        () {
      final period = DateTimeRange(
          start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31));
      final statuses = computeCategoryStatuses(
        const {'Food': 10000, 'Fuel': 5000, 'Travel': 8000},
        [
          tx('a', 12000, DateTime(2026, 10, 2), category: 'Food'),
          tx('b', 2500, DateTime(2026, 10, 3), category: 'Fuel'),
          tx('c', 9999, DateTime(2026, 10, 3),
              category: 'Fuel', excluded: true),
          tx('d', 7000, DateTime(2026, 9, 30), category: 'Travel'),
          tx('e', 4000, DateTime(2026, 10, 4),
              category: 'Food', type: TransactionType.income),
        ],
        period,
      );
      expect(statuses.map((s) => s.category), ['Food', 'Fuel', 'Travel']);
      expect(statuses[0].progress.isOver, isTrue);
      expect(statuses[0].progress.percentUsed, 120);
      expect(statuses[1].progress.spentMinor, 2500);
      expect(statuses[2].progress.spentMinor, 0);
    });
  });
}
