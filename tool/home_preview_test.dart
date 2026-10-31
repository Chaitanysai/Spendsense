// A test harness by design (it runs under `flutter test`), kept in tool/ so
// the normal suite never writes preview files into the workspace. That
// placement hides from the analyzer that the members below are test-only.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:spendsense/providers/update_provider.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/widgets/app_background.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';

TransactionModel _tx(
  String id,
  int rupees,
  String merchant,
  String category,
  DateTime date, {
  TransactionType type = TransactionType.expense,
  String method = 'UPI',
}) =>
    TransactionModel(
      id: id,
      amountMinor: rupees * 100,
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: method,
      date: date,
      time: '19:42',
      originalSms: '',
      isExcluded: false,
      source: 'Manual',
    );

Future<void> _loadFonts() async {
  const families = <String, List<String>>{
    'Poppins': [
      'Poppins-Regular.ttf',
      'Poppins-Medium.ttf',
      'Poppins-SemiBold.ttf',
      'Poppins-Bold.ttf',
    ],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final file in entry.value) {
      loader.addFont(rootBundle.load('assets/fonts/$file'));
    }
    await loader.load();
  }
}

Future<void> _render(
  WidgetTester tester, {
  required String name,
  required bool dark,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime.now().toIso8601String(),
    'theme_mode': dark ? 'dark' : 'light',
    'palette_id': 'midnight',
    'salary_day_setup': true,
    'salary_day': 1,
    'name': 'Chaitanya',
    'email': 'chai@example.com',
  });

  final transactions = TransactionProvider();
  await transactions.ready;
  transactions.debugSeed([
    _tx('t1', 420, 'Blue Tokai', 'Food', today),
    _tx('t2', 78, 'Metro Card', 'Travel', today),
    _tx('t3', 649, 'Netflix', 'Entertainment',
        today.subtract(const Duration(days: 1))),
    _tx('t4', 1240, 'Nature Basket', 'Food',
        today.subtract(const Duration(days: 2))),
    _tx('t5', 2199, 'FabIndia', 'Shopping',
        today.subtract(const Duration(days: 3))),
    _tx('t6', 500, 'HP Petrol', 'Fuel',
        today.subtract(const Duration(days: 4))),
    _tx('t7', 320, 'Third Wave', 'Food',
        today.subtract(const Duration(days: 5))),
    _tx('t8', 2850, 'Airtel Broadband', 'Bills',
        today.subtract(const Duration(days: 6))),
    _tx('t9', 12000, 'Rent', 'Bills',
        today.subtract(const Duration(days: 9))),
    _tx('t10', 4500, 'Zara', 'Shopping',
        today.subtract(const Duration(days: 12))),
    _tx('t11', 2100, 'Blue Tokai', 'Food',
        today.subtract(const Duration(days: 16))),
    _tx('t12', 65000, 'Salary', 'Income', today.subtract(const Duration(days: 2)),
        type: TransactionType.income, method: 'Bank'),
  ]);
  await transactions.setMonthlyBudgetMinor(5000000);

  final theme = ThemeProvider();
  await tester.pump();

  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('preview'),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: transactions),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider(create: (_) => PlannerProvider()),
          ChangeNotifierProvider(create: (_) => UpdateProvider()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: dark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor:
                dark ? Colors.black : const Color(0xFFF7F9F8),
          ),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            extendBody: true,
            body: const AppBackground(child: HomeScreen()),
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              backgroundColor: const Color(0xFF2A5BE0),
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
            bottomNavigationBar: const FloatingNavBar(
              items: [
                NavItem(Icons.home_rounded, 'HOME'),
                NavItem(Icons.event_note_rounded, 'BILLS'),
                NavItem(Icons.insights_rounded, 'INSIGHTS'),
                NavItem(Icons.credit_card_rounded, 'CARDS'),
                NavItem(Icons.settings_rounded, 'SETTINGS'),
              ],
              currentIndex: 0,
              onTap: _noop,
            ),
          ),
        ),
      ),
    ),
  );

  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(seconds: 2));
  await tester.pump(const Duration(seconds: 2));

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('preview')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('docs/design-research/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void _noop(int _) {}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('render dark home', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _loadFonts();
    await _render(tester, name: 'home-dark', dark: true);
  });

  testWidgets('render light home', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _loadFonts();
    await _render(tester, name: 'home-light', dark: false);
  });
}
