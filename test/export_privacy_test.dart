import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

void main() {
  test('safe export excludes raw SMS and source identifiers', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = TransactionCacheService();
    await cache.init();
    await cache.put(TransactionModel(
      id: 'tx-1',
      amount: 100,
      type: TransactionType.expense,
      merchant: 'Shop',
      category: 'Shopping',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 23),
      time: '10:00',
      originalSms: 'raw bank message',
      isExcluded: false,
      bank: 'Bank',
      account: '1234',
      reference: 'UTR-1',
    ));

    final safe =
        jsonDecode(await cache.exportToJsonString()) as Map<String, dynamic>;
    final record = (safe['transactions'] as List).single as Map;

    expect(
        record.keys,
        containsAll(
            ['id', 'amountMinor', 'type', 'merchant', 'category', 'date']));
    expect(record, isNot(contains('originalSms')));
    expect(record, isNot(contains('account')));
    expect(record, isNot(contains('reference')));
  });

  test('sensitive export requires an explicit caller choice', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = TransactionCacheService();
    await cache.init();
    await cache.put(TransactionModel(
      id: 'tx-2',
      amount: 100,
      type: TransactionType.expense,
      merchant: 'Shop',
      category: 'Shopping',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 23),
      time: '10:00',
      originalSms: 'raw bank message',
      isExcluded: false,
      account: '1234',
      reference: 'UTR-1',
    ));

    final sensitive = jsonDecode(
      await cache.exportToJsonString(includeSensitive: true),
    ) as Map<String, dynamic>;
    final record = (sensitive['transactions'] as List).single as Map;

    expect(record['originalSms'], 'raw bank message');
    expect(record['account'], '1234');
    expect(record['reference'], 'UTR-1');
  });
}
