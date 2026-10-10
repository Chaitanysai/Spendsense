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
      expect(result.amount, 239.00);
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
      expect(result.amount, 690.00);
      expect(result.amount, isNot(1440.77));
      expect(result.amount, isNot(987242762796));
      expect(result.amount, isNot(18004251199));
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
      expect(result.amount, 1.00);
      expect(result.amount, isNot(39.80));
      expect(result.amount, isNot(217406224829));
      expect(result.amount, isNot(180023400));
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
      expect(withBalance?.amount, 250);
      expect(withBalance?.merchant, 'ABC STORE');

      final withReference = await parse(
        'Rs 100 debited. Ref 123456789. Bal Rs 2000',
      );
      expect(withReference?.amount, 100);

      final drMarker = await parse('Rs 75 DR');
      expect(drMarker?.amount, 75);
    });

    test('preserves contextual parsing of the Axis example', () async {
      final result = await parse(
        'Your A/c has been debited towards Jio Prepaid Recharges for INR 239.00 on 06-10-26. 1c0d8d3d98594def965529cb4668c280@ptyes - Axis Bank',
      );
      expect(result?.amount, 239);
    });
  });
}
