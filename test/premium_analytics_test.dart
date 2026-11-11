import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/theme_provider.dart';
import 'package:spendsense/utils/app_spacing.dart';
import 'package:spendsense/widgets/category_breakdown_card.dart';
import 'package:spendsense/widgets/dashboard/spending_trend_card.dart';
import 'package:spendsense/widgets/floating_nav_bar.dart';
import 'package:spendsense/widgets/theme_toggle.dart';

/// Behavioural tests for the analytics and navigation motion.
///
/// These assert *state* (which pill is open, what the card reports, what was
/// persisted), not a frame's pixels, so they stay honest across devices and
/// font metrics. The open width is asserted as a relationship — wider than a
/// closed circle — because its exact value depends on font metrics.

TransactionModel _tx(DateTime date, int amountMinor) => TransactionModel(
      id: 'tx-${date.millisecondsSinceEpoch}-$amountMinor',
      amountMinor: amountMinor,
      type: TransactionType.expense,
      merchant: 'Merchant',
      category: 'Food',
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: '',
      isExcluded: false,
    );

void main() {
  group('expanding navigation pill', () {
    Future<void> pumpBar(WidgetTester tester, {required int index}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: _NavHarness(initialIndex: index),
          ),
        ),
      );
    }

    Finder slot(String label) => find.byKey(ValueKey('nav:$label'));

    double widthOf(WidgetTester tester, String label) => tester
        .getSize(find.descendant(
            of: slot(label), matching: find.byType(Container)).first)
        .width;

    testWidgets('only the tapped destination opens to show its label',
        (tester) async {
      await pumpBar(tester, index: 0);
      await tester.pump();

      await tester.tap(slot('Insights'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The open pill is wider than a closed 48dp circle; every other slot is
      // closed. The selected-pill key moved with the selection.
      expect(widthOf(tester, 'Insights'), greaterThan(48 + 20));
      for (final label in ['Home', 'Bills', 'Cards', 'Settings']) {
        expect(widthOf(tester, label), closeTo(48, 0.5), reason: label);
      }
      expect(
        find.descendant(
            of: slot('Insights'),
            matching: find.byKey(const Key('nav-selected-pill'))),
        findsOneWidget,
      );
    });

    testWidgets('opens on a curve that arrives once, with no overshoot',
        (tester) async {
      await pumpBar(tester, index: 0);
      await tester.pump();
      final closed = widthOf(tester, 'Settings');

      await tester.tap(slot('Settings'));
      await tester.pump();
      final samples = <double>[];
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        samples.add(widthOf(tester, 'Settings'));
      }
      final open = samples.last;

      expect(open, greaterThan(closed + 20));
      // Monotonic and never past the target: a width that overshoots slides
      // the clipped label in, out and in again (PanelUI's reason for a curve).
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], greaterThanOrEqualTo(samples[i - 1] - 0.01));
        expect(samples[i], lessThanOrEqualTo(open + 0.01));
      }
    });

    testWidgets('a second tap mid-flight retargets instead of queueing',
        (tester) async {
      await pumpBar(tester, index: 0);
      await tester.pump();

      await tester.tap(slot('Cards'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      await tester.tap(slot('Home'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(widthOf(tester, 'Home'), greaterThan(48 + 20));
      expect(widthOf(tester, 'Cards'), closeTo(48, 0.5),
          reason: 'the half-open pill reverses from where it got to');
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion opens the pill without animating',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpBar(tester, index: 0);
      await tester.pump();

      await tester.tap(slot('Bills'));
      await tester.pump();

      expect(widthOf(tester, 'Bills'), greaterThan(48 + 20));
      expect(widthOf(tester, 'Home'), closeTo(48, 0.5));
    });
  });

  group('theme toggle', () {
    testWidgets('writes an explicit, persisted dark preference',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: Consumer<ThemeProvider>(
            builder: (context, value, _) => MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: value.themeMode,
              home: const Scaffold(body: Center(child: ThemeToggle())),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(ThemeToggle));
      await tester.pumpAndSettle();

      expect(theme.themeMode, ThemeMode.dark);
      expect(Theme.of(tester.element(find.byType(ThemeToggle))).brightness,
          Brightness.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');

      await tester.tap(find.byType(ThemeToggle));
      await tester.pumpAndSettle();
      expect(prefs.getString('theme_mode'), 'light');
    });
  });

  group('category breakdown card', () {
    Map<String, int> many(int count) => {
          for (var i = 0; i < count; i++) 'Category $i': (count - i) * 1000,
        };

    Future<void> pumpCard(WidgetTester tester, Map<String, int> totals) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CategoryBreakdownCard(
                  totalsMinor: totals,
                  collapsedRows: 5,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('reveals every category on demand instead of hiding them',
        (tester) async {
      await pumpCard(tester, many(8));

      expect(find.text('+3 more categories'), findsOneWidget);
      expect(find.text('Show all'), findsOneWidget);

      await tester.tap(find.text('Show all'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Category 7'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
      expect(find.text('+3 more categories'), findsNothing);
    });

    testWidgets('selecting a category dims the other composition segments',
        (tester) async {
      await pumpCard(tester, many(3));

      await tester.tap(find.text('Category 2'));
      await tester.pump(const Duration(milliseconds: 300));

      final dimmed = tester
          .widgetList<Opacity>(find.byType(Opacity))
          .where((o) => (o.opacity - 0.45).abs() < 0.001)
          .length;
      // Two of three segments are not selected.
      expect(dimmed, 2);
    });
  });

  group('spending trend card', () {
    testWidgets('reduced motion reports a tapped day without animating',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final yesterday = DateTime(now.year, now.month, now.day - 1, 12);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SpendingTrendCard(
                  expenses: [
                    _tx(today, 25000),
                    _tx(yesterday, 12000),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('₹250'), findsWidgets);

      final chart =
          tester.getRect(find.byKey(const Key('spending-trend-chart')));
      await tester.tapAt(
        Offset(chart.left + chart.width * 5.5 / 7, chart.center.dy),
      );
      await tester.pump();

      expect(find.text('₹120'), findsOneWidget);
      expect(find.text('₹250'), findsNothing);
    });

    testWidgets('shows a real empty state rather than an empty plot',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpendingTrendCard(expenses: []),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No spending in the last 7 days'), findsOneWidget);
      expect(find.byKey(const Key('spending-trend-chart')), findsNothing);
    });
  });

  test('the motion tokens used by these widgets are declared once', () {
    expect(AppMotion.chart, const Duration(milliseconds: 600));
    expect(AppSpring.nav.stiffness, greaterThan(0));
  });
}

/// Small host that owns the selected index the way the app shell does.
class _NavHarness extends StatefulWidget {
  final int initialIndex;

  const _NavHarness({required this.initialIndex});

  @override
  State<_NavHarness> createState() => _NavHarnessState();
}

class _NavHarnessState extends State<_NavHarness> {
  static const _items = [
    NavItem(Icons.home_rounded, 'Home'),
    NavItem(Icons.event_note_rounded, 'Bills'),
    NavItem(Icons.insights_rounded, 'Insights'),
    NavItem(Icons.credit_card_rounded, 'Cards'),
    NavItem(Icons.settings_rounded, 'Settings'),
  ];

  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return FloatingNavBar(
      items: _items,
      currentIndex: _index,
      onTap: (i) => setState(() => _index = i),
    );
  }
}
