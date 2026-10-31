import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/services/sms_service.dart';
import 'package:spendsense/widgets/sms_import_prompt.dart';

/// The SMS start date is a first-run question with a long memory: it is asked
/// once, stored, reused by every later sync, and changeable only from Settings.

const String _startKey = 'sms_scan_start_date';

Future<TransactionProvider> _pumpPromptHost(WidgetTester tester) async {
  final provider = TransactionProvider();
  await provider.ready;

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => SmsImportPrompt.show(context),
              child: const Text('open prompt'),
            ),
          ),
        ),
      ),
    ),
  );
  return provider;
}

Future<TransactionProvider> _pumpHome(
  WidgetTester tester, {
  required VoidCallback onFetch,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final provider = TransactionProvider(
    smsService: SmsService(
      requestSmsPermission: () async => PermissionStatus.granted,
    ),
    resyncFetcher: () async {
      onFetch();
      return const [];
    },
  );
  await provider.ready;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: provider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  return provider;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('the stored date is what the sheet opens on', (tester) async {
    final saved = DateTime(2025, 10, 30);
    SharedPreferences.setMockInitialValues({
      _startKey: saved.toIso8601String(),
    });

    final provider = await _pumpPromptHost(tester);

    await tester.tap(find.text('open prompt'));
    await tester.pumpAndSettle();

    expect(find.text('30 Oct 2025'), findsOneWidget);
    expect(provider.smsScanStartDate, saved);
  });

  testWidgets('dismissing the first-run sheet stores the date it was showing',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final expected = DateTime(now.year, now.month, 1);

    final provider = await _pumpPromptHost(tester);

    await tester.tap(find.text('open prompt'));
    await tester.pumpAndSettle();
    expect(
        find.text(DateFormat('d MMM yyyy').format(expected)), findsOneWidget);

    // Tap the barrier: a dismissal, not the save button.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(provider.hasSmsScanStartDate, isTrue);
    expect(provider.smsScanStartDate, expected);
    expect(find.textContaining('Change it in Settings'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_startKey), expected.toIso8601String());
  });

  testWidgets('dismissing the sheet leaves an existing date untouched',
      (tester) async {
    final saved = DateTime(2025, 10, 30);
    SharedPreferences.setMockInitialValues({
      _startKey: saved.toIso8601String(),
    });

    final provider = await _pumpPromptHost(tester);

    await tester.tap(find.text('open prompt'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(provider.smsScanStartDate, saved);
    expect(find.textContaining('Change it in Settings'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_startKey), saved.toIso8601String());
  });

  testWidgets('the Sync SMS action syncs instead of asking again',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      _startKey: DateTime(2025, 10, 30).toIso8601String(),
    });

    var fetches = 0;
    await _pumpHome(tester, onFetch: () => fetches++);
    final before = fetches;

    await tester.tap(find.text('Sync SMS'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(fetches, before + 1,
        reason: 'the Sync SMS quick action must actually scan');
    expect(find.text('Check SMS from when?'), findsNothing,
        reason: 'a stored date must never be asked for again');
  });
}
