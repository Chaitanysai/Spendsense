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

  group('journal bookkeeping on a healthy activation', () {
    test('a plain put stages the journal once and leaves no committed marker',
        () async {
      final writes = <String>[];
      final cache = TransactionCacheService(
        writeHook: (op, key) async => writes.add('$op $key'),
      );
      await cache.init();
      writes.clear();
      await cache.put(_tx('journal-count', 5000));

      final journalSets = writes
          .where((entry) => entry.startsWith('set txj_import_journal'))
          .length;
      // The pending journal that makes the write recoverable. A second
      // 'committed' copy of the journal used to be written and immediately
      // deleted for activations that remove nothing — pure overhead.
      expect(journalSets, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('txj_import_journal'), isNull,
          reason: 'a completed activation leaves no journal behind');
    });

    test(
        'an already-applied pending non-replace activation replays identically, repeatedly',
        () async {
      // Simulate a crash in the window after the index commit but before the
      // journal was dropped: the pending journal describes work that is
      // already fully visible. Replay must converge to the identical state —
      // and stay there across repeated starts.
      final records = [_tx('replay-a', 1000), _tx('replay-b', 2000)];
      final cache = TransactionCacheService();
      await cache.init();
      await cache.putAll(records);

      final prefs = await SharedPreferences.getInstance();
      final encryption = LedgerEncryptionService();
      prefs.setString(
        'txj_import_journal',
        jsonEncode({
          'schemaVersion': 2,
          'ciphertext': await encryption.encryptText(jsonEncode({
            'v': 2,
            'phase': 'pending',
            'replace': false,
            'records': [for (final tx in records) tx.toJson()],
            'remove': <String>[],
          })),
        }),
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        final restarted = TransactionCacheService();
        await restarted.init();
        final loaded = await restarted.loadAll();
        expect(loaded.map((t) => t.id).toSet(), {'replay-a', 'replay-b'},
            reason: 'replay must not add, drop or duplicate rows');
        expect((await SharedPreferences.getInstance())
                .getString('txj_import_journal'),
            isNull,
            reason: 'the replayed journal must be consumed');
      }
    });

    Future<void> seedDeleteJournal(
      List<String> keepIds, {
      required List<String> removeIds,
      List<String>? targetIds,
    }) async {
      final cache = TransactionCacheService();
      await cache.init();
      await cache
          .putAll([for (final id in keepIds.followedBy(removeIds)) _tx(id, 100)]);
      final prefs = await SharedPreferences.getInstance();
      final encryption = LedgerEncryptionService();
      final journal = <String, dynamic>{
        'v': 2,
        'phase': 'delete_pending',
        'remove': removeIds,
        if (targetIds != null) 'targetIds': targetIds,
      };
      prefs.setString(
        'txj_import_journal',
        jsonEncode({
          'schemaVersion': 2,
          'ciphertext': await encryption.encryptText(jsonEncode(journal)),
        }),
      );
    }

    test('recovers a legacy delete_pending journal that carries targetIds',
        () async {
      // Compatibility with journals written by older app versions: the
      // recovery result must not depend on which journal shape arrives.
      await seedDeleteJournal(['del-keep-a', 'del-keep-b'],
          removeIds: ['del-gone'], targetIds: ['del-keep-a', 'del-keep-b']);

      final restarted = TransactionCacheService();
      await restarted.init();
      expect((await restarted.loadAll()).map((t) => t.id).toSet(),
          {'del-keep-a', 'del-keep-b'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('txe_del-gone'), isNull,
          reason: 'a recovered delete removes the payload');
      expect(prefs.getString('txj_import_journal'), isNull);
    });

    test('recovers a delete_pending journal without targetIds', () async {
      // Journals written from now on carry only the removed ids; recovery
      // computes the surviving index from the committed index minus 'remove'.
      await seedDeleteJournal(['del-keep-a', 'del-keep-b'],
          removeIds: ['del-gone']);

      final restarted = TransactionCacheService();
      await restarted.init();
      expect((await restarted.loadAll()).map((t) => t.id).toSet(),
          {'del-keep-a', 'del-keep-b'});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('txe_del-gone'), isNull);
      expect(prefs.getString('txj_import_journal'), isNull);
    });

    test('recovers a partial delete that names an id the ledger never had',
        () async {
      await seedDeleteJournal(['del-keep-a', 'del-keep-b'],
          removeIds: ['del-gone', 'never-existed']);

      final restarted = TransactionCacheService();
      await restarted.init();
      expect((await restarted.loadAll()).map((t) => t.id).toSet(),
          {'del-keep-a', 'del-keep-b'},
          reason: 'an unknown id in the removal list is ignored, not fatal');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('txj_import_journal'), isNull);
    });

    test('a corrupt payload fails loadAll with the same error shape it had '
        'when decryption ran on the main isolate', () async {
      // The sync-metadata migration is marked done so init() does not touch
      // the records themselves — the corruption is first met inside
      // loadAll's background isolate, and the exception must cross the
      // isolate boundary unchanged.
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final good = _tx('iso-good', 1000);
      final corrupt = _tx('iso-corrupt', 2000);
      final envelopeJson = jsonDecode(await encryption.encryptText(
        jsonEncode(corrupt.toJson()),
        recordId: 'iso-corrupt',
      )) as Map<String, dynamic>;
      // Flip one character inside the ciphertext: authentication must fail.
      final cipher = envelopeJson['ciphertext'] as String;
      envelopeJson['ciphertext'] = (cipher.startsWith('A') ? 'B' : 'A') +
          cipher.substring(1);
      SharedPreferences.setMockInitialValues({
        ...await _encryptedLedger([good, corrupt]),
        'txe_iso-corrupt': jsonEncode(envelopeJson),
        'tx_sync_metadata_v1': jsonEncode({'done': true, 'migrated': 0}),
      });

      final cache = TransactionCacheService();
      await cache.init();

      await expectLater(
        cache.loadAll(),
        throwsA(isA<LedgerMigrationException>().having(
          (e) => e.code,
          'code',
          'decrypt_failed',
        )),
      );
    });
  });

  group('a lost id index does not read as an empty ledger', () {
    test(
        'payloads alone are recovered and the rebuilt index survives a restart',
        () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final records = [_tx('a', 25000), _tx('b', 12000)];
      // The field state behind "restart shows zero": the payloads landed, the
      // index write did not. Before the fix, every payload was quarantined and
      // the dashboard showed an empty ledger with no error card.
      SharedPreferences.setMockInitialValues({
        for (final tx in records)
          'txe_${tx.id}': await encryption.encryptText(
            jsonEncode(tx.toJson()),
            recordId: tx.id,
          ),
      });

      final cache = TransactionCacheService();
      await cache.init();

      final loaded = await cache.loadAll();
      expect(loaded.map((t) => t.id).toSet(), {'a', 'b'});
      expect(cache.cachedIds.toSet(), {'a', 'b'});

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tx_cache_ids_v2'), isNotNull,
          reason: 'without a rewritten index the next launch repeats recovery');
      expect(
        prefs.getKeys().where((key) => key.startsWith('txq_')),
        isEmpty,
        reason: 'an authenticating payload is a record, not debris',
      );

      // The restart the user actually performs.
      final restarted = TransactionCacheService();
      await restarted.init();
      expect((await restarted.loadAll()).map((t) => t.id).toSet(), {'a', 'b'});
    });

    test('an index that exists but is empty is a committed empty ledger',
        () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final orphan = _tx('orphan', 9900);
      SharedPreferences.setMockInitialValues({
        'txe_orphan': await encryption.encryptText(
          jsonEncode(orphan.toJson()),
          recordId: 'orphan',
        ),
        'tx_cache_ids_v2': await encryption.encryptText(
          jsonEncode(const <String>[]),
          recordId: '__ledger_index__',
        ),
      });

      final cache = TransactionCacheService();
      await cache.init();

      // An empty index is the ledger saying "show nothing", not a lost index;
      // recovery must not resurrect a payload its own index does not list.
      expect(await cache.loadAll(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where(
            (key) => key.startsWith('txq_') && key.endsWith('_txe_orphan')),
        isNotEmpty,
      );
    });

    test('an unauthenticated payload is quarantined, the rest recovered',
        () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final badPayload = await encryption.encryptText(
        jsonEncode(_tx('bad', 7000).toJson()),
        recordId: 'bad',
      );
      SharedPreferences.setMockInitialValues({
        'txe_good': await encryption.encryptText(
          jsonEncode(_tx('good', 5000).toJson()),
          recordId: 'good',
        ),
        'txe_bad': _flip(badPayload),
      });

      final cache = TransactionCacheService();
      await cache.init();

      expect((await cache.loadAll()).single.id, 'good');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('txe_bad'), isNull,
          reason: 'bytes the key cannot authenticate are moved aside');
      expect(
          prefs.getKeys().where((key) => key.startsWith('txq_')), isNotEmpty);
      expect(prefs.getString('tx_cache_ids_v2'), isNotNull);
    });
  });
}
