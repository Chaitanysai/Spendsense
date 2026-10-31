import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/launch_screen.dart';
import 'package:spendsense/widgets/app_logo.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
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
}
