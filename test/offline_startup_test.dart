import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/main.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Gate 2.8 (offline startup): the app is offline-first. With every network
/// channel unmocked (no OTA manifest configured, no SMS permission granted),
/// startup must render a working dashboard and load the local ledger.

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const permissionsChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');
  setUp(() {
    // Only the permissions channel answers (denied); every HTTP-capable
    // channel stays unmocked, so any network attempt would fail loudly.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async {
      return <int, int>{108: 0};
    });
    AppColors.applyPalette(AppPalette.emerald);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, null);
    AppColors.applyPalette(AppPalette.emerald);
  });

  testWidgets('the app starts and renders the dashboard with no network',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      'sms_scan_start_date': DateTime(2026, 10, 1).toIso8601String(),
      'name': 'Asha',
    });

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
    await tester.pump(const Duration(seconds: 1));

    expect(transactions.hasLedgerInitError, isFalse,
        reason: 'the local encrypted ledger needs no network to load');
    expect(find.text('Welcome back'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
