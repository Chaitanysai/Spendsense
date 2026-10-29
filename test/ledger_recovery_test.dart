import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/ledger_encryption_service.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

/// Startup recovery for the encrypted ledger.
///
/// On 2.0.10 a phone could land in a state where every launch failed to read
/// the ledger, the dashboard said "Couldn't load your ledger", and only a full
/// resync brought the rows back. The cause was a bookkeeping mismatch being
/// treated as unrepairable while the store reported itself as initialized, so
/// the retry the error card offers did nothing.
///
/// These tests pin the two halves of the fix: a failed start can be retried,
/// and a repairable mismatch is repaired instead of failing closed forever.

TransactionModel _tx(String id, int amountMinor) => TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: TransactionType.expense,
      merchant: 'Merchant',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 1),
      time: '10:00',
      originalSms: '',
      isExcluded: false,
    );

Map<String, dynamic> _legacy(String id, int amount) => {
      'id': id,
      'amount': amount,
      'type': 'expense',
      'merchant': 'Legacy merchant',
      'category': 'Food',
      'paymentMethod': 'UPI',
      'date': '2026-10-23T10:00:00.000',
      'time': '10:00',
      'originalSms': '',
      'isExcluded': false,
    };

/// An encrypted ledger exactly as a completed activation leaves it.
Future<Map<String, String>> _encryptedLedger(
  List<TransactionModel> records,
) async {
  final encryption = LedgerEncryptionService();
  await encryption.createKeyIfMissing();
  return {
    for (final tx in records)
      'txe_${tx.id}': await encryption.encryptText(
        jsonEncode(tx.toJson()),
        recordId: tx.id,
      ),
    'tx_cache_ids_v2': await encryption.encryptText(
      jsonEncode([for (final tx in records) tx.id]),
      recordId: '__ledger_index__',
    ),
  };
}

String _flip(String base64) =>
    (base64.startsWith('A') ? 'B' : 'A') + base64.substring(1);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a failed start is retryable', () {
    test('the retry the error card offers actually reloads the ledger',
        () async {
      SharedPreferences.setMockInitialValues({
        'tx_cache_ids': jsonEncode(['retry-1']),
        'tx_retry-1': jsonEncode(_legacy('retry-1', 239)),
      });

      var failNext = true;
      final cache = TransactionCacheService(writeHook: (op, key) async {
        if (failNext && op == 'set' && key == 'tx_cache_ids_v2') {
          failNext = false;
          throw StateError('write interrupted');
        }
      });

      await expectLater(
        cache.init(),
        throwsA(isA<LedgerMigrationException>()),
      );

      // The single, cached service is what the provider retries with. It used
      // to return immediately because it had already flagged itself ready.
      await cache.init();
      final records = await cache.loadAll();

      expect(records.single.id, 'retry-1');
      expect(records.single.amountMinor, 23900);
    });
  });

  group('bookkeeping mismatches are repaired, not fatal', () {
    test('an index entry whose record is gone is dropped from the index',
        () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final keep = _tx('keep', 10000);
      SharedPreferences.setMockInitialValues({
        ...await _encryptedLedger([keep]),
        // The saved index also lists a record whose payload never landed.
        'tx_cache_ids_v2': await encryption.encryptText(
          jsonEncode(['keep', 'gone']),
          recordId: '__ledger_index__',
        ),
      });

      final cache = TransactionCacheService();
      await cache.init();
      expect((await cache.loadAll()).single.id, 'keep');

      // The repair is persisted: the next start does not see the ghost again.
      final restarted = TransactionCacheService();
      await restarted.init();
      expect((await restarted.loadAll()).single.id, 'keep');
    });

    test('a record whose payload is gone is dropped from the index', () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final keep = _tx('keep', 10000);
      final seed = await _encryptedLedger([keep]);
      // Only the payload for 'lost' is removed; the index still lists it.
      seed['tx_cache_ids_v2'] = await encryption.encryptText(
        jsonEncode(['keep', 'lost']),
        recordId: '__ledger_index__',
      );
      SharedPreferences.setMockInitialValues(seed);

      final cache = TransactionCacheService();
      await cache.init();
      expect((await cache.loadAll()).single.id, 'keep');
    });

    test('a corrupt staged payload is rewritten from its plaintext source',
        () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final tx = _tx('poisoned', 10000);
      final envelope = jsonDecode(await encryption.encryptText(
        jsonEncode(tx.toJson()),
        recordId: tx.id,
      )) as Map<String, dynamic>;
      envelope['ciphertext'] = _flip(envelope['ciphertext'] as String);

      SharedPreferences.setMockInitialValues({
        'tx_cache_ids': jsonEncode(['poisoned']),
        'tx_poisoned': jsonEncode(_legacy('poisoned', 239)),
        'txe_poisoned': jsonEncode(envelope),
      });
      final prefs = await SharedPreferences.getInstance();

      final cache = TransactionCacheService();
      await cache.init();
      final records = await cache.loadAll();

      // The plaintext source is the only trusted copy of a record whose
      // encrypted payload cannot be authenticated, so it is rewritten from
      // there instead of the record being lost or the start failing.
      expect(records.single.id, 'poisoned');
      expect(records.single.amountMinor, 23900);
      expect(prefs.getString('tx_poisoned'), isNull,
          reason: 'the source is retired once the restore verifies');
    });

    test('a corrupt skipped-message list does not block startup', () async {
      final seed = await _encryptedLedger([_tx('keep', 10000)]);
      SharedPreferences.setMockInitialValues({
        ...seed,
        'tx_rejected_ids': '{not a list',
      });
      final prefs = await SharedPreferences.getInstance();

      final cache = TransactionCacheService();
      await cache.init();

      expect((await cache.loadAll()).single.id, 'keep');
      expect(prefs.getString('tx_rejected_ids'), isNull,
          reason: 'the damaged list is reset, not rewritten as garbage');
    });

    test('a corrupt last-sync stamp does not block startup', () async {
      final seed = await _encryptedLedger([_tx('keep', 10000)]);
      SharedPreferences.setMockInitialValues({
        ...seed,
        'tx_cache_meta': '{not json',
      });

      final cache = TransactionCacheService();
      await cache.init();

      expect((await cache.loadAll()).single.id, 'keep');
      expect(cache.lastSyncTime, isNull);
    });

    test('a legacy source with no remaining record is skipped', () async {
      // `tx_cache_ids` lists a source that is no longer on disk. Its bytes are
      // gone, so nothing can be migrated — but the ledger must still open.
      SharedPreferences.setMockInitialValues({
        'tx_cache_ids': jsonEncode(['ghost']),
      });

      final cache = TransactionCacheService();
      await cache.init();
      expect(await cache.loadAll(), isEmpty);
    });
  });

  group('startup does no unnecessary work', () {
    test('a clean start writes nothing to the ledger', () async {
      SharedPreferences.setMockInitialValues(
        await _encryptedLedger([_tx('keep', 10000)]),
      );
      // The first start gives every record its sync identity.
      await TransactionCacheService().init();

      final writes = <String>[];
      final cache = TransactionCacheService(
        writeHook: (op, key) async => writes.add('$op $key'),
      );
      await cache.init();
      await cache.loadAll();

      // Re-encrypting the whole ledger on every launch is what made a cold
      // start feel like a resync.
      expect(writes, isEmpty);
    });
  });
}
