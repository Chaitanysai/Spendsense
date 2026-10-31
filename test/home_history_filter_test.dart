import 'package:flutter/material.dart';
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

TransactionModel _tx(String id, int rupees, String merchant, DateTime date) =>
    TransactionModel(
      id: id,
      amountMinor: rupees * 100,
      type: TransactionType.expense,
      merchant: merchant,
      category: 'Food',
      paymentMethod: 'UPI',
      date: date,
      time: '12:00',
      originalSms: '',
      isExcluded: false,
    );

Future<ThemeProvider> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime(2026, 9, 1).toIso8601String(),
    'name': 'Asha',
  });

  final transactions = TransactionProvider();
  await transactions.ready;
  transactions.debugSeed([
    _tx('current', 300, 'Current Cafe', DateTime(2026, 10, 10)),
    _tx('old', 500, 'Old Bazaar', DateTime(2026, 9, 10)),
  ]);

  // Defaults to history off before the async preference load completes.
  final theme = ThemeProvider();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: transactions),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(
          value: PeriodProvider.fixedForTest(
            salaryDay: 1,
            now: DateTime(2026, 10, 15),
          ),
        ),
        ChangeNotifierProvider.value(value: theme),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return theme;
}

Future<void> _showRecent(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Recent transactions'),
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

  testWidgets('history is off by default and hides earlier cycles',
      (tester) async {
    final theme = await _pumpHome(tester);
    expect(theme.includeHistory, isFalse);

    await _showRecent(tester);
    expect(find.text('Current Cafe'), findsOneWidget);
    expect(find.text('Old Bazaar'), findsNothing);
  });

  testWidgets('enabling history reveals earlier transactions on Home',
      (tester) async {
    final theme = await _pumpHome(tester);
    await theme.setIncludeHistory(true);
    await tester.pump(const Duration(seconds: 1));

    await _showRecent(tester);
    expect(find.text('Current Cafe'), findsOneWidget);
    expect(find.text('Old Bazaar'), findsOneWidget);

    // Toggling back hides them again without deleting anything.
    await theme.setIncludeHistory(false);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Old Bazaar'), findsNothing);
  });

  test('the preference is persisted', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeProvider();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await theme.setIncludeHistory(true);

    final restored = ThemeProvider();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(restored.includeHistory, isTrue);
  });
}
