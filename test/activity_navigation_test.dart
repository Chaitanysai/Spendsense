import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/activity_screen.dart';
import 'package:spendsense/widgets/app_page_route.dart';

/// Counts automatic syncs so a test can prove the scan does not start inside
/// the push transition.
class _CountingProvider extends TransactionProvider {
  int syncs = 0;
  bool fakeSyncing = false;

  @override
  bool get isSyncing => fakeSyncing;

  @override
  Future<void> syncFromSms({bool userInitiated = false}) async {
    syncs++;
  }
}

TransactionModel _tx(String id) => TransactionModel(
      id: id,
      amountMinor: 1200,
      type: TransactionType.expense,
      merchant: 'Cafe',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 20),
      time: '09:00',
      originalSms: '',
      isExcluded: false,
    );

Widget _harness(_CountingProvider provider, {bool reduceMotion = false}) {
  return ChangeNotifierProvider<TransactionProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () => AppPageRoute.pushOnce(
                  context,
                  name: ActivityScreen.routeName,
                  builder: (_) => const ActivityScreen(),
                ),
                child: const Text('See all'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps through the push/reverse transitions using bounded frames.
///
/// [WidgetTester.pumpAndSettle] would spin forever on a screen that shows the
/// repeating skeleton shimmer, so route tests use known durations instead.
Future<void> _settleRoute(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _CountingProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppPageRoute.debugResetInFlight();
    provider = _CountingProvider();
  });

  tearDown(() => provider.dispose());

  testWidgets('See all opens exactly one Activity route', (tester) async {
    await tester.pumpWidget(_harness(provider));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityScreen), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(ActivityScreen)))!;
    expect(route.settings.name, ActivityScreen.routeName);
  });

  testWidgets('a rapid double tap cannot stack two Activity screens',
      (tester) async {
    await tester.pumpWidget(_harness(provider));

    // Two taps inside one frame window, before the first push completes.
    await tester.tap(find.byKey(const Key('open')));
    await tester.tap(find.byKey(const Key('open')), warnIfMissed: false);
    await _settleRoute(tester);

    expect(find.byType(ActivityScreen), findsOneWidget);
    // Back once returns to the launcher: there is no second route underneath.
    Navigator.of(tester.element(find.byType(ActivityScreen))).pop();
    await _settleRoute(tester);
    expect(find.byType(ActivityScreen), findsNothing);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('the automatic SMS scan waits for the transition to finish',
      (tester) async {
    await tester.pumpWidget(_harness(provider));
    await tester.tap(find.byKey(const Key('open')));

    // First frame of the push: the route is animating, the scan must not run.
    await tester.pump();
    expect(provider.syncs, 0,
        reason: 'starting the scan here is what made the push feel slow');

    await tester.pumpAndSettle();
    expect(provider.syncs, 1,
        reason: 'the scan starts when the route animation completes');
  });

  testWidgets('reduced motion completes the route and starts one scan',
      (tester) async {
    await tester.pumpWidget(_harness(provider, reduceMotion: true));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();

    expect(find.byType(ActivityScreen), findsOneWidget);
    expect(provider.syncs, 1);
  });

  testWidgets('an in-flight sync is not started a second time', (tester) async {
    await tester.runAsync(() => provider.ready);
    // A non-empty list keeps the loading skeleton (an endless shimmer) off
    // screen, so bounded pumps are enough to settle the route.
    provider.debugSeed([_tx('a')]);
    provider.fakeSyncing = true;
    await tester.pumpWidget(_harness(provider));
    await tester.tap(find.byKey(const Key('open')));
    await _settleRoute(tester);

    expect(provider.syncs, 0);
  });

  testWidgets('seeded transactions render without rebuilding the filter twice',
      (tester) async {
    await tester.runAsync(() => provider.ready);
    provider.debugSeed([_tx('a'), _tx('b'), _tx('c')]);

    await tester.pumpWidget(_harness(provider));
    await tester.tap(find.byKey(const Key('open')));
    await _settleRoute(tester);

    expect(find.text('3 transactions'), findsOneWidget);
    // A rebuild triggered from outside the filter (e.g. a parent setState)
    // must not change the rendered result.
    await tester.pump();
    expect(find.text('3 transactions'), findsOneWidget);
  });
}
