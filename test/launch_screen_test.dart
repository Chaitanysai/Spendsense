import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/launch_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';
import 'package:spendsense/widgets/app_logo.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() => AppColors.applyPalette(AppPalette.defaultPalette));

  testWidgets('launch screen paints the mark and wordmark', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SpendSenseLaunchScreen()),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('SpendSense'), findsOneWidget);
    expect(find.text('SMART MONEY COPILOT'), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the gate is bypassed in debug/test builds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppLaunchGate(child: Scaffold(body: Text('app-ready'))),
      ),
    );
    await tester.pump();

    expect(find.text('app-ready'), findsOneWidget);
    expect(find.byType(SpendSenseLaunchScreen), findsNothing);
  });

  testWidgets('forced gate holds the launch screen then reveals the app',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final transactions = TransactionProvider();
    await transactions.ready;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: transactions),
        ],
        child: const MaterialApp(
          home: AppLaunchGate(
            forceShow: true,
            minimumDuration: Duration(milliseconds: 50),
            child: Scaffold(body: Text('app-ready')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SpendSenseLaunchScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('app-ready'), findsOneWidget);
    expect(find.byType(SpendSenseLaunchScreen), findsNothing);
  });

  testWidgets('launch canvas follows the active palette for every theme',
      (tester) async {
    // The launch screen used to paint Premium Blue's ramp literally, so every
    // other theme flashed navy before its own world appeared. This locks the
    // canvas to the selected palette and keeps the white wordmark legible on
    // the darkest and lightest stop alike.
    final seen = <String>{};
    for (final palette in AppPalette.all) {
      AppColors.applyPalette(palette);
      // A unique key per palette forces a fresh element: without it the first
      // build is reused and the canvas would be read from the previous theme.
      await tester.pumpWidget(
        MaterialApp(
          home: SpendSenseLaunchScreen(key: ValueKey(palette.id)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      final canvas = scaffold.backgroundColor!;
      seen.add(canvas.toARGB32().toRadixString(16));

      // White copy sits on this canvas, so it has to clear AA.
      expect(AppColors.contrastRatio(Colors.white, canvas),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.id}: wordmark is unreadable on the launch canvas');

      // Each palette must paint its own canvas, not a shared fixed one.
      expect(AppColors.contrastRatio(canvas, palette.darkBackground),
          lessThan(4.5),
          reason: '${palette.id}: launch canvas ignores the palette');

      expect(tester.takeException(), isNull, reason: palette.id);
    }

    // Distinct themes must produce distinct launch canvases.
    expect(seen.length, greaterThan(10),
        reason: 'launch canvas collapsed to a handful of fixed colours');
  });
}
