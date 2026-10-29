import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'providers/transaction_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/period_provider.dart';
import 'providers/theme_provider.dart';

import 'services/app_check/app_check_bootstrap.dart';
import 'screens/home_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/add_transaction_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/cards_screen.dart';

import 'utils/app_colors.dart';
import 'utils/app_spacing.dart';
import 'widgets/app_background.dart';
import 'widgets/app_page_route.dart';
import 'widgets/fade_indexed_stack.dart';
import 'widgets/floating_nav_bar.dart';

/// 🔥 SpendSense 2.0: Local-First, Offline Personal Expense Tracker
///
/// API keys are never bundled with the app: they come from --dart-define
/// (CI/development) or from the in-app AI settings, which persist them in
/// platform-encrypted storage on the user's device.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeFirebase();

  runApp(
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
}

/// Starts Firebase for the platform from `lib/firebase_options.dart`, then
/// activates App Check once through the shared bootstrap gate.
///
/// Cloud features need it; the local ledger does not. A failure here is logged
/// and swallowed so the offline-first app still opens (for example on a
/// platform with no Firebase app registered, or with no network on first run)
/// instead of dying on launch.
Future<void> _initializeFirebase() async {
  if (Firebase.apps.isEmpty) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (error) {
      debugPrint(
        'Firebase did not start (${error.runtimeType}); running offline-only.',
      );
      return;
    }
  }

  try {
    await AppCheckBootstrap.shared.ensureActivated();
  } catch (error) {
    // App Check is fail-closed once enforcement is enabled, so a failure is
    // never replaced by a debug provider. Keep startup working so the local
    // ledger still opens; cloud features may be unavailable.
    debugPrint(
      'App Check did not start (${error.runtimeType}); '
      'cloud features may be unavailable.',
    );
  }
}

class SpendSenseApp extends StatelessWidget {
  const SpendSenseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, theme, _) {
        // MaterialApp reads AppColors at build time, so consuming
        // ThemeProvider here is what re-resolves every token after a palette
        // or appearance change.
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'SpendSense',
          themeMode: theme.themeMode,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          home: const MainNavigationShell(),
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final baseTextTheme = GoogleFonts.poppinsTextTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.brand,
      onPrimary: Colors.white,
      secondary: AppColors.cyan,
      onSecondary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: isDark ? AppColors.darkSurface : Colors.white,
      onSurface: isDark ? const Color(0xFFEAF1FF) : const Color(0xFF0A1734),
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: AppColors.borderDarkOrLight(isDark)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: baseTextTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      scaffoldBackgroundColor:
          isDark ? AppColors.darkBackground : AppColors.background,
      primaryColor: AppColors.brand,
      splashColor: AppColors.brand.withValues(alpha: 0.08),
      highlightColor: AppColors.brand.withValues(alpha: 0.04),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardColor: isDark ? AppColors.darkSurface : Colors.white,
      dividerColor: isDark ? AppColors.borderDark : AppColors.borderLight,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceAlt : Colors.white,
        hintStyle: TextStyle(
          color: isDark ? const Color(0xFF74879F) : const Color(0xFF8391AC),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: BorderSide(color: AppColors.brand, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.brand),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? AppColors.brand : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.brand.withValues(alpha: 0.4)
              : AppColors.borderDarkOrLight(isDark),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurfaceAlt : const Color(0xFF0A1734),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  static const List<NavItem> _navItems = [
    NavItem(Icons.home_rounded, 'HOME'),
    NavItem(Icons.receipt_long_rounded, 'ACTIVITY'),
    NavItem(Icons.insights_rounded, 'INSIGHTS'),
    NavItem(Icons.credit_card_rounded, 'CARDS'),
    NavItem(Icons.settings_rounded, 'SETTINGS'),
  ];

  final List<Widget> _screens = const [
    HomeScreen(),
    ActivityScreen(),
    InsightsScreen(),
    CardsScreen(),
    SettingsScreen(),
  ];

  void _onTap(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  void _openAddTransaction() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const AddTransactionScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to appearance changes. The FAB below reads its gradient
    // straight from the AppColors tokens rather than from Theme.of, so without
    // this dependency the shell would not rebuild when a stored palette is
    // restored on startup and would keep the default ramp it painted first.
    context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: AppBackground(
        child: FadeIndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
      ),
      // End-floated rather than centre-floated: with five destinations the
      // centre slot is Insights and a centred button would cover its label.
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddTransaction,
        backgroundColor: Colors.transparent,
        elevation: 0,
        highlightElevation: 0,
        tooltip: 'Add transaction',
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: AppColors.electricGradient,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandBright.withValues(alpha: 0.42),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: FloatingNavBar(
        items: _navItems,
        currentIndex: _currentIndex,
        onTap: _onTap,
      ),
    );
  }
}
