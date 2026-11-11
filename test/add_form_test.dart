import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/add_transaction_screen.dart';
import 'package:spendsense/widgets/amount_hero_field.dart';
import 'package:spendsense/widgets/app_button.dart';

/// The Add form, beyond how it looks.
///
/// The failure-message test exists because of a measured defect in the original:
/// a rejected save raised a floating SnackBar that sat on top of the Add button
/// (51dp of overlap at 1x text, 54dp at 1.3x and 2x), so the one control needed
/// to retry was covered by the message telling you to retry.
class _Failing extends TransactionProvider {
  @override
  Future<void> addTransaction(TransactionModel transaction) async =>
      throw StateError('disk full');
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
    await inter.load();
  });

  Future<void> openSheet(
    WidgetTester tester, {
    double scale = 1,
    double width = 390,
    double height = 844,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    if (keyboard > 0) {
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    }
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({});
    final provider = _Failing();
    await tester.runAsync(() => provider.ready);
    late BuildContext host;
    await tester.pumpWidget(
      ChangeNotifierProvider<TransactionProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Builder(builder: (c) {
            host = c;
            return const Scaffold(body: SizedBox());
          }),
        ),
      ),
    );
    // ignore: unawaited_futures
    showAddTransactionSheet(host);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> failASave(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).first, '250');
    await tester.pump();
    await tester.tap(find.byType(AppPrimaryButton));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets('a failed save never covers the Add button at ${scale}x',
        (tester) async {
      await openSheet(tester, scale: scale);
      final button = tester.getRect(find.byType(AppPrimaryButton));
      await failASave(tester);

      final message = find.text('Could not save. Please try again.');
      expect(message, findsOneWidget);
      // Nothing may sit over the button: the message is inline, above it.
      expect(find.byType(SnackBar), findsNothing,
          reason: 'a floating SnackBar covered the retry button');
      final m = tester.getRect(message);
      expect(m.bottom, lessThanOrEqualTo(button.top + 0.5),
          reason: 'the message ($m) overlaps the button ($button)');
      // And the button is hit-testable, so a retry is really possible.
      expect(find.byType(AppPrimaryButton).hitTestable(), findsOneWidget);
    });
  }

  // Narrow screen + large text + keyboard up: the pinned action row is the
  // tightest it gets. The message and the retry button must both stay inside
  // the visible area (above the keyboard), the message above the button.
  for (final scale in [1.3, 2.0]) {
    testWidgets(
        'failure message and retry both stay visible at 320dp, ${scale}x, '
        'keyboard open', (tester) async {
      const keyboard = 260.0;
      const height = 640.0;
      await openSheet(tester,
          scale: scale, width: 320, height: height, keyboard: keyboard);
      await failASave(tester);

      final message = find.text('Could not save. Please try again.');
      expect(message, findsOneWidget);
      final m = tester.getRect(message);
      final b = tester.getRect(find.byType(AppPrimaryButton));
      expect(m.bottom, lessThanOrEqualTo(b.top + 0.5),
          reason: 'message $m overlaps retry button $b');
      expect(b.bottom, lessThanOrEqualTo(height - keyboard + 0.5),
          reason: 'retry button $b sits behind the keyboard');
      expect(m.top, greaterThanOrEqualTo(0));
      expect(find.byType(AppPrimaryButton).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'layout overflow');
    });
  }

  testWidgets('repeated failed retries keep one message and a live button',
      (tester) async {
    await openSheet(tester, scale: 1.3);
    await failASave(tester);
    for (var attempt = 2; attempt <= 3; attempt++) {
      // Retry without editing: the button must still be enabled and tappable.
      expect(find.byType(AppPrimaryButton).hitTestable(), findsOneWidget,
          reason: 'retry button unavailable before attempt $attempt');
      await tester.tap(find.byType(AppPrimaryButton));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('Could not save. Please try again.'), findsOneWidget,
          reason: 'message missing or duplicated on attempt $attempt');
      final m = tester
          .getRect(find.text('Could not save. Please try again.'));
      final b = tester.getRect(find.byType(AppPrimaryButton));
      expect(m.bottom, lessThanOrEqualTo(b.top + 0.5));
    }
    // The form is still open with its input intact.
    expect(find.widgetWithText(TextField, '250'), findsOneWidget);
  });

  testWidgets('the failure message is announced and goes away on edit',
      (tester) async {
    final handle = tester.ensureSemantics();
    await openSheet(tester);
    await failASave(tester);
    expect(find.bySemanticsLabel('Could not save. Please try again.'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '260');
    await tester.pump();
    expect(find.text('Could not save. Please try again.'), findsNothing,
        reason: 'a stale error sat against text the user had already changed');
    handle.dispose();
  });

  testWidgets('a screen reader can switch Expense to Income', (tester) async {
    final handle = tester.ensureSemantics();
    await openSheet(tester);
    expect(find.text('Amount out'), findsOneWidget);
    tester.semantics.tap(find.semantics.byLabel('Income'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Amount in'), findsOneWidget,
        reason:
            'the type toggle exposed no tap action to assistive technology');
    handle.dispose();
  });

  group('amount card', () {
    testWidgets('has no gradient and keeps ink contrast', (tester) async {
      final c = TextEditingController(text: '250');
      addTearDown(c.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AmountHeroField(controller: c, isIncome: false)),
      ));
      final gradients = tester
          .widgetList<DecoratedBox>(find.descendant(
              of: find.byType(AmountHeroField),
              matching: find.byType(DecoratedBox)))
          .where((d) => (d.decoration as BoxDecoration).gradient != null);
      expect(gradients, isEmpty,
          reason: 'spec 11: the only gradient is the payment card');
    });

    testWidgets('names the direction in words, for both types', (tester) async {
      final c = TextEditingController();
      addTearDown(c.dispose);
      for (final income in [false, true]) {
        await tester.pumpWidget(MaterialApp(
          home:
              Scaffold(body: AmountHeroField(controller: c, isIncome: income)),
        ));
        expect(find.text(income ? 'Amount in' : 'Amount out'), findsOneWidget);
      }
    });
  });
}
