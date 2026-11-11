import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/activity_screen.dart';
import 'package:spendsense/utils/formatters.dart';
import 'package:spendsense/widgets/app_chip.dart';
import 'package:spendsense/widgets/transaction_tile.dart';

/// What the Activity screen promises, beyond how it looks.
///
/// Filtering, sorting and the provider are covered by their own tests; these
/// pin the parts the redesign touched: the summary line, day grouping, the
/// excluded-row rules, the filter chips and their sheets, and the four empty
/// situations that must not look alike.
class _Provider extends TransactionProvider {
  _Provider({this.ledgerError = false});
  final bool ledgerError;
  int retries = 0;

  @override
  bool get hasLedgerInitError => ledgerError;

  @override
  String? get ledgerInitErrorCode => 'E_TEST';

  @override
  Future<void> retryLedgerInit() async => retries++;

  @override
  Future<void> syncFromSms({bool userInitiated = false}) async {}
}

TransactionModel _tx(
  String id,
  DateTime date,
  int minor,
  String merchant, {
  TransactionType type = TransactionType.expense,
  String category = 'Food',
  bool excluded = false,
}) =>
    TransactionModel(
      id: id,
      amountMinor: minor,
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: 'UPI',
      date: date,
      time: '10:00',
      originalSms: '',
      isExcluded: excluded,
      bank: 'HDFC Bank',
    );

/// Lets animations that start on a frame (fades, sheet slides) play out.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Taps the chip labelled [label], scrolling the filter row to it first. The
/// row is wider than a phone, so a chip past the edge cannot be hit as it is.
Future<void> tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(AppChip, label);
  expect(chip, findsOneWidget, reason: 'no "$label" chip');
  await tester.ensureVisible(chip);
  await tester.pump();
  await tester.tap(chip);
  await settle(tester);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await inter.load();
  });

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 12);
  DateTime ago(int days) => today.subtract(Duration(days: days));

  Future<_Provider> pump(
    WidgetTester tester,
    List<TransactionModel> rows, {
    bool ledgerError = false,
    double width = 390,
    double height = 844,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues(
        {'sms_scan_start_date': DateTime.now().toIso8601String()});
    final provider = _Provider(ledgerError: ledgerError);
    await tester.runAsync(() => provider.ready);
    provider.debugSeed(rows);
    await tester.pumpWidget(
      ChangeNotifierProvider<TransactionProvider>.value(
        value: provider,
        child: const MaterialApp(home: ActivityScreen()),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    return provider;
  }

  final ledger = [
    _tx('a', today, 24900, 'Swiggy'),
    _tx('b', today, 4500, 'Chai Point'),
    _tx('c', ago(1), 450000, 'Salary',
        type: TransactionType.income, category: 'Income'),
    _tx('d', ago(1), 12000, 'Uber', category: 'Travel'),
    _tx('e', ago(2), 99900, 'Hidden purchase', excluded: true),
  ];

  group('summary line', () {
    testWidgets('counts every row but sums only the ones that count',
        (tester) async {
      await pump(tester, ledger);
      expect(find.text('5 transactions'), findsOneWidget);
      // income 4,500; expenses 249 + 45 + 120 = 414. The excluded ₹999 is in
      // neither.
      expect(find.text('${Formatters.currency.format(450000)} in'),
          findsOneWidget);
      expect(find.text('${Formatters.currency.format(41400)} out'),
          findsOneWidget);
      expect(find.text('1 excluded'), findsOneWidget);
    });

    testWidgets('announces itself as one sentence, including exclusions',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, ledger);
      expect(
        find.bySemanticsLabel(RegExp(r'5 transactions\. .* in, .* out\. '
            r'1 excluded from totals')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a filter updates it', (tester) async {
      await pump(tester, ledger);
      await tapChip(tester, 'Type');
      await tester.tap(find.text('Income').last);
      await settle(tester);
      expect(find.text('1 transaction'), findsOneWidget);
      expect(
          find.text('${Formatters.currency.format(41400)} out'), findsNothing);
    });
  });

  group('day grouping', () {
    testWidgets('titles are Today / Yesterday / a date, in order',
        (tester) async {
      await pump(tester, ledger);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      final today_ = tester.getTopLeft(find.text('Today')).dy;
      final yesterday = tester.getTopLeft(find.text('Yesterday')).dy;
      expect(today_, lessThan(yesterday));
    });

    testWidgets('a day shows its net; an all-excluded day says so',
        (tester) async {
      await pump(tester, ledger);
      // Today: -249 - 45.
      expect(
          find.text('− ${Formatters.currency.format(29400)}'), findsOneWidget);
      // Yesterday: +4,500 - 120.
      expect(
          find.text('+ ${Formatters.currency.format(438000)}'), findsOneWidget);
      // Two days ago holds only the excluded row: no misleading ₹0.
      expect(find.text('Excluded'), findsWidgets);
      expect(find.text(Formatters.currency.format(0)), findsNothing);
    });

    testWidgets('an excluded row is labelled in its meta line', (tester) async {
      await pump(tester, ledger);
      expect(find.textContaining('Food · Excluded'), findsOneWidget);
    });

    testWidgets('sorting by amount drops the day titles', (tester) async {
      await pump(tester, ledger);
      await tapChip(tester, 'By date');
      expect(find.widgetWithText(AppChip, 'By amount'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
      expect(find.text('Yesterday'), findsNothing);
      // Flat rows show their own date, since no header carries it.
      expect(find.byType(TransactionTile), findsWidgets);
    });
  });

  group('filter chips', () {
    testWidgets('a chip reports selected once its filter is on',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, ledger);
      expect(find.bySemanticsLabel('Filter by type'), findsOneWidget);
      await tapChip(tester, 'Type');
      await tester.tap(find.text('Expense').last);
      await settle(tester);
      // The chip now carries the chosen value, reports selected, and says what
      // it filters (not just "Expense").
      final chip =
          tester.widget<AppChip>(find.widgetWithText(AppChip, 'Expense'));
      expect(chip.selected, isTrue);
      expect(chip.semanticLabel, 'Type filter: Expense');
      handle.dispose();
    });

    testWidgets('Clear removes search and every filter', (tester) async {
      await pump(tester, ledger);
      await tester.enterText(find.byType(TextField).first, 'swiggy');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1 transaction'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppChip, 'Clear'));
      await settle(tester);
      expect(find.text('5 transactions'), findsOneWidget);
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('every chip is at least 44dp tall', (tester) async {
      await pump(tester, ledger);
      for (final chip in tester.widgetList<AppChip>(find.byType(AppChip))) {
        final size = tester.getSize(find.byWidget(chip));
        expect(size.height, greaterThanOrEqualTo(44), reason: chip.label);
      }
    });
  });

  group('the four empty situations', () {
    testWidgets('no matches names the filters and offers to clear them',
        (tester) async {
      await pump(tester, ledger);
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('No matching transactions'), findsOneWidget);
      expect(find.textContaining('zzzz'), findsWidgets);
      expect(find.text('Clear all filters'), findsOneWidget);
      // A single active filter is told to remove it, not "one of them".
      expect(find.textContaining('Try removing it.'), findsOneWidget);
      expect(find.textContaining('one of them'), findsNothing);
    });

    testWidgets('an empty ledger is not a no-match', (tester) async {
      await pump(tester, const []);
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('No matching transactions'), findsNothing);
    });

    testWidgets('an unreadable ledger is an error with Retry, never "empty"',
        (tester) async {
      final provider = await pump(tester, const [], ledgerError: true);
      expect(find.text("Couldn't load your transactions"), findsOneWidget);
      expect(find.text('Nothing here yet'), findsNothing);
      expect(find.textContaining('E_TEST'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(provider.retries, 1);
    });

    testWidgets(
        'a short viewport scrolls the empty state instead of'
        ' overflowing', (tester) async {
      await pump(tester, const [], height: 360, scale: 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('filter sheets', () {
    testWidgets('the chosen row is announced as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, ledger);
      await tapChip(tester, 'Type');
      // What a screen reader needs: a button, tappable, with a selected state
      // that is true for the current choice and false for the others.
      final current = tester.getSemantics(find.text('All transactions'));
      expect(current.label, startsWith('All transactions'));
      expect(
        current,
        isSemantics(
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      final other = tester.getSemantics(find.text('Expense').last);
      expect(
        other,
        isSemantics(
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a pick-one list shows a check, not chevrons', (tester) async {
      await pump(tester, ledger);
      await tapChip(tester, 'Type');
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      // A chevron means "opens something"; no row here does.
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    });

    testWidgets('the last category stays reachable at 2x text', (tester) async {
      await pump(tester, ledger, width: 360, height: 640, scale: 2);
      await tapChip(tester, 'Category');
      final list = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(SingleChildScrollView),
      );
      expect(list, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an amount range with min above max is refused, aloud',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, ledger);
      await tapChip(tester, 'Amount');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(fields.evaluate().length - 2), '500');
      await tester.enterText(fields.at(fields.evaluate().length - 1), '100');
      await tester.ensureVisible(find.text('Apply'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await settle(tester);
      expect(find.text('Minimum must not exceed maximum.'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
        'Apply throws nothing (the original sheet disposed live'
        ' controllers)', (tester) async {
      await pump(tester, ledger);
      await tapChip(tester, 'Amount');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(fields.evaluate().length - 2), '10');
      await tester.enterText(fields.at(fields.evaluate().length - 1), '900');
      await tester.ensureVisible(find.text('Apply'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      // Step through the sheet's whole exit, where the old code threw.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('an applied range is shown again when the sheet reopens',
        (tester) async {
      await pump(tester, ledger);
      await tapChip(tester, 'Amount');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(fields.evaluate().length - 2), '100');
      await tester.enterText(fields.at(fields.evaluate().length - 1), '300');
      await tester.ensureVisible(find.text('Apply'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await settle(tester);
      await tapChip(
          tester,
          '${Formatters.currency.format(10000)} – '
          '${Formatters.currency.format(30000)}');
      expect(find.widgetWithText(TextField, '100'), findsOneWidget);
      expect(find.widgetWithText(TextField, '300'), findsOneWidget);
    });

    testWidgets('a valid amount range filters by integer paise',
        (tester) async {
      await pump(tester, ledger);
      await tapChip(tester, 'Amount');
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(fields.evaluate().length - 2), '100');
      await tester.enterText(fields.at(fields.evaluate().length - 1), '300');
      await tester.ensureVisible(find.text('Apply'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await settle(tester);
      // The original sheet disposed its controllers while the closing sheet was
      // still painting them and threw on every Apply. Nothing may throw now.
      expect(tester.takeException(), isNull);
      // ₹120 (Uber) and ₹249 (Swiggy) are inside 100 to 300; ₹45, ₹999 and
      // ₹4,500 are not.
      expect(find.text('2 transactions'), findsOneWidget);
    });
  });

  group('search', () {
    // The search box is the only TextField on the Activity screen.
    Finder field() => find.byType(TextField);

    testWidgets('matches a merchant, case-insensitively', (tester) async {
      await pump(tester, ledger);
      await tester.enterText(field(), 'SWIG');
      await tester.pump();
      expect(find.text('1 transaction'), findsOneWidget);
      expect(find.text('Swiggy'), findsOneWidget);
    });

    testWidgets('special characters are literal text, never a pattern',
        (tester) async {
      await pump(tester, ledger);
      for (final q in ['(', '[a-', r'\', '.*', '₹']) {
        await tester.enterText(field(), q);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'query "$q" threw');
      }
      await tester.enterText(field(), '.*');
      await tester.pump();
      expect(find.text('No matching transactions'), findsOneWidget,
          reason: '".*" must not match everything');
    });

    testWidgets('no results names the search, and Clear restores the list',
        (tester) async {
      await pump(tester, ledger);
      await tester.enterText(field(), 'zzzz');
      await tester.pump();
      expect(find.text('No matching transactions'), findsOneWidget);
      expect(find.textContaining('zzzz'), findsWidgets);
      await tester.tap(find.text('Clear all filters'));
      await settle(tester);
      expect(find.text('5 transactions'), findsOneWidget);
    });

    testWidgets('the field clear button empties the query and keeps results',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, ledger);
      await tester.enterText(field(), 'uber');
      await tester.pump();
      expect(find.text('1 transaction'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Clear search'));
      await tester.pump();
      expect(find.text('5 transactions'), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
      handle.dispose();
    });

    testWidgets('dragging the results dismisses the keyboard', (tester) async {
      await pump(tester, ledger);
      final scroll = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView).first);
      expect(scroll.keyboardDismissBehavior,
          ScrollViewKeyboardDismissBehavior.onDrag);
    });
  });
}
