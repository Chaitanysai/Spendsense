import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';

TransactionModel _tx({
  required String id,
  required int amountMinor,
  required DateTime date,
  TransactionType type = TransactionType.expense,
  String method = 'UPI',
  String? bank,
  String? account,
  String merchant = 'Shop',
  String category = 'Shopping',
  bool excluded = false,
  String? reference,
}) {
  return TransactionModel(
    id: id,
    amountMinor: amountMinor,
    type: type,
    merchant: merchant,
    category: category,
    paymentMethod: method,
    date: date,
    time: '10:00',
    originalSms: '',
    isExcluded: excluded,
    bank: bank,
    account: account,
    reference: reference,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TransactionProvider provider;
  final period = DateTimeRange(
    start: DateTime(2026, 10, 1),
    end: DateTime(2026, 10, 31, 23, 59),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    provider = TransactionProvider();
    await provider.ready;
  });

  tearDown(() => provider.dispose());

  void seedCanonicalFixture() {
    provider.debugSeed([
      // In period, two instruments.
      _tx(
          id: 'a',
          amountMinor: 10050,
          date: DateTime(2026, 10, 1),
          method: 'UPI',
          bank: 'HDFC',
          account: 'Savings'),
      // Last day of the period is included (inclusive boundary).
      _tx(
          id: 'b',
          amountMinor: 20000,
          date: DateTime(2026, 10, 31, 23, 30),
          method: 'Card',
          bank: 'ICICI',
          account: 'Credit card'),
      // Missing instrument attributes land in "Other".
      _tx(
          id: 'c',
          amountMinor: 5000,
          date: DateTime(2026, 10, 12),
          method: '',
          bank: null,
          account: '  '),
      // Same merchant and amount as 'c' but a distinct id: a real second row.
      _tx(
          id: 'd',
          amountMinor: 5000,
          date: DateTime(2026, 10, 20),
          method: '',
          merchant: 'Shop'),
      // Outside the period on both sides.
      _tx(id: 'before', amountMinor: 88800, date: DateTime(2026, 9, 30)),
      _tx(id: 'after', amountMinor: 99900, date: DateTime(2026, 11, 1)),
      // Income must never be counted as spending.
      _tx(
          id: 'income',
          amountMinor: 500000,
          date: DateTime(2026, 10, 5),
          type: TransactionType.income,
          method: 'UPI'),
      // Excluded by the user (the supported way to mark a transfer).
      _tx(
          id: 'excluded',
          amountMinor: 77700,
          date: DateTime(2026, 10, 10),
          excluded: true),
    ]);
  }

  group('canonical spending scope', () {
    test('counts only in-period, non-excluded expenses', () {
      seedCanonicalFixture();

      // 100.50 + 200.00 + 50.00 + 50.00
      expect(provider.spendingTotalForPeriod(period), 40050);
      // Income, excluded, and out-of-window rows are absent.
      expect(provider.expensesInPeriod(period).length, 4);
    });

    test('inclusive end boundary and exclusive next day', () {
      seedCanonicalFixture();

      final ids = provider.expensesInPeriod(period).map((t) => t.id).toSet();
      expect(ids, contains('b'));
      expect(ids, isNot(contains('after')));
      expect(ids, isNot(contains('before')));
    });

    test('Home and Instruments derive from the same total', () {
      seedCanonicalFixture();

      expect(provider.totalExpensesForPeriod(period),
          provider.spendingTotalForPeriod(period));
    });
  });

  group('instrument reconciliation', () {
    test('every grouping sums to the canonical total', () {
      seedCanonicalFixture();
      final total = provider.spendingTotalForPeriod(period);

      for (final keyOf in <String? Function(TransactionModel)>[
        (t) => t.paymentMethod,
        (t) => t.bank,
        (t) => t.account,
      ]) {
        final stats = provider.spendingStatsForPeriod(period, keyOf);
        final sum = stats.values.fold<int>(0, (s, e) => s + e.spent);
        expect(sum, total);
      }
    });

    test('income never appears in instrument spending', () {
      seedCanonicalFixture();
      final stats = provider.spendingStatsForPeriod(period, (t) => t.paymentMethod);

      // The 5,000.00 income row is on UPI; UPI must only carry spending.
      expect(stats['UPI']!.spent, 10050);
      expect(stats['UPI']!.received, 0);
    });

    test('blank, null and "Others" collapse into one Other bucket', () {
      provider.debugSeed([
        _tx(id: '1', amountMinor: 100, date: DateTime(2026, 10, 2), method: ''),
        _tx(
            id: '2',
            amountMinor: 200,
            date: DateTime(2026, 10, 3),
            bank: null),
        _tx(
            id: '3',
            amountMinor: 300,
            date: DateTime(2026, 10, 4),
            bank: 'Others'),
      ]);

      final byBank = provider.spendingStatsForPeriod(period, (t) => t.bank);
      expect(byBank.keys, ['Other']);
      expect(byBank['Other']!.spent, 600);
      expect(byBank['Other']!.count, 3);
    });

    test('the all-time roll-up keeps income and is a different scope', () {
      seedCanonicalFixture();

      final allTime = provider.statsBy((t) => t.paymentMethod);
      // Deliberately different from the period total: this is the old,
      // all-time figure the Instruments screen used to display.
      expect(allTime.values.fold<int>(0, (s, e) => s + e.spent),
          isNot(provider.spendingTotalForPeriod(period)));
      expect(allTime['UPI']!.received, 500000);
    });

    test('shares are computed from the scoped denominator', () {
      seedCanonicalFixture();
      final stats = provider.spendingStatsForPeriod(period, (t) => t.paymentMethod);
      final total = provider.spendingTotalForPeriod(period);

      final shares = stats.values.map((s) => s.spent / total);
      // No NaN, no negative, and the sum is 1 when every row is bucketed.
      expect(shares.every((s) => s >= 0 && s <= 1), isTrue);
      expect(shares.fold<double>(0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });
  });
}
