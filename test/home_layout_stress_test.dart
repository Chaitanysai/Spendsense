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
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/widgets/transaction_tile.dart';

/// Scrolls the whole Home tab, top to bottom, at the sizes where it breaks.
///
/// A layout overflow is thrown during layout, so a screen can pass every
/// finder-based test and still paint a yellow-and-black stripe on a real phone.
/// This drives the real shell with a seeded ledger (long merchant names, large
/// amounts, a long profile name) and fails on *any* exception while scrolling,
/// including ones thrown for rows that are only built when they scroll into
/// view.
///
/// It was written after the "Spent this cycle" row of the category card
/// overflowed by 25dp at 320dp / 2x text (27dp in dark mode). Be exact about that
/// finding: it reproduced only in Flutter's default test font (Ahem, one em per
/// glyph), which is much wider than the app's Inter. With Inter loaded, as it is
/// below, the old and the new card both pass. The `Wrap` in the card stays as a
/// defensive layout, but it is not evidence of a defect on a phone. What this
/// test still guards is any *other* row that overflows while Home scrolls.
///
/// The summary exception names only the Row; the `creator:` chain in the full
/// exception names the file and line.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Real glyph metrics. Without this, widget tests draw text in the blocky
    // Ahem font (1em per glyph), which is far wider than Inter and inflates
    // every overflow. The capture harness loads it the same way.
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await inter.load();
  });

  endClearanceTests();

  const cases = <(String, double, double, double)>[
    ('360x760', 360, 760, 1.0),
    ('320x640', 320, 640, 1.0),
    ('360x760 at 1.3x text', 360, 760, 1.3),
    ('411x860 at 2.0x text', 411, 860, 2.0),
    ('320x640 at 2.0x text', 320, 640, 2.0),
    ('landscape 844x390', 844, 390, 1.0),
  ];

  for (final dark in [false, true]) {
    for (final (name, w, h, scale) in cases) {
      testWidgets(
          'Home scrolls end to end without a layout error: $name '
          '${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = Size(w * 3, h * 3);
        tester.view.devicePixelRatio = 3;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        SharedPreferences.setMockInitialValues({
          'sms_scan_start_date': DateTime.now().toIso8601String(),
          'name': 'Asha Venkataraman-Krishnamurthy',
          'theme_mode': dark ? 'dark' : 'light',
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
        await tester.pump(const Duration(seconds: 3));
        await tester.runAsync(() => transactions.ready);

        final now = DateTime.now();
        const categories = [
          'Food',
          'Transport',
          'Groceries',
          'Shopping',
          'Bills & Utilities',
          'Entertainment',
          'Health',
        ];
        transactions.debugSeed([
          for (var i = 0; i < 14; i++)
            TransactionModel(
              id: 'x$i',
              amountMinor: 1234567800 + i * 500,
              type:
                  i % 4 == 0 ? TransactionType.income : TransactionType.expense,
              merchant: 'A very long merchant name number $i Pvt Ltd',
              category: categories[i % categories.length],
              paymentMethod: 'UPI',
              date: DateTime(now.year, now.month, now.day, 10)
                  .subtract(Duration(days: i % 6)),
              time: '10:00',
              originalSms: '',
              isExcluded: false,
              bank: 'HDFC Bank',
            ),
        ]);
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull, reason: 'at rest');

        final scroller = find
            .descendant(
              of: find.byType(HomeScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        for (var step = 0; step < 80; step++) {
          await tester.drag(scroller, const Offset(0, -140));
          await tester.pump(const Duration(milliseconds: 250));
          expect(tester.takeException(), isNull, reason: 'scroll step $step');
          if (tester.state<ScrollableState>(scroller).position.extentAfter <
              1) {
            break;
          }
        }
      });
    }
  }
}

/// The last thing on Home must be reachable: scrolled to the end, its bottom
/// edge sits above the floating navigation bar, at every size. This is the
/// replacement for the old "add button never overlaps" check; with no floating
/// button the only thing that can cover content is the bar itself.
void endClearanceTests() {
  for (final (name, w, h, scale) in const <(String, double, double, double)>[
    ('390x844', 390, 844, 1.0),
    ('320x640', 320, 640, 1.0),
    ('360x760 at 1.3x', 360, 760, 1.3),
    ('411x860 at 2.0x', 411, 860, 2.0),
    ('landscape 844x390', 844, 390, 1.0),
  ]) {
    testWidgets('Home end of scroll clears the navigation bar: $name',
        (tester) async {
      tester.view.physicalSize = Size(w * 3, h * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({
        'sms_scan_start_date': DateTime.now().toIso8601String(),
        'name': 'Asha',
      });
      final tx = TransactionProvider();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: tx),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const SpendSenseApp(),
      ));
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(() => tx.ready);
      final now = DateTime.now();
      tx.debugSeed([
        for (var i = 0; i < 8; i++)
          TransactionModel(
            id: 'e$i',
            amountMinor: 10000 + i * 700,
            type: TransactionType.expense,
            merchant: 'Shop $i',
            category: 'Food',
            paymentMethod: 'UPI',
            date: DateTime(now.year, now.month, now.day, 10)
                .subtract(Duration(days: i % 5)),
            time: '10:00',
            originalSms: '',
            isExcluded: false,
            bank: 'HDFC Bank',
          ),
      ]);
      await tester.pump(const Duration(seconds: 2));
      final scroller = find
          .descendant(
              of: find.byType(HomeScreen), matching: find.byType(Scrollable))
          .first;
      // Rows build lazily, so the true end is only known after the list has
      // been walked. Jump to the current max until it stops growing.
      final position = tester.state<ScrollableState>(scroller).position;
      for (var i = 0; i < 6; i++) {
        position.jumpTo(position.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 600));
      }
      expect(position.extentAfter, lessThan(1), reason: 'not at the end');
      final bar = tester.getRect(find.byKey(const ValueKey('nav:Home')));
      // The last thing Home paints is the final Recent-transactions row. Measure
      // that real widget: a probe that matches nothing would pass vacuously, so
      // the test first insists it found rows.
      final tiles = find.byType(TransactionTile);
      expect(tiles, findsWidgets, reason: 'no transaction rows were built');
      var lowest = 0.0;
      for (final e in tiles.evaluate()) {
        final ro = e.renderObject! as RenderBox;
        final r = MatrixUtils.transformRect(
            ro.getTransformTo(null), Offset.zero & ro.size);
        if (r.bottom > lowest) lowest = r.bottom;
      }
      expect(lowest, greaterThan(bar.top - 400),
          reason: 'measured row is nowhere near the bottom of the screen');
      // ignore: avoid_print
      print('END $name barTop=${bar.top.toStringAsFixed(1)} '
          'lastRowBottom=${lowest.toStringAsFixed(1)} '
          'gap=${(bar.top - lowest).toStringAsFixed(1)}');
      expect(lowest, lessThanOrEqualTo(bar.top + 0.5),
          reason: 'content ends under the bar at $name');
    });
  }
}
