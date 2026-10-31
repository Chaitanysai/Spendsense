import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/sms_service.dart';

TransactionModel _tx(String id) => TransactionModel(
      id: id,
      amountMinor: 12000,
      type: TransactionType.expense,
      merchant: 'Cafe',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 20),
      time: '09:00',
      originalSms: '',
      isExcluded: false,
    );

SmsMessageModel _sms() => SmsMessageModel(
      id: 'sms-1',
      body: 'Rs 450 debited from A/c XX1234 to Zomato on 12-10-26',
      date: DateTime(2026, 10, 12),
    );

void main() {
  test('overlapping resync calls share one scan', () async {
    SharedPreferences.setMockInitialValues({});
    final gate = Completer<List<SmsMessageModel>>();
    var fetchCount = 0;
    final provider = TransactionProvider(
      resyncFetcher: () {
        fetchCount++;
        return gate.future;
      },
    );
    await provider.ready;

    final first = provider.resyncFromSms();
    final second = provider.resyncFromSms();

    expect(identical(first, second), isTrue);
    gate.complete([_sms()]);
    expect(await first, isTrue);
    expect(fetchCount, 1);
    provider.dispose();
  });

  test('a resync finishing after disposal does not notify listeners', () async {
    SharedPreferences.setMockInitialValues({});
    final gate = Completer<List<SmsMessageModel>>();
    final provider = TransactionProvider(
      resyncFetcher: () => gate.future,
    );
    await provider.ready;

    final resync = provider.resyncFromSms();
    provider.dispose();
    gate.complete([]);

    expect(await resync, isFalse);
  });

  // Activity caches its filtered list keyed on the ledger's identity. Editing a
  // record in place kept that identity, so returning from the editor showed the
  // old amount/merchant until a filter changed. Every mutation must replace the
  // list.
  group('ledger list identity changes on mutation', () {
    test('addTransaction, edit, exclude, category and delete all rekey', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TransactionProvider();
      await provider.ready;
      await provider.addTransaction(_tx('tx-1'));

      var before = provider.transactions;
      await provider.updateTransaction(
        'tx-1',
        amount: 9900,
        merchant: 'Edited',
        category: 'Shopping',
        type: TransactionType.expense,
        isExcluded: false,
      );
      expect(identical(provider.transactions, before), isFalse);
      expect(provider.transactions.single.merchant, 'Edited');
      expect(provider.transactions.single.amountMinor, 9900);

      before = provider.transactions;
      await provider.toggleExclude('tx-1');
      expect(identical(provider.transactions, before), isFalse);
      expect(provider.transactions.single.isExcluded, isTrue);

      before = provider.transactions;
      await provider.updateCategory('tx-1', 'Bills');
      expect(identical(provider.transactions, before), isFalse);
      expect(provider.transactions.single.category, 'Bills');

      before = provider.transactions;
      await provider.addTransaction(_tx('tx-2'));
      expect(identical(provider.transactions, before), isFalse);
      expect(provider.transactions, hasLength(2));

      before = provider.transactions;
      await provider.deleteTransactionsByIds({'tx-1'});
      expect(identical(provider.transactions, before), isFalse);
      expect(provider.transactions.single.id, 'tx-2');
      provider.dispose();
    });
  });
}
