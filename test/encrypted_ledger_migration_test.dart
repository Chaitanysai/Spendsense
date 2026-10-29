import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/services/ledger_encryption_service.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

void main() {
  test('migrates legacy whole rupees to encrypted paise records', () async {
    SharedPreferences.setMockInitialValues({
      'tx_cache_ids': jsonEncode(['legacy-1']),
      'tx_legacy-1': jsonEncode({
        'id': 'legacy-1',
        'amount': 125,
        'type': 'expense',
        'merchant': 'Legacy Shop',
        'category': 'Shopping',
        'paymentMethod': 'UPI',
        'date': '2026-10-23T10:00:00.000',
        'time': '10:00',
        'originalSms': '',
        'isExcluded': false,
      }),
    });

    final cache = TransactionCacheService();
    await cache.init();
    final records = await cache.loadAll();
    final prefs = await SharedPreferences.getInstance();

    expect(records.single.amountMinor, 12500);
    expect(prefs.getString('txe_legacy-1'), isNotNull);
    expect(prefs.getString('txe_legacy-1'), isNot(contains('Legacy Shop')));
    // The plaintext source is retired once the encrypted copy is verified: it
    // holds the merchant and amount in clear text, and keeping it let a stale
    // copy block every later start.
    expect(prefs.getString('tx_legacy-1'), isNull);
    expect(prefs.getString('tx_cache_ids'), isNull);
  });

  test('tampered encrypted data fails closed', () async {
    SharedPreferences.setMockInitialValues({
      'tx_cache_ids_v2': jsonEncode(['tx-1']),
      'txe_tx-1': 'tampered',
    });

    final cache = TransactionCacheService();
    // Sync metadata migration reads each payload during init, so tampering may
    // fail closed there; if it does not, loadAll must fail instead. Either way
    // no plaintext/corrupt record may be surfaced.
    await expectLater(
      () async {
        await cache.init();
        await cache.loadAll();
      },
      throwsA(isA<LedgerMigrationException>()),
    );
  });

  test('encryption uses a fresh nonce for each payload', () async {
    final service = LedgerEncryptionService();
    await service.createKeyIfMissing();
    final first = await service.encryptText('same');
    final second = await service.encryptText('same');

    expect(first, isNot(second));
    expect(await service.decryptText(first), 'same');
    expect(await service.decryptText(second), 'same');
  });
}
