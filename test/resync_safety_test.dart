import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/sms_service.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

// Task B: resync must never clear the ledger before it knows the scan
// succeeded, and a failed/partial scan must leave the ledger unchanged.
// Synthetic fixtures only; no real SMS text.

TransactionModel _tx(String id, int amount,
        {String source = 'SMS-Parser',
        TransactionType type = TransactionType.expense}) =>
    TransactionModel(
      id: id,
      amount: amount,
      type: type,
      merchant: 'Merchant $id',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 12, 9, 30),
      time: '09:30',
      originalSms: 'debit notice $id',
      isExcluded: false,
      source: source,
    );

SmsMessageModel _sms(String id) => SmsMessageModel(
      id: id,
      body: 'Rs 450 debited from A/c XX1234 to Zomato on 12-10-26',
      date: DateTime(2026, 10, 12),
    );

class _FakeWriteHook {
  int failAt;
  bool persistent;
  int calls = 0;
  _FakeWriteHook(this.failAt, {this.persistent = false});

  Future<void> call(String op, String key) async {
    calls++;
    if (persistent ? calls >= failAt : calls == failAt) {
      throw StateError('injected write failure #$calls');
    }
  }
}

/// Builds an initialised provider over [seed], with an injectable cache write
/// hook and an injectable SMS source.
Future<TransactionProvider> _provider({
  required List<TransactionModel> seed,
  List<SmsMessageModel>? inbox,
  bool throws = false,
  _FakeWriteHook? hook,
}) async {
  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime(2026, 1, 1).toIso8601String(),
  });

  // Seed through a separate, unhealthy-free cache first.
  final seeder = TransactionCacheService();
  await seeder.init();
  await seeder.putAll(seed);

  final provider = TransactionProvider(
    resyncFetcher: () async {
      if (throws) throw StateError('sms channel unavailable');
      return inbox ?? [];
    },
  );
  // Let construction-time init() finish before touching the hook.
  await provider.ready;
  provider.debugSetCacheWriteHook(hook?.call);
  return provider;
}

List<String> _ids(TransactionProvider p) =>
    p.transactions.map((t) => t.id).toList()..sort();

int _total(TransactionProvider p) =>
    p.transactions.fold<int>(0, (s, t) => s + t.amountMinor);

void main() {
  group('REPRODUCTION: resync must not clear before it scans', () {
    test('a resync whose scan returns nothing leaves the ledger intact',
        () async {
      final provider = await _provider(
        seed: [_tx('sms-a', 100), _tx('sms-b', 200)],
        inbox: [],
      );
      final before = _ids(provider);

      await provider.resyncFromSms();

      expect(_ids(provider), before,
          reason: 'an empty scan is not evidence that the ledger is empty');
      expect(_total(provider), 30000);
      // And it survives a restart.
      final restarted = TransactionProvider();
      await restarted.ready;
      expect(_ids(restarted), before);
    });

    test('a resync whose scan throws leaves the ledger intact', () async {
      final provider = await _provider(
        seed: [_tx('sms-a', 100), _tx('sms-b', 200)],
        throws: true,
      );

      await provider.resyncFromSms();

      expect(_ids(provider), ['sms-a', 'sms-b']);
      expect(_total(provider), 30000);
    });
  });

  group('a successful resync replaces only what it can rebuild', () {
    test('SMS-derived rows are replaced; manual rows are kept', () async {
      final provider = await _provider(
        seed: [
          _tx('sms-old', 100),
          _tx('manual-1', 900, source: 'Manual'),
          _tx('manual-2', 50, source: 'Manual'),
          _tx('sms-old-2', 70),
        ],
        inbox: [_sms('sms-new-1'), _sms('sms-new-2')],
      );

      await provider.resyncFromSms();

      expect(
          _ids(provider), ['manual-1', 'manual-2', 'sms-new-1', 'sms-new-2']);
      expect(_total(provider), (900 + 50 + 450 + 450) * 100);
    });

    test('repeating a resync is idempotent', () async {
      final provider = await _provider(
        seed: [_tx('sms-old', 100), _tx('manual-1', 900, source: 'Manual')],
        inbox: [_sms('sms-new-1')],
      );

      await provider.resyncFromSms();
      final once = _ids(provider);
      final onceTotal = _total(provider);
      await provider.resyncFromSms();
      await provider.resyncFromSms();

      expect(_ids(provider), once);
      expect(_total(provider), onceTotal);
    });
  });

  group('failure injection on the resync activation and rollback path', () {
    test('every interruption point leaves the whole old ledger or the new one',
        () async {
      final seed = [
        _tx('sms-old', 100),
        _tx('manual-1', 900, source: 'Manual')
      ];
      final inbox = [_sms('sms-new-1'), _sms('sms-new-2')];

      // Learn the finished state and how many writes a resync performs.
      final counter = _FakeWriteHook(1 << 30);
      final probe = await _provider(seed: seed, inbox: inbox, hook: counter);
      // Captured BEFORE the resync: after it, a fresh provider's init() would
      // legitimately complete the journal and report the finished ledger.
      final oldIds = _ids(probe);
      final oldTotal = _total(probe);
      counter.calls = 0;
      await probe.resyncFromSms();
      final finishedIds = _ids(probe);
      final finishedTotal = _total(probe);
      final writes = counter.calls;
      expect(writes, greaterThan(3));
      expect(oldIds, isNot(equals(finishedIds)));

      // Failures are injected from the Nth write onwards. The probe above shows
      // which N still roll back and which N already switched the ledger.
      // 5 of the 8 writes are staging; the index switch is write 6, so a
      // failure from #6 on leaves the finished ledger (still entirely valid).
      final commitAt = 6;

      for (final persistent in [false, true]) {
        for (var n = 1; n <= writes; n++) {
          final hook = _FakeWriteHook(n, persistent: persistent);
          final provider =
              await _provider(seed: seed, inbox: inbox, hook: hook);
          hook.calls = 0;

          await provider.resyncFromSms();

          // Partition the interruption points rather than demanding "old or
          // new" at every one. Both are acceptable and each half is checked:
          //  * the write of the id index is the single visibility switch, so
          //    everything before it must roll back and everything after it must
          //    leave the finished ledger;
          //  * whenever a run completes without throwing, it MUST have
          //    committed — a silent half-commit would be the bug.
          final ids = _ids(provider);
          final isOld = ids.join(',') == oldIds.join(',');
          final isNew = ids.join(',') == finishedIds.join(',');
          expect(isOld || isNew, isTrue,
              reason: 'writes fail from #$n: got $ids, expected the old '
                  '$oldIds or the finished $finishedIds');
          if (n < commitAt) {
            expect(isOld, isTrue,
                reason: 'write #$n failed before the index switch, so the '
                    'ledger must be unchanged');
          } else {
            expect(isNew, isTrue,
                reason: 'write #$n is at/after the index switch, so the '
                    'finished ledger must be visible');
          }
          expect(_total(provider), isOld ? oldTotal : finishedTotal);

          // The thing that must never happen: a resync leaves a HALF-rebuilt
          // ledger. Either every old SMS-derived row is still there, or none
          // of them is (replaced by the new set).
          final hasOldRow = ids.contains('sms-old');
          final hasNewRows = ids.contains('sms-new-1');
          expect(hasOldRow && hasNewRows, isFalse,
              reason: 'write #$n: half-rebuilt ledger $ids mixes old and new '
                  'SMS rows');

          // Memory and disk agree after a restart. A restarted provider also
          // COMPLETES a staged-but-uncommitted journal by design, so the
          // on-disk state is either the visible ledger or the finished one —
          // never a partial mix.
          final restarted = TransactionProvider();
          await restarted.ready;
          final restartedIds = _ids(restarted);
          expect(
              restartedIds.join(',') == ids.join(',') ||
                  restartedIds.join(',') == finishedIds.join(','),
              isTrue,
              reason:
                  'write #$n: after restart got $restartedIds, expected the '
                  'visible $ids or the finished $finishedIds');
          expect(restartedIds.toSet().length, restartedIds.length,
              reason: 'write #$n: no duplicates');
        }
      }
    });

    test('a failed resync can be retried to completion, without duplicates',
        () async {
      final seed = [
        _tx('sms-old', 100),
        _tx('manual-1', 900, source: 'Manual')
      ];
      final inbox = [_sms('sms-new-1'), _sms('sms-new-2')];

      final hook = _FakeWriteHook(3);
      final provider = await _provider(seed: seed, inbox: inbox, hook: hook);
      await provider.resyncFromSms(); // fails part-way
      hook.persistent = false;
      hook.failAt = 1 << 30; // the retry is healthy

      await provider.resyncFromSms();
      final once = _ids(provider);
      await provider.resyncFromSms();

      expect(_ids(provider), once);
      expect(once.toSet().length, once.length, reason: 'no duplicates');
      expect(once, ['manual-1', 'sms-new-1', 'sms-new-2']);
    });
  });

  group('the "nothing changed" empty-cache guard is gone', () {
    test('clearing every transaction is visible after a restart', () async {
      final provider = await _provider(seed: [_tx('sms-a', 100)]);
      await provider.clearAll();
      expect(provider.transactions, isEmpty);

      final restarted = TransactionProvider();
      await restarted.ready;
      expect(restarted.transactions, isEmpty,
          reason:
              'an emptied ledger must not be resurrected from stale memory');
    });
  });
}
