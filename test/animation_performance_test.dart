import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/screens/bills_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:spendsense/main.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/providers/period_provider.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/widgets/fade_indexed_stack.dart';
import 'package:spendsense/widgets/fade_slide_in.dart';
import 'package:spendsense/widgets/page_entry.dart';

/// A tab body that counts how often its State is created, like the real tab
/// screens (no GlobalKey, const instances held by the shell).
class _Probe extends StatefulWidget {
  final String label;
  final List<String> log;
  const _Probe(this.label, this.log);

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init ${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('dispose ${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

void main() {
  group('tab stack rebuild cost', () {
    testWidgets(
        'switching tabs never re-creates or disposes a tab (no keys needed)',
        (tester) async {
      final log = <String>[];
      final children = [_Probe('A', log), _Probe('B', log), _Probe('C', log)];

      Widget host(int index) => MaterialApp(
            home: FadeIndexedStack(index: index, children: children),
          );

      await tester.pumpWidget(host(0));
      await tester.pumpAndSettle();
      final afterFirstBuild = List<String>.of(log);

      for (final i in [1, 2, 0, 2, 1, 0]) {
        await tester.pumpWidget(host(i));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();

      expect(
        log.where((e) => e.startsWith('dispose')),
        isEmpty,
        reason: 'a tab that is switched away from must stay alive',
      );
      expect(
        log.where((e) => e.startsWith('init')).length,
        afterFirstBuild.where((e) => e.startsWith('init')).length,
        reason: 'a tab must not run initState again on every switch',
      );
    });

    testWidgets('reduced motion also keeps every tab alive', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      final log = <String>[];
      final children = [_Probe('A', log), _Probe('B', log)];
      Widget host(int index) => MaterialApp(
            home: FadeIndexedStack(index: index, children: children),
          );

      await tester.pumpWidget(host(0));
      for (final i in [1, 0, 1]) {
        await tester.pumpWidget(host(i));
        await tester.pump();
      }

      expect(log.where((e) => e.startsWith('dispose')), isEmpty);
      expect(log.where((e) => e.startsWith('init')).length, 2);
    });

    testWidgets('only the visible tab is laid out and painted', (tester) async {
      final log = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: FadeIndexedStack(
          index: 1,
          children: [_Probe('A', log), _Probe('B', log)],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('B'), findsOneWidget);
      expect(find.text('A'), findsNothing); // offstage, skipped by find
      expect(find.text('A', skipOffstage: false), findsOneWidget);
    });

    testWidgets('FadeSlideIn reaches rest and stops its ticker',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FadeSlideIn(child: Text('x')),
      ));
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('tab stack animation behaviour', () {
    testWidgets('rapid switching ends with no running tickers or layers',
        (tester) async {
      final log = <String>[];
      final children = [
        _Probe('A', log),
        const FadeSlideIn(child: Text('B')),
        _Probe('C', log),
      ];
      Widget host(int index) => MaterialApp(
            home: FadeIndexedStack(index: index, children: children),
          );

      await tester.pumpWidget(host(0));
      for (final i in [1, 2, 0, 1, 2, 1, 0, 2, 0]) {
        await tester.pumpWidget(host(i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();

      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'nothing may keep ticking once the last fade finished');
      expect(log.where((e) => e.startsWith('dispose')), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a retained tab does NOT replay its entrance when re-selected',
        (tester) async {
      final children = [
        const Text('A'),
        const FadeSlideIn(child: Text('B-content')),
      ];
      Widget host(int index) => MaterialApp(
            home: FadeIndexedStack(index: index, children: children),
          );

      await tester.pumpWidget(host(0));
      await tester.pumpWidget(host(1));
      await tester.pumpAndSettle();

      double entranceOpacity() => tester
          .widget<FadeTransition>(find
              .descendant(
                of: find.byType(PageEntrance),
                matching: find.byType(FadeTransition),
              )
              .first)
          .opacity
          .value;
      expect(entranceOpacity(), 1.0);

      await tester.pumpWidget(host(0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(1));
      await tester.pump();
      await tester.pump();

      // Regression: this used to restart the whole page entrance (400 ms fade +
      // slide) on every tab switch, and re-trigger everything keyed off the
      // page-entry generation — the hero balance counting up from zero, budget
      // bars refilling from empty. A page the user returns to is already
      // familiar; it must appear at rest.
      expect(entranceOpacity(), 1.0,
          reason: 'returning to a retained tab must not replay its entrance');

      await tester.pump(const Duration(milliseconds: 500));
      expect(entranceOpacity(), 1.0);

      // An unrelated rebuild must not start it either.
      await tester.pumpWidget(host(1));
      await tester.pump();
      expect(entranceOpacity(), 1.0,
          reason: 'only a first entry may play an entrance animation');
    });
  });

  group('shell: state kept across tab switches', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    Future<_CountingProvider> pumpShell(
      WidgetTester tester, {
      required bool withStartDate,
    }) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        if (withStartDate)
          'sms_scan_start_date': DateTime.now().toIso8601String(),
      });
      final provider = _CountingProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<TransactionProvider>.value(value: provider),
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const SpendSenseApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      return provider;
    }

    Future<void> goTo(WidgetTester tester, String label) async {
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('the shell syncs once on launch, and tab navigation never does',
        (tester) async {
      final provider = await pumpShell(tester, withStartDate: true);

      // The shell owns the launch sync now: it fires once, after the first
      // frame, regardless of which tab is showing.
      expect(provider.syncs, 1, reason: 'launch performs exactly one scan');

      await goTo(tester, 'BILLS');
      expect(provider.syncs, 1,
          reason: 'passive navigation must not scan SMS or ask permission');

      await goTo(tester, 'HOME');
      await goTo(tester, 'BILLS');
      await goTo(tester, 'INSIGHTS');
      expect(provider.syncs, 1, reason: 'no tab switch adds a scan');
    });

    testWidgets('a running sync is not restarted by visiting Bills',
        (tester) async {
      final provider = await pumpShell(tester, withStartDate: true);
      final afterLaunch = provider.syncs;
      provider.syncing = true;

      await goTo(tester, 'INSIGHTS');
      await goTo(tester, 'BILLS');
      await goTo(tester, 'HOME');
      await goTo(tester, 'BILLS');

      expect(provider.syncs, afterLaunch,
          reason: 'Bills never starts or joins a scan');
    });

    testWidgets('Bills stays alive across tab switches', (tester) async {
      await pumpShell(tester, withStartDate: true);
      await goTo(tester, 'BILLS');
      await goTo(tester, 'HOME');
      expect(find.byType(BillsScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('Settings re-checks the connection each time it is shown',
        (tester) async {
      var checks = 0;
      const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'check') checks++;
        return 'wifi';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      await pumpShell(tester, withStartDate: true);
      final atLaunch = checks;
      expect(atLaunch, 1);

      await goTo(tester, 'SETTINGS');
      expect(checks, atLaunch + 1);

      await goTo(tester, 'HOME');
      expect(checks, atLaunch + 1, reason: 'leaving must not re-check');

      await goTo(tester, 'SETTINGS');
      expect(checks, atLaunch + 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Settings ignores a connection check that finishes after it '
        'was disposed', (tester) async {
      final gate = Completer<void>();
      var hold = false;
      const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (hold) await gate.future;
        return 'wifi';
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      await pumpShell(tester, withStartDate: true);
      hold = true;
      await goTo(tester, 'SETTINGS'); // starts a check that stays pending

      await tester.pumpWidget(const SizedBox()); // the whole shell is gone
      gate.complete();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    testWidgets('Insights rebuilds when its tab is shown again',
        (tester) async {
      final provider = await pumpShell(tester, withStartDate: true);
      await goTo(tester, 'INSIGHTS');
      await goTo(tester, 'HOME');

      provider.transactionReads = 0;
      await goTo(tester, 'INSIGHTS');

      expect(provider.transactionReads, greaterThan(0),
          reason: 'month totals use DateTime.now(), so a return must refresh');
    });

    testWidgets('Home asks for the SMS start date when none is set',
        (tester) async {
      await pumpShell(tester, withStartDate: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Check SMS from when?'), findsOneWidget);
    });

    testWidgets(
        'a dismissed start-date prompt stores the date and never comes back',
        (tester) async {
      final provider = await pumpShell(tester, withStartDate: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Check SMS from when?'), findsOneWidget);

      // Dismiss the sheet the way a back gesture would.
      Navigator.of(tester.element(find.text('Check SMS from when?'))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Check SMS from when?'), findsNothing);
      expect(provider.hasSmsScanStartDate, isTrue,
          reason: 'a dismissal keeps the date the sheet was showing');

      // Staying on Home must not re-open it.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Check SMS from when?'), findsNothing);

      // Let the confirmation snackbar clear so it cannot intercept taps.
      await tester.pump(const Duration(seconds: 5));

      await goTo(tester, 'INSIGHTS');
      await goTo(tester, 'HOME');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Check SMS from when?'), findsNothing,
          reason: 'the question is asked once; the stored date answers it');
    });

    testWidgets('Home does not ask when a start date already exists',
        (tester) async {
      await pumpShell(tester, withStartDate: true);
      await goTo(tester, 'INSIGHTS');
      await goTo(tester, 'HOME');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Check SMS from when?'), findsNothing);
    });
  });
}

/// Counts sync requests instead of reading real SMS.
class _CountingProvider extends TransactionProvider {
  int syncs = 0;
  bool syncing = false;
  int transactionReads = 0;

  @override
  List<TransactionModel> get transactions {
    transactionReads++;
    return super.transactions;
  }

  @override
  bool get isSyncing => syncing;

  @override
  Future<void> syncFromSms({bool userInitiated = false}) async {
    syncs++;
  }
}
