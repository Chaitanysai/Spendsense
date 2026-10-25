import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/main.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/ledger_encryption_service.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Regression tests for the corrupted-ledger UX: a ledger that fails closed
/// must be visible and distinguishable from a genuinely empty ledger. An
/// initialization failure must never render the empty dashboard as if the load
/// had succeeded.

const _tamperedIndex = {
  // A well-formed envelope whose payload cannot authenticate: any base64
  // garbage with the right envelope shape fails closed in decryptText.
  'tx_cache_ids_v2':
      '{"schemaVersion":2,"algorithm":"AES-256-GCM","nonce":"AAAA","ciphertext":"AAAA","mac":"AAAA"}',
};

TransactionModel _tx(String id) => TransactionModel(
      id: id,
      amountMinor: 23950,
      type: TransactionType.expense,
      merchant: 'Merchant',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 1),
      time: '10:00',
      originalSms: '',
      isExcluded: false,
    );

Future<void> _pumpApp(WidgetTester tester, {Size size = const Size(1080, 2340)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final transactions = TransactionProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: transactions),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const SpendSenseApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 150));
  await transactions.ready;
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // The app shell builds every tab, and ActivityScreen's initState triggers a
  // startup SMS sync. Without a mocked permissions channel that sync never
  // settles in the test environment and the dashboard stays on skeletons.
  // Answering "denied" terminates the sync deterministically.
  const permissionsChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async {
      return <int, int>{108: 0}; // sms permission: denied
    });
    AppColors.applyPalette(AppPalette.emerald);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, null);
    AppColors.applyPalette(AppPalette.emerald);
  });

  test('provider records a ledger init failure as an error, not empty success',
      () async {
    SharedPreferences.setMockInitialValues(_tamperedIndex);

    final provider = TransactionProvider();
    await provider.ready;

    expect(provider.hasLedgerInitError, isTrue,
        reason: 'a failed ledger read must not look like a successful load');
    expect(provider.ledgerInitError, isA<LedgerKeyUnavailableException>());
    expect(provider.transactions, isEmpty);
    expect(provider.isLoadingCache, isFalse);

    // Mutations are no-ops while the ledger is unavailable: nothing can be
    // half-written into a store that failed to open.
    await provider.addTransaction(_tx('blocked'));
    expect(provider.transactions, isEmpty);
    await provider.syncFromSms();
    expect(provider.hasLedgerInitError, isTrue);
  });

  test('retrying after the store is repaired clears the error and loads',
      () async {
    SharedPreferences.setMockInitialValues(_tamperedIndex);
    final provider = TransactionProvider();
    await provider.ready;
    expect(provider.hasLedgerInitError, isTrue);

    // Repair the store (a fresh, valid, empty ledger) and retry.
    SharedPreferences.setMockInitialValues({
      'sms_scan_start_date': DateTime(2026, 10, 1).toIso8601String(),
    });
    await provider.retryLedgerInit();

    expect(provider.hasLedgerInitError, isFalse);
    expect(provider.transactions, isEmpty,
        reason: 'a repaired empty ledger is genuinely empty, not an error');
    expect(provider.isLoadingCache, isFalse);
  });

  testWidgets('an init failure renders the ledger error, never the empty '
      'dashboard', (tester) async {
    SharedPreferences.setMockInitialValues({
      ..._tamperedIndex,
      'sms_scan_start_date': DateTime(2026, 10, 1).toIso8601String(),
      'name': 'Asha',
    });

    // A tall viewport builds the whole lazy sliver list in one frame.
    await _pumpApp(tester, size: const Size(1080, 8000));

    expect(find.text("Couldn't load your ledger"), findsWidgets,
        reason: 'the error must be visible on the dashboard');
    expect(find.text('Nothing found'), findsNothing,
        reason: 'an error state must not reuse the empty-ledger copy');
    expect(find.text('No transactions yet'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);

    // Retrying with the store still broken keeps the error surfaced.
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Couldn't load your ledger"), findsWidgets);
  });

  testWidgets('a genuinely empty ledger still renders the empty state',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'sms_scan_start_date': DateTime(2026, 10, 1).toIso8601String(),
      'name': 'Asha',
    });

    await _pumpApp(tester, size: const Size(1080, 8000));

    expect(find.text("Couldn't load your ledger"), findsNothing);
    expect(find.text('Nothing found'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a loaded ledger with transactions renders neither state',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'sms_scan_start_date': DateTime(2026, 10, 1).toIso8601String(),
      'name': 'Asha',
    });

    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final transactions = TransactionProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: transactions),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const SpendSenseApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await transactions.ready;
    transactions.debugSeed([_tx('live')]);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Nothing found'), findsNothing);
    expect(find.text("Couldn't load your ledger"), findsNothing);
  });
}
