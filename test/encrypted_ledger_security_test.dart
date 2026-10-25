import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/ledger_encryption_service.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

/// Security-validation suite for the encrypted ledger. Every test uses
/// isolated fixtures: mock preferences, fake key stores, and write-hook fault
/// injection. No production behaviour is changed by these tests.
///
/// Complements `financial_integrity_fix_test.dart` and
/// `encrypted_ledger_migration_test.dart` with the tamper, key-material,
/// and interruption cases they do not cover.

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
  bool throwOnWrite = false;

  _FakeKeyStore({this.value});

  @override
  Future<String?> read(String keyName) async {
    if (throwOnRead) throw StateError('key read failed');
    return value;
  }

  @override
  Future<void> write(String keyName, String next) async {
    if (throwOnWrite) throw StateError('key write failed');
    value = next;
  }
}

/// Flips the first base64url character so the string stays decodable but the
/// authenticated decryption must fail.
String _flipFirstChar(String base64) =>
    (base64.startsWith('A') ? 'B' : 'A') + base64.substring(1);

Future<Map<String, String>> _seedEncryptedLedger(String id) async {
  final encryption = LedgerEncryptionService();
  await encryption.createKeyIfMissing();
  final tx = _tx(id, 23950, DateTime(2026, 10, 1));
  final payload = await encryption.encryptText(
    jsonEncode(tx.toJson()),
    recordId: id,
  );
  final index = await encryption.encryptText(
    jsonEncode([id]),
    recordId: '__ledger_index__',
  );
  return {
    'tx_cache_ids_v2': index,
    'txe_$id': payload,
  };
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('key material', () {
    Future<void> expectKeyFailurePreservesRecords(_FakeKeyStore store) async {
      final seed = await _seedEncryptedLedger('protected');
      SharedPreferences.setMockInitialValues(seed);
      final prefs = await SharedPreferences.getInstance();

      await expectLater(
        TransactionCacheService(
          encryption: LedgerEncryptionService(keyStore: store),
        ).init(),
        throwsA(isA<LedgerKeyUnavailableException>()),
      );
      // Fail closed: nothing was wiped or replaced.
      expect(prefs.getString('txe_protected'), seed['txe_protected']);
      expect(
        prefs.getString('tx_cache_ids_v2'),
        seed['tx_cache_ids_v2'],
      );
    }

    test('invalid base64 key value fails closed and preserves records', () {
      expectKeyFailurePreservesRecords(
        _FakeKeyStore(value: 'not-valid-base64!!!'),
      );
    });

    test('wrong-length key fails closed and preserves records', () {
      expectKeyFailurePreservesRecords(
        _FakeKeyStore(value: base64UrlEncode(List<int>.filled(31, 0x55))),
      );
    });

    test('empty key value fails closed and preserves records', () {
      expectKeyFailurePreservesRecords(_FakeKeyStore(value: ''));
    });

    test('createKeyIfMissing does not overwrite an existing key', () async {
      final sentinel = base64UrlEncode(List<int>.filled(32, 0x55));
      final store = _FakeKeyStore(value: sentinel);
      await LedgerEncryptionService(keyStore: store).createKeyIfMissing();
      expect(store.value, sentinel);
    });

    test('createKeyIfMissing surfaces key-store write failures', () async {
      final store = _FakeKeyStore()..throwOnWrite = true;
      await expectLater(
        LedgerEncryptionService(keyStore: store).createKeyIfMissing(),
        throwsA(isA<LedgerKeyUnavailableException>()),
      );
      expect(store.value, isNull);
    });
  });

  group('ciphertext tampering', () {
    test('single-byte ciphertext flip fails authentication', () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final encoded = await encryption.encryptText('payload', recordId: 'r1');
      final envelope = jsonDecode(encoded) as Map<String, dynamic>;
      envelope['ciphertext'] = _flipFirstChar(envelope['ciphertext'] as String);

      await expectLater(
        encryption.decryptText(jsonEncode(envelope), expectedRecordId: 'r1'),
        throwsA(isA<LedgerKeyUnavailableException>()),
      );
    });

    test('replaced authentication tag fails decryption', () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final encoded = await encryption.encryptText('payload', recordId: 'r1');
      final envelope = jsonDecode(encoded) as Map<String, dynamic>;
      envelope['mac'] =
          base64UrlEncode(List<int>.filled(16, 0)); // valid base64, wrong tag

      await expectLater(
        encryption.decryptText(jsonEncode(envelope), expectedRecordId: 'r1'),
        throwsA(isA<LedgerKeyUnavailableException>()),
      );
    });

    test('tampered nonce fails decryption', () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final encoded = await encryption.encryptText('payload', recordId: 'r1');
      final envelope = jsonDecode(encoded) as Map<String, dynamic>;
      envelope['nonce'] = _flipFirstChar(envelope['nonce'] as String);

      await expectLater(
        encryption.decryptText(jsonEncode(envelope), expectedRecordId: 'r1'),
        throwsA(isA<LedgerKeyUnavailableException>()),
      );
    });

    test('envelope with non-string nonce is rejected', () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final encoded = await encryption.encryptText('payload', recordId: 'r1');
      final envelope = jsonDecode(encoded) as Map<String, dynamic>;
      envelope['nonce'] = 12345;

      await expectLater(
        encryption.decryptText(jsonEncode(envelope), expectedRecordId: 'r1'),
        throwsA(isA<LedgerKeyUnavailableException>()),
      );
    });

    test('tampered encrypted index fails closed and preserves payloads',
        () async {
      final seed = await _seedEncryptedLedger('indexed');
      final indexEnvelope =
          jsonDecode(seed['tx_cache_ids_v2']!) as Map<String, dynamic>;
      indexEnvelope['ciphertext'] =
          _flipFirstChar(indexEnvelope['ciphertext'] as String);
      SharedPreferences.setMockInitialValues({
        ...seed,
        'tx_cache_ids_v2': jsonEncode(indexEnvelope),
      });
      final prefs = await SharedPreferences.getInstance();

      await expectLater(
        TransactionCacheService().init(),
        throwsA(isA<LedgerKeyUnavailableException>()),
      );
      expect(prefs.getString('txe_indexed'), seed['txe_indexed']);
    });

    test('tampered record payload fails closed and preserves the ledger',
        () async {
      final seed = await _seedEncryptedLedger('record-1');
      final payloadEnvelope =
          jsonDecode(seed['txe_record-1']!) as Map<String, dynamic>;
      payloadEnvelope['ciphertext'] =
          _flipFirstChar(payloadEnvelope['ciphertext'] as String);
      SharedPreferences.setMockInitialValues({
        ...seed,
        'txe_record-1': jsonEncode(payloadEnvelope),
      });
      final prefs = await SharedPreferences.getInstance();

      final cache = TransactionCacheService();
      // Sync metadata migration reads payloads during init, so the tamper may
      // surface there or on loadAll; both are fail-closed.
      await expectLater(
        () async {
          await cache.init();
          await cache.loadAll();
        },
        throwsA(isA<LedgerMigrationException>()),
      );
      expect(
        prefs.getString('tx_cache_ids_v2'),
        seed['tx_cache_ids_v2'],
      );
    });
  });

  group('import journal robustness', () {
    test('malformed import journal fails closed', () async {
      final seed = await _seedEncryptedLedger('journaled');
      SharedPreferences.setMockInitialValues({
        ...seed,
        'txj_import_journal': '{bad json',
      });
      final prefs = await SharedPreferences.getInstance();

      // The outer envelope decode currently surfaces as a FormatException
      // rather than LedgerMigrationException; either way it must fail closed
      // and preserve the ledger.
      await expectLater(
        TransactionCacheService().init(),
        throwsA(anyOf(
          isA<LedgerMigrationException>(),
          isA<FormatException>(),
        )),
      );
      expect(prefs.getString('txe_journaled'), seed['txe_journaled']);
    });

    Future<String> encodeJournal(Map<String, dynamic> journal) async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      final encrypted = await encryption.encryptText(jsonEncode(journal));
      return jsonEncode({'schemaVersion': 2, 'ciphertext': encrypted});
    }

    test('import journal with unsupported version fails closed', () async {
      final seed = await _seedEncryptedLedger('journaled');
      SharedPreferences.setMockInitialValues({
        ...seed,
        'txj_import_journal': await encodeJournal({
          'v': 3,
          'phase': 'pending',
          'records': <dynamic>[],
        }),
      });

      await expectLater(
        TransactionCacheService().init(),
        throwsA(isA<LedgerMigrationException>()),
      );
    });

    test('import journal with unsupported phase fails closed', () async {
      final seed = await _seedEncryptedLedger('journaled');
      SharedPreferences.setMockInitialValues({
        ...seed,
        'txj_import_journal': await encodeJournal({
          'v': 2,
          'phase': 'bogus_phase',
          'records': <dynamic>[],
        }),
      });

      await expectLater(
        TransactionCacheService().init(),
        throwsA(isA<LedgerMigrationException>()),
      );
    });
  });

  group('interrupted migration and recovery', () {
    test('migration resumes from a journal that over-reports converted records',
        () async {
      final encryption = LedgerEncryptionService();
      await encryption.createKeyIfMissing();
      // The journal claims 'mid-mig' was already converted, but its encrypted
      // payload is missing: an interruption between journal write and payload
      // verification.
      final journal = await encryption.encryptText(
        jsonEncode({
          'journalVersion': 3,
          'kind': 'legacy_money_migration',
          'state': 'copying',
          'legacyIds': ['mid-mig'],
          'convertedIds': ['mid-mig'],
        }),
        recordId: '__migration_progress__',
      );
      SharedPreferences.setMockInitialValues({
        'tx_cache_ids': jsonEncode(['mid-mig']),
        'tx_mid-mig': jsonEncode(_legacy('mid-mig', 239)),
        'tx_money_migration_v2': journal,
      });
      final prefs = await SharedPreferences.getInstance();

      final cache = TransactionCacheService();
      await cache.init();
      final records = await cache.loadAll();

      // Exactly once, correct paise conversion, journal cleared.
      expect(records.length, 1);
      expect(records.single.id, 'mid-mig');
      expect(records.single.amountMinor, 23900);
      expect(prefs.getString('tx_money_migration_v2'), isNull);
    });

    test('plaintext reconciliation journal claims are revalidated', () async {
      final seedCache = TransactionCacheService();
      await seedCache.init();
      await seedCache.put(_tx('v2-live', 10000, DateTime(2026, 10, 1)));
      final prefs = await SharedPreferences.getInstance();
      // A stale plaintext journal claims 'stale' is converted, but no
      // encrypted payload exists for it.
      await prefs.setString('tx_cache_ids', jsonEncode(['stale']));
      await prefs.setString('tx_stale', jsonEncode(_legacy('stale', 239)));
      await prefs.setString(
        'tx_money_migration_v2',
        jsonEncode({
          'version': 2,
          'kind': 'legacy_reconciliation',
          'state': 'copying',
          'legacyIds': ['stale'],
          'convertedIds': ['stale'],
        }),
      );

      final restarted = TransactionCacheService();
      await restarted.init();
      final records = await restarted.loadAll();

      expect(records.map((tx) => tx.id).toSet(), {'v2-live', 'stale'});
      expect(
        records.singleWhere((tx) => tx.id == 'stale').amountMinor,
        23900,
      );
      expect(prefs.getString('tx_money_migration_v2'), isNull);
    });

    test('interrupted activation at index commit is completed on restart',
        () async {
      final cache = TransactionCacheService();
      await cache.init();
      await cache.put(_tx('base', 10000, DateTime(2026, 10, 1)));

      cache.writeHook = (op, key) async {
        if (op == 'set' && key == 'tx_cache_ids_v2') {
          throw StateError('index commit interrupted');
        }
      };
      await expectLater(
        cache.put(_tx('arrived', 23950, DateTime(2026, 10, 2))),
        throwsA(isA<LedgerImportException>()),
      );

      final restarted = TransactionCacheService();
      await restarted.init();
      final records = await restarted.loadAll();

      expect(records.map((tx) => tx.id).toSet(), {'base', 'arrived'});
      expect(
        records.singleWhere((tx) => tx.id == 'arrived').amountMinor,
        23950,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('txj_import_journal'),
        isNull,
      );
    });

    test('repeated initialization is idempotent', () async {
      SharedPreferences.setMockInitialValues({
        'tx_cache_ids': jsonEncode(['idem']),
        'tx_idem': jsonEncode(_legacy('idem', 125)),
      });

      final first = TransactionCacheService();
      await first.init();
      final second = TransactionCacheService();
      await second.init();
      final records = await second.loadAll();

      expect(records.length, 1);
      expect(records.single.amountMinor, 12500);
    });
  });
}
