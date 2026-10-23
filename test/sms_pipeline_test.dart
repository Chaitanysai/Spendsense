import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/smart_parser.dart';
import 'package:spendsense/services/transaction_cache_service.dart';
import 'package:spendsense/utils/bank_recognizer.dart';

/// Verification for the SMS transaction pipeline: parsing, bank coverage,
/// duplicate suppression and persistence across a restart.
void main() {
  group('BankRecognizer — supported bank coverage', () {
    // One representative message shape per supported bank.
    const bankCases = <String, String>{
      'HDFC Bank': 'HDFC Bank INR 450.00 debited at Zomato',
      'ICICI Bank': 'ICICI Bank INR 1200.50 debited at Amazon',
      'Axis Bank': 'Axis Bank INR 99.00 debited to Swiggy',
      'SBI': 'State Bank of India INR 250.00 debited at Uber',
      'Kotak Mahindra Bank': 'Kotak INR 75.25 debited at Cafe',
      'Punjab National Bank': 'Punjab National Bank INR 300.00 debited',
      'IDBI Bank': 'IDBI Bank INR 60.00 debited at Metro',
      'IndusInd Bank': 'IndusInd INR 500.00 debited at BookMyShow',
      'Canara Bank': 'Canara Bank INR 40.00 debited',
      'Union Bank of India': 'Union Bank of India INR 88.00 debited',
      'Federal Bank': 'Federal Bank INR 150.00 debited',
      'Airtel Payments Bank': 'Airtel Payments Bank INR 20.00 debited',
      'Paytm Payments Bank': 'Paytm Payments Bank INR 65.00 debited',
      'Bank of Baroda': 'Bank of Baroda INR 210.00 debited',
      'IDFC FIRST Bank': 'IDFC FIRST Bank INR 33.00 debited',
      'YES Bank': 'YES Bank INR 77.00 debited',
      'RBL Bank': 'RBL Bank INR 12.00 debited',
      'Central Bank of India': 'Central Bank of India INR 400.00 debited',
      'South Indian Bank': 'South Indian Bank INR 90.00 debited',
      'Bank of Maharashtra': 'Bank of Maharashtra INR 55.00 debited',
    };

    bankCases.forEach((expected, sms) {
      test('detects $expected', () {
        expect(BankRecognizer.detectFromSms(sms), expected);
      });
    });

    test('detects every alias token it advertises', () {
      // Guards against an alias being added without a matching canonical entry.
      const tokens = [
        'airtel payments bank',
        'paytm payments bank',
        'bank of baroda',
        'punjab national bank',
        'state bank of india',
        'south indian bank',
        'karur vysya',
        'city union bank',
        'bank of maharashtra',
        'punjab and sind',
        'central bank of india',
        'union bank of india',
        'canara bank',
        'idbi bank',
        'indusind',
        'yes bank',
        'idfc',
        'bandhan',
        'rbl',
        'kotak',
        'federal bank',
        'icici',
        'hdfc',
        'axis',
      ];
      for (final token in tokens) {
        expect(
          BankRecognizer.detectFromSms('Paid to $token via UPI'),
          isNotNull,
          reason: 'alias "$token" did not resolve',
        );
      }
    });

    test('prefers the more specific alias over a contained token', () {
      // 'south indian bank' must win over 'indian bank'.
      expect(
        BankRecognizer.detectFromSms('South Indian Bank INR 10 debited'),
        'South Indian Bank',
      );
      expect(
        BankRecognizer.detectFromSms('Union Bank of India INR 10 debited'),
        'Union Bank of India',
      );
    });

    test('returns null when no bank is named', () {
      expect(
          BankRecognizer.detectFromSms('Your bill of Rs 500 is due'), isNull);
    });

    test('normalize rejects degenerate and unknown values', () {
      expect(BankRecognizer.normalize('Bank'), isNull);
      expect(BankRecognizer.normalize('Your Bank'), isNull);
      expect(BankRecognizer.normalize('Bank Account'), isNull);
      expect(BankRecognizer.normalize('Others'), isNull);
      expect(BankRecognizer.normalize('unknown'), isNull);
      expect(BankRecognizer.normalize(''), isNull);
      expect(BankRecognizer.normalize(null), isNull);
    });

    test('normalize keeps a real bank and canonicalises a known alias', () {
      expect(BankRecognizer.normalize('HDFC'), 'HDFC Bank');
      expect(BankRecognizer.normalize('hdfc'), 'HDFC Bank');
      expect(BankRecognizer.normalize('Dena Bank'), 'Dena Bank');
    });

    test('isKnown excludes the display fallback', () {
      expect(BankRecognizer.isKnown('HDFC Bank'), isTrue);
      expect(BankRecognizer.isKnown('Others'), isFalse);
      expect(BankRecognizer.isKnown(''), isFalse);
      expect(BankRecognizer.isKnown(null), isFalse);
    });
  });

  group('SmartParser — direction and amount', () {
    late SmartParser parser;
    final at = DateTime(2026, 10, 12, 9, 30);

    setUp(() => parser = SmartParser());

    Future<TransactionModel?> parse(String sms, [String id = 'test']) =>
        parser.parse(sms, id, at);

    test('reads a debit with merchant, bank and amount', () async {
      final tx = await parse(
        'HDFC Bank INR 450.00 debited at Zomato',
        'sms-1',
      );
      expect(tx, isNotNull);
      expect(tx!.type, TransactionType.expense);
      expect(tx.amountMinor, 45000);
      expect(tx.bank, 'HDFC Bank');
    });

    test('rejects a credit — SMS import is debit-only by design', () async {
      // Salaries/refunds arriving by SMS are deliberately not auto-imported, so
      // the dashboard never silently double-counts an inflow the user also
      // records manually.
      expect(
          SmartParser.isDebitExpenseSms(
              'HDFC Bank INR 25000.00 credited to your account'),
          isFalse);
      expect(
          await parse(
              'HDFC Bank INR 25000.00 credited to your account', 'sms-2'),
          isNull);
    });

    test('ignores OTP, promotional and balance-only messages', () async {
      const noise = [
        'Your OTP is 482913 for the transaction',
        'Get 10% off your next order at our store',
        'Avl Bal: 52340.67 as on 12-10-2026',
      ];
      for (final sms in noise) {
        expect(
          await parse(sms, 'noise'),
          isNull,
          reason: 'should not parse: $sms',
        );
      }
    });

    test('the same message parsed twice yields the same id', () async {
      const sms = 'Axis Bank INR 99.00 debited at Swiggy';
      final a = await parse(sms, 'stable-id');
      final b = await parse(sms, 'stable-id');
      expect(a!.id, b!.id);
      expect(a.id, 'stable-id');
    });

    test('the same amount credits and debits are treated oppositely', () async {
      final debit = await parse(
        'ICICI Bank INR 5000.00 debited from your account',
        'd1',
      );
      expect(debit, isNotNull);
      expect(debit!.type, TransactionType.expense);

      final credit = await parse(
        'ICICI Bank INR 5000.00 credited to your account',
        'c1',
      );
      expect(credit, isNull);
    });
  });

  group('TransactionCacheService — dedup and persistence', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    TransactionModel tx(String id, {double amount = 100}) => TransactionModel(
          id: id,
          amount: amount.toInt(),
          type: TransactionType.expense,
          merchant: 'Test',
          category: 'Food',
          paymentMethod: 'UPI',
          date: DateTime(2026, 10, 12),
          time: '12:00',
          originalSms: 'raw $id',
          isExcluded: false,
          source: 'SMS',
        );

    test('contains() is false before anything is stored', () async {
      final cache = TransactionCacheService();
      await cache.init();
      expect(cache.contains('sms-1'), isFalse);
    });

    test('a stored SMS is reported as already seen', () async {
      final cache = TransactionCacheService();
      await cache.init();
      await cache.put(tx('sms-1'));
      expect(cache.contains('sms-1'), isTrue);
      expect(cache.contains('sms-2'), isFalse);
    });

    test('re-putting the same SMS does not duplicate it', () async {
      final cache = TransactionCacheService();
      await cache.init();
      await cache.put(tx('sms-1'));
      await cache.put(tx('sms-1'));
      await cache.put(tx('sms-1'));

      expect(cache.cachedIds.where((id) => id == 'sms-1').length, 1);
      expect((await cache.loadAll()).length, 1);
    });

    test('putAll is idempotent for overlapping ids', () async {
      final cache = TransactionCacheService();
      await cache.init();
      await cache.putAll([tx('sms-1'), tx('sms-2')]);
      await cache.putAll([tx('sms-2'), tx('sms-3')]);

      final all = await cache.loadAll();
      expect(all.length, 3);
      expect(all.map((t) => t.id).toSet(), {'sms-1', 'sms-2', 'sms-3'});
    });

    test('transactions survive a restart of the cache service', () async {
      final first = TransactionCacheService();
      await first.init();
      await first.putAll([tx('sms-1', amount: 450), tx('sms-2', amount: 1200)]);

      // Simulate an app restart: brand-new service over the same storage.
      final second = TransactionCacheService();
      await second.init();

      expect(second.contains('sms-1'), isTrue);
      expect(second.contains('sms-2'), isTrue);
      final restored = await second.loadAll();
      expect(restored.length, 2);
      expect(restored.map((t) => t.amountMinor).toSet(), {45000, 120000});
      final reread = await second.get('sms-1');
      expect(reread, isNotNull);
      expect(reread!.amountMinor, 45000);
      expect(reread.originalSms, 'raw sms-1');
    });

    test('removing an id clears it from the dedup set', () async {
      final cache = TransactionCacheService();
      await cache.init();
      await cache.put(tx('sms-1'));
      await cache.remove('sms-1');

      expect(cache.contains('sms-1'), isFalse);
      expect((await cache.loadAll()).isEmpty, isTrue);

      final restarted = TransactionCacheService();
      await restarted.init();
      expect(restarted.contains('sms-1'), isFalse);
    });

    test('a rejected id is also suppressed on rescan', () async {
      final cache = TransactionCacheService();
      await cache.init();
      await cache.markRejected('sms-bad');
      expect(cache.contains('sms-bad'), isTrue);

      final restarted = TransactionCacheService();
      await restarted.init();
      expect(restarted.contains('sms-bad'), isTrue);
    });

    test('exported JSON round-trips through import', () async {
      final cache = TransactionCacheService();
      await cache.init();
      await cache.putAll([tx('sms-1', amount: 450), tx('sms-2', amount: 99)]);

      final exported = await cache.exportToJsonString();
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      expect((decoded['transactions'] as List).length, 2);

      SharedPreferences.setMockInitialValues({});
      final fresh = TransactionCacheService();
      await fresh.init();
      await fresh.importFromJsonString(exported);

      expect((await fresh.loadAll()).length, 2);
      expect(fresh.contains('sms-1'), isTrue);
    });
  });
}
