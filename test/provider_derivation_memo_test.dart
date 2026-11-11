import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';

/// Derivation-memo contract for TransactionProvider (P1.1).
///
/// The memo must be invisible except for speed: same values as the naive
/// computation, invalidated the moment the ledger changes, and never serving
/// rows across a ledger version boundary.

TransactionModel _tx(
  String id,
  int amountMinor,
  DateTime date, {
  bool excluded = false,
  TransactionType type = TransactionType.expense,
  String method = 'UPI',
}) {
  return TransactionModel(
    id: id,
    amountMinor: amountMinor,
    type: type,
    merchant: 'Merchant $id',
    category: 'Food',
    paymentMethod: method,
    date: date,
    time: '10:00',
    originalSms: '',
    isExcluded: excluded,
  );
}

void main() {
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

  group('tracked lists', () {
    test('are cached per ledger version and invalidated by every mutation',
        () async {
      provider.debugSeed([
        _tx('a', 100, DateTime(2026, 10, 1)),
        _tx('b', 200, DateTime(2026, 10, 2), excluded: true),
      ]);

      final first = provider.trackedTransactions;
      expect(identical(first, provider.trackedTransactions), isTrue,
          reason: 'repeated reads without a change must hit the cache');
      expect(identical(provider.trackedExpenses, provider.trackedExpenses),
          isTrue);
      expect(first.map((t) => t.id), ['a']);
      expect(provider.trackedExpenses.map((t) => t.id), ['a']);

      // Every mutation kind replaces the ledger list and must invalidate.
      await provider.addTransaction(
          _tx('c', 300, DateTime(2026, 10, 3)) as dynamic);
      expect(identical(first, provider.trackedTransactions), isFalse);
      // The ledger keeps date-descending order.
      expect(provider.trackedTransactions.map((t) => t.id), ['c', 'a']);

      final afterAdd = provider.trackedExpenses;
      await provider.toggleExclude('a');
      expect(identical(afterAdd, provider.trackedExpenses), isFalse);
      expect(provider.trackedExpenses.map((t) => t.id), ['c']);

      final afterExclude = provider.trackedTransactions;
      await provider.deleteTransactionsByIds({'c'});
      expect(identical(afterExclude, provider.trackedTransactions), isFalse);
      expect(provider.trackedTransactions, isEmpty);
    });

    test('contents always equal the naive computation', () async {
      provider.debugSeed([
        _tx('a', 100, DateTime(2026, 10, 1)),
        _tx('b', 200, DateTime(2026, 10, 2),
            excluded: true, type: TransactionType.income),
        _tx('c', 300, DateTime(2026, 10, 3), type: TransactionType.income),
      ]);

      final naiveTracked =
          provider.transactions.where((t) => !t.isExcluded).toList();
      expect(provider.trackedTransactions, naiveTracked);

      final naiveExpenses = provider.transactions
          .where((t) =>
              !t.isExcluded && t.type == TransactionType.expense)
          .toList();
      expect(provider.trackedExpenses, naiveExpenses);
    });

    test('an empty ledger that fills later does not serve the stale empty '
        'lists to either getter', () async {
      // Regression: the two caches must invalidate independently. If they
      // shared one source marker, refreshing trackedTransactions for a newer
      // ledger made trackedExpenses look current while still empty — the
      // "Last 7 days" card then kept its empty message after data landed.
      provider.debugSeed(const []);
      expect(provider.trackedTransactions, isEmpty);
      expect(provider.trackedExpenses, isEmpty);

      provider.debugSeed([_tx('late', 100, DateTime(2026, 10, 1))]);
      expect(provider.trackedTransactions.map((t) => t.id), ['late']);
      expect(provider.trackedExpenses.map((t) => t.id), ['late'],
          reason: 'trackedExpenses must not serve the stale empty list');
    });

    test('the derived lists follow an exclusion change', () async {
      // Regression: setExclusionForIds and restoreExclusionStates used to
      // mutate the ledger list in place, which kept its identity and made the
      // identity-keyed caches (this memo and the screens) serve the pre-change
      // rows. `totalTrackedExpenses` then reported the excluded amount.
      provider.debugSeed([
        _tx('keep', 50000, DateTime(2026, 10, 1)),
        _tx('drop', 100000, DateTime(2026, 10, 2)),
      ]);
      expect(provider.totalTrackedExpenses, 150000);

      final changed = await provider.setExclusionForIds({'drop'}, true);
      expect(changed, 1);
      expect(provider.totalTrackedExpenses, 50000,
          reason: 'the memoized expense list must reflect the exclusion');
      expect(provider.trackedExpenses.map((t) => t.id), ['keep']);

      final restored = await provider.restoreExclusionStates({'drop': false});
      expect(restored, 1);
      expect(provider.totalTrackedExpenses, 150000);
    });
  });

  group('expensesInPeriod', () {
    test('is cached per period and invalidated by ledger changes', () async {
      provider.debugSeed([
        _tx('a', 100, DateTime(2026, 10, 1)),
        _tx('b', 200, DateTime(2026, 10, 31, 23, 30)),
        _tx('c', 300, DateTime(2026, 11, 1)),
        _tx('d', 400, DateTime(2026, 10, 15), excluded: true),
        _tx('e', 500, DateTime(2026, 10, 15), type: TransactionType.income),
      ]);

      final first = provider.expensesInPeriod(period);
      expect(identical(first, provider.expensesInPeriod(period)), isTrue,
          reason: 'same period on the same ledger must hit the cache');
      // Boundary semantics unchanged: inclusive start, inclusive end day,
      // excluded rows and income never count.
      expect(first.map((t) => t.id), ['a', 'b']);

      // A different period is a different cache entry.
      final november = DateTimeRange(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 30, 23, 59),
      );
      expect(provider.expensesInPeriod(november).map((t) => t.id), ['c']);

      // Mutations invalidate.
      await provider.addTransaction(_tx('f', 600, DateTime(2026, 10, 20)));
      final second = provider.expensesInPeriod(period);
      expect(identical(first, second), isFalse);
      // Date-descending ledger order.
      expect(second.map((t) => t.id), ['b', 'f', 'a']);
    });

    test('null period means the current calendar month and is memoized per '
        'month key', () async {
      final now = DateTime.now();
      provider.debugSeed([
        _tx('this-month', 100, DateTime(now.year, now.month, 5)),
        _tx('last-month', 200,
            DateTime(now.year, now.month == 1 ? 12 : now.month - 1, 5)),
      ]);

      final first = provider.expensesInPeriod(null);
      expect(identical(first, provider.expensesInPeriod(null)), isTrue);
      expect(first.map((t) => t.id), ['this-month']);
    });

    test('spending totals reconcile with the memoized rows', () async {
      provider.debugSeed([
        _tx('a', 10050, DateTime(2026, 10, 1), method: 'UPI'),
        _tx('b', 20000, DateTime(2026, 10, 31, 23, 30), method: 'Card'),
        _tx('c', 5000, DateTime(2026, 10, 12), method: ''),
        _tx('excluded', 999, DateTime(2026, 10, 12), excluded: true),
      ]);

      final rows = provider.expensesInPeriod(period).toList();
      expect(provider.spendingTotalForPeriod(period),
          rows.fold<int>(0, (sum, t) => sum + t.amountMinor));
    });
  });
}
