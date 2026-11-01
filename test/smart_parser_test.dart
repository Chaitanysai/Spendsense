import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/smart_parser.dart';

void main() {
  late SmartParser parser;
  final date = DateTime(2026, 10, 6, 12, 1);

  setUp(() => parser = SmartParser());

  Future<TransactionModel?> parse(String sms, [String id = 'test']) =>
      parser.parse(sms, id, date);

  group('debit-only SMS import', () {
    test('Axis debit extracts merchant, bank and contextual amount', () async {
      const sms =
          'Your A/c has been debited towards Jio Prepaid Recharges for INR 239.00 on 06-10-26. 1c0d8d3d98594def965529cb4668c280@ptyes - Axis Bank';
      final result = await parse(sms, 'axis');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amountMinor, 23900);
      expect(result.merchant, 'Jio Prepaid Recharges');
      expect(result.bank, 'Axis Bank');
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('Federal UPI debit excludes reference, balance and phone', () async {
      const sms =
          'Debited Rs 690.00 from a/c X0592 on 06Oct26 12:01 via UPI to YAMA BHARATH. Ref 987242762796.Bal Rs 1440.77. Not you?Call 18004251199 -Federal Bank';
      final result = await parse(sms, 'federal-debit');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amountMinor, 69000);
      expect(result.amountMinor, isNot(144077));
      expect(result.amountMinor, isNot(98724276279600));
      expect(result.amountMinor, isNot(1800425119900));
      expect(result.merchant, 'YAMA BHARATH');
      expect(result.bank, 'Federal Bank');
      expect(result.account, '0592');
      expect(result.paymentMethod, 'UPI');
      expect(result.reference, '987242762796');
      expect(result.confidence, greaterThanOrEqualTo(0.8));
    });

    test('Federal credit is rejected before amount extraction', () async {
      const sms =
          'Rs 178.09 credited to your A/c XX0592 via IMPS on 06OCT2026 13:55:02 IMPS Ref no 627915996113 Bal:Rs 9618.86 -Federal Bank';
      expect(SmartParser.isDebitExpenseSms(sms), isFalse);
      expect(await parse(sms, 'federal-credit'), isNull);
    });

    test('Airtel Payments Bank debit uses generic merchant', () async {
      const sms =
          'Rs. 1.00 debited from Airtel Payments Bank a/c Txn ID 217406224829 Bal:39.80 Call 180023400 for help';
      final result = await parse(sms, 'airtel');
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amountMinor, 100);
      expect(result.amountMinor, isNot(3980));
      expect(result.amountMinor, isNot(21740622482900));
      expect(result.amountMinor, isNot(18002340000));
      expect(result.bank, 'Airtel Payments Bank');
      expect(result.reference, '217406224829');
      expect(result.merchant, 'Bank Debit');
    });

    test('rejects credit, balance-only, OTP and promotional messages',
        () async {
      for (final sms in [
        'Your account has been credited with Rs 5000',
        'Available balance Rs 5000',
        'OTP for transaction is 123456',
        'Get cashback of Rs 100',
        'Rs 178.09 credited ... Bal Rs 9618.86',
        'Your payment of Rs 250 was declined and not debited',
        'Dr Sharma balance is Rs 5000',
      ]) {
        expect(await parse(sms), isNull, reason: sms);
      }
    });

    test('uses debit amount before balance and reference sections', () async {
      final withBalance = await parse(
        'Rs 250 debited via UPI to ABC STORE. Bal Rs 5000',
      );
      expect(withBalance?.amountMinor, 25000);
      expect(withBalance?.merchant, 'ABC STORE');

      final withReference = await parse(
        'Rs 100 debited. Ref 123456789. Bal Rs 2000',
      );
      expect(withReference?.amountMinor, 10000);

      final drMarker = await parse('Rs 75 DR');
      expect(drMarker?.amountMinor, 7500);
    });

    test('preserves contextual parsing of the Axis example', () async {
      final result = await parse(
        'Your A/c has been debited towards Jio Prepaid Recharges for INR 239.00 on 06-10-26. 1c0d8d3d98594def965529cb4668c280@ptyes - Axis Bank',
      );
      expect(result?.amountMinor, 23900);
    });
  });

  group('outgoing transfers', () {
    // Banks often announce money leaving the account as "sent" rather than
    // "debited". Those messages were rejected outright, so transfers were
    // never recorded as spending.
    test('"sent from your account" is an expense', () async {
      final result = await parse(
        'Rs. 600 sent from your account on 01-11-26 to Rahul',
      );
      expect(result, isNotNull);
      expect(result!.type, TransactionType.expense);
      expect(result.amountMinor, 60000);
    });

    test('"sent to" is an expense', () async {
      final result = await parse(
        'Rs 600 sent to Rahul on 01-11-26 from A/c XX1234',
      );
      expect(result, isNotNull);
      expect(result!.amountMinor, 60000);
    });

    test('"sent via UPI" is an expense and keeps the payment method', () async {
      final result = await parse('INR 250 sent via UPI to Swiggy');
      expect(result, isNotNull);
      expect(result!.amountMinor, 25000);
      expect(result.paymentMethod, 'UPI');
    });

    test('"transferred" is an expense', () async {
      final result = await parse(
        'Rs. 1200 transferred from A/c XX1234 to Meera on 01-11-26',
      );
      expect(result, isNotNull);
      expect(result!.amountMinor, 120000);
    });

    test('money arriving is still rejected — "sent you" is not spending',
        () async {
      expect(
        SmartParser.isDebitExpenseSms('Rahul has sent you Rs 600 on 01-11-26'),
        isFalse,
      );
      expect(await parse('Rahul has sent you Rs 600 on 01-11-26'), isNull);
    });
  });
}
