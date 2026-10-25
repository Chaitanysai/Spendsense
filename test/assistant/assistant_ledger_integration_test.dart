import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exclusion and deletion update every dependent canonical total',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = TransactionProvider();
    await provider.ready;
    addTearDown(provider.dispose);

    provider.debugSeed([
      tx(
        id: 'groww',
        amountMinor: 100000,
        date: DateTime(2026, 10, 1),
        merchant: 'Groww',
        category: 'Investment',
      ),
      tx(
        id: 'food',
        amountMinor: 50000,
        date: DateTime(2026, 10, 2),
        merchant: 'Swiggy',
        category: 'Food',
      ),
      tx(
        id: 'salary',
        amountMinor: 1000000,
        date: DateTime(2026, 10, 3),
        merchant: 'Employer',
        category: 'Income',
        type: TransactionType.income,
      ),
    ]);

    final october = DateTimeRange(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 31),
    );

    expect(provider.totalTrackedExpenses, 150000);
    expect(provider.totalTrackedIncome, 1000000);
    expect(provider.spendingTotalForPeriod(october), 150000);
    expect(
      provider
          .spendingStatsForPeriod(
            october,
            (transaction) => transaction.category,
          )
          .values
          .fold<int>(0, (sum, stat) => sum + stat.spent),
      150000,
    );

    const budgets = {'Investment': 1000000, 'Food': 40000};
    final budgetBefore = computeCategoryStatuses(
      budgets,
      provider.transactions,
      october,
    );
    expect(
      budgetBefore
          .singleWhere((s) => s.category == 'Investment')
          .progress
          .spentMinor,
      100000,
    );

    var notifications = 0;
    provider.addListener(() => notifications++);

    final excluded = await provider.setExclusionForIds({'groww'}, true);
    expect(excluded, 1);
    expect(provider.totalTrackedExpenses, 50000);
    expect(provider.spendingTotalForPeriod(october), 50000);
    expect(provider.availableBalance, 950000);
    final stats = provider.spendingStatsForPeriod(
      october,
      (transaction) => transaction.category,
    );
    expect(stats.keys, isNot(contains('Investment')));
    expect(stats['Food']!.spent, 50000);
    expect(notifications, greaterThan(0));

    final budgetAfter = computeCategoryStatuses(
      budgets,
      provider.transactions,
      october,
    );
    expect(
      budgetAfter
          .singleWhere((s) => s.category == 'Investment')
          .progress
          .spentMinor,
      0,
    );
    expect(
      budgetAfter.singleWhere((s) => s.category == 'Food').progress.spentMinor,
      50000,
    );

    final restored = await provider.setExclusionForIds({'groww'}, false);
    expect(restored, 1);
    expect(provider.totalTrackedExpenses, 150000);

    final removed = await provider.deleteTransactionsByIds({'groww'});
    expect(removed, hasLength(1));
    expect(provider.transactions, hasLength(2));
    expect(provider.totalTrackedExpenses, 50000);

    await provider.restoreTransactions(removed);
    expect(provider.transactions, hasLength(3));
    expect(provider.totalTrackedExpenses, 150000);
    expect(
      provider.transactions.singleWhere((t) => t.id == 'groww').isExcluded,
      false,
    );
  });

  test('exclusion, deletion and undo preserve and advance sync metadata',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = TransactionProvider();
    await provider.ready;
    addTearDown(provider.dispose);

    provider.debugSeed([
      tx(
        id: 'sync-target',
        amountMinor: 100000,
        date: DateTime(2026, 10, 1),
        merchant: 'Groww',
        category: 'Investment',
      ),
      tx(
        id: 'sync-other',
        amountMinor: 50000,
        date: DateTime(2026, 10, 2),
        merchant: 'Swiggy',
        category: 'Food',
      ),
    ]);

    final changed = await provider.setExclusionForIds({'sync-target'}, true);
    expect(changed, 1);
    final excluded =
        provider.transactions.singleWhere((t) => t.id == 'sync-target');
    expect(excluded.syncId, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(excluded.updatedAtMs, greaterThan(0));
    final firstSyncId = excluded.syncId;
    final firstUpdatedAt = excluded.updatedAtMs;

    final noChange = await provider.setExclusionForIds({'sync-target'}, true);
    expect(noChange, 0);
    expect(
      provider.transactions.singleWhere((t) => t.id == 'sync-target').syncId,
      firstSyncId,
    );

    final removed = await provider.deleteTransactionsByIds({'sync-target'});
    expect(removed, hasLength(1));
    expect(removed.single.syncId, firstSyncId);
    expect(
        provider.transactions.map((t) => t.id), isNot(contains('sync-target')));

    await provider.restoreTransactions(removed);
    final restored =
        provider.transactions.singleWhere((t) => t.id == 'sync-target');
    expect(restored.syncId, firstSyncId);
    expect(restored.updatedAtMs, greaterThan(firstUpdatedAt));
    expect(restored.isExcluded, true);
  });
}
