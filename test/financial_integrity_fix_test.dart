import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/cache_service.dart';
import 'package:spendsense/services/database_service.dart';
import 'package:spendsense/services/ledger_encryption_service.dart';
import 'package:spendsense/services/recurring_detector_service.dart';
import 'package:spendsense/services/transaction_cache_service.dart';
import 'package:spendsense/services/ai_query_service.dart';

TransactionModel _tx(String id, int amountMinor, DateTime date) =>
    TransactionModel(
      id: id,
      amountMinor: amountMinor,
      type: TransactionType.expense,
      merchant: 'Merchant',
      category: 'Food',
      paymentMethod: 'UPI',
      date: date,
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

class _FakeKeyStore implements LedgerKeyStore {
  String? value;
  bool throwOnRead = false;

  _FakeKeyStore({this.value});

  @override
  Future<String?> read(String keyName) async {
    if (throwOnRead) throw StateError('key read failed');
    return value;
  }

  @override
  Future<void> write(String keyName, String next) async {
    value = next;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('local AI formats integer paise averages as INR', () {
    final now = DateTime.now();
    final response = AIQueryService().tryAnswer(
      'What is my average spending per day?',
      [_tx('a', 12500, now)],
    );

    expect(response, contains('₹125'));
    expect(response, isNot(contains('₹12500')));

    final decimalResponse = AIQueryService().tryAnswer(
      'What is my average spending per day?',
      [_tx('b', 23950, now)],
    );
    expect(decimalResponse, contains('₹239.50'));
  });

  test('recurring averages round half paise upward', () {
    final service = RecurringDetectorService();
    final recurring = service.detectRecurring([
      _tx('a', 100, DateTime(2026, 1, 1)),
      _tx('b', 101, DateTime(2026, 2, 1)),
    ]);

    expect(recurring.single.averageAmountMinor, 101);
  });

  test('provider aggregates keep integer paise', () {
    final provider = TransactionProvider();
    provider.debugSeed([
      _tx('a', 12500, DateTime(2026, 10, 1)),
      _tx('b', 23950, DateTime(2026, 10, 2)),
    ]);

    expect(provider.totalTrackedExpenses, 36450);
    expect(provider.availableBalance, -36450);
  });

  test('metadata tampering fails authenticated decryption', () async {
    final encryption = LedgerEncryptionService();
    await encryption.createKeyIfMissing();
    final encoded = await encryption.encryptText('payload', recordId: 'r1');
    final envelope = jsonDecode(encoded) as Map<String, dynamic>;
    envelope['recordId'] = 'r2';

    expect(
      encryption.decryptText(
        jsonEncode(envelope),
        expectedRecordId: 'r1',
      ),
      throwsA(isA<LedgerKeyUnavailableException>()),
    );
  });

  test('key failures preserve encrypted records and never empty the ledger',
      () async {
    final validStore = _FakeKeyStore(
      value: base64UrlEncode(List<int>.filled(32, 0x55)),
    );
    final writer = LedgerEncryptionService(keyStore: validStore);
    final tx = _tx('key-protected', 23950, DateTime(2026, 10, 1));
    final payload = await writer.encryptText(
      jsonEncode(tx.toJson()),
      recordId: tx.id,
    );
    final index = await writer.encryptText(
      jsonEncode([tx.id]),
      recordId: '__ledger_index__',
    );

    Future<void> expectFailure(_FakeKeyStore store) async {
      SharedPreferences.setMockInitialValues({
        'tx_cache_ids_v2': index,
        'txe_key-protected': payload,
      });
      // Must await: a bare expect() on a Future only checks that a matcher
      // object was created, so the fail-closed assertion never ran.
      await expectLater(
        TransactionCacheService(
          encryption: LedgerEncryptionService(keyStore: store),
        ).init(),
        throwsA(isA<LedgerKeyUnavailableException>()),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('txe_key-protected'), payload);
      expect(prefs.getString('tx_cache_ids_v2'), index);
    }

    await expectFailure(_FakeKeyStore());
    await expectFailure(_FakeKeyStore()..throwOnRead = true);
  });

  test('an unindexed orphan record is set aside, not resurrected', () async {
    final encryption = LedgerEncryptionService();
    await encryption.createKeyIfMissing();
    final tx = _tx('orphan', 12500, DateTime(2026, 10, 1));
    final payload = await encryption.encryptText(
      jsonEncode(tx.toJson()),
      recordId: tx.id,
    );
    final index = await encryption.encryptText(
      jsonEncode(<String>[]),
      recordId: '__ledger_index__',
    );

    SharedPreferences.setMockInitialValues({
      'tx_cache_ids_v2': index,
      'txe_orphan': payload,
    });

    // The index is the only thing that makes a record visible. A payload
    // outside it is either a write whose index commit never landed or the
    // leftover of a delete/replace that was cut short, and the two look
    // identical on disk. Adopting it would bring deleted rows back, so it is
    // moved to a quarantine key: kept for diagnosis, never loaded.
    final cache = TransactionCacheService();
    await cache.init();
    final records = await cache.loadAll();

    expect(records, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('txe_orphan'), isNull);
    expect(
      prefs.getKeys().where(
          (k) => k.startsWith('txq_') && k.endsWith('_txe_orphan')),
      isNotEmpty,
    );
  });

  test('an unauthenticatable orphan is quarantined, not loaded', () async {
    final encryption = LedgerEncryptionService();
    await encryption.createKeyIfMissing();
    final tx = _tx('poisoned', 12500, DateTime(2026, 10, 1));
    final payload = jsonDecode(await encryption.encryptText(
      jsonEncode(tx.toJson()),
      recordId: tx.id,
    )) as Map<String, dynamic>;
    final ciphertext = payload['ciphertext'] as String;
    payload['ciphertext'] =
        (ciphertext.startsWith('A') ? 'B' : 'A') + ciphertext.substring(1);
    final index = await encryption.encryptText(
      jsonEncode(<String>[]),
      recordId: '__ledger_index__',
    );

    SharedPreferences.setMockInitialValues({
      'tx_cache_ids_v2': index,
      'txe_poisoned': jsonEncode(payload),
    });

    final cache = TransactionCacheService();
    await cache.init();
    expect(await cache.loadAll(), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('txe_poisoned'), isNull,
        reason: 'an unauthenticated record cannot enter the ledger');
    expect(
      prefs.getKeys().where(
          (k) => k.startsWith('txq_') && k.endsWith('_txe_poisoned')),
      isNotEmpty,
      reason: 'its bytes are kept aside for diagnosis, not deleted',
    );
  });

  test('malformed legacy records are set aside, never substituted', () async {
    SharedPreferences.setMockInitialValues({
      'tx_cache_ids': jsonEncode(['legacy']),
      'tx_legacy': jsonEncode({
        'amount': 125,
        'type': 'expense',
        'merchant': 'Shop',
        'category': 'Food',
        'paymentMethod': 'UPI',
        'date': '2026-10-23T10:00:00.000',
        'time': '10:00',
        'originalSms': '',
        'isExcluded': false,
      }),
    });

    // An undecodable source cannot become a record, and it must not wedge the
    // ledger either: it is moved out of the live namespace.
    final cache = TransactionCacheService();
    await cache.init();
    expect(await cache.loadAll(), isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tx_legacy'), isNull);
    expect(
      prefs.getKeys().where((k) => k.startsWith('txq_') && k.endsWith('_tx_legacy')),
      isNotEmpty,
    );
  });

  test('journaled put recovers after payload-stage failure', () async {
    final cache = TransactionCacheService();
    await cache.init();
    cache.writeHook = (op, key) async {
      if (key.startsWith('txe_')) {
        throw StateError('payload failure');
      }
    };

    await expectLater(
      cache.put(_tx('recover', 12500, DateTime(2026, 10, 1))),
      throwsA(isA<LedgerImportException>()),
    );

    final restarted = TransactionCacheService();
    await restarted.init();
    expect((await restarted.loadAll()).single.amountMinor, 12500);
  });

  test('journaled deletion survives a failed payload removal', () async {
    final cache = TransactionCacheService();
    await cache.init();
    await cache.put(_tx('delete', 12500, DateTime(2026, 10, 1)));
    cache.writeHook = (op, key) async {
      if (op == 'remove' && key.startsWith('txe_')) {
        throw StateError('delete failure');
      }
    };

    await expectLater(
      cache.remove('delete'),
      throwsA(isA<LedgerMigrationException>()),
    );

    final restarted = TransactionCacheService();
    await restarted.init();
    expect(await restarted.loadAll(), isEmpty);
  });

  test('duplicate plaintext indexes fail before activation', () async {
    SharedPreferences.setMockInitialValues({
      'tx_cache_ids_v2': jsonEncode(['same', 'same']),
    });

    expect(
      TransactionCacheService().init(),
      throwsA(isA<LedgerMigrationException>()),
    );
  });

  test('explicit legacy rupees migrate exactly once', () async {
    SharedPreferences.setMockInitialValues({
      'cached_transactions_v1': jsonEncode([
        {
          'id': 'legacy-cache',
          'amount': 239,
          'type': 'expense',
          'merchant': 'Shop',
          'category': 'Food',
          'paymentMethod': 'UPI',
          'date': '2026-10-23T10:00:00.000',
          'time': '10:00',
          'originalSms': '',
          'isExcluded': false,
        },
      ]),
    });

    final cache = CacheService();
    final migrated = await cache.migrateLegacyWholeRupeeCache();
    expect(migrated.single.amountMinor, 23900);
    expect((await cache.loadTransactions()).single.amountMinor, 23900);
  });

  test('unmarked legacy cache records are rejected', () async {
    SharedPreferences.setMockInitialValues({
      'cached_transactions_v1': jsonEncode([
        {'id': 'ambiguous', 'amount': 23950},
      ]),
    });

    expect(
      CacheService().loadTransactions(),
      throwsA(isA<LegacyCacheFormatException>()),
    );
  });

  test('explicit paise cache records retain their exact amount', () async {
    final cache = CacheService();
    await cache.saveTransactions([
      _tx('paise-cache', 23950, DateTime(2026, 10, 1)),
    ]);

    expect((await cache.loadTransactions()).single.amountMinor, 23950);
  });

  test('malformed legacy cache reads do not become empty success', () async {
    SharedPreferences.setMockInitialValues({
      'cached_transactions_v1': '{bad json',
    });

    expect(
      CacheService().loadTransactions(),
      throwsA(isA<LegacyCacheFormatException>()),
    );
  });

  test('SQLite rows require explicit paise metadata', () {
    final row = <String, dynamic>{
      'schemaVersion': 2,
      'currency': 'INR',
      'amountUnit': 'paise',
      'amountMinor': 23950,
      'id': 'sqlite-1',
      'type': 'expense',
      'merchant': 'Shop',
      'category': 'Food',
      'paymentMethod': 'UPI',
      'date': '2026-10-23T10:00:00.000',
      'time': '10:00',
      'originalSms': '',
      'isExcluded': 0,
    };

    expect(DatabaseService.decodeRowForTesting(row).amountMinor, 23950);
    expect(
      () =>
          DatabaseService.decodeRowForTesting({...row, 'amountUnit': 'rupees'}),
      throwsA(isA<LegacyDatabaseFormatException>()),
    );
  });

  test('reconciles a legacy record added after v2 activation', () async {
    final cache = TransactionCacheService();
    await cache.init();
    await cache.put(_tx('v2', 10000, DateTime(2026, 10, 1)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tx_cache_ids', jsonEncode(['legacy-after-v2']));
    await prefs.setString(
        'tx_legacy-after-v2', jsonEncode(_legacy('legacy-after-v2', 239)));

    final restarted = TransactionCacheService();
    await restarted.init();
    final records = await restarted.loadAll();
    expect(records.map((tx) => tx.id).toSet(), {'v2', 'legacy-after-v2'});
    expect(records.singleWhere((tx) => tx.id == 'legacy-after-v2').amountMinor,
        23900);
    expect(prefs.getString('tx_money_migration_v2'), isNull);
  });

  test('a stale legacy source never overrides or blocks its encrypted record',
      () async {
    final cache = TransactionCacheService();
    await cache.init();
    await cache.put(_tx('same-id', 10000, DateTime(2026, 10, 1)));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tx_cache_ids', jsonEncode(['same-id']));
    await prefs.setString('tx_same-id', jsonEncode(_legacy('same-id', 239)));

    // The encrypted record is authoritative. Comparing the two on every start
    // made this conflict permanent: once the sync stamped `updatedAtMs` the
    // comparison could never match, so init failed on every launch.
    final restarted = TransactionCacheService();
    await restarted.init();
    final records = await restarted.loadAll();

    expect(records.single.amountMinor, 10000);
    expect(prefs.getString('tx_same-id'), isNull,
        reason: 'the superseded plaintext source is retired');
  });

  test('legacy reconciliation resumes after index interruption', () async {
    final seed = TransactionCacheService();
    await seed.init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tx_cache_ids', jsonEncode(['resume-legacy']));
    await prefs.setString(
        'tx_resume-legacy', jsonEncode(_legacy('resume-legacy', 239)));

    final interrupted = TransactionCacheService(writeHook: (op, key) async {
      if (op == 'set' && key == 'tx_cache_ids_v2') {
        throw StateError('index interruption');
      }
    });
    await expectLater(interrupted.init(), throwsA(isA<StateError>()));
    expect(prefs.getString('tx_money_migration_v2'),
        isNot(contains('resume-legacy')));

    final restarted = TransactionCacheService();
    await restarted.init();
    expect((await restarted.loadAll()).single.amountMinor, 23900);
  });

  test('malformed migration journal fails closed', () async {
    final seed = TransactionCacheService();
    await seed.init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tx_money_migration_v2', '{bad json');

    expect(
      TransactionCacheService().init(),
      throwsA(isA<LedgerMigrationException>()),
    );
  });

  test('tampered migration journal fails closed', () async {
    final seed = TransactionCacheService();
    await seed.init();
    final encryption = LedgerEncryptionService();
    final encoded = await encryption.encryptText(
      jsonEncode({
        'journalVersion': 3,
        'kind': 'legacy_reconciliation',
        'state': 'copying',
        'legacyIds': ['journal-id'],
        'convertedIds': <String>[],
      }),
      recordId: '__migration_progress__',
    );
    final envelope = jsonDecode(encoded) as Map<String, dynamic>;
    envelope['ciphertext'] = 'tampered';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tx_money_migration_v2', jsonEncode(envelope));

    expect(
      TransactionCacheService().init(),
      throwsA(isA<LedgerKeyUnavailableException>()),
    );
  });
}
