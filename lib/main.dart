import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';

import 'providers/transaction_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/period_provider.dart';
import 'providers/planner_provider.dart';
import 'providers/sound_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/update_provider.dart';

import 'services/sound_service.dart';

import 'screens/home_screen.dart';
import 'screens/activity_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/add_transaction_screen.dart';
import 'screens/insights_screen.dart';
import 'screens/cards_screen.dart';

import 'utils/app_colors.dart';
import 'utils/app_spacing.dart';
import 'utils/app_typography.dart';
import 'widgets/app_background.dart';
import 'widgets/fade_indexed_stack.dart';
import 'widgets/floating_nav_bar.dart';
import 'widgets/sound_scope.dart';

/// 🔥 SpendSense 2.0: Local-First, Offline Personal Expense Tracker
///
/// API keys are never bundled with the app: they come from --dart-define
/// (CI/development) or from the in-app AI settings, which persist them in
/// platform-encrypted storage on the user's device.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    // Sound is a garnish that any screen may emit, so it is published above the
    // whole app. `SoundScope` is intentionally outside `MultiProvider`: widgets
    // resolve it without subscribing, and its absence is a valid, silent state
    // (which is what keeps widget tests free of audio hardware).
    SoundScope(
      provider: SoundProvider(),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TransactionProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          // Budgets, bills and recurring plans. Persisted encrypted with the
          // ledger key; never part of the transaction ledger itself.
          ChangeNotifierProvider(create: (_) => PlannerProvider()),
          // Loads the installed version and performs one silent, non-blocking
          // manifest check when OTA_MANIFEST_URL was supplied at build time.
          ChangeNotifierProvider(create: (_) => UpdateProvider()..init()),
        ],
        child: const SpendSenseApp(),
      ),
    ),
  );
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
          theme: _buildTheme(Brightness.light, theme.fontPreset),
          darkTheme: _buildTheme(Brightness.dark, theme.fontPreset),
          // Pushed routes use a transparent Scaffold over an AppBackground in
          // their body, so the app bar strip had nothing behind it and showed
          // the window's black (invisible title in light mode). One canvas
          // under the whole navigator fixes every screen.
          builder: (context, child) => ColoredBox(
            color: AppColors.scaffold(context),
            child: _withUserTextScale(context, child, theme.fontScale),
          ),
          home: const MainNavigationShell(),
        );
      },
    );
  }

  /// Composes the user's font-scale preference with the system text scale.
  /// The result is capped so the largest combination still fits the layouts
  /// (which are built to reflow up to 2x).
  static Widget _withUserTextScale(
    BuildContext context,
    Widget? child,
    double userScale,
  ) {
    if (child == null) return const SizedBox.shrink();
    if (userScale == FontScale.standard) return child;
    final media = MediaQuery.of(context);
    final system = media.textScaler.scale(14) / 14;
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(
          (system * userScale).clamp(0.8, 2.0).toDouble(),
        ),
      ),
      child: child,
    );
  }

  /// The app theme for [brightness], exposed so tests can inspect the real
  /// component themes (button ink, overlay surfaces) without booting the app.
  @visibleForTesting
  ThemeData themeFor(Brightness brightness, FontPreset preset) =>
      _buildTheme(brightness, preset);

  ThemeData _buildTheme(Brightness brightness, FontPreset preset) {
    final isDark = brightness == Brightness.dark;
    final baseTextTheme = AppTypography.textTheme(
      isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      preset: preset,
    );

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.brand,
      onPrimary: Colors.white,
      secondary: AppColors.brandBright,
      onSecondary: Colors.white,
      tertiary: AppColors.lime,
      onTertiary: const Color(0xFF0B3B2C),
      error: AppColors.danger,
      onError: Colors.white,
      surface: isDark ? AppColors.darkSurface : Colors.white,
      onSurface: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0A1A14),
      outlineVariant: AppColors.borderDarkOrLight(isDark),
    );

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: AppColors.borderDarkOrLight(isDark)),
    );

    // Navy palettes lift overlays one step above the canvas; AMOLED and light
    // keep their existing surfaces.
    final glassCanvas = isDark && AppColors.isGlassPalette;
    final overlaySurface = !isDark
        ? Colors.white
        : glassCanvas
            ? AppColors.darkSurfaceAlt
            : AppColors.darkSurface;
    final overlayEdge = glassCanvas
        ? BorderSide(color: Colors.white.withValues(alpha: 0.10))
        : BorderSide.none;

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
          color: isDark ? const Color(0xFF8A8A8A) : const Color(0xFF6B7A72),
        ),
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFFB3B3B3) : const Color(0xFF4A5A53),
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
          backgroundColor: AppColors.filledBrand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      // Text and outlined buttons use the readable brand ink, not the fill
      // colour: on a navy dialog the raw blue brand measured under 3:1.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
            foregroundColor: AppColors.brandInkFor(isDark)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandInkFor(isDark),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.filledBrand,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      // Chips (filter pills, prompt chips) follow the green selected state in
      // one place rather than being restyled per screen.
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : Colors.white,
        selectedColor: AppColors.brand.withValues(alpha: 0.16),
        side: BorderSide(color: AppColors.borderDarkOrLight(isDark)),
        labelStyle: TextStyle(
          color: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0A1A14),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        secondaryLabelStyle: TextStyle(
          color: AppColors.brandInkFor(isDark),
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        shape: const StadiumBorder(),
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
      // Overlays share one surface, one hairline and one radius scale so a
      // dialog, sheet, menu and picker read as the same family of glass.
      dialogTheme: DialogThemeData(
        backgroundColor: overlaySurface,
        surfaceTintColor: Colors.transparent,
        barrierColor: const Color(0x6B000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: overlayEdge,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: overlaySurface,
        modalBackgroundColor: overlaySurface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.borderDarkOrLight(isDark),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
          side: overlayEdge,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: overlaySurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: overlayEdge,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(overlaySurface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: overlayEdge,
          )),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: overlaySurface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: overlaySurface,
        headerForegroundColor: scheme.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: overlayEdge,
        ),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: overlaySurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: overlayEdge,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurfaceAlt : const Color(0xFF0B3B2C),
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

  /// The Add button hides while the user scrolls down (so it never sits on top
  /// of the content being read) and returns on scroll up or a tab change.
  bool _fabVisible = true;

  bool _onUserScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final visible = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _fabVisible,
    };
    if (visible != _fabVisible) setState(() => _fabVisible = visible);
    return false;
  }

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
      // Only a real tab change gets a cue; re-tapping the active tab is silent.
      SoundScope.play(context, SoundEventType.selectionChanged);
      setState(() {
        _currentIndex = index;
        _fabVisible = true;
      });
    }
  }

  void _openAddTransaction() {
    SoundScope.play(context, SoundEventType.buttonTap);
    // The dashboard's floating action opens the shared form as a modal sheet so
    // logging an entry never loses the dashboard behind it.
    showAddTransactionSheet(context);
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
        child: NotificationListener<UserScrollNotification>(
          onNotification: _onUserScroll,
          child: FadeIndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
        ),
      ),
      // End-floated rather than centre-floated: with five destinations the
      // centre slot is Insights and a centred button would cover its label.
      floatingActionButton: MediaQuery.maybeDisableAnimationsOf(context) == true
          // Reduced motion: no slide or fade, the button just appears or
          // disappears.
          ? (_fabVisible
              ? _AddFab(onPressed: _openAddTransaction)
              : const SizedBox.shrink())
          : IgnorePointer(
              ignoring: !_fabVisible,
              child: AnimatedSlide(
                offset: _fabVisible ? Offset.zero : const Offset(0, 1.5),
                duration: AppMotion.respect(context, AppMotion.base),
                curve: AppMotion.easeOut,
                child: AnimatedOpacity(
                  opacity: _fabVisible ? 1 : 0,
                  duration: AppMotion.respect(context, AppMotion.base),
                  child: _AddFab(onPressed: _openAddTransaction),
                ),
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

/// The floating Add action. Icon + tooltip carry the meaning, and the green
/// gradient is the primary action colour rather than a decorative glow.
class _AddFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    // On black the palette's mid→deep ramp ends in a muddy dark tone, so dark
    // mode runs brand into a lightly deepened brand instead (white icon stays
    // legible, the accent stays vivid).
    final gradient = dark
        ? LinearGradient(
            colors: [
              AppColors.filledBrand,
              Color.lerp(AppColors.filledBrand, AppColors.navyDeep, 0.4) ??
                  AppColors.filledBrand,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : AppColors.actionGradient;
    return SizedBox(
      width: 58,
      height: 58,
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        highlightElevation: 0,
        tooltip: 'Add transaction',
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            gradient: gradient,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.18 : 0.30),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.36),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}
