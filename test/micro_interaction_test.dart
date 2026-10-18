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
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/app_states.dart';
import 'package:spendsense/widgets/pressable.dart';

/// Stage 4 — micro-interactions: press feedback, selection semantics and the
/// state swaps that replaced the old hard-cut bodies.
Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime.now().toIso8601String(),
  });
  final transactions = TransactionProvider()
    ..debugSeed([
      TransactionModel(
        id: 'micro-1',
        amount: 250,
        type: TransactionType.expense,
        merchant: 'Zomato',
        category: 'Food',
        paymentMethod: 'UPI',
        date: DateTime.now(),
        time: '',
        originalSms: '',
        isExcluded: false,
        source: 'Test',
      ),
    ]);

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
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(milliseconds: 400));
}

/// Holds a press on [finder] and reports the scale of the nearest [AnimatedScale]
/// while the finger is still down.
Future<double> _scaleWhilePressed(WidgetTester tester, Finder finder) async {
  final slot = find.ancestor(
      of: finder, matching: find.byType(AnimatedScale, skipOffstage: false));
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(const Duration(milliseconds: 80));
  final scale = tester.widget<AnimatedScale>(slot.last).scale;
  await gesture.up();
  await tester.pump(AppMotion.fast);
  return scale;
}

/// The dashboard stays mounted (and onstage) underneath the pushed add screen,
/// and both show the word "Food", so label finders have to be scoped.
Finder _inAddScreen(String label) => find.descendant(
      of: find.byType(AddTransactionScreen),
      matching: find.text(label),
    );

Future<void> _openAddScreen(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pump();
  await tester.pump(AppMotion.base);
  expect(find.byType(AddTransactionScreen), findsOneWidget);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('press feedback', () {
    testWidgets('a nav slot dips while it is held', (tester) async {
      await _pumpShell(tester);

      final pressed = await _scaleWhilePressed(tester, find.text('CARDS'));
      expect(pressed, lessThan(1.0),
          reason: 'the tab bar had no tactile response before this stage');
      expect(pressed, greaterThan(0.9));
    });

    testWidgets('a category chip dips while it is held', (tester) async {
      await _pumpShell(tester);
      await _openAddScreen(tester);

      final pressed = await _scaleWhilePressed(tester, _inAddScreen('Food'));
      expect(pressed, lessThan(1.0));
      expect(pressed, greaterThan(0.9));
    });

    testWidgets('the press dip is gone once the finger lifts', (tester) async {
      await _pumpShell(tester);
      await _openAddScreen(tester);

      final chip = _inAddScreen('Food');
      await _scaleWhilePressed(tester, chip);
      final rest = tester.widget<AnimatedScale>(
          find.ancestor(of: chip, matching: find.byType(AnimatedScale)).last);
      expect(rest.scale, 1.0, reason: 'the chip must settle back to full size');
    });

    testWidgets('a drag that starts on a chip hands over to the scroll view',
        (tester) async {
      await _pumpShell(tester);
      await _openAddScreen(tester);

      final chip = _inAddScreen('Food');
      final slot = find.ancestor(
          of: chip, matching: find.byType(AnimatedScale, skipOffstage: false));
      expect(find.ancestor(of: chip, matching: find.byType(Pressable)),
          findsWidgets);

      final gesture = await tester.startGesture(tester.getCenter(chip));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<AnimatedScale>(slot.last).scale, lessThan(1.0));

      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(slot.last).scale, 1.0,
          reason: 'the press is raw-pointer driven, so a scroll drag starting '
              'on a control has to lift the dip instead of leaving it stuck');
      await gesture.up();
      await tester.pump(AppMotion.fast);
    });

    testWidgets('a filter chip inside a horizontal scroll row dips and lifts',
        (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.text('ACTIVITY'));
      await tester.pump(AppMotion.tab);
      await tester.pump(AppMotion.tab);

      final chip = find.descendant(
          of: find.byType(ActivityScreen), matching: find.text('Amount'));
      final slot = find.ancestor(
          of: chip, matching: find.byType(AnimatedScale, skipOffstage: false));
      final semantics =
          find.ancestor(of: chip, matching: find.byType(Semantics)).first;

      final gesture = await tester.startGesture(tester.getCenter(chip));
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.widget<AnimatedScale>(slot.last).scale, lessThan(1.0),
          reason: 'the sort chips live in a horizontal scroll view, the exact '
              'place where arena-delayed tap feedback never showed');

      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(slot.last).scale, 1.0,
          reason: 'handing the drag to the scroll view must release the dip');
      await gesture.up();
      await tester.pump(AppMotion.fast);

      expect(tester.widget<Semantics>(semantics).properties.button, isTrue,
          reason: 'the chip reads as one button, not icon + label + icon');
    });

    testWidgets('reduced motion removes the dip, not the tap', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

      await _pumpShell(tester);
      await _openAddScreen(tester);

      final chip = _inAddScreen('Food');
      final pressed = await _scaleWhilePressed(tester, chip);
      expect(pressed, 1.0, reason: 'no scale animation under reduced motion');

      await tester.tap(chip);
      await tester.pump();
      final semantics = tester.widget<Semantics>(
          find.ancestor(of: chip, matching: find.byType(Semantics)).first);
      expect(semantics.properties.selected, isTrue,
          reason: 'the tap still selects the chip');
    });
  });

  group('selection semantics', () {
    testWidgets('category chips announce themselves as buttons',
        (tester) async {
      await _pumpShell(tester);
      await _openAddScreen(tester);

      final chip = tester.widget<Semantics>(find
          .ancestor(of: _inAddScreen('Food'), matching: find.byType(Semantics))
          .first);
      expect(chip.properties.button, isTrue);
      expect(chip.properties.selected, isTrue,
          reason: 'Food is the default category, so it must read as selected');

      final other = tester.widget<Semantics>(find
          .ancestor(
              of: _inAddScreen('Shopping'), matching: find.byType(Semantics))
          .first);
      expect(other.properties.button, isTrue);
      expect(other.properties.selected, isFalse);
    });

    testWidgets('the expense/income segment exposes its selection',
        (tester) async {
      await _pumpShell(tester);
      await _openAddScreen(tester);

      Finder props(String label) => find.ancestor(
            of: _inAddScreen(label),
            matching: find.byType(Semantics),
          );

      expect(
          tester.widget<Semantics>(props('Expense').first).properties.selected,
          isTrue);
      expect(
          tester.widget<Semantics>(props('Income').first).properties.selected,
          isFalse);

      await tester.tap(_inAddScreen('Income'));
      await tester.pump(AppMotion.base);
      expect(
          tester.widget<Semantics>(props('Income').first).properties.selected,
          isTrue,
          reason: 'switching type must move the announced selection');
    });
  });

  group('animated state swaps', () {
    testWidgets('the activity body is state-swapped, not hard-cut',
        (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.text('ACTIVITY'));
      await tester.pump(AppMotion.tab);
      await tester.pump(AppMotion.tab);

      expect(find.byType(ActivityScreen), findsOneWidget);
      expect(find.byType(AppStateSwap), findsOneWidget,
          reason: 'skeleton, empty and list states have to cross-fade');
    });

    testWidgets('a state swap cross-fades instead of snapping', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.text('ACTIVITY'));
      await tester.pump(AppMotion.tab);
      await tester.pump(AppMotion.tab);

      final swap = find.byType(AppStateSwap);
      expect(find.descendant(of: swap, matching: find.byType(AnimatedSwitcher)),
          findsOneWidget);
    });
  });
}
