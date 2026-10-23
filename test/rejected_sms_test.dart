import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

// B6: a message the app skipped must be recoverable, must never be processed
// twice, and recovery must not retain or log message contents.
// Only message IDs are stored for skipped messages (never bodies). Synthetic
// fixtures only.

TransactionModel _tx(String id, int amount) => TransactionModel(
      id: id,
      amount: amount,
      type: TransactionType.expense,
      merchant: 'Merchant $id',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 12),
      time: '09:30',
      originalSms: 'synthetic $id',
      isExcluded: false,
      source: 'SMS-Parser',
    );

Future<TransactionCacheService> _service() async {
  final c = TransactionCacheService();
  await c.init();
  return c;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('skipped messages are recoverable', () {
    test('clearAll also forgets skipped ids (audit R3), in memory and on disk',
        () async {
      final cache = await _service();
      await cache.markRejected('sms-skipped');
      expect(cache.contains('sms-skipped'), isTrue);

      await cache.clearAll();

      expect(cache.contains('sms-skipped'), isFalse,
          reason: 'a rescan must be able to look at this message again');
      expect((await _service()).contains('sms-skipped'), isFalse,
          reason: 'and the forgetting must survive a restart');
    });

    test('clearRejected forgets only skipped ids and reports how many',
        () async {
      final cache = await _service();
      await cache.putAll([_tx('kept-1', 100), _tx('kept-2', 200)]);
      await cache.markRejected('skip-1');
      await cache.markRejected('skip-2');
      await cache.markRejected('skip-3');

      final n = await cache.clearRejected();

      expect(n, 3);
      expect(cache.rejectedCount, 0);
      expect(cache.contains('skip-1'), isFalse);
      expect(cache.contains('kept-1'), isTrue,
          reason: 'saved transactions must keep blocking re-import');
      expect((await cache.loadAll()).length, 2);
      final restarted = await _service();
      expect(restarted.rejectedCount, 0);
      expect(restarted.cachedIds, {'kept-1', 'kept-2'});
    });

    test('clearRejected on an empty set is a harmless no-op', () async {
      final cache = await _service();
      expect(await cache.clearRejected(), 0);
      expect(cache.rejectedCount, 0);
    });

    test('a message reconsidered and then accepted is never stored twice',
        () async {
      final cache = await _service();
      await cache.markRejected('sms-1');
      await cache.clearRejected();

      // The next sync re-parses it and saves it — repeatedly, if retried.
      await cache.put(_tx('sms-1', 450));
      await cache.put(_tx('sms-1', 450));
      await cache.clearRejected(); // a second recheck must not disturb it
      await cache.put(_tx('sms-1', 450));

      expect(cache.cachedIds.where((i) => i == 'sms-1').length, 1);
      expect((await cache.loadAll()).length, 1);
    });

    test('a saved transaction is not reprocessed even after a recheck',
        () async {
      final cache = await _service();
      await cache.put(_tx('sms-1', 450));
      await cache.clearRejected();
      expect(cache.contains('sms-1'), isTrue);
    });

    test('rejection is still permanent WITHOUT an explicit recheck', () async {
      final cache = await _service();
      await cache.markRejected('sms-1');
      expect(cache.contains('sms-1'), isTrue);
      expect((await _service()).contains('sms-1'), isTrue);
    });
  });

  group('no message contents are retained or logged', () {
    test('only metadata is persisted for skipped messages', () async {
      final cache = await _service();
      await cache.markRejected('sms-1');
      await cache.markRejected('sms-2');

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('tx_rejected_ids')!;
      // Current format: one entry per message with an id, a reason code and a
      // timestamp. Never the message body itself.
      final entries = jsonDecode(stored) as List;
      expect(entries.length, 2);
      expect(entries.map((e) => (e as Map)['id']).toList().toSet(),
          {'sms-1', 'sms-2'});
      expect(
          entries.every((e) => (e as Map)
              .keys
              .toSet()
              .every((k) => {'id', 'reason', 'firstSeen'}.contains(k))),
          isTrue);
    });

    test('rejecting, rechecking and clearing never print the ids\' contents',
        () async {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      addTearDown(() => debugPrint = original);

      final cache = await _service();
      await cache.putAll([_tx('sms-1', 987654)]);
      await cache.markRejected('sms-2');
      await cache.clearRejected();
      await cache.clearAll();

      final joined = printed.join('\n');
      expect(joined.contains('Merchant sms-1'), isFalse);
      expect(joined.contains('synthetic'), isFalse);
      expect(joined.contains('987654'), isFalse);
    });
  });
}
