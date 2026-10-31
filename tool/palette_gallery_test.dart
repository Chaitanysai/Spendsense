// Render every screen for each 2026 palette and theme into a gallery.
//
// Run:
//   flutter test --no-pub tool/palette_gallery_test.dart
//
// Images land in build/palette_gallery/<palette>/<light|dark>/<screen>.png.
// They are build artefacts, not source: compose them into contact sheets and
// review; do not commit the raw captures.
//
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
import 'package:spendsense/widgets/app_background.dart';

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
    ('01-home', const HomeScreen()),
    ('02-activity', const ActivityScreen()),
    ('03-bills', const BillsScreen()),
    ('04-insights', const InsightsScreen()),
    ('05-cards', const CardsScreen()),
    ('06-settings', const SettingsScreen()),
    ('07-budgets', const BudgetsScreen()),
    ('08-recurring', const RecurringScreen()),
    ('09-assistant', const AssistantScreen()),
    ('10-appearance', const AppearanceScreen()),
    ('11-add', const AddTransactionScreen()),
    ('12-summary', const SummaryScreen()),
    ('13-assistant-privacy', const AssistantPrivacyScreen()),
    ('14-sound', const SoundSettingsScreen()),
    ('15-typography', const TypographyScreen()),
    ('16-update', const UpdateScreen()),
    ('17-auth', const AuthScreen()),
    ('18-details', TransactionDetailsScreen(transaction: transaction)),
    ('19-ai-settings', const AISettingsScreen()),
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
  });

  final palettes = [
    AppPalette.premiumBlue,
    AppPalette.deepNavy,
    AppPalette.softPastelTeal,
    AppPalette.plumBlush,
  ];

  for (final palette in palettes) {
    for (final dark in [false, true]) {
      testWidgets(
        'gallery · ${palette.id} · ${dark ? 'dark' : 'light'}',
        (tester) async {
          tester.view.physicalSize = const Size(1080, 2340);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          SharedPreferences.setMockInitialValues({
            'sms_scan_start_date': DateTime.now().toIso8601String(),
            'theme_mode': dark ? 'dark' : 'light',
            'palette_id': palette.id,
            'salary_day_setup': true,
            'salary_day': 1,
            'name': 'Chaitanya',
            'email': 'chai@example.com',
          });

          AppColors.applyPalette(palette);

          final transactions = TransactionProvider();
          await transactions.ready;
          transactions.debugSeed(_demoLedger());
          await transactions.setMonthlyBudgetMinor(5000000);

          final planner = PlannerProvider();
          await planner.ready;
          final theme = ThemeProvider();
          final app = const SpendSenseApp();

          final output = Directory(
            'build/palette_gallery/${palette.id}/${dark ? 'dark' : 'light'}',
          );
          // Runs inside the fake-async test zone: a real I/O future awaited
          // here would never complete. The synchronous call is safe and tiny.
          output.createSync(recursive: true);

          for (final (name, screen) in _screens()) {
            final key = ValueKey('gallery-$name-${palette.id}-$dark');
            await tester.pumpWidget(
              RepaintBoundary(
                key: key,
                child: ColoredBox(
                  // Some screens rely on the app-level canvas behind their
                  // transparent Scaffold; without this the captures composite
                  // their empty background onto black.
                  color: dark ? AppColors.darkBackground : AppColors.background,
                  child: MultiProvider(
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
                      home: name == '01-home'
                          ? const AppBackground(child: HomeScreen())
                          : screen,
                    ),
                  ),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(seconds: 1));

            final boundary =
                tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
            await tester.runAsync(() async {
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('${output.path}/$name.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
            });
          }
        },
      );
    }
  }
}
