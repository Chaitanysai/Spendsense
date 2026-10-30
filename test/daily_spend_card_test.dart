import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/home_screen.dart';

/// The "Last 7 days" card: today is the default answer, every earlier day can
/// be inspected by tapping its column, and a week with no spending says so
/// instead of drawing seven invisible bars.

TransactionModel _tx(String id, DateTime date, int amountMinor) =>
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

Finder _inCard(Finder matching) => find.descendant(
      of: find.byKey(const Key('daily-spend-card')),
      matching: matching,
    );

Future<TransactionProvider> _pumpHome(
  WidgetTester tester,
  List<TransactionModel> seed,
) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime.now().toIso8601String(),
  });

  final provider = TransactionProvider();
  // The async init replaces the list when it finishes; seed only after it.
  await provider.ready;
  provider.debugSeed(seed);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  await tester.scrollUntilVisible(find.text('Last 7 days'), 300);
  await tester.pump(const Duration(seconds: 2));
  return provider;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('defaults to today and switches to a tapped earlier day',
      (tester) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 12);
    await _pumpHome(tester, [
      _tx('today', DateTime(now.year, now.month, now.day, 12), 25000),
      _tx('yesterday', yesterday, 12000),
    ]);

    expect(_inCard(find.text('Today')), findsOneWidget);
    expect(_inCard(find.text('₹250')), findsOneWidget);

    // Tap the sixth of seven equal slots: yesterday's column.
    final chart = tester.getRect(find.byType(BarChart));
    await tester
        .tapAt(Offset(chart.left + chart.width * 5.5 / 7, chart.center.dy));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_inCard(find.text(DateFormat('EEEE').format(yesterday))),
        findsOneWidget);
    expect(_inCard(find.text('₹120')), findsOneWidget);
    expect(_inCard(find.text('₹250')), findsNothing,
        reason: 'the header must describe the selected day only');
  });

  testWidgets('a week with no spending says so, and fills in when data lands',
      (tester) async {
    final provider = await _pumpHome(tester, const []);

    expect(
        _inCard(find.text('No spending in the last 7 days')), findsOneWidget);
    expect(_inCard(find.text('Today')), findsOneWidget);
    expect(_inCard(find.text('₹0')), findsOneWidget);

    // A ledger that loads after first paint must still grow the chart instead
    // of leaving the empty message on screen.
    final now = DateTime.now();
    provider.debugSeed([
      _tx('late', DateTime(now.year, now.month, now.day, 12), 25000),
    ]);
    await tester.pump(const Duration(seconds: 2));

    expect(_inCard(find.text('No spending in the last 7 days')), findsNothing);
    expect(_inCard(find.text('₹250')), findsOneWidget);
  });
}
