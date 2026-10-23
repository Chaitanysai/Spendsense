import 'package:flutter/material.dart';
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
import 'package:spendsense/screens/activity_screen.dart';
import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/screens/cards_screen.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/screens/insights_screen.dart';
import 'package:spendsense/screens/settings_screen.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/app_button.dart';
import 'package:spendsense/widgets/budget_gauge.dart';
import 'package:spendsense/widgets/app_page_route.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed = route;
    super.didPush(route, previousRoute);
  }
}

TransactionModel _tx({
  required double amount,
  TransactionType type = TransactionType.expense,
  String method = 'UPI',
  String? bank,
  String? account,
  String category = 'Food',
  String merchant = 'Test Merchant',
}) =>
    TransactionModel(
      id: 'id-$amount-$method-$type',
      amount: amount.toInt(),
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: method,
      date: DateTime.now(),
      time: '',
      originalSms: '',
      isExcluded: false,
      bank: bank,
      account: account,
      source: 'Test',
    );

Future<TransactionProvider> _pumpShell(WidgetTester tester) async {
  // Galaxy S24 is the design target: 1080x2340 at 3x => 360x780 logical.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime.now().toIso8601String(),
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
  await tester.pump(const Duration(milliseconds: 100));
  return transactions;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('five-destination navigation', () {
    testWidgets('bar exposes exactly Home, Activity, Insights, Cards, Settings',
        (tester) async {
      await _pumpShell(tester);

      final bar = tester.widget<FloatingNavBar>(find.byType(FloatingNavBar));
      expect(
        bar.items.map((i) => i.label).toList(),
        ['HOME', 'ACTIVITY', 'INSIGHTS', 'CARDS', 'SETTINGS'],
      );
      expect(bar.items, hasLength(5));
    });

    testWidgets('each destination selects its own screen', (tester) async {
      await _pumpShell(tester);

      final expected = <String, Type>{
        'ACTIVITY': ActivityScreen,
        'INSIGHTS': InsightsScreen,
        'CARDS': CardsScreen,
        'SETTINGS': SettingsScreen,
      };

      for (final entry in expected.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(entry.value), findsOneWidget,
            reason: 'tapping ${entry.key} should show ${entry.value}');
      }
    });

    testWidgets('populated screens lay out cleanly at phone width',
        (tester) async {
      final transactions = await _pumpShell(tester);
      // Seed after the provider's empty-database read settles, otherwise the
      // read replaces the seeded rows.
      await tester.pump(const Duration(seconds: 1));
      transactions.debugSeed([
        _tx(
            amount: 1499.5,
            method: 'UPI',
            bank: 'HDFC Bank',
            merchant: 'Bamboli Purefresh Veg And Fruits Supermart Pvt Ltd',
            category: 'Food & Groceries'),
        _tx(
            amount: 25000,
            method: 'Credit Card',
            bank: 'ICICI Bank',
            category: 'Shopping'),
        _tx(
            amount: 320,
            type: TransactionType.income,
            method: 'Bank Transfer',
            bank: 'State Bank of India',
            category: 'Income'),
      ]);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'layout error on the populated Home dashboard');

      for (final label in ['ACTIVITY', 'INSIGHTS', 'CARDS', 'SETTINGS']) {
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text(label), findsWidgets, reason: '$label is visible');
        expect(tester.takeException(), isNull,
            reason: 'layout error while showing $label');
      }
    });

    testWidgets('recurring expenses stays reachable from Settings',
        (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.text('SETTINGS'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Recurring expenses'), findsOneWidget);
    });
  });

  group('secondary route transitions', () {
    testWidgets('AppPageRoute uses a shorter reverse transition',
        (tester) async {
      final observer = _RecordingNavigatorObserver();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              AppPageRoute(builder: (_) => const Text('DETAILS')),
            ),
            child: const Text('OPEN'),
          ),
        ),
      ));

      await tester.tap(find.text('OPEN'));
      await tester.pump(const Duration(milliseconds: 300));

      final route = observer.pushed! as PageRoute<dynamic>;
      expect(route, isA<AppPageRoute<dynamic>>());
      expect(route.transitionDuration, AppMotion.base);
      expect(route.reverseTransitionDuration, AppMotion.fast);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 160));
    });
  });

  group('add transaction', () {
    testWidgets('floating action opens the real creation workflow',
        (tester) async {
      await _pumpShell(tester);

      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(AddTransactionScreen), findsOneWidget);
    });

    testWidgets('saving an income entry persists it as income', (tester) async {
      final transactions = TransactionProvider();
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: transactions),
                ChangeNotifierProvider(create: (_) => AuthProvider()),
                ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
              ],
              child: const AddTransactionScreen(
                  initialType: TransactionType.income),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField).first, '500');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('Add income'));
      await tester.pump(const Duration(seconds: 1));

      expect(transactions.transactions, hasLength(1));
      expect(transactions.transactions.single.type, TransactionType.income);
    });

    testWidgets('expense mode is the default and rejects a zero amount',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiProvider(
              providers: [
                ChangeNotifierProvider(create: (_) => TransactionProvider()),
                ChangeNotifierProvider(create: (_) => AuthProvider()),
                ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
              ],
              child: const AddTransactionScreen(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Add expense'), findsOneWidget);
      expect(
        tester
            .widget<AppPrimaryButton>(find.byType(AppPrimaryButton))
            .onPressed,
        isNull,
        reason: 'save must stay disabled until an amount is entered',
      );
    });
  });

  group('budget gauge', () {
    Future<void> pumpGauge(WidgetTester tester,
        {required int spent, required int budget}) async {
      await tester.pumpWidget(
        MaterialApp(
            home: Scaffold(body: BudgetGauge(spent: spent, budget: budget))),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('renders the used percentage', (tester) async {
      await pumpGauge(tester, spent: 2500, budget: 10000);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('of budget'), findsOneWidget);
    });

    testWidgets('a zero budget shows a prompt instead of dividing by zero',
        (tester) async {
      await pumpGauge(tester, spent: 500, budget: 0);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('no budget'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('overspend shows the real percentage without overflowing',
        (tester) async {
      await pumpGauge(tester, spent: 30000, budget: 10000);
      expect(find.text('300%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('instrument roll-ups', () {
    test('statsBy groups by payment method and separates income', () {
      final provider = TransactionProvider();
      // statsBy reads the in-memory list; seed it through the public API.
      provider.debugSeed([
        _tx(amount: 100, method: 'UPI'),
        _tx(amount: 50, method: 'UPI'),
        _tx(amount: 700, method: 'Card', bank: 'HDFC'),
        _tx(amount: 200, type: TransactionType.income, method: 'UPI'),
      ]);

      final byMethod = provider.statsBy((t) => t.paymentMethod);
      expect(byMethod['UPI']!.spent, 15000);
      expect(byMethod['UPI']!.received, 20000);
      expect(byMethod['UPI']!.count, 3);
      expect(byMethod['Card']!.spent, 70000);
    });

    test('a blank attribute falls back to Other rather than vanishing', () {
      final provider = TransactionProvider();
      provider.debugSeed([
        _tx(amount: 10, bank: ''),
        _tx(amount: 20, bank: null),
        _tx(amount: 30, bank: '  Axis Bank  '),
      ]);

      final byBank = provider.statsBy((t) => t.bank);
      expect(byBank['Other']!.count, 2);
      expect(byBank['Axis Bank']!.spent, 3000,
          reason: 'surrounding whitespace must not split one bank in two');
    });
  });

  group('previous period', () {
    test('precedes the current salary-aligned window', () {
      final provider = PeriodProvider();
      final previous = provider.previousPeriod!;
      expect(previous.end.isBefore(provider.currentPeriod.start), isTrue);
    });

    test('is null for a custom window, which has no predecessor', () {
      final provider = PeriodProvider();
      provider.setMode(
        PeriodMode.custom,
        custom: DateTimeRange(
          start: DateTime(2026, 1, 1),
          end: DateTime(2026, 1, 31),
        ),
      );
      expect(provider.previousPeriod, isNull);
    });
  });
}
