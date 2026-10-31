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
import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/utils/formatters.dart';
import 'package:spendsense/widgets/app_button.dart';
import 'package:spendsense/widgets/budget_summary.dart';
import 'package:spendsense/utils/budget_math.dart';
import 'package:spendsense/widgets/fade_indexed_stack.dart';

TransactionModel _tx({
  required int amount,
  TransactionType type = TransactionType.expense,
  String merchant = 'Test Merchant',
  String category = 'Food',
}) =>
    TransactionModel(
      id: 'id-$amount-$type-$merchant',
      amount: amount,
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: 'UPI',
      date: DateTime.now(),
      time: '',
      originalSms: '',
      isExcluded: false,
      bank: 'HDFC Bank',
      source: 'Test',
    );

Future<TransactionProvider> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1080, 2340),
  bool dark = false,
  String? paletteId,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime.now().toIso8601String(),
    'theme_mode': dark ? 'dark' : 'light',
    'name': 'Asha',
    if (paletteId != null) 'palette_id': paletteId,
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
  return transactions;
}

/// Seeds rows only after the provider's empty-database read settles — otherwise
/// that read replaces the seeded list. The extra pump is what lets the animated
/// amount actually tick: `TweenAnimationBuilder` starts its controller on the
/// next frame, so a single pump only ever shows the start value.
Future<void> _seed(WidgetTester tester, List<TransactionModel> rows,
    TransactionProvider provider) async {
  await tester.pump(const Duration(seconds: 1));
  provider.debugSeed(rows);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => AppColors.applyPalette(AppPalette.emerald));
  tearDown(() => AppColors.applyPalette(AppPalette.emerald));

  group('home entry points share one form', () {
    testWidgets('the floating action opens the shared form as a modal sheet',
        (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(AddTransactionScreen), findsOneWidget);
      final form = tester
          .widget<AddTransactionScreen>(find.byType(AddTransactionScreen));
      expect(form.asSheet, isTrue);
      // The dashboard is still mounted behind the sheet, not replaced by it.
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('the quick-action tile opens the same form in income mode',
        (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.text('Add income'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final form = tester
          .widget<AddTransactionScreen>(find.byType(AddTransactionScreen));
      expect(form.initialType, TransactionType.income);
    });

    testWidgets('a sheet entry persists through the shared provider',
        (tester) async {
      final transactions = await _pumpShell(tester);
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.enterText(find.byType(TextField).first, '750');
      await tester.pump(const Duration(milliseconds: 100));

      final saveButton = find.byType(AppPrimaryButton);
      expect(saveButton, findsOneWidget);
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      // The sheet has to finish its exit transition before it leaves the tree.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(transactions.transactions, hasLength(1));
      expect(transactions.transactions.single.amountMinor, 75000);
      expect(transactions.transactions.single.source, 'Manual');
      // A successful save dismisses the sheet.
      expect(find.byType(AddTransactionScreen), findsNothing);
    });

    testWidgets('the save action stays disabled until an amount is entered',
        (tester) async {
      await _pumpShell(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        tester
            .widget<AppPrimaryButton>(find.byType(AppPrimaryButton))
            .onPressed,
        isNull,
      );
    });
  });

  group('budget summary states', () {
    Future<void> pump(
      WidgetTester tester, {
      required int spent,
      required int budget,
      double width = 360,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: BudgetSummary(
                  progress:
                      BudgetProgress(spentMinor: spent, budgetMinor: budget),
                  periodLabel: '1 Oct – 31 Oct',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('zero budget prompts instead of dividing', (tester) async {
      await pump(tester, spent: 500, budget: 0);
      expect(find.text('No budget set'), findsOneWidget);
      expect(find.text('Set a budget'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('zero spending shows 0% and the full amount left',
        (tester) async {
      await pump(tester, spent: 0, budget: 10000);
      expect(find.textContaining('0% used'), findsOneWidget);
      expect(find.textContaining('left'), findsOneWidget);
    });

    testWidgets('partial spend shows the rounded percentage', (tester) async {
      await pump(tester, spent: 4250, budget: 10000);
      expect(find.textContaining('43% used'), findsOneWidget);
    });

    testWidgets('exactly full is fully used, not over', (tester) async {
      await pump(tester, spent: 10000, budget: 10000);
      expect(find.textContaining('100% used'), findsOneWidget);
      expect(find.text('Budget fully used'), findsOneWidget);
      expect(find.textContaining('over budget'), findsNothing);
    });

    testWidgets('overspend keeps the real percentage and no positive remainder',
        (tester) async {
      await pump(tester, spent: 15000, budget: 10000);
      expect(find.textContaining('150% used'), findsOneWidget);
      expect(find.textContaining('over budget (+50%)'), findsOneWidget);
      expect(find.textContaining('left'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has no circular progress and survives large text',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, spent: 30000000000, budget: 10000, width: 220);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
          find.byType(CustomPaint).evaluate().where((e) =>
              e.widget is CustomPaint &&
              (e.widget as CustomPaint).painter != null),
          isEmpty);
      expect(tester.takeException(), isNull);
    });
  });
  group('balance card', () {
    testWidgets('shows current-cycle spending as the primary figure',
        (tester) async {
      final transactions = await _pumpShell(tester);
      await _seed(
        tester,
        [
          _tx(amount: 1000, merchant: 'Groceries'),
          _tx(amount: 4000, type: TransactionType.income, merchant: 'Salary'),
        ],
        transactions,
      );

      expect(find.text(Formatters.currency.format(100000)), findsWidgets);
      expect(find.text('Total spent this cycle'), findsOneWidget);
    });

    testWidgets('the eye toggle masks the figure without touching the data',
        (tester) async {
      final transactions = await _pumpShell(tester);
      await _seed(
        tester,
        [_tx(amount: 1250, type: TransactionType.income, merchant: 'Refund')],
        transactions,
      );

      expect(find.text(Formatters.currency.format(0)), findsWidgets);

      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('••••••'), findsOneWidget);
      expect(transactions.transactions.single.amountMinor, 125000);
    });

    testWidgets('never invents a cycle change without a prior window',
        (tester) async {
      final transactions = await _pumpShell(tester);
      await _seed(
        tester,
        [_tx(amount: 900, merchant: 'Coffee')],
        transactions,
      );

      expect(find.textContaining('than last cycle'), findsNothing);
    });
  });

  group('themes', () {
    testWidgets(
        'AMOLED dark mode resolves a dark theme on a pitch-black canvas',
        (tester) async {
      await _pumpShell(tester, dark: true, paletteId: 'midnight');
      await tester.pump(const Duration(milliseconds: 500));

      final theme = Theme.of(tester.element(find.byType(HomeScreen)));
      expect(theme.brightness, Brightness.dark);
      // Regression: the glass pass briefly tinted this navy. The canvas is
      // #000000; navy lives on the cards, not behind them.
      expect(AppColors.darkBackground, const Color(0xFF000000));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
    });

    testWidgets('light and dark both lay the dashboard out without errors',
        (tester) async {
      for (final dark in [false, true]) {
        final transactions = await _pumpShell(tester, dark: dark);
        await _seed(
          tester,
          [
            _tx(amount: 1499, merchant: 'Bamboli Purefresh Veg And Fruits'),
            _tx(
                amount: 25000,
                type: TransactionType.income,
                merchant: 'Salary'),
          ],
          transactions,
        );
        expect(tester.takeException(), isNull,
            reason: 'dark=$dark must not overflow');
      }
    });
  });

  group('light and dark across every palette', () {
    testWidgets('each accent renders the dashboard in both themes',
        (tester) async {
      final seeded = [
        _tx(amount: 1499, merchant: 'Bamboli Purefresh Veg'),
        _tx(amount: 40000, type: TransactionType.income, merchant: 'Salary'),
        _tx(amount: 800, merchant: 'Metro Card', category: 'Travel'),
      ];

      for (final palette in AppPalette.all) {
        for (final dark in [false, true]) {
          AppColors.applyPalette(palette);
          final transactions = await _pumpShell(tester, dark: dark);
          await _seed(tester, seeded, transactions);

          expect(
            tester.takeException(),
            isNull,
            reason: '${palette.id} ($palette.label) failed in '
                '${dark ? 'dark' : 'light'} mode',
          );
          // The token mirror is what every widget reads, so assert it holds for
          // this palette rather than a stale previous one.
          expect(AppColors.brand, palette.brand);
        }
      }
    });
  });

  group('layout resilience', () {
    testWidgets('the dashboard survives a 320dp-wide phone', (tester) async {
      final transactions = await _pumpShell(
        tester,
        size: const Size(960, 1600), // 320 x 533 logical
      );
      await _seed(
        tester,
        [
          _tx(amount: 124999, merchant: 'An Extremely Long Merchant Name Ltd'),
          _tx(amount: 500000, type: TransactionType.income, merchant: 'Salary'),
        ],
        transactions,
      );

      // The current-cycle expense is the primary Home metric.
      expect(find.text(Formatters.currency.format(12499900)), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dashboard survives a large system text scale',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({
        'sms_scan_start_date': DateTime.now().toIso8601String(),
      });
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(1.6),
          ),
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => TransactionProvider()),
              ChangeNotifierProvider(create: (_) => AuthProvider()),
              ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
              ChangeNotifierProvider(create: (_) => ThemeProvider()),
            ],
            child: const SpendSenseApp(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('motion', () {
    test('tab transition uses the shared base motion token', () {
      const stack = FadeIndexedStack(
        index: 0,
        children: [SizedBox(), SizedBox()],
      );

      expect(stack.duration, AppMotion.base);
    });

    testWidgets('tab switches preserve child state and scroll position',
        (tester) async {
      final firstScroll = ScrollController();
      addTearDown(firstScroll.dispose);
      final firstKey = GlobalKey();

      await tester.pumpWidget(MaterialApp(
        home: FadeIndexedStack(
          index: 0,
          children: [
            ListView(
              key: firstKey,
              controller: firstScroll,
              children: const [
                SizedBox(height: 900, child: Text('FIRST CONTENT')),
              ],
            ),
            const Center(child: Text('SECOND CONTENT')),
          ],
        ),
      ));
      await tester.pumpAndSettle();

      firstScroll.jumpTo(300);
      await tester.pump();
      expect(firstScroll.position.pixels, 300);

      await tester.pumpWidget(MaterialApp(
        home: FadeIndexedStack(
          index: 1,
          children: [
            ListView(
              key: firstKey,
              controller: firstScroll,
              children: const [
                SizedBox(height: 900, child: Text('FIRST CONTENT')),
              ],
            ),
            const Center(child: Text('SECOND CONTENT')),
          ],
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      await tester.pumpWidget(MaterialApp(
        home: FadeIndexedStack(
          index: 0,
          children: [
            ListView(
              key: firstKey,
              controller: firstScroll,
              children: const [
                SizedBox(height: 900, child: Text('FIRST CONTENT')),
              ],
            ),
            const Center(child: Text('SECOND CONTENT')),
          ],
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      expect(firstScroll.position.pixels, 300);
      expect(find.text('FIRST CONTENT'), findsOneWidget);
    });

    testWidgets('tab switches keep both the tab state and the scroll state',
        (tester) async {
      await _pumpShell(tester);

      expect(
        tester.widget<FadeIndexedStack>(find.byType(FadeIndexedStack)).index,
        0,
      );

      await tester.tap(find.text('INSIGHTS'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<FadeIndexedStack>(find.byType(FadeIndexedStack)).index,
        2,
        reason: 'INSIGHTS is the third destination',
      );

      await tester.tap(find.text('HOME'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<FadeIndexedStack>(find.byType(FadeIndexedStack)).index,
        0,
      );
    });

    testWidgets('reduced motion settles immediately with no transition',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      SharedPreferences.setMockInitialValues({
        'sms_scan_start_date': DateTime.now().toIso8601String(),
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => TransactionProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const SpendSenseApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // One frame after the tap the incoming tab is already at rest: the fade
      // wrapper is not inserted at all when animations are disabled.
      await tester.tap(find.text('CARDS'));
      await tester.pump();

      expect(find.byType(FadeTransition), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
