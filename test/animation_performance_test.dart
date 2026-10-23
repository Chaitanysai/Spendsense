import 'dart:async';

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
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/widgets/fade_indexed_stack.dart';
import 'package:spendsense/widgets/fade_slide_in.dart';

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

    testWidgets('an entrance animation plays once, not on every revisit',
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
              .ancestor(
                of: find.text('B-content'),
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
      expect(entranceOpacity(), 1.0,
          reason: 'the inner entrance must not restart on a revisit');
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

    testWidgets('Activity syncs SMS at launch and again on every return',
        (tester) async {
      final provider = await pumpShell(tester, withStartDate: true);
      expect(provider.syncs, 1, reason: 'one sync at launch');

      await goTo(tester, 'ACTIVITY');
      expect(provider.syncs, 2, reason: 'returning to Activity re-syncs');

      await goTo(tester, 'HOME');
      expect(provider.syncs, 2, reason: 'leaving Activity must not sync');

      await goTo(tester, 'ACTIVITY');
      expect(provider.syncs, 3);

      // Re-tapping the tab you are already on is not a return.
      await goTo(tester, 'ACTIVITY');
      expect(provider.syncs, 3);
    });

    testWidgets('a return while a sync is running does not start another',
        (tester) async {
      final provider = await pumpShell(tester, withStartDate: true);
      provider.syncing = true;

      await goTo(tester, 'INSIGHTS');
      await goTo(tester, 'ACTIVITY');
      await goTo(tester, 'HOME');
      await goTo(tester, 'ACTIVITY');

      expect(provider.syncs, 1, reason: 'only the launch sync ran');
    });

    testWidgets('Activity keeps its search text across tab switches',
        (tester) async {
      await pumpShell(tester, withStartDate: true);
      await goTo(tester, 'ACTIVITY');

      await tester.enterText(find.byType(TextField).first, 'swiggy');
      await tester.pump();

      await goTo(tester, 'HOME');
      await goTo(tester, 'ACTIVITY');

      expect(find.text('swiggy'), findsOneWidget);
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
        'a dismissed start-date prompt comes back on return to Home, '
        'but never opens twice at once', (tester) async {
      await pumpShell(tester, withStartDate: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Check SMS from when?'), findsOneWidget);

      // Dismiss the sheet the way a back gesture would.
      Navigator.of(tester.element(find.text('Check SMS from when?'))).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Check SMS from when?'), findsNothing);

      // Staying on Home must not re-open it.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Check SMS from when?'), findsNothing);

      await goTo(tester, 'INSIGHTS');
      await goTo(tester, 'HOME');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Check SMS from when?'), findsOneWidget,
          reason: 'same as before: an unset date is asked again on return');
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
  Future<void> syncFromSms() async {
    syncs++;
  }
}
