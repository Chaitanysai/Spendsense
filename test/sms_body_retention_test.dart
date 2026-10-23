import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/smart_parser.dart';

// Task D: end-to-end proof that a NEWLY parsed record does not carry the raw
// bank SMS, while everything derived from it is still correct.
// Synthetic fixtures only.

const _debit =
    'Rs 450 debited from A/c XX1234 to Zomato on 12-10-26. Avl Bal Rs 12,340.50';

void main() {
  test('a parsed record keeps the derived fields but not the raw body',
      () async {
    final tx =
        await SmartParser().parse(_debit, 'sms-1', DateTime(2026, 10, 12));

    expect(tx, isNotNull);
    expect(tx!.originalSms, isEmpty,
        reason: 'the raw bank SMS must not be retained on new records');
    // The derived data the user actually sees is unaffected.
    expect(tx.amountMinor, 45000);
    expect(tx.type, TransactionType.expense);
    expect(tx.merchant.toLowerCase(), contains('zomato'));
    expect(tx.id, 'sms-1');
  });

  test('a manually added record still uses an empty body', () {
    final tx = TransactionModel(
      id: 'm1',
      amount: 100,
      type: TransactionType.expense,
      merchant: 'Shop',
      category: 'Food',
      paymentMethod: 'Cash',
      date: DateTime(2026, 10, 12),
      time: '10:00',
      originalSms: '',
      isExcluded: false,
      source: 'Manual',
    );
    expect(tx.originalSms, isEmpty);
    expect(tx.source, 'Manual');
  });

  test('an existing record with a stored body is still readable unchanged',
      () async {
    // Simulate a record persisted before the policy change.
    final legacy = TransactionModel.fromJson({
      'id': 'old-1',
      'amount': 450,
      'type': 'expense',
      'merchant': 'Zomato',
      'category': 'Food',
      'paymentMethod': 'UPI',
      'date': '2026-10-12T09:30:00.000',
      'time': '09:30',
      'originalSms': _debit,
      'isExcluded': false,
      'source': 'SMS-Parser',
    });
    expect(legacy.originalSms, _debit,
        reason: 'existing bodies must not be rewritten by this change');
    expect(legacy.originalSms, isNotEmpty);
  });

  test('round-tripping an existing record preserves its stored body', () {
    final legacy = TransactionModel(
      id: 'old-2',
      amount: 450,
      type: TransactionType.expense,
      merchant: 'Zomato',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 12),
      time: '09:30',
      originalSms: _debit,
      isExcluded: false,
      source: 'SMS-Parser',
    );
    final reread = TransactionModel.fromJson(legacy.toJson());
    expect(reread.originalSms, _debit);
  });
}
