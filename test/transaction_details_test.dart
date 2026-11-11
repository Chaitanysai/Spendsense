import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/transaction_details_screen.dart';
import 'package:spendsense/widgets/app_button.dart';
import 'package:spendsense/widgets/app_list_row.dart';
import 'package:spendsense/widgets/app_surface.dart';

/// The details/edit screen, beyond how it looks.
///
/// Two behaviours were added or fixed in the redesign and are pinned here:
///  * a rejected save is reported inline, above Save. The original raised a
///    floating SnackBar that sat on the Save button (52dp of overlap at 1x text,
///    54dp at 2x, measured on the unmodified screen);
///  * leaving with unsaved edits asks first, and a saved edit leaves silently.
class _Provider extends TransactionProvider {
  _Provider({this.fail = false});
  final bool fail;
  final List<String> updated = [];

  @override
  Future<void> updateTransaction(
    String id, {
    required int amount,
    required String merchant,
    required String category,
    required TransactionType type,
    required bool isExcluded,
    String? bank,
  }) async {
    if (fail) throw StateError('disk full');
    updated.add(id);
  }
}

TransactionModel _tx({String merchant = 'Swiggy'}) => TransactionModel(
      id: 't1',
      amountMinor: 24900,
      type: TransactionType.expense,
      merchant: merchant,
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 11, 9),
      time: '10:42 AM',
      originalSms: '',
      isExcluded: false,
      bank: 'HDFC Bank',
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await inter.load();
  });

  Future<_Provider> open(
    WidgetTester tester, {
    bool fail = false,
    String merchant = 'Swiggy',
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final provider = _Provider(fail: fail);
    await tester.runAsync(() => provider.ready);
    await tester.pumpWidget(
      ChangeNotifierProvider<TransactionProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TransactionDetailsScreen(
                        transaction: _tx(merchant: merchant),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    return provider;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('a failed save never covers the Save button at ${scale}x',
        (tester) async {
      await open(tester, fail: true, scale: scale);
      final button = tester.getRect(find.byType(AppPrimaryButton));
      await tester.tap(find.byType(AppPrimaryButton));
      await settle(tester);

      final message = find.text('Could not save. Please try again.');
      expect(message, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing,
          reason: 'a floating SnackBar covered the Save button');
      expect(
          tester.getRect(message).bottom, lessThanOrEqualTo(button.top + 0.5));
      expect(find.byType(AppPrimaryButton).hitTestable(), findsOneWidget);
    });
  }

  testWidgets('a blank merchant is flagged on its field and above Save',
      (tester) async {
    await open(tester, merchant: '');
    await tester.tap(find.byType(AppPrimaryButton));
    await settle(tester);
    expect(find.text('Enter a merchant.'), findsOneWidget);
    expect(find.text('Enter a valid merchant and amount'), findsOneWidget);
    // Typing clears both: nothing stale sits against corrected text.
    await tester.enterText(find.widgetWithText(TextField, 'Merchant'), 'Cafe');
    await tester.pump();
    expect(find.text('Enter a merchant.'), findsNothing);
    expect(find.text('Enter a valid merchant and amount'), findsNothing);
  });

  group('leaving the screen', () {
    testWidgets('with no edits, back leaves at once', (tester) async {
      await open(tester);
      await tester.pageBack();
      await settle(tester);
      expect(find.byType(TransactionDetailsScreen), findsNothing);
      expect(find.text('Discard changes?'), findsNothing);
    });

    testWidgets('with edits, back asks first and Keep editing stays',
        (tester) async {
      await open(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Merchant'), 'Cafe');
      await tester.pump();
      await tester.pageBack();
      await settle(tester);
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await settle(tester);
      expect(find.byType(TransactionDetailsScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Cafe'), findsOneWidget,
          reason: 'the edit must survive "Keep editing"');
    });

    testWidgets('Discard leaves and drops the edit', (tester) async {
      await open(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Merchant'), 'Cafe');
      await tester.pump();
      await tester.pageBack();
      await settle(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(find.byType(TransactionDetailsScreen), findsNothing);
    });

    testWidgets('a saved edit leaves without asking', (tester) async {
      final provider = await open(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Merchant'), 'Cafe');
      await tester.pump();
      await tester.tap(find.byType(AppPrimaryButton));
      await settle(tester);
      expect(provider.updated, ['t1']);
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(TransactionDetailsScreen), findsNothing);
    });

    testWidgets('a failed save keeps the edits and keeps the guard',
        (tester) async {
      await open(tester, fail: true);
      await tester.enterText(
          find.widgetWithText(TextField, 'Merchant'), 'Cafe');
      await tester.pump();
      await tester.tap(find.byType(AppPrimaryButton));
      await settle(tester);
      await tester.pageBack();
      await settle(tester);
      expect(find.text('Discard changes?'), findsOneWidget,
          reason: 'nothing was saved, so leaving still discards the edit');
    });
  });

  testWidgets('the detail rows are announced as one group', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    expect(find.bySemanticsLabel('Transaction details'), findsOneWidget);
    expect(find.text('Date & time'), findsOneWidget);
    expect(find.text('Payment method'), findsOneWidget);
    // The payment method is the row's subtitle (the category picker has no UPI
    // chip text of its own on an expense, but the picker does list "UPI").
    expect(
      find.descendant(
        of: find.byType(AppListGroup),
        matching: find.text('UPI'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the detail rows share one title column at ${scale}x',
        (tester) async {
      // Found in a 2x capture: the Exclude row had no leading plate, so its
      // title started ~50px left of the two rows above it.
      await open(tester, scale: scale);
      double titleX(String text) {
        final f = find.text(text);
        expect(f, findsOneWidget, reason: text);
        return tester.getTopLeft(f).dx;
      }

      await tester.ensureVisible(find.text('Exclude from Insights'));
      await tester.pump();
      final date = titleX('Date & time');
      final method = titleX('Payment method');
      final exclude = titleX('Exclude from Insights');
      expect(method, closeTo(date, 0.5));
      expect(exclude, closeTo(method, 0.5),
          reason: 'Exclude title at $exclude, Payment method at $method');
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('the title starts right after the back arrow at ${scale}x',
        (tester) async {
      // The default titleSpacing left the title 72dp from the edge: 16dp of
      // dead space after the 56dp arrow slot, 56dp off the page margin.
      await open(tester, scale: scale);
      final title = tester.getTopLeft(find.text('Edit transaction')).dx;
      expect(title, closeTo(56, 0.5),
          reason: 'title at $title, expected directly after the 56dp slot');
    });

    testWidgets('the last field is separated from Save at ${scale}x',
        (tester) async {
      await open(tester, scale: scale);
      final bank = find.byType(TextField).last;
      await tester.ensureVisible(bank);
      await tester.pump();
      final field = tester.getRect(bank);
      final button = tester.getRect(find.byType(AppPrimaryButton));
      expect(button.top - field.bottom, greaterThanOrEqualTo(12),
          reason: 'Bank field $field runs into the Save button $button');
      expect(
        find.descendant(
          of: find.byType(Scaffold),
          matching: find.byType(AppSeparator),
        ),
        findsWidgets,
        reason: 'no hairline ends the scroll region above the action bar',
      );
    });
  }

  testWidgets('there is no delete action (declined for this stage)',
      (tester) async {
    await open(tester);
    expect(find.textContaining('Delete'), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
  });
}
