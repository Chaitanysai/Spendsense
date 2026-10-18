import 'package:flutter/material.dart';
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
import 'package:spendsense/screens/activity_screen.dart';
import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/screens/transaction_details_screen.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';
import 'package:spendsense/widgets/transaction_tile.dart';

/// Stage 3 — navigation transitions and the shared-element flight.
TransactionModel _tx(double amount, {String merchant = 'Zomato'}) =>
    TransactionModel(
      id: 'nav-$amount',
      amount: amount.toInt(),
      type: TransactionType.expense,
      merchant: merchant,
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime.now(),
      time: '',
      originalSms: '',
      isExcluded: false,
      source: 'Test',
    );

Future<TransactionProvider> _pumpShell(
  WidgetTester tester, {
  List<TransactionModel> seed = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime.now().toIso8601String(),
  });
  final transactions = TransactionProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: transactions),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const SpendSenseApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  // The provider's cache read lands after the first frames and would otherwise
  // replace a seed applied too early.
  await tester.pump(const Duration(seconds: 1));
  if (seed.isNotEmpty) {
    transactions.debugSeed(seed);
    await tester.pump(const Duration(milliseconds: 400));
  }
  return transactions;
}

/// The dashboard builds its sliver children lazily, so a row exists only once
/// it has been scrolled into view.
Future<void> _revealRows(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    if (find.byType(TransactionTile).evaluate().isNotEmpty) return;
    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('no TransactionTile became visible after scrolling the dashboard');
}

/// A pushed page is not in the tree until the frame after `pump()` settles, so
/// every navigation assertion follows this two-step advance.
Future<void> _settlePush(WidgetTester tester, {Duration? beyond}) async {
  await tester.pump();
  await tester.pump(beyond ?? AppMotion.base);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('tile to details flight', () {
    testWidgets('opening a row pushes details and completes the Hero',
        (tester) async {
      await _pumpShell(tester, seed: [_tx(250)]);
      await _revealRows(tester);

      /// The tag the row carries before anything is pushed. Flutter replaces a
      /// hero with a placeholder while it flies, so the pairing can only be
      /// compared against the destination, not while both are mid-flight.
      Object? rowTag() => tester
          .widgetList<Hero>(find.descendant(
              of: find.byType(TransactionTile).first,
              matching: find.byType(Hero)))
          .first
          .tag;

      final expectedTag = rowTag();
      expect(expectedTag, isNotNull,
          reason: 'the row must offer a shared element');

      await tester.tap(find.byType(TransactionTile).first);
      // The page enters the tree on the frame after the push is claimed, so
      // advance twice before reading geometry.
      await tester.pump();
      await tester.pump();
      expect(find.byType(TransactionDetailsScreen), findsOneWidget);

      // First frame of the transition: still sliding up from its start offset.
      final startY =
          tester.getTopLeft(find.byType(TransactionDetailsScreen)).dy;
      expect(startY, greaterThan(0),
          reason:
              'the pushed page must animate into place, not appear instantly');

      await tester.pump(AppMotion.base ~/ 2);
      await tester.pump(AppMotion.slow);

      final landingTags = tester
          .widgetList<Hero>(find.descendant(
              of: find.byType(TransactionDetailsScreen),
              matching: find.byType(Hero)))
          .map((h) => h.tag)
          .toList();
      expect(landingTags, contains(expectedTag),
          reason: 'the details page must land on the tag the row flew from');
      expect(tester.getTopLeft(find.byType(TransactionDetailsScreen)).dy,
          closeTo(0, 0.5),
          reason: 'the transition must finish with the page exactly in place');
      expect(tester.takeException(), isNull);
      expect(find.text('Edit transaction'), findsOneWidget);
    });

    testWidgets('Home and Activity rows do not collide on hero tags',
        (tester) async {
      // Both tabs stay mounted in the shell route, so an unscoped tag would put
      // two Heroes with the same key in one PageRoute subtree — which Flutter
      // turns into an exception the moment a flight starts.
      await _pumpShell(tester, seed: [_tx(250), _tx(700, merchant: 'Uber')]);
      await _revealRows(tester);

      await tester.tap(find.text('ACTIVITY'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final homeStillMounted =
          find.byType(HomeScreen, skipOffstage: false).evaluate().isNotEmpty;
      expect(homeStillMounted, isTrue,
          reason: 'Home must stay mounted underneath the Activity tab');
      expect(find.byType(ActivityScreen), findsOneWidget);

      await tester.tap(find.byType(TransactionTile).first);
      await _settlePush(tester);
      await tester.pump(AppMotion.base);
      expect(tester.takeException(), isNull,
          reason: 'two mounted lists with the same transaction id must not '
              'share a hero tag');
      expect(find.byType(TransactionDetailsScreen), findsOneWidget);
    });

    testWidgets('each list declares its own hero scope', (tester) async {
      await _pumpShell(tester, seed: [_tx(250), _tx(700)]);
      await _revealRows(tester);

      expect(
        tester
            .widgetList<TransactionTile>(find.byType(TransactionTile))
            .every((t) => t.heroScope == 'home'),
        isTrue,
      );

      await tester.tap(find.text('ACTIVITY'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      final scopes = tester
          .widgetList<TransactionTile>(find.byType(TransactionTile))
          .map((t) => t.heroScope)
          .toSet();
      expect(scopes, contains('activity'));
    });
  });

  group('route stack behaviour', () {
    testWidgets('a rapid double tap opens exactly one details page',
        (tester) async {
      await _pumpShell(tester, seed: [_tx(250)]);
      await _revealRows(tester);

      final tile = find.byType(TransactionTile).first;
      await tester.tap(tile);
      // The second tap lands while the first route is already sliding in, so it
      // is covered; warnIfMissed is off because being covered is the point.
      await tester.tap(tile, warnIfMissed: false);
      await _settlePush(tester);
      await tester.pump(AppMotion.base);

      expect(find.byType(TransactionDetailsScreen), findsOneWidget,
          reason: 'two taps on a row must not stack two identical routes');
    });

    testWidgets('back returns to the tab it left, not to Home', (tester) async {
      await _pumpShell(tester, seed: [_tx(250)]);

      await tester.tap(find.text('CARDS'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(AppMotion.base);
      expect(find.byType(AddTransactionScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(AddTransactionScreen))).pop();
      await tester.pump();
      await tester.pump(AppMotion.base);

      final nav = tester.widget<FloatingNavBar>(find.byType(FloatingNavBar));
      expect(nav.currentIndex, 3, reason: 'CARDS tab must still be selected');
    });

    testWidgets('reduced motion still navigates, just without the slide',
        (tester) async {
      // Reduced motion must not cost a navigation step: the real push path has
      // to arrive on the same frame it was requested.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _pumpShell(tester, seed: [_tx(250)]);
      await _revealRows(tester);

      await tester.tap(find.byType(TransactionTile).first);
      // Two zero-duration frames: the page needs the second before it is in the
      // tree, and no time passes, so a normal transition would still be parked
      // at its start offset here.
      await tester.pump();
      await tester.pump();
      expect(find.byType(TransactionDetailsScreen), findsOneWidget,
          reason: 'reduced motion must still move between screens');

      // One frame is the whole transition: the page is already exactly where it
      // rests, which is the counterpart of the sliding first frame above.
      expect(
          tester.getTopLeft(find.byType(TransactionDetailsScreen)), Offset.zero,
          reason: 'reduced motion must land the page in place on the first '
              'frame instead of sliding it up');

      Navigator.of(tester.element(find.byType(TransactionDetailsScreen))).pop();
      await tester.pump();
      await tester.pump();
      expect(find.byType(TransactionDetailsScreen), findsNothing,
          reason: 'back must leave immediately under reduced motion');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tab state survives a round trip and a tab switch',
        (tester) async {
      await _pumpShell(tester, seed: [_tx(250)]);
      await _revealRows(tester);

      final scrollable = find
          .descendant(
              of: find.byType(HomeScreen), matching: find.byType(Scrollable))
          .first;
      final before = tester.state<ScrollableState>(scrollable);
      final offset = before.position.pixels;
      expect(offset, greaterThan(0), reason: 'the reveal drag must stick');

      await tester.tap(find.byType(TransactionTile).first);
      await _settlePush(tester);
      Navigator.of(tester.element(find.byType(TransactionDetailsScreen))).pop();
      await tester.pump();
      await tester.pump(AppMotion.slow);

      // Leaving Home for another tab and back must not recreate its Scrollable.
      await tester.tap(find.text('INSIGHTS'));
      await tester.pump(AppMotion.tab);
      await tester.pump(AppMotion.tab);
      await tester.tap(find.text('HOME'));
      await tester.pump(AppMotion.tab);
      await tester.pump(AppMotion.tab);

      expect(tester.state<ScrollableState>(scrollable), same(before),
          reason: 'neither a route push nor a tab switch may rebuild the '
              'dashboard subtree');
      expect(before.position.pixels, offset,
          reason: 'the dashboard must come back scrolled to the same place');
    });
  });
}
