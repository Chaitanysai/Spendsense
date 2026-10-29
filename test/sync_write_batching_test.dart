import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/sms_service.dart';

/// The sync write path is batched.
///
/// A scan used to save each message on its own: five whole-file rewrites and
/// three AES-GCM operations per SMS, with the entire id index re-encrypted
/// every time. On a first import of hundreds of messages that is minutes of
/// "encrypting and syncing" and it is what this suite pins against.
///
/// The contract now: one journalled activation per scan, so the ledger index
/// is written once no matter how many messages were imported, and the skipped
/// list is flushed once no matter how many were skipped.

SmsMessageModel _sms(String id, String body) => SmsMessageModel(
      id: id,
      body: body,
      date: DateTime(2026, 10, 12),
    );

SmsMessageModel _debit(String id) => _sms(
      id,
      'Rs 450 debited from A/c XX1234 to Zomato on 12-10-26',
    );

Future<TransactionProvider> _provider(List<SmsMessageModel> inbox) async {
  SharedPreferences.setMockInitialValues({
    'sms_scan_start_date': DateTime(2026, 1, 1).toIso8601String(),
  });
  final provider = TransactionProvider(
    smsService: SmsService(
      requestSmsPermission: () async => PermissionStatus.granted,
      openSettings: () async => true,
    ),
    resyncFetcher: () async => inbox,
  );
  await provider.ready;
  return provider;
}

void main() {
  test('a scan writes the ledger index once, however many it imports',
      () async {
    final provider = await _provider([
      _debit('sms-1'),
      _debit('sms-2'),
      _debit('sms-3'),
    ]);
    final writes = <String>[];
    provider.debugSetCacheWriteHook((op, key) async => writes.add('$op $key'));

    await provider.syncFromSms(userInitiated: true);

    expect(
      provider.transactions.map((t) => t.id).toSet(),
      {'sms-1', 'sms-2', 'sms-3'},
    );
    expect(
      writes.where((w) => w == 'set tx_cache_ids_v2').length,
      1,
      reason: 'one index commit per scan, not one per message',
    );
    provider.dispose();
  });

  test('a scan flushes the skipped-message list once', () async {
    final provider = await _provider([
      _debit('sms-1'),
      _sms('credit-1', 'Rs 5,000 credited to A/c XX1234 on 12-10-26'),
      _sms('credit-2', 'Rs 900 credited to A/c XX1234 on 12-10-26'),
      _sms('credit-3', 'Rs 200 credited to A/c XX1234 on 12-10-26'),
    ]);
    final writes = <String>[];
    provider.debugSetCacheWriteHook((op, key) async => writes.add('$op $key'));

    await provider.syncFromSms(userInitiated: true);

    expect(provider.transactions.map((t) => t.id).toSet(), {'sms-1'});
    expect(
      writes.where((w) => w == 'set tx_rejected_ids').length,
      1,
      reason: 'one flush per scan, not one per skipped message',
    );
    provider.dispose();
  });

  test('a batch that cannot be saved leaves no rows on screen', () async {
    final provider = await _provider([_debit('sms-1'), _debit('sms-2')]);
    provider.debugSetCacheWriteHook((op, key) async {
      if (op == 'set' && key == 'tx_cache_ids_v2') {
        throw StateError('index write failed');
      }
    });

    await provider.syncFromSms(userInitiated: true);

    // The batch is all-or-nothing, so nothing parsed may be shown as saved.
    expect(provider.transactions, isEmpty);
    expect(provider.syncFailure, SyncFailure.scanFailed);
    provider.dispose();
  });
}
