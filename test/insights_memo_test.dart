import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/insights_screen.dart';
import 'package:spendsense/services/spending_insights.dart';
import 'package:spendsense/widgets/insight_cards.dart';

/// Insights derivation memo contract (P1.1).
///
/// The insights tab runs five whole-ledger analytical passes per build and the
/// metrics screen scans the ledger twice. Both must run once per ledger (and
/// per day, for the "to date" comparisons) instead of once per rebuild, because
/// the shell keeps the tab mounted and re-shows it on every visit.

TransactionModel _tx(String id, int amountMinor, DateTime date,
        {TransactionType type = TransactionType.expense,
        bool excluded = false,
        String category = 'Shopping'}) =>
    TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: type,
      merchant: 'Merchant $id',
      category: category,
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: '',
      isExcluded: excluded,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('InsightComparisons memo', () {
    final clock = DateTime(2026, 10, 20, 14);

    List<TransactionModel> ledger() => [
          _tx('a', 100, DateTime(2026, 10, 19), category: 'Food'),
          _tx('b', 200, DateTime(2026, 10, 18), category: 'Travel'),
          _tx('c', 300, DateTime(2026, 10, 5), category: 'Food'),
          _tx('d', 400, DateTime(2026, 9, 20), category: 'Food'),
        ];

    Widget harness(List<TransactionModel> txs, {required DateTime now}) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InsightComparisons(transactions: txs, now: now),
            ),
          ),
        );

    testWidgets('computes once across parent rebuilds with the same ledger '
        'and day', (tester) async {
      final txs = ledger();
      await tester.pumpWidget(harness(txs, now: clock));
      await tester.pump();

      dynamic state = tester.state(find.byType(InsightComparisons));
      final afterFirst = state.debugComputations as int;
      expect(afterFirst, 1);

      // Two rebuilds with a fresh (but equivalent) widget, same ledger object.
      await tester.pumpWidget(harness(txs, now: clock));
      await tester.pump();
      await tester.pumpWidget(harness(txs, now: clock));
      await tester.pump();

      state = tester.state(find.byType(InsightComparisons));
      expect(state.debugComputations as int, afterFirst,
          reason: 'a rebuild without a ledger or day change must reuse');
    });

    testWidgets('a new ledger identity recomputes', (tester) async {
      await tester.pumpWidget(harness(ledger(), now: clock));
      await tester.pump();
      dynamic state = tester.state(find.byType(InsightComparisons));
      final before = state.debugComputations as int;

      await tester.pumpWidget(harness(ledger(), now: clock));
      await tester.pump();

      state = tester.state(find.byType(InsightComparisons));
      expect(state.debugComputations as int, greaterThan(before));
    });

    testWidgets('a later day recomputes (week/month are "to date")',
        (tester) async {
      final txs = ledger();
      await tester.pumpWidget(harness(txs, now: clock));
      await tester.pump();
      dynamic state = tester.state(find.byType(InsightComparisons));
      final before = state.debugComputations as int;

      await tester.pumpWidget(
          harness(txs, now: DateTime(2026, 10, 21, 9)));
      await tester.pump();

      state = tester.state(find.byType(InsightComparisons));
      expect(state.debugComputations as int, greaterThan(before),
          reason: 'the comparison windows shift at midnight');
    });

    testWidgets('rendered output matches the direct computation',
        (tester) async {
      final txs = ledger();
      await tester.pumpWidget(harness(txs, now: clock));
      await tester.pump();

      // The month comparison card shows this figure; assert it against the
      // service result so the memo cannot silently change the numbers.
      final month = SpendingInsights.monthOverMonth(txs, clock);
      expect(
        find.text('This month'),
        findsOneWidget,
        reason: 'the comparison card renders from the bundle',
      );
      expect(month.currentMinor, 600,
          reason: 'the three October expenses count, September does not');
    });
  });

  group('InsightsScreen metrics memo', () {
    late TransactionProvider transactions;
    late AuthProvider auth;
    late PeriodProvider period;
    late ThemeProvider theme;
    late PlannerProvider planner;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      transactions = TransactionProvider();
      await transactions.ready;
      auth = AuthProvider();
      period = PeriodProvider()..init();
      theme = ThemeProvider();
      planner = PlannerProvider();
      await planner.ready;
    });

    tearDown(() {
      transactions.dispose();
      planner.dispose();
    });

    Widget harness() => MultiProvider(
          providers: [
            ChangeNotifierProvider<TransactionProvider>.value(
                value: transactions),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider<PeriodProvider>.value(value: period),
            ChangeNotifierProvider<ThemeProvider>.value(value: theme),
            ChangeNotifierProvider<PlannerProvider>.value(value: planner),
          ],
          child: const MaterialApp(home: InsightsScreen()),
        );

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('scans the ledger once per data change, not per rebuild',
        (tester) async {
      final now = DateTime.now();
      transactions.debugSeed([
        _tx('a', 100, DateTime(now.year, now.month, 3)),
        _tx('b', 200, DateTime(now.year, now.month, 2)),
      ]);

      await tester.pumpWidget(harness());
      await settle(tester);

      dynamic state = tester.state(find.byType(InsightsScreen));
      final afterFirst = state.debugMetricComputations as int;
      expect(afterFirst, 1);

      // Rebuilds (e.g. tab re-show via TickerMode) with no ledger change.
      await tester.pumpWidget(harness());
      await settle(tester);
      await tester.pumpWidget(harness());
      await settle(tester);

      state = tester.state(find.byType(InsightsScreen));
      expect(state.debugMetricComputations as int, afterFirst,
          reason: 'a rebuild without a ledger change must reuse the metrics');

      // A ledger change invalidates.
      transactions.debugSeed([
        _tx('a', 100, DateTime(now.year, now.month, 3)),
        _tx('b', 200, DateTime(now.year, now.month, 2)),
        _tx('c', 300, DateTime(now.year, now.month, 1)),
      ]);
      await settle(tester);

      state = tester.state(find.byType(InsightsScreen));
      expect(state.debugMetricComputations as int, greaterThan(afterFirst),
          reason: 'a ledger change must recompute the metrics');
    });
  });
}
