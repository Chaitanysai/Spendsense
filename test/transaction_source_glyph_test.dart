import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/widgets/transaction_tile.dart';

/// A small glyph marks where a transaction came from, so an email import is
/// visible on the dashboard without opening anything.
///
/// SMS is the default channel, so it is deliberately unmarked: a glyph on
/// nearly every row would say nothing and cost the meta line space it does not
/// have at 360 dp.
TransactionModel _tx({required String source, String category = 'Food'}) =>
    TransactionModel(
      id: 'tx-$source',
      amountMinor: 25000,
      type: TransactionType.expense,
      merchant: 'Cafe Coffee Day',
      category: category,
      paymentMethod: 'UPI',
      date: DateTime(2026, 11, 2),
      time: '09:00',
      originalSms: '',
      isExcluded: false,
      source: source,
      bank: 'HDFC Bank',
    );

Widget _host(TransactionModel tx) => MaterialApp(
      home: Scaffold(body: TransactionTile(transaction: tx)),
    );

void main() {
  group('source glyph selection', () {
    test('an email import is marked with the envelope the app already uses',
        () {
      expect(transactionSourceIcon('Email-Gmail'), Icons.mail_outline_rounded);
    });

    test('a hand-entered row is marked with a pencil', () {
      expect(transactionSourceIcon('Manual'), Icons.edit_rounded);
    });

    test('every SMS variant stays unmarked', () {
      expect(transactionSourceIcon('SMS-Parser'), isNull);
      expect(transactionSourceIcon('SMS-AI'), isNull);
      // An unknown future source must not crash or invent a glyph.
      expect(transactionSourceIcon('Something-Else'), isNull);
    });
  });

  group('the tile renders it', () {
    testWidgets('an email import draws exactly one source icon',
        (tester) async {
      await tester.pumpWidget(_host(_tx(source: 'Email-Gmail')));
      await tester.pumpAndSettle();

      // The category bubble carries an icon too, so assert on the specific one
      // rather than on a count of all icons in the tree.
      expect(find.byIcon(Icons.mail_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
    });

    testWidgets('a manual row draws the pencil, not the envelope',
        (tester) async {
      await tester.pumpWidget(_host(_tx(source: 'Manual')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline_rounded), findsNothing);
    });

    testWidgets('an SMS row draws neither mark', (tester) async {
      await tester.pumpWidget(_host(_tx(source: 'SMS-Parser')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mail_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
    });

    testWidgets('the meta text is still shown alongside the glyph',
        (tester) async {
      await tester.pumpWidget(_host(_tx(source: 'Email-Gmail')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Food'), findsOneWidget);
      expect(find.textContaining('HDFC Bank'), findsOneWidget);
    });
  });

  group('the glyph does not break the row on a narrow screen', () {
    testWidgets('no overflow at 320 dp with a long merchant and bank',
        (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final long = TransactionModel(
        id: 'long',
        amountMinor: 123456789,
        type: TransactionType.expense,
        merchant: 'The Very Long Merchant Name Private Limited',
        category: 'Shopping',
        paymentMethod: 'UPI',
        date: DateTime(2026, 11, 2),
        time: '09:00',
        originalSms: '',
        isExcluded: false,
        source: 'Email-Gmail',
        bank: 'State Bank of India',
      );

      await tester.pumpWidget(_host(long));
      await tester.pumpAndSettle();

      // A RenderFlex overflow would throw during layout, failing the test.
      expect(tester.takeException(), isNull);
    });
  });
}
