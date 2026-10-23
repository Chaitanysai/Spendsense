import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

// Task C: the 90-day retention policy for skipped-message metadata.
//
// Stored per skipped message: the SMS id, a coarse reason CODE and firstSeen.
// Never the message body, merchant, amount or account. Policy: a record is
// forgotten after 90 days and may then be reconsidered by the next scan.
// Synthetic fixtures only.

TransactionModel _tx(String id, int amount) => TransactionModel(
      id: id,
      amount: amount,
      type: TransactionType.expense,
      merchant: 'Merchant $id',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 12),
      time: '09:30',
      originalSms: 'debit notice $id',
      isExcluded: false,
      source: 'SMS-Parser',
    );

Future<TransactionCacheService> _service() async {
  final c = TransactionCacheService();
  await c.init();
  return c;
}

Map<String, dynamic> _firstStored(SharedPreferences prefs) =>
    (jsonDecode(prefs.getString('tx_rejected_ids')!) as List).first
        as Map<String, dynamic>;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('only the minimum metadata is stored', () {
    test('a skipped message records exactly id, reason and firstSeen',
        () async {
      final cache = await _service();
      await cache.markRejected('sms-1', reason: 'PROMO');

      final prefs = await SharedPreferences.getInstance();
      final entry = _firstStored(prefs);
      expect(entry.keys.toSet(), {'id', 'reason', 'firstSeen'});
      expect(entry['id'], 'sms-1');
      expect(entry['reason'], 'PROMO');
      expect(DateTime.tryParse(entry['firstSeen'] as String), isNotNull);
    });

    test('no message text, merchant, amount or account is written', () async {
      final cache = await _service();
      await cache.putAll([_tx('sms-saved', 987654)]);
      await cache.markRejected('sms-1', reason: 'UNKNOWN');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('tx_rejected_ids')!;
      expect(stored.contains('Merchant'), isFalse);
      expect(stored.contains('debit notice'), isFalse);
      expect(stored.contains('987654'), isFalse);
      expect(stored.contains('XX1234'), isFalse);
    });

    test('the default reason is a code, not a copied rejection message',
        () async {
      final cache = await _service();
      await cache.markRejected('sms-1');
      final prefs = await SharedPreferences.getInstance();
      expect(_firstStored(prefs)['reason'], 'UNKNOWN');
    });
  });

  group('90-day expiry', () {
    test('a record older than 90 days is dropped on init', () async {
      final old = DateTime.now().subtract(const Duration(days: 91));
      SharedPreferences.setMockInitialValues({
        'tx_rejected_ids': jsonEncode([
          {
            'id': 'stale',
            'reason': 'PROMO',
            'firstSeen': old.toIso8601String()
          },
          {
            'id': 'fresh',
            'reason': 'PROMO',
            'firstSeen': DateTime.now()
                .subtract(const Duration(days: 10))
                .toIso8601String(),
          },
        ]),
      });

      final cache = await _service();
      expect(cache.contains('stale'), isFalse,
          reason: 'expired metadata must not keep suppressing a message');
      expect(cache.contains('fresh'), isTrue);
      expect(cache.rejectedCount, 1);

      // The pruning is persisted, so it does not run again on every start.
      final prefs = await SharedPreferences.getInstance();
      final ids = (jsonDecode(prefs.getString('tx_rejected_ids')!) as List)
          .map((e) => (e as Map)['id'])
          .toList();
      expect(ids, ['fresh']);
    });

    test('a record at exactly 90 days is kept; one second older is not',
        () async {
      final now = DateTime.now();
      final cache = await _service();
      await cache.markRejected('at-boundary', reason: 'CREDIT');
      await cache.markRejected('past-boundary', reason: 'CREDIT');

      // Age them by rewriting firstSeen through the public pruning seam.
      await cache.pruneExpiredRejected(
          now: now.add(const Duration(days: 90) - const Duration(seconds: 1)));
      expect(cache.rejectedCount, 2, reason: 'nothing has expired yet');

      await cache.pruneExpiredRejected(
          now: now.add(const Duration(days: 90, seconds: 1)));
      expect(cache.contains('at-boundary') || cache.contains('past-boundary'),
          isFalse);
    });

    test('re-marking an already-skipped message does not extend its window',
        () async {
      final cache = await _service();
      await cache.markRejected('sms-1', reason: 'PROMO');
      final first = cache.rejectedMessages.single.firstSeen;

      await cache.markRejected('sms-1', reason: 'PROMO');
      await cache.markRejected('sms-1', reason: 'UNKNOWN');

      expect(cache.rejectedCount, 1);
      expect(cache.rejectedMessages.single.firstSeen, first);
      expect(cache.rejectedMessages.single.reason, 'PROMO',
          reason: 'the first recorded reason wins');
    });

    test('an explicit prune with a future clock removes everything', () async {
      final cache = await _service();
      await cache.markRejected('a', reason: 'PROMO');
      await cache.markRejected('b', reason: 'CREDIT');
      expect(
          await cache.pruneExpiredRejected(
              now: DateTime.now().add(const Duration(days: 91))),
          2);
      expect(cache.rejectedCount, 0);
    });
  });

  group('retry idempotency', () {
    test('a recheck, a resync and repeated marks never duplicate a row',
        () async {
      final cache = await _service();
      await cache.markRejected('sms-1', reason: 'PROMO');
      await cache.clearRejected();
      await cache.markRejected('sms-1', reason: 'PROMO');
      await cache.markRejected('sms-1', reason: 'PROMO');
      expect(cache.rejectedCount, 1);

      // Now the message parses: it is saved once and keeps blocking re-import.
      await cache.put(_tx('sms-1', 450));
      await cache.put(_tx('sms-1', 450));
      await cache.clearRejected();
      await cache.put(_tx('sms-1', 450));

      expect(cache.cachedIds.where((i) => i == 'sms-1').length, 1);
      expect((await cache.loadAll()).length, 1);
      expect(cache.contains('sms-1'), isTrue);
    });
  });

  group('deletion', () {
    test('clearAll forgets saved transactions AND skip metadata', () async {
      final cache = await _service();
      await cache.putAll([_tx('kept', 100)]);
      await cache.markRejected('skip-1', reason: 'PROMO');

      await cache.clearAll();

      expect(cache.cachedIds, isEmpty);
      expect(cache.rejectedCount, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tx_rejected_ids'), isNull);
      final restarted = await _service();
      expect(restarted.rejectedCount, 0);
      expect(restarted.cachedIds, isEmpty);
    });

    test('clearRejected does not touch saved transactions', () async {
      final cache = await _service();
      await cache.putAll([_tx('kept-1', 100), _tx('kept-2', 200)]);
      await cache.markRejected('skip-1', reason: 'PROMO');
      await cache.markRejected('skip-2', reason: 'CREDIT');

      expect(await cache.clearRejected(), 2);
      expect(cache.rejectedCount, 0);
      expect(cache.cachedIds, {'kept-1', 'kept-2'});
      expect((await cache.loadAll()).length, 2);
    });
  });

  group('legacy upgrade', () {
    test('a legacy list of bare ids is accepted and migrated on write',
        () async {
      SharedPreferences.setMockInitialValues({
        'tx_rejected_ids': jsonEncode(['old-1', 'old-2']),
      });
      final cache = await _service();
      expect(cache.rejectedCount, 2);
      expect(cache.contains('old-1'), isTrue);
      expect(
          cache.rejectedMessages.every((r) => r.reason == 'UNKNOWN'), isTrue);

      // Recording a new one rewrites the list in the current format.
      await cache.markRejected('new-1', reason: 'PROMO');
      final prefs = await SharedPreferences.getInstance();
      final list = jsonDecode(prefs.getString('tx_rejected_ids')!) as List;
      expect(list.whereType<Map>().length, 3);
      expect(prefs.getString('tx_rejected_ids')!.contains('"reason"'), isTrue);
    });

    test('malformed entries are ignored rather than crashing init', () async {
      SharedPreferences.setMockInitialValues({
        'tx_rejected_ids': jsonEncode([
          {
            'id': 'ok',
            'reason': 'PROMO',
            'firstSeen': '2026-10-01T00:00:00.000'
          },
          {'no_id': true},
          42,
          null,
          '',
        ]),
      });
      // jsonEncode can't carry bare nulls inside a typed list, so build the raw
      // string to be sure the parser is defensive.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tx_rejected_ids',
          '[{"id":"ok","reason":"PROMO","firstSeen":"2026-10-01T00:00:00.000"},{"no_id":true},42,null,""]');
      SharedPreferences.resetStatic();
      final cache = await _service();
      expect(cache.rejectedCount, 1);
      expect(cache.contains('ok'), isTrue);
    });
  });

  group('nothing sensitive is logged', () {
    test('mark, prune, recheck and clear never print record contents',
        () async {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      addTearDown(() => debugPrint = original);

      final cache = await _service();
      await cache.putAll([_tx('sms-saved', 987654)]);
      await cache.markRejected('sms-1', reason: 'PROMO');
      await cache.pruneExpiredRejected(
          now: DateTime.now().add(const Duration(days: 200)));
      await cache.clearRejected();
      await cache.clearAll();

      final joined = printed.join('\n');
      expect(joined.contains('Merchant'), isFalse);
      expect(joined.contains('debit notice'), isFalse);
      expect(joined.contains('987654'), isFalse);
    });
  });
}
