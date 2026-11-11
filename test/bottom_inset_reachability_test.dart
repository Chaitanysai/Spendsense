import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
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
import 'package:spendsense/screens/bills_screen.dart';
import 'package:spendsense/screens/cards_screen.dart';
import 'package:spendsense/screens/home_screen.dart';
import 'package:spendsense/screens/insights_screen.dart';
import 'package:spendsense/screens/settings_screen.dart';
import 'package:spendsense/widgets/app_page_route.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';

/// The last thing on every tab must be reachable, not hidden by the floating
/// navigation bar.
///
/// `AppSpacing.tabBottomInset` was 164dp while a floating Add button sat above
/// the bar, and became 108dp when that button was removed. Every tab pads the
/// end of its scroll view with it. This scrolls each tab to its real end, with a
/// seeded ledger large enough to scroll, and checks that the lowest line of text
/// on screen ends above the bar, and that no line is cut off by the screen edge.
///
/// Activity is not a tab: it is pushed over the shell, so the bar is not on top
/// of it. It is checked against the bottom of the screen instead.
///
/// It reads painted text (`RenderParagraph`), so it needs no knowledge of how
/// each screen builds its rows. The gap is printed so the numbers are visible,
/// not just a pass.
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

  const sizes = <(String, double, double, double, double)>[
    ('390x844', 390, 844, 1.0, 0),
    ('320x640', 320, 640, 1.0, 0),
    ('411x860 at 2.0x text', 411, 860, 2.0, 0),
    ('landscape 844x390', 844, 390, 1.0, 0),
    ('390x844 with a 34dp gesture inset', 390, 844, 1.0, 34),
  ];

  List<TransactionModel> ledger(DateTime now) {
    final day = DateTime(now.year, now.month, now.day, 10);
    var n = 0;
    TransactionModel row(
      DateTime date,
      int minor,
      String merchant,
      String category, {
      String bank = 'HDFC Bank',
      String account = 'XX1234',
      String method = 'UPI',
      TransactionType type = TransactionType.expense,
    }) =>
        TransactionModel(
          id: 'r${n++}',
          amountMinor: minor,
          type: type,
          merchant: merchant,
          category: category,
          paymentMethod: method,
          date: date,
          time: '10:00',
          originalSms: '',
          isExcluded: false,
          bank: bank,
          account: account,
        );

    final rows = <TransactionModel>[];
    // Monthly subscriptions, so Bills has something to detect.
    for (final (name, minor, category) in const [
      ('Netflix', 64900, 'Entertainment'),
      ('Rent', 2500000, 'Bills'),
      ('Gym', 150000, 'Health'),
      ('Jio Fiber', 79900, 'Bills'),
      ('Spotify', 11900, 'Entertainment'),
      ('Insurance', 420000, 'Insurance'),
    ]) {
      for (var k = 0; k < 4; k++) {
        rows.add(row(
            day.subtract(Duration(days: 30 * k + 3)), minor, name, category));
      }
    }
    // Everyday spend across banks, accounts and payment methods.
    const banks = ['HDFC Bank', 'ICICI Bank', 'SBI', 'Axis Bank'];
    const methods = ['UPI', 'Credit Card', 'Debit Card', 'Net Banking'];
    const categories = [
      'Food',
      'Transport',
      'Groceries',
      'Shopping',
      'Health',
      'Travel',
      'Education',
    ];
    for (var i = 0; i < 40; i++) {
      rows.add(row(
        day.subtract(Duration(days: i % 28)),
        15000 + i * 900,
        'Store $i',
        categories[i % categories.length],
        bank: banks[i % banks.length],
        account: 'XX${1000 + i % 6}',
        method: methods[i % methods.length],
      ));
    }
    rows.add(row(
        day.subtract(const Duration(days: 8)), 8500000, 'Salary', 'Income',
        type: TransactionType.income));
    return rows;
  }

  /// Every distinct layout error reported during the test, keyed by the `lib/`
  /// file of the widget that reported it. Installed in place of the framework's
  /// fail-on-first handler so a screen with a known overflow can still be
  /// measured; the gate is [knownOverflows], an exact match, so a new overflow
  /// fails and a fixed one fails too, which tells its stage to delete the entry.
  Set<String> collectErrors() {
    final files = <String>{};
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final m = RegExp(r'lib/[\w/]+\.dart').firstMatch(details.toString());
      files.add(m?.group(0) ?? details.exceptionAsString().split('\n').first);
    };
    addTearDown(() => FlutterError.onError = previous);
    return files;
  }

  Future<TransactionProvider> pump(
    WidgetTester tester, {
    required double w,
    required double h,
    required double scale,
    required double inset,
  }) async {
    tester.view.physicalSize = Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = FakeViewPadding(bottom: inset * 3);
    tester.view.viewPadding = FakeViewPadding(bottom: inset * 3);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    SharedPreferences.setMockInitialValues({
      'sms_scan_start_date': DateTime.now().toIso8601String(),
      'name': 'Asha',
    });
    final tx = TransactionProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: tx),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => PeriodProvider()..init()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const SpendSenseApp(),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() => tx.ready);
    return tx;
  }

  /// Scrolls the page's own vertical scroller to its end and measures the
  /// lowest painted text. Returns what it saw so the caller can assert on it.
  Future<({double lowest, String last, double max, int cutOff})> atEnd(
    WidgetTester tester,
    Finder screen,
    double screenHeight,
  ) async {
    ScrollPosition? page;
    for (final s in tester
        .stateList<ScrollableState>(
          find.descendant(of: screen, matching: find.byType(Scrollable)),
        )
        .where((s) => s.widget.axis == Axis.vertical)) {
      if (page == null ||
          s.position.viewportDimension > page.viewportDimension) {
        page = s.position;
      }
    }
    var max = 0.0;
    if (page != null) {
      // Rows build lazily, so the true end is only known after walking there.
      for (var i = 0; i < 8; i++) {
        page.jumpTo(page.maxScrollExtent);
        await tester.pump(const Duration(milliseconds: 500));
      }
      max = page.maxScrollExtent;
    }

    var lowest = 0.0;
    var last = '';
    var cutOff = 0;
    for (final e in find
        .descendant(of: screen, matching: find.byType(RichText))
        .evaluate()) {
      final ro = e.renderObject;
      if (ro is! RenderParagraph || !ro.attached || !ro.hasSize) continue;
      if (ro.size.isEmpty) continue;
      final text = ro.text.toPlainText().trim();
      if (text.isEmpty) continue;
      final r = MatrixUtils.transformRect(
          ro.getTransformTo(null), Offset.zero & ro.size);
      // Built ahead of the viewport, or scrolled off the top: not on screen.
      if (r.top >= screenHeight || r.bottom <= 0) continue;
      if (r.bottom > screenHeight + 0.5) {
        cutOff++; // runs off the bottom of the screen
      } else if (r.bottom > lowest) {
        // A paragraph taller than the screen that starts above it still counts:
        // its bottom edge is what has to clear the bar. (Cards at 2x text has
        // one 792dp tall; filtering on `top >= 0` skipped it and reported 0.)
        lowest = r.bottom;
        last = text;
      }
    }
    return (lowest: lowest, last: last, max: max, cutOff: cutOff);
  }

  /// Layout overflows that already exist, measured with the real Inter glyph
  /// widths (an earlier version of this table was measured in the blocky Ahem
  /// test font, which is far wider, and wrongly listed Bills, Activity and more
  /// of Insights; it is corrected here).
  ///
  /// `CategoryBubble` overflows on Insights at 2.0x text. It is not caused by the
  /// bottom-inset change and is not Home's: the foundation report already
  /// records the same widget overflowing by 4dp at 1.3x on the pre-redesign
  /// code, and assigns it to the Insights stage. The entry stays here so a new
  /// overflow fails this test, and so the stage that fixes it fails it too and
  /// deletes the line.
  const knownOverflows = <String, Set<String>>{
    'Insights|411x860 at 2.0x text': {'lib/widgets/category_bubble.dart'},
  };

  for (final (name, w, h, scale, inset) in sizes) {
    for (final (label, screenType) in <(String, Type)>[
      ('Home', HomeScreen),
      ('Bills', BillsScreen),
      ('Insights', InsightsScreen),
      ('Cards', CardsScreen),
      ('Settings', SettingsScreen),
    ]) {
      testWidgets('$label end of scroll clears the navigation bar: $name',
          (tester) async {
        final errors = collectErrors();
        final tx = await pump(tester, w: w, h: h, scale: scale, inset: inset);
        await tester.tap(find.byKey(ValueKey('nav:$label')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
        // The launch sync ends in an error in this harness and reloads the
        // empty database over a seed, so seed after the tab is open.
        tx.debugSeed(ledger(DateTime.now()));
        await tester.pump(const Duration(seconds: 1));
        expect(tx.trackedTransactions, isNotEmpty, reason: 'ledger vanished');

        final result = await atEnd(tester, find.byType(screenType), h);
        final barTop = tester.getRect(find.byType(FloatingNavBar)).top;
        // ignore: avoid_print
        print(
            'REACH $label | $name | scrollMax=${result.max.toStringAsFixed(0)} '
            'barTop=${barTop.toStringAsFixed(1)} '
            'lowestText=${result.lowest.toStringAsFixed(1)} '
            '(${result.last.length > 28 ? result.last.substring(0, 28) : result.last}) '
            'gap=${(barTop - result.lowest).toStringAsFixed(1)} '
            'cutOff=${result.cutOff} overflowIn=${errors.join(',')}');
        expect(result.lowest, greaterThan(0), reason: 'no text found');
        expect(result.lowest, lessThanOrEqualTo(barTop),
            reason: '$label ends under the bar at $name');
        expect(result.cutOff, 0,
            reason: '$label has text cut off by the screen at $name');
        expect(errors, knownOverflows['$label|$name'] ?? <String>{},
            reason: '$label layout errors at $name differ from the known set');
      });
    }

    testWidgets('Activity end of scroll is fully on screen: $name',
        (tester) async {
      final errors = collectErrors();
      final tx = await pump(tester, w: w, h: h, scale: scale, inset: inset);
      tx.debugSeed(ledger(DateTime.now()));
      await tester.pump(const Duration(seconds: 1));
      Navigator.of(tester.element(find.byType(MainNavigationShell))).push(
        AppPageRoute<void>(builder: (_) => const ActivityScreen()),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      tx.debugSeed(ledger(DateTime.now()));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ActivityScreen), findsOneWidget);

      final result = await atEnd(tester, find.byType(ActivityScreen), h);
      final bottom = h - inset;
      // ignore: avoid_print
      print(
          'REACH Activity | $name | scrollMax=${result.max.toStringAsFixed(0)} '
          'screenBottom=${bottom.toStringAsFixed(1)} '
          'lowestText=${result.lowest.toStringAsFixed(1)} '
          '(${result.last.length > 28 ? result.last.substring(0, 28) : result.last}) '
          'gap=${(bottom - result.lowest).toStringAsFixed(1)} '
          'cutOff=${result.cutOff} overflowIn=${errors.join(',')}');
      expect(result.max, greaterThan(0), reason: 'Activity did not scroll');
      expect(result.lowest, lessThanOrEqualTo(bottom));
      expect(result.cutOff, 0);
      expect(errors, knownOverflows['Activity|$name'] ?? <String>{},
          reason: 'Activity layout errors at $name differ from the known set');
    });
  }
}
