// A device preview harness for the Home redesign.
//
// It runs the real HomeScreen with a fixed, in-memory ledger and budget so the
// redesigned states can be reviewed on hardware without touching the installed
// SpendSense app or any real data. Build it under a separate application id
// (the `preview` flavor step is documented in docs/design-research).
//
// Run:
//   flutter run -t tool/preview_app.dart -d <device>
//
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/planner_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/providers/update_provider.dart';
import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/widgets/app_background.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('theme_mode', 'dark');
  await prefs.setString('palette_id', 'midnight');
  await prefs.setString('name', 'Chaitanya');
  await prefs.setString('email', 'chai@example.com');
  await prefs.setBool('salary_day_setup', true);
  await prefs.setInt('salary_day', 1);
  // Suppress the first-run SMS prompt; this preview never reads messages.
  await prefs.setString(
    'sms_scan_start_date',
    DateTime.now().toIso8601String(),
  );

  AppColors.applyPalette(AppPalette.midnight);

  final transactions = TransactionProvider();
  await transactions.ready;
  transactions.debugSeed(_demoLedger());
  // Mark the scan window as chosen so the first-run SMS prompt and permission
  // request never appear over the preview. `resync: false` keeps it offline.
  await transactions.setSmsScanStartDate(
    DateTime.now().subtract(const Duration(days: 30)),
    resync: false,
  );
  try {
    await transactions.setMonthlyBudgetMinor(5000000);
  } catch (_) {
    // The preview still renders with the default budget if persistence is
    // unavailable; nothing here should block the screen.
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: transactions),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => PlannerProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: const _PreviewApp(),
    ),
  );
}

List<TransactionModel> _demoLedger() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  TransactionModel tx(
    String id,
    int rupees,
    String merchant,
    String category,
    int daysAgo, {
    TransactionType type = TransactionType.expense,
    String method = 'UPI',
  }) {
    final date = today.subtract(Duration(days: daysAgo));
    return TransactionModel(
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
  }

  return [
    tx('p1', 420, 'Blue Tokai', 'Food', 0),
    tx('p2', 78, 'Metro Card', 'Travel', 0),
    tx('p3', 649, 'Netflix', 'Entertainment', 1),
    tx('p4', 1240, 'Nature Basket', 'Food', 2),
    tx('p5', 2199, 'FabIndia', 'Shopping', 3),
    tx('p6', 500, 'HP Petrol', 'Fuel', 4),
    tx('p7', 320, 'Third Wave', 'Food', 5),
    tx('p8', 2850, 'Airtel Broadband', 'Bills', 6),
    tx('p9', 12000, 'Rent', 'Bills', 9),
    tx('p10', 4500, 'Zara', 'Shopping', 12),
    tx('p11', 2100, 'Blue Tokai', 'Food', 16),
    tx('p12', 65000, 'Salary', 'Income', 2,
        type: TransactionType.income, method: 'Bank'),
  ];
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SpendSense Preview',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const _PreviewShell(),
    );
  }
}

class _PreviewShell extends StatefulWidget {
  const _PreviewShell();

  @override
  State<_PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<_PreviewShell> {
  /// Mirrors the production shell: the Add button steps out of the way while
  /// the user scrolls down, so the chart and list underneath stay tappable.
  bool _fabVisible = true;

  bool _onScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final visible = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _fabVisible,
    };
    if (visible != _fabVisible) setState(() => _fabVisible = visible);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onScroll,
        child: const AppBackground(child: HomeScreen()),
      ),
      floatingActionButton: _fabVisible
          ? FloatingActionButton(
              onPressed: () => showAddTransactionSheet(context),
              backgroundColor: AppColors.filledBrand,
              tooltip: 'Add transaction',
              child: const Icon(Icons.add_rounded, color: Colors.white),
            )
          : null,
      bottomNavigationBar: FloatingNavBar(
        items: const [
          NavItem(Icons.home_rounded, 'HOME'),
          NavItem(Icons.event_note_rounded, 'BILLS'),
          NavItem(Icons.insights_rounded, 'INSIGHTS'),
          NavItem(Icons.credit_card_rounded, 'CARDS'),
          NavItem(Icons.settings_rounded, 'SETTINGS'),
        ],
        currentIndex: 0,
        onTap: (_) {},
      ),
    );
  }
}
