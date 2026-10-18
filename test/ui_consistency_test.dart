import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/screens/insights_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/category_bubble_cluster.dart';

/// Guards the light/dark colour contracts that the premium-card pass relies on,
/// plus the empty states the brief asked for.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => AppColors.applyPalette(AppPalette.oceanBlue));
  tearDown(() => AppColors.applyPalette(AppPalette.oceanBlue));

  group('glass tokens respect brightness', () {
    Future<T> read<T>(
        WidgetTester tester, Brightness b, T Function(BuildContext) f) async {
      late T value;
      await tester.pumpWidget(
        MaterialApp(
          theme: b == Brightness.dark ? ThemeData.dark() : ThemeData.light(),
          home: Builder(
            builder: (c) {
              value = f(c);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // MaterialApp animates between themes; read only once it has settled, or
      // a light read can still observe the previous dark theme.
      await tester.pumpAndSettle();
      return value;
    }

    testWidgets('glassFill differs between light and dark', (tester) async {
      final darkBrightness =
          await read(tester, Brightness.dark, (c) => Theme.of(c).brightness);
      expect(darkBrightness, Brightness.dark,
          reason: 'dark theme must actually resolve as dark');
      final lightFill =
          await read(tester, Brightness.light, AppColors.glassFill);
      final darkFill = await read(tester, Brightness.dark, AppColors.glassFill);

      expect(lightFill, isNot(darkFill));
      // The dark card is tinted toward the palette navy, not a neutral grey, so
      // its blue channel leads its red one.
      expect(darkFill.b, greaterThan(darkFill.r));
    });

    testWidgets('glass sheen is faint in dark, full in light', (tester) async {
      final lightSheen =
          await read(tester, Brightness.light, AppColors.glassSheenFor);
      final darkSheen =
          await read(tester, Brightness.dark, AppColors.glassSheenFor);

      expect(lightSheen, AppColors.glassSheen);
      expect(darkSheen, AppColors.darkGlassSheen);
      expect(
        lightSheen.colors.first.a,
        greaterThan(darkSheen.colors.first.a),
      );
    });
  });

  group('CategoryBubbleCluster', () {
    testWidgets('empty totals show a described empty state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CategoryBubbleCluster(totals: {})),
        ),
      );
      expect(find.text('No spending to chart yet'), findsOneWidget);
    });

    testWidgets('on a gradient the labels invert to white', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CategoryBubbleCluster(
              totals: {'Food': 100},
              onGradient: true,
            ),
          ),
        ),
      );
      final label = tester.widget<Text>(find.text('Food'));
      expect(label.style?.color, Colors.white);
    });

    testWidgets('on a plain surface the labels stay theme-coloured',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CategoryBubbleCluster(totals: {'Food': 100}),
          ),
        ),
      );
      final label = tester.widget<Text>(find.text('Food'));
      expect(label.style?.color, isNot(Colors.white));
    });
  });

  group('empty states reach the screens', () {
    Widget app(Widget home) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => TransactionProvider()),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(home: home),
        );

    testWidgets('Home category card explains the empty state', (tester) async {
      SharedPreferences.setMockInitialValues({
        'sms_scan_start_date': DateTime.now().toIso8601String(),
      });
      await tester.pumpWidget(app(const HomeScreen()));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No spending to break down yet'), findsOneWidget);
      expect(find.text('Add expense'), findsWidgets);
    });

    testWidgets('Insights top categories explain the empty state',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(app(const InsightsScreen()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('No spending recorded this month yet.'), findsOneWidget);
    });
  });
}
