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
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Gate 2.7 (large text / accessibility): the main dashboard must not produce
/// layout overflow errors at elevated text scales, with data and empty.

TransactionModel _tx(String id, int amountMinor, DateTime date, String merchant) =>
    TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: TransactionType.expense,
      merchant: merchant,
      category: 'Food',
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: '',
      isExcluded: false,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  const permissionsChannel =
      MethodChannel('flutter.baseflow.com/permissions/methods');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, (call) async {
      // An empty status map: every requested permission reads as denied.
      return <int, int>{};
    });
    AppColors.applyPalette(AppPalette.emerald);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionsChannel, null);
    AppColors.applyPalette(AppPalette.emerald);
  });

  Future<TransactionProvider> pumpDashboard(WidgetTester tester,
      {required double textScale, List<TransactionModel> seed = const []}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
    if (seed.isNotEmpty) transactions.debugSeed(seed);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    return transactions;
  }

  List<TransactionModel> sampleTransactions() => [
        for (var i = 0; i < 8; i++)
          _tx(
            'tx-$i',
            12500 + i * 7,
            DateTime(2026, 10, 1 + i),
            i.isEven
                ? 'SyntheticShop'
                : 'A Very Long Merchant Name That Stresses Line Wrapping $i',
          ),
      ];

  for (final scale in [1.3, 2.0]) {
    testWidgets('dashboard with data has no overflow at ${scale}x text',
        (tester) async {
      await pumpDashboard(tester, textScale: scale, seed: sampleTransactions());
      expect(find.text('Welcome back'), findsOneWidget);
      // Any layout exception (e.g. RenderFlex overflow) fails the test and is
      // reported by the binding with the full widget chain.
    });

    testWidgets('empty dashboard has no overflow at ${scale}x text',
        (tester) async {
      await pumpDashboard(tester, textScale: scale);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
