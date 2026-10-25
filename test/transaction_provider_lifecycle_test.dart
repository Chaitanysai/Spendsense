import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/sms_service.dart';

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
}
