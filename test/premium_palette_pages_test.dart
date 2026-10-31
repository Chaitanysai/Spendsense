import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/main.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/providers/update_provider.dart';
import 'package:spendsense/screens/activity_screen.dart';
import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/screens/ai_settings_screen.dart';
import 'package:spendsense/screens/appearance_screen.dart';
import 'package:spendsense/screens/assistant_privacy_screen.dart';
import 'package:spendsense/screens/assistant_screen.dart';
import 'package:spendsense/screens/auth/auth_screen.dart';
import 'package:spendsense/screens/bills_screen.dart';
import 'package:spendsense/screens/budgets_screen.dart';
import 'package:spendsense/screens/cards_screen.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/screens/insights_screen.dart';
import 'package:spendsense/screens/recurring_screen.dart';
import 'package:spendsense/screens/settings_screen.dart';
import 'package:spendsense/screens/sound_settings_screen.dart';
import 'package:spendsense/screens/summary_screen.dart';
import 'package:spendsense/screens/transaction_details_screen.dart';
import 'package:spendsense/screens/typography_screen.dart';
import 'package:spendsense/screens/update_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Every screen, in both themes, under each of the 2026 premium palettes.
///
/// This is a render/integration sweep, not a pixel test: it boots each route
/// with real providers and a seeded ledger and fails on any layout exception
/// (including a RenderFlex overflow), missing provider, or plugin crash. The
/// point is to make "every page and tile" a mechanical check rather than a
/// manual tour.

TransactionModel _tx(
  String id,
  int rupees,
  String merchant,
  String category,
  int daysAgo, {
  TransactionType type = TransactionType.expense,
}) {
  final date = DateTime.now().subtract(Duration(days: daysAgo));
  return TransactionModel(
    id: id,
    amountMinor: rupees * 100,
    type: type,
    merchant: merchant,
    category: category,
    paymentMethod: 'UPI',
    date: date,
    time: '18:30',
    originalSms: '',
    isExcluded: false,
    source: 'Test',
    bank: 'HDFC Bank',
  );
}

List<TransactionModel> _demoLedger() => [
      _tx('1', 420, 'Blue Tokai', 'Food', 0),
      _tx('2', 78, 'Metro Card', 'Travel', 0),
      _tx('3', 649, 'Netflix', 'Entertainment', 1),
      _tx('4', 1240, 'Nature Basket', 'Food', 2),
      _tx('5', 2199, 'FabIndia', 'Shopping', 3),
      _tx('6', 500, 'HP Petrol', 'Fuel', 4),
      _tx('7', 2850, 'Airtel Broadband', 'Bills', 6),
      _tx('8', 12000, 'Rent', 'Bills', 9),
      _tx('9', 4500, 'Zara', 'Shopping', 12),
      _tx('10', 65000, 'Salary', 'Income', 2, type: TransactionType.income),
    ];

typedef ScreenEntry = (String, Widget);

List<ScreenEntry> _screens() {
  final transaction = _demoLedger().first;
  return [
    ('home', const HomeScreen()),
    ('activity', const ActivityScreen()),
    ('add-transaction', const AddTransactionScreen()),
    ('ai-settings', const AISettingsScreen()),
    ('appearance', const AppearanceScreen()),
    ('assistant-privacy', const AssistantPrivacyScreen()),
    ('assistant', const AssistantScreen()),
    ('auth', const AuthScreen()),
    ('bills', const BillsScreen()),
    ('budgets', const BudgetsScreen()),
    ('cards', const CardsScreen()),
    ('insights', const InsightsScreen()),
    ('recurring', const RecurringScreen()),
    ('settings', const SettingsScreen()),
    ('sound-settings', const SoundSettingsScreen()),
    ('summary', const SummaryScreen()),
    ('transaction-details', TransactionDetailsScreen(transaction: transaction)),
    ('typography', const TypographyScreen()),
    ('update', const UpdateScreen()),
  ];
}

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

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadFonts();
  });

  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');
  const connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
  const secureStorage =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, (call) async => <int, int>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivity, (call) async => 'wifi');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
      return switch (call.method) {
        'read' => null,
        'readAll' => <String, String>{},
        'containsKey' => false,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissions, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivity, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
    AppColors.applyPalette(AppPalette.premiumBlue);
  });

  final palettes = [
    AppPalette.premiumBlue,
    AppPalette.deepNavy,
    AppPalette.softPastelTeal,
    AppPalette.plumBlush,
    // Paper is flat (no glass or gradients) with its own highlight ink, so it
    // must render every screen rather than being assumed similar.
    AppPalette.paper,
  ];

  for (final palette in palettes) {
    for (final dark in [false, true]) {
      testWidgets(
        '${palette.label} · ${dark ? 'dark' : 'light'} · every screen renders',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 2280);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          SharedPreferences.setMockInitialValues({
            'sms_scan_start_date': DateTime.now().toIso8601String(),
            'theme_mode': dark ? 'dark' : 'light',
            'palette_id': palette.id,
            'salary_day_setup': true,
            'salary_day': 1,
            'name': 'Asha',
            'email': 'asha@example.com',
          });

          AppColors.applyPalette(palette);

          final transactions = TransactionProvider();
          await transactions.ready;
          transactions.debugSeed(_demoLedger());
          await transactions.setMonthlyBudgetMinor(4000000);

          final planner = PlannerProvider();
          await planner.ready;

          final theme = ThemeProvider();
          final app = const SpendSenseApp();

          final failures = <String>[];

          for (final (name, screen) in _screens()) {
            final errors = <FlutterErrorDetails>[];
            final previousOnError = FlutterError.onError;
            FlutterError.onError = errors.add;

            try {
              await tester.pumpWidget(
                MultiProvider(
                  providers: [
                    ChangeNotifierProvider.value(value: transactions),
                    ChangeNotifierProvider(create: (_) => AuthProvider()),
                    ChangeNotifierProvider(
                      create: (_) => PeriodProvider()..init(),
                    ),
                    ChangeNotifierProvider.value(value: theme),
                    ChangeNotifierProvider.value(value: planner),
                    ChangeNotifierProvider(create: (_) => UpdateProvider()),
                  ],
                  child: MaterialApp(
                    key: ValueKey('$name-${palette.id}-$dark'),
                    debugShowCheckedModeBanner: false,
                    theme: app.themeFor(
                      dark ? Brightness.dark : Brightness.light,
                      theme.fontPreset,
                    ),
                    home: screen,
                  ),
                ),
              );

              await tester.pump(const Duration(milliseconds: 300));
              await tester.pump(const Duration(seconds: 1));

              // Walk the page: a first-viewport render never builds the rows
              // below the fold. Three flings exercise the rest of every long
              // list at the current palette and theme.
              for (var step = 0; step < 3; step++) {
                final scrollables = find.byType(Scrollable);
                if (scrollables.evaluate().isEmpty) break;
                await tester.fling(
                  scrollables.first,
                  const Offset(0, -700),
                  1500,
                );
                await tester.pump(const Duration(milliseconds: 600));
                await tester.pump(const Duration(milliseconds: 300));
              }
            } catch (error) {
              errors.add(FlutterErrorDetails(exception: error));
            } finally {
              FlutterError.onError = previousOnError;
              // Clear the binding's pending error so the next screen starts
              // from a clean slate.
              tester.takeException();
            }

            if (errors.isNotEmpty) {
              final first = errors.first;
              debugPrint('SCREEN FAILURE $name\n$first');
              failures.add('$name: ${first.exceptionAsString()}');
            }
          }

          expect(
            failures,
            isEmpty,
            reason: '${palette.label} · ${dark ? 'dark' : 'light'}',
          );
        },
      );
    }
  }
}
