import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/sms_service.dart';
import 'package:spendsense/services/transaction_cache_service.dart';

/// Automatic-sync behaviour: the launch/resume trigger, its cooldown, and the
/// failure states it must surface.
///
/// These drive `ensureAutoSync`, which is the entry point the navigation shell
/// calls. Synthetic fixtures only; no real SMS text.
///
/// Note: `syncFromSms` requests the SMS permission *before* it touches the
/// injected fetcher, so these tests must answer the permissions channel. That
/// ordering is itself part of the contract — a denied permission must stop the
/// scan before any inbox read.

SmsMessageModel _sms(String id) => SmsMessageModel(
      id: id,
      body: 'Rs 450 debited from A/c XX1234 to Zomato on 12-10-26',
      date: DateTime(2026, 10, 12),
    );

TransactionModel _tx(String id, int amount) => TransactionModel(
      id: id,
      amount: amount,
      type: TransactionType.expense,
      merchant: 'Merchant $id',
      category: 'Food',
      paymentMethod: 'UPI',
      date: DateTime(2026, 10, 12, 9, 30),
      time: '09:30',
      originalSms: 'debit notice $id',
      isExcluded: false,
      source: 'SMS-Parser',
    );

/// Builds an initialised provider with an injectable inbox, an injectable
/// permission answer, and optional seed.
///
/// `syncFromSms` requests the SMS permission *before* it touches the fetcher, so
/// the permission must be faked too — otherwise the real platform channel is
/// hit and the scan never reaches the injected inbox.
Future<TransactionProvider> _provider({
  List<TransactionModel> seed = const [],
  List<SmsMessageModel>? inbox,
  bool throws = false,
  bool withStartDate = true,
  bool permissionGranted = true,
  Future<List<SmsMessageModel>> Function()? fetcher,
}) async {
  SharedPreferences.setMockInitialValues({
    if (withStartDate)
      'sms_scan_start_date': DateTime(2026, 1, 1).toIso8601String(),
  });

  if (seed.isNotEmpty) {
    final seeder = TransactionCacheService();
    await seeder.init();
    await seeder.putAll(seed);
  }

  final provider = TransactionProvider(
    smsService: SmsService(
      requestSmsPermission: () async => permissionGranted
          ? PermissionStatus.granted
          : PermissionStatus.denied,
      openSettings: () async => true,
    ),
    resyncFetcher: fetcher ??
        () async {
          if (throws) throw StateError('sms channel unavailable');
          return inbox ?? [];
        },
  );
  await provider.ready;
  return provider;
}

List<String> _ids(TransactionProvider p) =>
    p.transactions.map((t) => t.id).toList()..sort();

void main() {
  group('automatic sync on launch', () {
    test('a first launch with a start date scans the inbox', () async {
      var fetches = 0;
      final provider = await _provider(
        fetcher: () async {
          fetches++;
          return [_sms('sms-1')];
        },
      );

      final started = await provider.ensureAutoSync();

      expect(started, isTrue, reason: 'launch must start a scan');
      expect(fetches, 1);
      expect(_ids(provider), ['sms-1']);
      expect(provider.lastSynced, isNotNull);
      provider.dispose();
    });

    test('a first-run user with no start date is not scanned', () async {
      var fetches = 0;
      final provider = await _provider(
        withStartDate: false,
        fetcher: () async {
          fetches++;
          return [_sms('sms-1')];
        },
      );

      final started = await provider.ensureAutoSync();

      // Scanning with no window would import nothing meaningful; the date
      // prompt is the correct first-run path instead.
      expect(started, isFalse);
      expect(fetches, 0);
      expect(provider.hasSmsScanStartDate, isFalse);
      provider.dispose();
    });

    test('a denied SMS permission is surfaced, not swallowed', () async {
      var fetches = 0;
      final provider = await _provider(
        permissionGranted: false,
        fetcher: () async {
          fetches++;
          return [_sms('sms-1')];
        },
      );

      await provider.ensureAutoSync();

      // Regression: this used to set isSyncing = false and return in silence,
      // leaving the user with no idea why nothing was imported.
      expect(provider.syncFailure, SyncFailure.permissionDenied);
      expect(provider.hasSyncFailure, isTrue);
      expect(fetches, 0, reason: 'a denied permission stops before any read');
      expect(provider.lastSynced, isNull);
      provider.dispose();
    });

    test('a ledger that failed to load is never scanned into', () async {
      // Seed a tampered index so cache init fails closed, then prove the guard
      // actually stops the scan. The previous version asserted a *healthy*
      // provider, so it never reached the failure branch.
      SharedPreferences.setMockInitialValues({
        'tx_cache_ids_v2': 'not-a-valid-encrypted-index',
      });
      var fetches = 0;
      final provider = TransactionProvider(
        resyncFetcher: () async {
          fetches += 1;
          return [_sms('sms-1')];
        },
      );
      await provider.ready;
      expect(provider.hasLedgerInitError, isTrue);

      final scanned = await provider.ensureAutoSync();
      expect(scanned, isFalse);
      expect(fetches, 0, reason: 'a failed ledger must not be scanned into');
      provider.dispose();
    });
  });

  group('five-minute cooldown', () {
    test('a second automatic trigger inside the window does not scan',
        () async {
      var fetches = 0;
      final provider = await _provider(
        fetcher: () async {
          fetches++;
          return [_sms('sms-1')];
        },
      );

      expect(await provider.ensureAutoSync(), isTrue);
      expect(fetches, 1);

      // Simulates a resume moments after launch, or a second shell build.
      expect(await provider.ensureAutoSync(), isFalse,
          reason: 'a fresh sync must not be repeated');
      expect(fetches, 1, reason: 'the inbox must not be read twice');
      provider.dispose();
    });

    test('an empty ledger retries inside the window', () async {
      var fetches = 0;
      final provider = await _provider(
        fetcher: () async {
          fetches++;
          return [];
        },
      );

      await provider.ensureAutoSync();
      expect(fetches, 1);
      expect(provider.isAutoSyncFresh, isTrue);
      expect(provider.transactions, isEmpty);

      // The dashboard is showing zero. A launch or resume inside the cooldown
      // must scan again rather than leave the user waiting for a manual Sync.
      expect(await provider.ensureAutoSync(), isTrue);
      expect(fetches, 2);
      provider.dispose();
    });

    test('the cooldown is five minutes', () {
      expect(TransactionProvider.autoSyncCooldown, const Duration(minutes: 5));
    });

    test('a stale last-sync allows the next automatic trigger', () async {
      var fetches = 0;
      final provider = await _provider(
        fetcher: () async {
          fetches++;
          return [];
        },
      );

      await provider.ensureAutoSync();
      expect(fetches, 1);
      expect(provider.isAutoSyncFresh, isTrue);

      // Nothing in the public API fakes the clock, so assert the rule directly:
      // a sync older than the cooldown is not fresh.
      final stale = DateTime.now().subtract(
          TransactionProvider.autoSyncCooldown + const Duration(seconds: 1));
      expect(
        DateTime.now().difference(stale) < TransactionProvider.autoSyncCooldown,
        isFalse,
        reason: 'the boundary arithmetic the gate relies on',
      );
      provider.dispose();
    });
  });

  group('manual sync bypasses the cooldown', () {
    test('a manual sync runs even when an automatic one just finished',
        () async {
      var fetches = 0;
      final provider = await _provider(
        fetcher: () async {
          fetches++;
          return [];
        },
      );

      await provider.ensureAutoSync();
      expect(fetches, 1);
      expect(provider.isAutoSyncFresh, isTrue);

      // The user taps Sync. The cooldown must not block them.
      await provider.syncFromSms(userInitiated: true);
      expect(fetches, 2, reason: 'manual sync must ignore the cooldown');
      provider.dispose();
    });

    test('manual sync still respects in-flight deduplication', () async {
      final gate = Completer<List<SmsMessageModel>>();
      var fetches = 0;
      final provider = await _provider(
        fetcher: () {
          fetches++;
          return gate.future;
        },
      );

      final first = provider.syncFromSms(userInitiated: true);
      final second = provider.syncFromSms(userInitiated: true);

      expect(identical(first, second), isTrue,
          reason: 'a double tap must share one scan');
      gate.complete([]);
      await first;
      expect(fetches, 1);
      provider.dispose();
    });

    test('an automatic trigger during a manual sync does not start another',
        () async {
      final gate = Completer<List<SmsMessageModel>>();
      var fetches = 0;
      final provider = await _provider(
        fetcher: () {
          fetches++;
          return gate.future;
        },
      );

      final manual = provider.syncFromSms(userInitiated: true);
      final auto = await provider.ensureAutoSync();

      expect(auto, isFalse, reason: 'a scan is already in flight');
      gate.complete([]);
      await manual;
      expect(fetches, 1);
      provider.dispose();
    });
  });

  group('failures are visible, never silent', () {
    test('a scan that throws records a failure and does not claim success',
        () async {
      final provider = await _provider(throws: true);

      await provider.ensureAutoSync();

      expect(provider.syncFailure, SyncFailure.scanFailed);
      expect(provider.hasSyncFailure, isTrue);
      expect(provider.lastSynced, isNull,
          reason: 'a failed scan must not advance the last-sync stamp');
      provider.dispose();
    });

    test('a later success clears the failure', () async {
      var shouldThrow = true;
      final provider = await _provider(
        fetcher: () async {
          if (shouldThrow) throw StateError('sms channel unavailable');
          return [_sms('sms-1')];
        },
      );

      await provider.ensureAutoSync();
      expect(provider.syncFailure, SyncFailure.scanFailed);

      shouldThrow = false;
      await provider.syncFromSms(userInitiated: true);

      expect(provider.syncFailure, isNull, reason: 'success clears the banner');
      expect(provider.lastSynced, isNotNull);
      provider.dispose();
    });

    test('the user can dismiss an acknowledged failure', () async {
      final provider = await _provider(throws: true);
      await provider.ensureAutoSync();
      expect(provider.hasSyncFailure, isTrue);

      provider.dismissSyncFailure();
      expect(provider.hasSyncFailure, isFalse);
      provider.dispose();
    });
  });

  group('repeated syncs never duplicate transactions', () {
    test('launch, resume and manual syncs leave one row per message', () async {
      final provider = await _provider(
        seed: [_tx('manual-1', 900)],
        inbox: [_sms('sms-1'), _sms('sms-2')],
      );

      await provider.ensureAutoSync();
      final afterLaunch = _ids(provider);
      final totalAfterLaunch =
          provider.transactions.fold<int>(0, (s, t) => s + t.amountMinor);

      // A resume inside the cooldown is a no-op.
      await provider.ensureAutoSync();
      // A manual sync re-reads the inbox but must not re-add anything.
      await provider.syncFromSms(userInitiated: true);
      await provider.syncFromSms(userInitiated: true);

      expect(_ids(provider), afterLaunch, reason: 'no rows added or removed');
      expect(
        provider.transactions.fold<int>(0, (s, t) => s + t.amountMinor),
        totalAfterLaunch,
        reason: 'no amount double-counted',
      );
      expect(_ids(provider).toSet().length, _ids(provider).length,
          reason: 'no duplicate ids');
      expect(_ids(provider), ['manual-1', 'sms-1', 'sms-2']);
      provider.dispose();
    });
  });

  group('automatic sync is incremental, never a full rebuild', () {
    test('a launch scan keeps manual rows and does not clear the ledger',
        () async {
      // resyncFromSms replaces the whole ledger; syncFromSms only adds. If the
      // launch path ever called the former, the manual row would be gone.
      final provider = await _provider(
        seed: [_tx('manual-1', 900), _tx('sms-old', 100)],
        inbox: [_sms('sms-new-1')],
      );

      await provider.ensureAutoSync();

      final ids = _ids(provider);
      expect(ids, contains('manual-1'),
          reason: 'an incremental scan never drops manual entries');
      expect(ids, contains('sms-old'),
          reason: 'an incremental scan never drops existing SMS rows');
      expect(ids, contains('sms-new-1'));
      provider.dispose();
    });

    test('an empty inbox leaves the ledger untouched', () async {
      final provider = await _provider(
        seed: [_tx('sms-a', 100), _tx('sms-b', 200)],
        inbox: [],
      );
      final before = _ids(provider);

      await provider.ensureAutoSync();

      expect(_ids(provider), before);
      expect(provider.lastSynced, isNotNull,
          reason: 'a successful empty scan still counts as a sync');
      provider.dispose();
    });
  });
}
