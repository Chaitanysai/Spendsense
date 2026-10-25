import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

// Import policy under test (documented in docs/product-readiness/remediation-b5.md):
//  * The whole file is validated before anything is written.
//  * Accepted envelope: {"version": 2|"2"|"2.0" (optional), "count": int (optional),
//    "transactions": [...]} or a bare list (legacy).
//  * Every record needs a non-empty string id, an integral amount in
//    1..1,000,000,000,000, type "expense"|"income" and a parseable date.
//  * Duplicate ids, count mismatches, unsupported versions and empty replace
//    payloads are rejected.
//  * merge = upsert by id (imported wins). replace = ledger becomes exactly the
//    imported set. Both are idempotent.
//
// Synthetic fixtures only. No real SMS text or financial data.

TransactionModel _tx(String id, int amount,
        {TransactionType type = TransactionType.expense, String? merchant}) =>
    TransactionModel(
      id: id,
      amount: amount,
      type: type,
      merchant: merchant ?? 'Merchant $id',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 12, 9, 30),
      time: '09:30',
      originalSms: 'synthetic body $id',
      isExcluded: false,
      source: 'Manual',
    );

Map<String, dynamic> _rec(String id, Object? amount,
        {Object? type = 'expense', Object? date = '2026-10-12T09:30:00.000'}) =>
    {
      'id': id,
      'amount': amount,
      'type': type,
      'merchant': 'Merchant $id',
      'category': 'Food',
      'paymentMethod': 'UPI',
      'date': date,
      'time': '09:30',
      'originalSms': 'synthetic body $id',
      'isExcluded': false,
      'source': 'Manual',
    };

String _envelope(List<Object?> txs, {Object? version = '2.0', Object? count}) =>
    jsonEncode({
      if (version != null) 'version': version,
      if (count != null) 'count': count,
      'transactions': txs,
    });

/// ids, the total, storage keys, and decrypted logical records.
class _Ledger {
  final List<String> ids;
  final int total;
  final Map<String, String> raw;
  _Ledger(this.ids, this.total, this.raw);

  String get _key => '${ids.join('|')}#$total#${jsonEncode(raw)}';

  @override
  bool operator ==(Object other) => other is _Ledger && _key == other._key;

  @override
  int get hashCode => _key.hashCode;

  @override
  String toString() =>
      '_Ledger(ids=$ids, total=$total, persistedKeys=${raw.length})';
}

Future<_Ledger> _snapshot(TransactionCacheService cache) async {
  final all = await cache.loadAll();
  final prefs = await SharedPreferences.getInstance();
  final raw = <String, String>{
    for (final k in prefs.getKeys().toList()..sort())
      if ((k.startsWith('tx_') || k.startsWith('txe_')) &&
          prefs.get(k) is String)
        // Encrypted envelopes (records, index, migration journal) use a fresh
        // nonce per write by design, so only their presence is comparable.
        k: (k.startsWith('txe_') ||
                k == 'tx_cache_ids_v2' ||
                k == 'tx_money_migration_v2')
            ? '<encrypted>'
            : prefs.getString(k)!,
  };
  final ids = all.map((t) => t.id).toList()..sort();
  return _Ledger(ids, all.fold<int>(0, (s, t) => s + t.amountMinor), raw);
}

/// Seeds WITHOUT the hook, then arms it, so injected failures only ever hit
/// the import under test and never the fixture setup.
Future<TransactionCacheService> _freshService(
    {WriteHook? hook, List<TransactionModel>? seed}) async {
  final cache = TransactionCacheService();
  await cache.init();
  if (seed != null) await cache.putAll(seed);
  cache.writeHook = hook;
  return cache;
}

/// Injects a failure into the Nth persisted write/remove performed by an import.
class _FailAt {
  final int n;
  final bool persistent;
  int calls = 0;
  _FailAt(this.n, {this.persistent = false});

  Future<void> call(String op, String key) async {
    calls++;
    if (persistent ? calls >= n : calls == n) {
      throw StateError('injected failure at write #$calls');
    }
  }
}

class _Counter {
  int calls = 0;
  Future<void> call(String op, String key) async => calls++;
}

final _oldLedger = [_tx('keep-1', 111), _tx('keep-2', 222)];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('REPRODUCTION (audit R1)', () {
    test('replace:true with one malformed element keeps the old ledger',
        () async {
      final cache = await _freshService(seed: _oldLedger);
      final before = await _snapshot(cache);

      await expectLater(
        cache.importFromJsonString(_envelope([_rec('new-1', 500), 42]),
            replace: true),
        throwsA(isA<LedgerImportException>()),
      );

      final after = await _snapshot(cache);
      expect(after, before);
      expect(after.ids, ['keep-1', 'keep-2']);
      expect(after.total, 33300);
    });
  });

  group('validation happens before any mutation', () {
    final cases = <String, String>{
      'not JSON at all': '{nope',
      'JSON string instead of an envelope': '"hello"',
      'JSON number instead of an envelope': '12',
      'object without a transactions list': '{"version":"2.0"}',
      'transactions is not a list': '{"transactions":{"a":1}}',
      'unsupported version 3.0': _envelope([_rec('n1', 5)], version: '3.0'),
      'unsupported version 1': _envelope([_rec('n1', 5)], version: 1),
      'unsupported version text': _envelope([_rec('n1', 5)], version: 'beta'),
      'element is not an object': _envelope([_rec('n1', 5), 'oops']),
      'missing id': _envelope([
        {..._rec('x', 5)}..remove('id')
      ]),
      'empty id': _envelope([_rec('', 5)]),
      // `tx_` + id is the storage key, so these ids would overwrite the ledger
      // index / rejected-set / sync metadata themselves.
      'reserved id cache_ids (collides with the ledger index key)':
          _envelope([_rec('cache_ids', 5)]),
      'reserved id rejected_ids': _envelope([_rec('rejected_ids', 5)]),
      'reserved id cache_meta': _envelope([_rec('cache_meta', 5)]),
      'id longer than 200 characters': _envelope([_rec('x' * 201, 5)]),
      'non-string id': _envelope([
        {..._rec('x', 5), 'id': 7}
      ]),
      'missing amount': _envelope([
        {..._rec('n1', 5)}..remove('amount')
      ]),
      'string amount': _envelope([_rec('n1', '450')]),
      'fractional amount': _envelope([_rec('n1', 450.5)]),
      'negative amount': _envelope([_rec('n1', -5)]),
      'zero amount': _envelope([_rec('n1', 0)]),
      'null amount': _envelope([_rec('n1', null)]),
      'amount above the supported ceiling': _envelope([_rec('n1', 1e15)]),
      'invalid type': _envelope([_rec('n1', 5, type: 'refund')]),
      'missing type': _envelope([
        {..._rec('n1', 5)}..remove('type')
      ]),
      'missing date': _envelope([
        {..._rec('n1', 5)}..remove('date')
      ]),
      'unparseable date': _envelope([_rec('n1', 5, date: 'yesterday')]),
      'wrong field type (isExcluded)': _envelope([
        {..._rec('n1', 5), 'isExcluded': 'yes'}
      ]),
      'duplicate ids inside the file':
          _envelope([_rec('dup', 5), _rec('dup', 6)]),
      'count larger than the records (truncated file)':
          _envelope([_rec('n1', 5)], count: 3),
      'count smaller than the records': _envelope([_rec('n1', 5)], count: 0),
      'count is not an integer': _envelope([_rec('n1', 5)], count: 'one'),
    };

    for (final replace in [false, true]) {
      for (final entry in cases.entries) {
        test('${replace ? 'replace' : 'merge'}: rejects ${entry.key}',
            () async {
          final cache = await _freshService(seed: _oldLedger);
          final before = await _snapshot(cache);

          await expectLater(
            cache.importFromJsonString(entry.value, replace: replace),
            throwsA(isA<LedgerImportException>()),
          );

          expect(await _snapshot(cache), before,
              reason: 'ids, total and every persisted byte must be unchanged');
          // And the in-memory state a restart would rebuild is the same.
          final restarted = await _freshService();
          expect(await _snapshot(restarted), before);
        });
      }
    }

    test('replace: an empty payload would erase the ledger, so it is rejected',
        () async {
      final cache = await _freshService(seed: _oldLedger);
      final before = await _snapshot(cache);
      await expectLater(
        cache.importFromJsonString(_envelope([]), replace: true),
        throwsA(isA<LedgerImportException>()),
      );
      expect(await _snapshot(cache), before);
    });

    test('merge: an empty payload is a harmless no-op returning 0', () async {
      final cache = await _freshService(seed: _oldLedger);
      final before = await _snapshot(cache);
      expect(await cache.importFromJsonString(_envelope([])), 0);
      expect(await _snapshot(cache), before);
    });

    test('rejection messages never echo record contents', () async {
      final cache = await _freshService(seed: _oldLedger);
      final secret = 'SENSITIVE-MERCHANT-MARKER';
      final payload = _envelope([
        {..._rec('n1', -5), 'merchant': secret, 'originalSms': secret}
      ]);
      try {
        await cache.importFromJsonString(payload, replace: true);
        fail('expected a rejection');
      } on LedgerImportException catch (e) {
        expect(e.toString().contains(secret), isFalse);
        expect(e.message.contains(secret), isFalse);
        expect(e.code, isNotEmpty);
        expect(e.recordIndex, 0);
      }
    });
  });

  group('accepted inputs', () {
    test('bare list (legacy) is accepted', () async {
      final cache = await _freshService();
      final n = await cache
          .importFromJsonString(jsonEncode([_rec('a', 10), _rec('b', 20)]));
      expect(n, 2);
      expect((await _snapshot(cache)).total, 3000);
    });

    test('unversioned envelope (legacy) is accepted', () async {
      final cache = await _freshService();
      await cache
          .importFromJsonString(_envelope([_rec('a', 10)], version: null));
      expect((await _snapshot(cache)).ids, ['a']);
    });

    for (final v in <Object>[2, '2', '2.0', 2.0]) {
      test('version ${jsonEncode(v)} is accepted', () async {
        final cache = await _freshService();
        await cache
            .importFromJsonString(_envelope([_rec('a', 10)], version: v));
        expect((await _snapshot(cache)).ids, ['a']);
      });
    }

    test('an integral amount written as 450.0 is accepted as 450', () async {
      final cache = await _freshService();
      await cache.importFromJsonString(_envelope([_rec('a', 450.0)]));
      expect((await _snapshot(cache)).total, 45000);
    });

    test('a matching count field is accepted', () async {
      final cache = await _freshService();
      final n = await cache.importFromJsonString(
          _envelope([_rec('a', 1), _rec('b', 2)], count: 2));
      expect(n, 2);
    });
  });

  group('success semantics are explicit and predictable', () {
    test('merge upserts by id: imported wins, others are kept', () async {
      final cache = await _freshService(seed: _oldLedger);
      final n = await cache.importFromJsonString(
          _envelope([_rec('keep-2', 999), _rec('new-1', 5)]));
      expect(n, 2);

      final s = await _snapshot(cache);
      expect(s.ids, ['keep-1', 'keep-2', 'new-1']);
      expect(s.total, (111 + 999 + 5) * 100);
    });

    test('replace makes the ledger exactly the imported set', () async {
      final cache = await _freshService(seed: _oldLedger);
      await cache.importFromJsonString(
          _envelope([_rec('keep-2', 999), _rec('new-1', 5)]),
          replace: true);

      final s = await _snapshot(cache);
      expect(s.ids, ['keep-2', 'new-1']);
      expect(s.total, (999 + 5) * 100);
      expect(s.raw.keys.where((k) => k == 'tx_keep-1'), isEmpty,
          reason: 'the removed transaction must not linger as a payload');
    });

    test('retrying the same merge is idempotent (no duplicates)', () async {
      final cache = await _freshService(seed: _oldLedger);
      final file = _envelope([_rec('keep-2', 999), _rec('new-1', 5)]);
      await cache.importFromJsonString(file);
      final once = await _snapshot(cache);
      await cache.importFromJsonString(file);
      await cache.importFromJsonString(file);
      expect(await _snapshot(cache), once);
      expect(once.ids.toSet().length, once.ids.length);
    });

    test('retrying the same replace is idempotent', () async {
      final cache = await _freshService(seed: _oldLedger);
      final file = _envelope([_rec('keep-2', 999), _rec('new-1', 5)]);
      await cache.importFromJsonString(file, replace: true);
      final once = await _snapshot(cache);
      await cache.importFromJsonString(file, replace: true);
      expect(await _snapshot(cache), once);
    });

    test('a successful import survives a restart', () async {
      final cache = await _freshService(seed: _oldLedger);
      await cache.importFromJsonString(_envelope([_rec('new-1', 5)]),
          replace: true);
      final live = await _snapshot(cache);
      expect(await _snapshot(await _freshService()), live);
    });

    test('export then replace-import round-trips exactly', () async {
      final source = await _freshService(seed: [
        _tx('a', 450),
        _tx('b', 1200, type: TransactionType.income),
      ]);
      final exported = await source.exportToJsonString();
      final before = await _snapshot(source);

      SharedPreferences.setMockInitialValues({});
      final fresh = await _freshService(seed: [_tx('stale', 1)]);
      await fresh.importFromJsonString(exported, replace: true);

      final after = await _snapshot(fresh);
      expect(after.ids, before.ids);
      expect(after.total, before.total);
      final types =
          (await fresh.loadAll()).map((t) => '${t.id}:${t.type.name}');
      expect(types.toSet(), {'a:expense', 'b:income'});
    });
  });

  group('interrupted writes (failure after every single write)', () {
    for (final replace in [false, true]) {
      test(
          '${replace ? 'replace' : 'merge'}: every interruption point is '
          'all-or-nothing', () async {
        final file = _envelope([
          _rec('keep-2', 999), // overlaps an existing id
          _rec('new-1', 5),
          _rec('new-2', 7),
        ]);

        // Dry run on an identical store to learn the expected end state and
        // how many persisted writes an import performs.
        SharedPreferences.setMockInitialValues({});
        final counter = _Counter();
        final dry = await _freshService(hook: counter.call, seed: _oldLedger);
        counter.calls = 0;
        await dry.importFromJsonString(file, replace: replace);
        final expectedAfter = await _snapshot(dry);
        final writes = counter.calls;
        expect(writes, greaterThan(3));

        SharedPreferences.setMockInitialValues({});
        final seeded = await _freshService(seed: _oldLedger);
        final before = await _snapshot(seeded);

        for (var n = 1; n <= writes; n++) {
          SharedPreferences.setMockInitialValues({});
          final fail = _FailAt(n);
          final cache = await _freshService(hook: fail.call, seed: _oldLedger);
          fail.calls = 0;

          var threw = false;
          try {
            await cache.importFromJsonString(file, replace: replace);
          } catch (_) {
            threw = true;
          }

          final after = await _snapshot(cache);
          final restarted = await _snapshot(await _freshService());
          // Visible state (ids + total) must agree between memory and disk.
          // Raw bytes are compared only for the rolled-back case below: after
          // a committed import, an unreferenced payload awaiting cleanup is
          // invisible and is removed by the next start.
          expect(restarted.ids, after.ids,
              reason: 'write #$n: memory and storage must agree');
          expect(restarted.total, after.total,
              reason: 'write #$n: memory and storage must agree');
          if (threw) {
            expect(after, before,
                reason: 'write #$n failed, so nothing may have changed');
          } else {
            // Only the post-commit cleanup of replaced payloads may fail
            // quietly; the visible ledger must already be the final one.
            expect(after.ids, expectedAfter.ids, reason: 'write #$n');
            expect(after.total, expectedAfter.total, reason: 'write #$n');
          }
        }
      });
    }
  });

  group('process dies mid-import (every later write fails too)', () {
    for (final replace in [false, true]) {
      test(
          '${replace ? 'replace' : 'merge'}: the ledger is never a partial '
          'import, and a retry completes it exactly once', () async {
        final file = _envelope([
          _rec('keep-2', 999),
          _rec('new-1', 5),
          _rec('new-2', 7),
        ]);

        SharedPreferences.setMockInitialValues({});
        final counter = _Counter();
        final dry = await _freshService(hook: counter.call, seed: _oldLedger);
        counter.calls = 0;
        await dry.importFromJsonString(file, replace: replace);
        final finalState = await _snapshot(dry);
        final writes = counter.calls;

        SharedPreferences.setMockInitialValues({});
        final seeded = await _freshService(seed: _oldLedger);
        final oldIds = (await _snapshot(seeded)).ids;

        for (var n = 1; n <= writes; n++) {
          SharedPreferences.setMockInitialValues({});
          final dead = _FailAt(n, persistent: true);
          final cache = await _freshService(hook: dead.call, seed: _oldLedger);
          dead.calls = 0;
          try {
            await cache.importFromJsonString(file, replace: replace);
          } catch (_) {}

          // "Restart the app": a brand-new service over whatever is on disk.
          final restarted = await _freshService();
          final visible = await _snapshot(restarted);
          expect(
            visible.ids.toString() == oldIds.toString() ||
                visible.ids.toString() == finalState.ids.toString(),
            isTrue,
            reason: 'write #$n: visible ids ${visible.ids} must be exactly the '
                'old ledger $oldIds or the finished one ${finalState.ids}',
          );
          expect(visible.ids.toSet().length, visible.ids.length);

          // Retry with a healthy process converges to the finished ledger.
          await restarted.importFromJsonString(file, replace: replace);
          final retried = await _snapshot(restarted);
          expect(retried.ids, finalState.ids, reason: 'write #$n retry ids');
          expect(retried.total, finalState.total, reason: 'write #$n retry');
        }
      });
    }
  });
}
