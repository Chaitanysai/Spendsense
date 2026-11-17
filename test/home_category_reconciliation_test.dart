import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/utils/formatters.dart';
import 'package:spendsense/widgets/category_breakdown_card.dart';

/// Regression suite for the Home spend reconciliation defect.
///
/// The hero and Overview used the canonical period spend (transfers excluded,
/// duplicates collapsed), while "Spending by category" summed a different
/// population: all tracked expenses in the cycle, including Transfer rows and
/// repeated SMS imports. This suite seeds those exact records and asserts that
/// every Home figure derives from one source.
TransactionModel _tx({
  required String id,
  required int amountMinor,
  TransactionType type = TransactionType.expense,
  String category = 'Food',
  DateTime? date,
  bool excluded = false,
  String syncId = '',
}) {
  return TransactionModel(
    id: id,
    amountMinor: amountMinor,
    type: type,
    merchant: 'Merchant $id',
    category: category,
    paymentMethod: 'UPI',
    date: date ?? DateTime(2026, 11, 10),
    time: '12:00',
    originalSms: '',
    isExcluded: excluded,
    syncId: syncId,
    source: 'Test',
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  required List<TransactionModel> transactions,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime(2026, 9, 1).toIso8601String(),
    'name': 'Asha',
    'include_transaction_history': false,
  });

  final provider = TransactionProvider();
  await provider.ready;
  provider.debugSeed(transactions);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(
          value: PeriodProvider.fixedForTest(
            salaryDay: 1,
            // The seeded rows default to 2026-11-10, so the fixed clock must
            // put the active salary cycle in November, not October.
            now: DateTime(2026, 11, 15),
          ),
        ),
        ChangeNotifierProvider.value(value: ThemeProvider()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _showCategoryCard(WidgetTester tester) async {
  // The category section is a lazily built sliver child, so it does not exist
  // until the vertical scroller reaches it. Scroll the outer CustomScrollView
  // (the first Scrollable, as in the sibling Home tests) to materialise it.
  await tester.scrollUntilVisible(
    find.text('Spent this cycle'),
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // The encrypted ledger reads secure storage and platform channels during
  // `provider.ready`. Mirror the other Home widget suites: an unmocked key
  // lookup hangs the widget-test binding instead of throwing.
  setUp(() {
    const secureStorage = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    const permissions = MethodChannel(
      'flutter.baseflow.com/permissions/methods',
    );
    const connectivity = MethodChannel(
      'dev.fluttercommunity.plus/connectivity',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      permissions,
      (call) async => <int, int>{},
    );
    messenger.setMockMethodCallHandler(connectivity, (call) async => 'wifi');
    messenger.setMockMethodCallHandler(secureStorage, (call) async {
      return switch (call.method) {
        'read' => null,
        'readAll' => <String, String>{},
        'containsKey' => false,
        'write' => null,
        'delete' => null,
        'deleteAll' => null,
        _ => null,
      };
    });
  });

  final period = DateTimeRange(
    start: DateTime(2026, 11, 1),
    end: DateTime(2026, 11, 30),
  );

  group('canonical Home spend population', () {
    test('counts only eligible expense rows, once', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(id: 'food-1', amountMinor: 100000, syncId: 'f1'),
        _tx(id: 'food-2', amountMinor: 50000, syncId: 'f2'),
        _tx(id: 'bills-1', amountMinor: 25000, category: 'Bills', syncId: 'b1'),
        _tx(
          id: 'transfer',
          amountMinor: 700000,
          category: 'Transfer',
          syncId: 't1',
        ),
        _tx(
          id: 'income',
          amountMinor: 900000,
          type: TransactionType.income,
          syncId: 'i1',
        ),
        _tx(id: 'excluded', amountMinor: 300000, excluded: true, syncId: 'x1'),
        // A repeated SMS import: new local id, same sync identity.
        _tx(id: 'duplicate', amountMinor: 100000, syncId: 'f1'),
        _tx(
          id: 'last-cycle',
          amountMinor: 999000,
          date: DateTime(2026, 10, 31),
          syncId: 'old1',
        ),
      ]);

      final rows = provider.spendTransactionsForPeriod(period).toList();
      final byCategory = provider.spendingStatsForPeriod(
        period,
        (t) => t.category,
      );

      expect(rows.map((t) => t.id).toList(), ['food-1', 'food-2', 'bills-1']);
      expect(provider.spendAmountForPeriod(period), 175000);
      expect(provider.spendingTotalForPeriod(period), 175000);
      expect(byCategory['Food']!.spent, 150000);
      expect(byCategory['Food']!.count, 2);
      expect(byCategory['Bills']!.spent, 25000);
      expect(byCategory['Bills']!.count, 1);
      expect(byCategory.containsKey('Transfer'), isFalse);
      expect(
        byCategory.values.fold<int>(0, (sum, s) => sum + s.spent),
        provider.spendAmountForPeriod(period),
      );
      expect(
        byCategory.values.fold<int>(0, (sum, s) => sum + s.count),
        rows.length,
      );
    });

    test('period boundaries include both ends and exclude the next day', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(id: 'start', amountMinor: 100, date: DateTime(2026, 11, 1)),
        _tx(id: 'end', amountMinor: 200, date: DateTime(2026, 11, 30, 23, 59)),
        _tx(id: 'after', amountMinor: 400, date: DateTime(2026, 12, 1)),
      ]);

      expect(provider.spendAmountForPeriod(period), 300);
      expect(provider.spendTransactionsForPeriod(period).length, 2);
    });

    test('blank categories are normalised and empty categories are absent', () {
      final provider = TransactionProvider();
      provider.debugSeed([_tx(id: 'blank', amountMinor: 500, category: '   ')]);

      final byCategory = provider.spendingStatsForPeriod(
        period,
        (t) => t.category,
      );
      expect(byCategory.keys.toList(), ['Other']);
      expect(byCategory['Other']!.count, 1);
      expect(byCategory.containsKey('Bills'), isFalse);
    });
  });

  testWidgets(
    'Home category total equals the hero and excludes transfers and income',
    (tester) async {
      await _pumpHome(
        tester,
        transactions: [
          _tx(id: 'food', amountMinor: 30000, syncId: 'f1'),
          _tx(
            id: 'transfer',
            amountMinor: 50000,
            category: 'Transfer',
            syncId: 't1',
          ),
          _tx(
            id: 'salary',
            amountMinor: 100000,
            type: TransactionType.income,
            syncId: 'i1',
          ),
        ],
      );
      await _showCategoryCard(tester);

      final card = find.byType(CategoryBreakdownCard);
      expect(card, findsOneWidget);

      // ₹300 is the spend hero / Overview figure. The old code summed ₹800 here
      // (₹300 spend + ₹500 transfer) and offered a "Transfer" category row.
      // With one category the card headline and the single category row both
      // show ₹300; the old defect would have shown ₹800 in both places.
      expect(
        find.descendant(
          of: card,
          matching: find.text(Formatters.currency.format(30000)),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text(Formatters.currency.format(80000)),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('Transfer')),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.text('1 transaction')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
