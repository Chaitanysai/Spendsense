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

/// Home derivation memo contract (P1.1).
///
/// Home must sort and cycle-filter the ledger once per data change, not once
/// per build: the shell keeps every tab mounted, so a balance toggle or a
/// sync-state flip rebuilds Home without any ledger change.

TransactionModel _tx(String id, int amountMinor, DateTime date) =>
    TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: TransactionType.expense,
      merchant: 'Merchant $id',
      category: 'Food',
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: '',
      isExcluded: false,
    );

/// Rebuild driver: a fresh non-const [HomeScreen] instance per pump forces the
/// existing element to rebuild while the providers above stay identical.
Widget harness({
  required TransactionProvider transactions,
  required AuthProvider auth,
  required PeriodProvider period,
  required ThemeProvider theme,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: transactions),
      ChangeNotifierProvider.value(value: auth),
      ChangeNotifierProvider.value(value: period),
      ChangeNotifierProvider.value(value: theme),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: HomeScreen(), // deliberately not const
      ),
    ),
  );
}

/// The glass/screen suites pump fixed durations instead of pumpAndSettle —
/// Home carries entrance animations; mirror that pattern here.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 900));
  await tester.pump(const Duration(milliseconds: 900));
}

void main() {
  late TransactionProvider transactions;
  late AuthProvider auth;
  late PeriodProvider period;
  late ThemeProvider theme;

  setUpAll(() {
    // Mutations hit the encrypted ledger, whose store is a real (FFI) sqflite
    // database in tests — without this the write future never completes in the
    // widget-test binding.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // Platform channels the ledger's secure key store talks to. In a widget
  // test the binding answers reads from these mocks instead of the OS; an
  // unmocked channel makes the key lookup hang forever rather than throw.
  const secureStorage =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const permissions =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  const connectivity =
      MethodChannel('dev.fluttercommunity.plus/connectivity');

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        permissions, (call) async => <int, int>{});
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'salary_day_setup': true,
      'salary_day': 1,
      'sms_scan_start_date': DateTime.now().toIso8601String(),
    });
    transactions = TransactionProvider();
    await transactions.ready;
    auth = AuthProvider();
    period = PeriodProvider()..init();
    theme = ThemeProvider();
  });

  // Leave the shared binary messenger as we found it, so a later suite that
  // mocks the same channels (e.g. the glass render test) keeps its handlers.
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureStorage, null);
    messenger.setMockMethodCallHandler(permissions, null);
    messenger.setMockMethodCallHandler(connectivity, null);
  });

  tearDown(() => transactions.dispose());

  testWidgets('sorts and filters once per data change, not once per build',
      (tester) async {
    transactions.debugSeed([
      _tx('a', 100, DateTime(2026, 10, 1)),
      _tx('b', 200, DateTime(2026, 10, 2)),
    ]);

    await tester.pumpWidget(harness(
      transactions: transactions,
      auth: auth,
      period: period,
      theme: theme,
    ));
    await _settle(tester);

    dynamic state = tester.state(find.byType(HomeScreen));
    final computationsAfterFirstBuild = state.debugDerivationComputations as int;
    expect(computationsAfterFirstBuild, greaterThanOrEqualTo(1));

    // Two rebuilds with NO data change: the memo must not recompute.
    await tester.pumpWidget(harness(
      transactions: transactions,
      auth: auth,
      period: period,
      theme: theme,
    ));
    await _settle(tester);
    await tester.pumpWidget(harness(
      transactions: transactions,
      auth: auth,
      period: period,
      theme: theme,
    ));
    await _settle(tester);

    state = tester.state(find.byType(HomeScreen));
    expect(state.debugDerivationComputations as int,
        computationsAfterFirstBuild,
        reason: 'a rebuild without a ledger change must reuse the derivation');

    // The sorted list handed to sections stays identical across those builds.
    final sortedBefore = state.debugSortedTracked as List<TransactionModel>?;

    // A data change invalidates the memo. The ledger write performs real
    // async I/O, so it must run on the real event loop — the widget-test
    // binding's fake clock would otherwise never let its continuations run.
    await tester.runAsync(() async {
      await transactions.addTransaction(_tx('c', 300, DateTime(2026, 10, 3)));
    });
    await _settle(tester);

    state = tester.state(find.byType(HomeScreen));
    expect(state.debugDerivationComputations as int,
        greaterThan(computationsAfterFirstBuild),
        reason: 'a ledger change must recompute the derivation');
    final sortedAfter = state.debugSortedTracked as List<TransactionModel>?;
    expect(identical(sortedBefore, sortedAfter), isFalse);
    expect(sortedAfter!.map((t) => t.id), ['c', 'b', 'a'],
        reason: 'date-descending order preserved');
  });

  testWidgets('history toggle and cycle change recompute the filtered lists',
      (tester) async {
    transactions.debugSeed([
      _tx('in-cycle', 100, DateTime.now()),
      // Outside the current salary cycle (a year ago).
      _tx('old', 200, DateTime.now().subtract(const Duration(days: 400))),
    ]);

    await tester.pumpWidget(harness(
      transactions: transactions,
      auth: auth,
      period: period,
      theme: theme,
    ));
    await _settle(tester);

    dynamic state = tester.state(find.byType(HomeScreen));
    final baseline = state.debugDerivationComputations as int;
    // History ON by default: both rows visible (the list IS the sorted list).
    expect((state.debugCycleTracked as List<TransactionModel>?)
        ?.map((t) => t.id), ['in-cycle', 'old']);

    // Toggling history re-derives (a preference change is a key change).
    await tester.runAsync(() => theme.setIncludeHistory(false));
    await _settle(tester);

    state = tester.state(find.byType(HomeScreen));
    expect(state.debugDerivationComputations as int, greaterThan(baseline));
    expect((state.debugCycleTracked as List<TransactionModel>?)
        ?.map((t) => t.id), ['in-cycle'],
        reason: 'history off hides rows outside the current cycle');
  });
}
