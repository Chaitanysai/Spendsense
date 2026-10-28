import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';
import '../utils/bank_recognizer.dart';
import '../utils/period_math.dart';
import '../utils/money_parser.dart';
import '../services/sms_service.dart';
import '../services/bill_classifier.dart';
import '../services/smart_parser.dart';
import '../services/gemini_service.dart';
import '../services/transaction_cache_service.dart';
import '../services/ledger_tombstone_store.dart';
import '../services/budget_monitor_service.dart';

class TransactionProvider with ChangeNotifier {
  static const _smsScanStartKey = 'sms_scan_start_date';

  /// How long an automatic sync stays "fresh".
  ///
  /// Automatic triggers (app launch, resume from background) are skipped while
  /// the last successful sync is younger than this. Manual sync ignores it.
  /// Without a cooldown, every resume — a notification glance, a permission
  /// dialog, a share sheet — would start a full inbox scan.
  static const Duration autoSyncCooldown = Duration(minutes: 5);

  List<TransactionModel> _transactions = [];
  bool _isSyncing = false;
  bool _isLoadingCache = true;
  Object? _ledgerInitError;
  DateTime? _lastSynced;
  DateTime? _smsScanStartDate;
  int _monthlyBudgetMinor = 2000000;
  int _newThisSync = 0;

  /// Why the most recent sync attempt did not complete, or null when the last
  /// attempt succeeded (or none has run).
  ///
  /// A failed sync used to be indistinguishable from a no-op: the scan caught
  /// its error and only wrote to the device log, and a denied SMS permission
  /// returned early in silence. Both now surface here so the UI can say what
  /// happened and offer a retry.
  SyncFailure? _syncFailure;
  bool _isAutoSyncing = false;

  final TransactionCacheService _cache = TransactionCacheService();
  final LedgerTombstoneStore _tombstones = LedgerTombstoneStore();
  final BudgetMonitorService _budgetMonitor = BudgetMonitorService();
  late final Future<void> _initialization;
  bool _disposed = false;
  Future<void>? _smsSyncInFlight;
  Future<bool>? _resyncInFlight;

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  List<TransactionModel> get transactions => _transactions;

  /// Replaces the in-memory list without touching the database or SMS pipeline,
  /// so aggregation behaviour can be tested without platform plugins.
  @visibleForTesting
  void debugSeed(List<TransactionModel> seed) {
    _transactions = List.of(seed);
    _notifyIfAlive();
  }

  bool get isSyncing => _isSyncing;
  bool get isLoadingCache => _isLoadingCache;

  /// The error that aborted ledger initialization or load, if any.
  ///
  /// Non-null means the encrypted ledger failed closed: records are intact on
  /// disk but could not be read. A null value together with an empty
  /// [transactions] list means the ledger is genuinely empty — the two states
  /// must never be presented the same way.
  Object? get ledgerInitError => _ledgerInitError;
  bool get hasLedgerInitError => _ledgerInitError != null;

  DateTime? get lastSynced => _lastSynced;
  DateTime? get smsScanStartDate => _smsScanStartDate;
  bool get hasSmsScanStartDate => _smsScanStartDate != null;

  /// Why the last sync attempt failed, or null when it succeeded.
  SyncFailure? get syncFailure => _syncFailure;

  /// True when the last sync attempt did not complete and the user has not
  /// dismissed it. Drives the actionable status strip.
  bool get hasSyncFailure => _syncFailure != null;

  /// True while an automatic (launch or resume) sync is running, as opposed to
  /// a user-initiated one.
  bool get isAutoSyncing => _isAutoSyncing;

  /// Whether an automatic sync would be a no-op right now.
  ///
  /// Exposed so the UI and tests can reason about the cooldown without
  /// duplicating the rule.
  bool get isAutoSyncFresh {
    final last = _lastSynced;
    if (last == null) return false;
    return DateTime.now().difference(last) < autoSyncCooldown;
  }

  /// Clears the visible failure once the user has acknowledged it.
  void dismissSyncFailure() {
    if (_syncFailure == null) return;
    _syncFailure = null;
    _notifyIfAlive();
  }
  int get monthlyBudgetMinor => _monthlyBudgetMinor;

  /// Compatibility getter. The returned number is integer paise.
  @Deprecated('Use monthlyBudgetMinor.')
  int get monthlyBudget => _monthlyBudgetMinor;
  int get newThisSync => _newThisSync;

  /// [resyncFetcher] is a test seam: it replaces the SMS inbox source so the
  /// sync pipeline can be driven without the platform channel or the SMS
  /// permission. Null in production, where the real inbox is read.
  ///
  /// [smsService] is the second half of that seam: the permission check runs
  /// before any inbox read, so a test that only fakes the fetcher would still
  /// hit the real permission channel. Injecting the service lets a test decide
  /// whether permission is granted without a platform round trip.
  TransactionProvider({
    @visibleForTesting Future<List<SmsMessageModel>> Function()? resyncFetcher,
    @visibleForTesting SmsService? smsService,
  })  : _resyncFetcher = resyncFetcher,
        _smsServiceOverride = smsService {
    _initialization = _init();
  }

  final Future<List<SmsMessageModel>> Function()? _resyncFetcher;
  final SmsService? _smsServiceOverride;

  /// Completes when the initial cache/budget load has finished.
  @visibleForTesting
  Future<void> get ready => _initialization;

  /// Test seam: injects failures into the ledger's persisted writes. Debug
  /// builds only — `assert` is compiled out of release, and the hook itself is
  /// unused there.
  void debugSetCacheWriteHook(WriteHook? hook) {
    assert(() {
      _cache.writeHook = hook;
      return true;
    }());
  }

  /// Serialises database writes so an in-flight sync can never interleave with
  /// a user edit or a second sync (audit R4).
  Future<void> _dbLock = Future.value();

  Future<T> _locked<T>(Future<T> Function() action) {
    final previous = _dbLock;
    final done = previous.then((_) => action());
    _dbLock = done.then((_) {}, onError: (_) {});
    return done;
  }

  /// Stamps a transaction with sync metadata: a fresh syncId when it has
  /// none, and a modification timestamp kept strictly monotonic per record
  /// (moved one millisecond past the previous stamp if the clock has not
  /// advanced) so the sync layer can order every change.
  TransactionModel _stampSyncMeta(TransactionModel tx) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stamped = tx.copyWith(
      updatedAtMs: now > tx.updatedAtMs ? now : tx.updatedAtMs + 1,
    );
    if (stamped.syncId.isNotEmpty) return stamped;
    return stamped.copyWith(syncId: TransactionModel.newSyncId());
  }

  /// Re-reads the ledger from the cache and replaces the in-memory list, so an
  /// external write (e.g. from the sync layer) becomes visible. Serialised
  /// with the same write lock as every local write, so a pull can never
  /// interleave with a local write.
  Future<void> reloadFromStore() async {
    await _initialization;
    await _locked(() => _loadFromCache());
    _notifyIfAlive();
  }

  /// Records deletion tombstones for snapshots about to be removed, so a
  /// later pull cannot resurrect them. Fail-soft: deletion always proceeds.
  Future<void> _recordTombstones(List<TransactionModel> removed) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _tombstones.addAll([
      for (final tx in removed)
        LedgerTombstone(
          syncId: tx.syncId,
          id: tx.id,
          deletedAtMs: now,
        )
    ]);
  }

  Future<void> _init() async {
    try {
      await _cache.init();
      await Future.wait([_loadBudget(), _loadFromCache()]);
      _lastSynced = _cache.lastSyncTime;
    } catch (error) {
      // The ledger failed closed: nothing was wiped or replaced, it just could
      // not be read. Surface the failure instead of letting it masquerade as a
      // successful empty load.
      _ledgerInitError = error;
      debugPrint(
          '🔒 Ledger init failed (${error.runtimeType}) — data preserved');
    }
    _isLoadingCache = false;
    _notifyIfAlive();
  }

  /// Retries ledger initialization after a failure, e.g. once the underlying
  /// store has been repaired. Does nothing when there is no error to retry.
  Future<void> retryLedgerInit() async {
    if (_ledgerInitError == null) return;
    _ledgerInitError = null;
    _isLoadingCache = true;
    _notifyIfAlive();
    await _init();
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.loadAll();
    // Assign unconditionally: an empty store is a real state (the user may
    // have cleared or resynced), and keeping the previous in-memory list would
    // resurrect transactions that no longer exist on disk.
    _transactions = cached;
    if (cached.isNotEmpty) {
      debugPrint('📦 Loaded ${cached.length} transactions from local DB');
    }
  }

  Future<void> _loadBudget() async {
    final prefs = await SharedPreferences.getInstance();
    final versioned = prefs.getString('monthly_budget_v2');
    if (versioned != null) {
      final data = jsonDecode(versioned);
      if (data is Map &&
          data['schemaVersion'] == 2 &&
          data['currency'] == 'INR' &&
          data['amountMinor'] is int) {
        _monthlyBudgetMinor = data['amountMinor'] as int;
      } else {
        throw const LedgerMigrationException(
            'invalid_budget', 'The saved budget format is invalid.');
      }
    } else {
      final legacy = prefs.getDouble('monthly_budget');
      if (legacy != null) {
        _monthlyBudgetMinor = parseRupeesToPaise(legacy.toString());
        await prefs.setString(
          'monthly_budget_v2',
          jsonEncode({
            'schemaVersion': 2,
            'currency': 'INR',
            'amountMinor': _monthlyBudgetMinor,
          }),
        );
      }
    }
    final startRaw = prefs.getString(_smsScanStartKey);
    _smsScanStartDate = startRaw == null ? null : DateTime.tryParse(startRaw);
    _salaryDay = prefs.getInt('salary_day') ?? 1;
  }

  Future<void> setMonthlyBudgetMinor(int amountMinor) async {
    if (amountMinor < 0) {
      throw ArgumentError.value(amountMinor, 'amountMinor');
    }
    _monthlyBudgetMinor = amountMinor;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'monthly_budget_v2',
      jsonEncode({
        'schemaVersion': 2,
        'currency': 'INR',
        'amountMinor': amountMinor,
      }),
    );
    _notifyIfAlive();
  }

  /// Legacy rupee setter kept for old callers during the migration window.
  Future<void> setMonthlyBudget(double amount) async {
    await setMonthlyBudgetMinor(parseRupeesToPaise(amount.toString()));
  }

  Future<void> setSmsScanStartDate(
    DateTime date, {
    bool resync = true,
  }) async {
    final normalized = DateTime(date.year, date.month, date.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_smsScanStartKey, normalized.toIso8601String());
    _smsScanStartDate = normalized;
    _notifyIfAlive();

    if (resync) {
      await forceFullResync();
    }
  }

  /// Expenses inside [period] (or, when null, the current CALENDAR month —
  /// a deliberately different period from the salary cycle; callers that mean
  /// the salary cycle must pass [PeriodProvider.currentPeriod]).
  ///
  /// Boundaries are calendar days: the start day and the end day are both
  /// included, decided in local time, with no `Duration` arithmetic so a DST
  /// change cannot shift a day.
  Iterable<TransactionModel> expensesInPeriod(DateTimeRange? period) {
    if (period == null) {
      final now = DateTime.now();
      return _transactions.where((t) =>
          t.type == TransactionType.expense &&
          !t.isExcluded &&
          _isLocalMonth(t.date, now));
    }

    final startDay = PeriodMath.dateOnly(period.start);
    final endDayExclusive = PeriodMath.addDays(period.end, 1);

    return _transactions.where((t) =>
        t.type == TransactionType.expense &&
        !t.isExcluded &&
        !_localDate(t.date).isBefore(startDay) &&
        _localDate(t.date).isBefore(endDayExclusive));
  }

  DateTime _localDate(DateTime date) => date.toLocal();

  bool _isLocalMonth(DateTime value, DateTime day) {
    final local = _localDate(value);
    return local.year == day.year && local.month == day.month;
  }

  int totalExpensesForPeriod(DateTimeRange? period) =>
      expensesInPeriod(period).fold<int>(0, (sum, t) => sum + t.amountMinor);

  int get totalExpenses => totalExpensesForPeriod(null);

  String topCategoryForPeriod(DateTimeRange? period) {
    if (_transactions.isEmpty) return "None";
    final Map<String, int> totals = {};
    for (final t in expensesInPeriod(period)) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amountMinor;
    }
    if (totals.isEmpty) return "None";
    return totals.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  String get topCategory => topCategoryForPeriod(null);

  List<String> get availableCategories {
    final cats = _transactions.map((t) => t.category).toSet().toList();
    cats.sort();
    return cats;
  }

  Iterable<TransactionModel> get trackedTransactions =>
      _transactions.where((t) => !t.isExcluded);

  Iterable<TransactionModel> get trackedExpenses =>
      trackedTransactions.where((t) => t.type == TransactionType.expense);

  int get totalTrackedExpenses =>
      trackedExpenses.fold<int>(0, (sum, t) => sum + t.amountMinor);

  int get totalTrackedIncome => trackedTransactions
      .where((t) => t.type == TransactionType.income)
      .fold<int>(0, (sum, t) => sum + t.amountMinor);

  /// Net balance across all non-excluded transactions. Amounts are stored as
  /// positive magnitudes; transaction type supplies the direction.
  int get availableBalance => totalTrackedIncome - totalTrackedExpenses;

  String get topTrackedCategory {
    final totals = <String, int>{};
    for (final t in trackedExpenses) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amountMinor;
    }
    if (totals.isEmpty) return 'None';
    return totals.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Roll-up of tracked transactions by a payment attribute — method, bank or
  /// account. Kept here so the grouping rule (excluded transactions never
  /// count, a blank attribute means "Other") has a single owner.
  ///
  /// This is the *all-time, income-inclusive* roll-up. Screens that label an
  /// amount as spending for a period must use [spendingStatsForPeriod] so the
  /// figure reconciles with [spendingTotalForPeriod].
  Map<String, InstrumentStat> statsBy(
      String? Function(TransactionModel transaction) keyOf) {
    final stats = <String, InstrumentStat>{};
    for (final t in trackedTransactions) {
      final key = _instrumentKey(keyOf(t));
      final stat = stats.putIfAbsent(key, InstrumentStat.new);
      stat.count++;
      if (t.type == TransactionType.income) {
        stat.received += t.amountMinor;
      } else {
        stat.spent += t.amountMinor;
      }
    }
    return stats;
  }

  /// Canonical spending total for [period]: non-excluded expense magnitudes
  /// only. Income, excluded rows and rows outside the window never count.
  ///
  /// Every "spent" figure that claims to describe [period] must come from this
  /// method (Home's cycle card, Payment Instruments, category bars) so the
  /// numbers reconcile by construction instead of by coincidence.
  int spendingTotalForPeriod(DateTimeRange? period) =>
      totalExpensesForPeriod(period);

  /// Spending grouped by instrument inside [period], using the *same* rows and
  /// the *same* filter as [spendingTotalForPeriod]. Summing every `spent` in
  /// the returned map therefore equals that total exactly.
  ///
  /// Income rows are ignored entirely: a refund credited to a card is not
  /// spending, and counting it would break the reconciliation invariant.
  Map<String, InstrumentStat> spendingStatsForPeriod(
    DateTimeRange? period,
    String? Function(TransactionModel transaction) keyOf,
  ) {
    final stats = <String, InstrumentStat>{};
    for (final t in expensesInPeriod(period)) {
      final key = _instrumentKey(keyOf(t));
      final stat = stats.putIfAbsent(key, InstrumentStat.new);
      stat.count++;
      stat.spent += t.amountMinor;
    }
    return stats;
  }

  /// One place decides how an instrument key is normalised: null, blank and
  /// the stored unknown label all collapse into "Other".
  String _instrumentKey(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        trimmed.toLowerCase() ==
            TransactionModel.unknownBankLabel.toLowerCase()) {
      return 'Other';
    }
    return trimmed;
  }

  /// Scans SMS. [userInitiated] is true only for an explicit user action
  /// (pull to refresh, a Sync button); it lets a permanently denied permission
  /// open Android settings. Automatic syncs never do.
  Future<void> syncFromSms({bool userInitiated = false}) {
    final current = _smsSyncInFlight;
    if (current != null) return current;

    final operation = _syncFromSms(userInitiated: userInitiated);
    _smsSyncInFlight = operation;
    operation.then<void>(
      (_) {
        if (identical(_smsSyncInFlight, operation)) _smsSyncInFlight = null;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_smsSyncInFlight, operation)) _smsSyncInFlight = null;
      },
    );
    return operation;
  }

  /// The automatic trigger: app launch and resume from background.
  ///
  /// This is the entry point the shell calls, and it is deliberately separate
  /// from [syncFromSms] so the automatic path can never open Android settings
  /// or bypass the cooldown. It returns without doing anything when:
  ///
  /// * the ledger failed to load (there is nothing safe to scan into);
  /// * no SMS scan start date has been chosen yet — a first-run user gets the
  ///   date prompt instead, and scanning with no window would import nothing
  ///   meaningful;
  /// * a sync is already in flight (launch and resume can fire back to back);
  /// * the last successful sync is younger than [autoSyncCooldown].
  ///
  /// It always uses the incremental [syncFromSms], never the full rebuild in
  /// [resyncFromSms].
  ///
  /// Returns true when a scan was actually started.
  Future<bool> ensureAutoSync() async {
    await _initialization;
    if (_ledgerInitError != null) return false;
    if (!hasSmsScanStartDate) return false;
    if (_smsSyncInFlight != null) return false;
    if (isAutoSyncFresh) return false;

    _isAutoSyncing = true;
    _notifyIfAlive();
    try {
      await syncFromSms();
      return true;
    } finally {
      _isAutoSyncing = false;
      _notifyIfAlive();
    }
  }

  Future<void> _syncFromSms({bool userInitiated = false}) async {
    await _initialization;
    if (_ledgerInitError != null) return;
    _isSyncing = true;
    _newThisSync = 0;
    _notifyIfAlive();

    try {
      final smsService = _smsServiceOverride ?? SmsService();
      final smartParser = SmartParser();
      final aiParser = GeminiService();

      final hasPermission = await smsService.requestPermissions(
        openSettingsIfBlocked: userInitiated,
      );
      if (!hasPermission) {
        // A denied permission is a real, actionable state: nothing was scanned
        // and the user can fix it. It used to return in silence.
        _syncFailure = SyncFailure.permissionDenied;
        _isSyncing = false;
        _notifyIfAlive();
        return;
      }

      final fetcher = _resyncFetcher;
      final messages = fetcher != null
          ? await fetcher()
          : await smsService.fetchTransactionSms(
              fromDate: _smsScanStartDate,
            );

      final newMessages = messages
          .where((msg) => msg.id.isNotEmpty && !_cache.contains(msg.id))
          .toList();

      debugPrint('📩 SMS fetched: ${messages.length}');
      debugPrint('🆕 New to process: ${newMessages.length}');

      if (newMessages.isEmpty) {
        _lastSynced = DateTime.now();
        _syncFailure = null;
        await _cache.updateSyncMeta();
        _isSyncing = false;
        _notifyIfAlive();
        return;
      }

      final newTxs = <TransactionModel>[];

      for (final msg in newMessages) {
        if (!SmartParser.isDebitExpenseSms(msg.body)) {
          debugPrint(
            'SMS FILTER: REJECT reason=${SmartParser.debitSmsRejectionReason(msg.body)}',
          );
          await _cache.markRejected(msg.id,
              reason: SmartParser.debitSmsRejectionReason(msg.body));
          continue;
        }
        final localResult = await smartParser.parse(msg.body, msg.id, msg.date);

        TransactionModel? finalResult;
        if (localResult != null && localResult.confidence >= 0.8) {
          finalResult = localResult;
          // Confidence only: merchant and amount are financial data and must
          // not reach the device log.
          debugPrint('⚡ Local High-Confidence (${localResult.confidence})');
        } else if (localResult != null) {
          final aiResult = await aiParser.parseSms(msg.body, msg.id, msg.date);
          if (aiResult != null && aiResult.type == TransactionType.expense) {
            // The AI path may not return a bank; keep the locally detected one
            // rather than silently dropping it.
            finalResult = _preferBank(aiResult, localResult);
          } else {
            finalResult = localResult.copyWith(needsReview: true);
          }
        }

        if (finalResult != null) {
          finalResult = _stampSyncMeta(_withBillHint(finalResult, msg.body));
          newTxs.add(finalResult);
          final newIds = {finalResult.id};
          _transactions.removeWhere((t) => newIds.contains(t.id));
          _transactions.add(finalResult);
          _transactions.sort((a, b) => b.date.compareTo(a.date));
          _newThisSync++;
          await _cache.put(finalResult);
          _notifyIfAlive(); // Yield to UI
        } else {
          // Both local and AI rejected this valid-looking debit
          await _cache.markRejected(msg.id,
              reason: SmartParser.debitSmsRejectionReason(msg.body));
        }
      }

      await Future.wait([
        _cache.updateSyncMeta(),
      ]);

      _lastSynced = DateTime.now();
      _syncFailure = null;
      debugPrint(
          '✅ Sync complete — ${newTxs.length} new transactions saved locally');
    } catch (e) {
      // Never silent: a scan that threw did not update the ledger, so the UI
      // must not imply it did.
      debugPrint('❌ Sync error: ${e.runtimeType}');
      _syncFailure = SyncFailure.scanFailed;
    } finally {
      _isSyncing = false;
      _notifyIfAlive();
    }

    // The budget alert is a notification side effect, not part of the sync.
    // It runs after the outcome is recorded and its own failure is contained:
    // a broken alert must never relabel a successful sync as failed.
    if (_syncFailure == null) {
      try {
        await _budgetMonitor.checkBudgetAlert(this);
      } catch (e) {
        debugPrint('Budget alert skipped (${e.runtimeType})');
      }
    }
  }

  /// Rebuilds every SMS-derived transaction from the current scan window.
  ///
  /// The old implementation cleared the cache FIRST, so any failure in the
  /// following scan (no permission, a platform error, an empty inbox) left the
  /// user with nothing. This version never clears before it can scan:
  ///
  ///  1. scan — if the inbox yields nothing or the scan throws, return with the
  ///     ledger untouched (an empty scan is not evidence of an empty ledger);
  ///  2. parse into a staging list, keeping manual entries;
  ///  3. validate that the staging result is a complete, non-empty ledger and
  ///     commit it through one journalled activation, rolling back on failure.
  ///
  /// Returns true when the ledger was replaced, false when it was left alone.
  Future<bool> resyncFromSms() {
    final current = _resyncInFlight;
    if (current != null) return current;

    final operation = _performResyncFromSms();
    _resyncInFlight = operation;
    operation.then<void>(
      (_) {
        if (identical(_resyncInFlight, operation)) _resyncInFlight = null;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_resyncInFlight, operation)) _resyncInFlight = null;
      },
    );
    return operation;
  }

  Future<bool> _performResyncFromSms() async {
    await _initialization;
    if (_ledgerInitError != null) return false;
    _isSyncing = true;
    _newThisSync = 0;
    _notifyIfAlive();
    try {
      final fetcher = _resyncFetcher;
      final messages = fetcher != null
          ? await fetcher()
          : await SmsService().fetchTransactionSms(fromDate: _smsScanStartDate);

      if (messages.isEmpty) {
        debugPrint('↩️ Resync found no messages — ledger left unchanged');
        return false;
      }

      final staged = <TransactionModel>[];
      final cache = TransactionCacheService();
      await cache.init();
      final smartParser = SmartParser();
      final aiParser = GeminiService();

      for (final msg in messages) {
        if (msg.id.isEmpty) continue;
        if (!SmartParser.isDebitExpenseSms(msg.body)) continue;
        final localResult = await smartParser.parse(msg.body, msg.id, msg.date);
        TransactionModel? result;
        if (localResult != null && localResult.confidence >= 0.8) {
          result = localResult;
        } else if (localResult != null) {
          final aiResult = await aiParser.parseSms(msg.body, msg.id, msg.date);
          if (aiResult != null && aiResult.type == TransactionType.expense) {
            result = _preferBank(aiResult, localResult);
          } else {
            result = localResult.copyWith(needsReview: true);
          }
        }
        if (result != null) {
          result = _withBillHint(result, msg.body);
          // A rebuild must not discard a user's own edits to a known row.
          final existing =
              _transactions.where((t) => t.id == result!.id).firstOrNull;
          staged.add(existing == null
              ? _stampSyncMeta(result)
              : result.copyWith(
                  category: existing.category,
                  isExcluded: existing.isExcluded,
                  needsReview: false,
                  bank: existing.bank,
                  syncId: existing.syncId,
                  updatedAtMs: existing.updatedAtMs,
                ));
        }
      }

      if (staged.isEmpty) {
        debugPrint('↩️ Resync parsed nothing — ledger left unchanged');
        return false;
      }
      final manual = _transactions
          .where((t) => t.source == 'Manual')
          .toList(growable: false);
      final finalSet = [...manual, ...staged];
      final unique = <String, TransactionModel>{
        for (final t in finalSet) t.id: t,
      };
      final ledger = unique.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      await _locked(() => _cache.replaceAllWithIds(
            ledger,
            expectedIds: {for (final t in ledger) t.id},
          ));

      _transactions = ledger;
      _lastSynced = DateTime.now();
      _notifyIfAlive();
      return true;
    } catch (e) {
      debugPrint('❌ Resync error (${e.runtimeType}) — ledger left unchanged');
      return false;
    } finally {
      _isSyncing = false;
      _notifyIfAlive();
    }
  }

  /// Kept for callers that used the old name; delegates to [resyncFromSms].
  Future<void> forceFullResync() async {
    await resyncFromSms();
  }

  Future<void> toggleExclude(String id) async {
    await _initialization;
    if (_ledgerInitError != null) return;
    final index = _transactions.indexWhere((t) => t.id == id);
    if (index != -1) {
      final updated = _stampSyncMeta(_transactions[index].copyWith(
        isExcluded: !_transactions[index].isExcluded,
      ));
      _transactions[index] = updated;
      await _cache.put(updated);
      _notifyIfAlive();
    }
  }

  /// Sets the exclusion flag on several records through ONE journalled write.
  ///
  /// Returns how many records actually changed. Memory is updated only after
  /// the encrypted write verifies, so a failed write cannot make the dashboard
  /// show a change that is not persisted. All dependent screens rebuild from
  /// this provider, preserving a single source of spending truth.
  Future<int> setExclusionForIds(
    Set<String> ids,
    bool isExcluded,
  ) async {
    await _initialization;
    if (_ledgerInitError != null) {
      throw StateError('The ledger is unreadable; no change was made.');
    }
    if (ids.isEmpty) return 0;
    return _locked(() async {
      final updated = <TransactionModel>[];
      for (final tx in _transactions) {
        if (!ids.contains(tx.id) || tx.isExcluded == isExcluded) continue;
        updated.add(_stampSyncMeta(tx.copyWith(isExcluded: isExcluded)));
      }
      if (updated.isEmpty) return 0;
      await _cache.putAll(updated);
      final byId = {for (final tx in updated) tx.id: tx};
      for (var i = 0; i < _transactions.length; i++) {
        final replacement = byId[_transactions[i].id];
        if (replacement != null) _transactions[i] = replacement;
      }
      _notifyIfAlive();
      return updated.length;
    });
  }

  /// Deletes several records through one journalled index switch. Returns the
  /// exact snapshots that were removed (for the assistant audit/undo trail).
  Future<List<TransactionModel>> deleteTransactionsByIds(
    Set<String> ids,
  ) async {
    await _initialization;
    if (_ledgerInitError != null) {
      throw StateError('The ledger is unreadable; no change was made.');
    }
    if (ids.isEmpty) return const [];
    return _locked(() async {
      final removed = [
        for (final tx in _transactions)
          if (ids.contains(tx.id)) tx
      ];
      if (removed.isEmpty) return const <TransactionModel>[];
      await _cache.removeMany(ids);
      // Best-effort: a failed tombstone write must not prevent local deletion.
      await _recordTombstones(removed);
      final removedIds = {for (final tx in removed) tx.id};
      _transactions.removeWhere((tx) => removedIds.contains(tx.id));
      _notifyIfAlive();
      return removed;
    });
  }

  Future<int> restoreTransactions(List<TransactionModel> snapshots) async {
    await _initialization;
    if (_ledgerInitError != null) {
      throw StateError('The ledger is unreadable; no change was made.');
    }
    if (snapshots.isEmpty) return 0;
    return _locked(() async {
      snapshots = [for (final s in snapshots) _stampSyncMeta(s)];
      await _cache.putAll(snapshots);
      final byId = {for (final tx in snapshots) tx.id: tx};
      _transactions = [
        for (final tx in _transactions)
          if (!byId.containsKey(tx.id)) tx else byId[tx.id]!,
        for (final tx in snapshots)
          if (!_transactions.any((existing) => existing.id == tx.id)) tx,
      ]..sort((a, b) => b.date.compareTo(a.date));
      _notifyIfAlive();
      return snapshots.length;
    });
  }

  /// Restores the exact pre-change exclusion flags for an undo.
  Future<int> restoreExclusionStates(Map<String, bool> previousStates) async {
    await _initialization;
    if (_ledgerInitError != null) {
      throw StateError('The ledger is unreadable; no change was made.');
    }
    if (previousStates.isEmpty) return 0;
    return _locked(() async {
      final updated = <TransactionModel>[];
      for (final tx in _transactions) {
        final target = previousStates[tx.id];
        if (target == null || tx.isExcluded == target) continue;
        updated.add(_stampSyncMeta(tx.copyWith(isExcluded: target)));
      }
      if (updated.isEmpty) return 0;
      await _cache.putAll(updated);
      final byId = {for (final tx in updated) tx.id: tx};
      for (var i = 0; i < _transactions.length; i++) {
        final replacement = byId[_transactions[i].id];
        if (replacement != null) _transactions[i] = replacement;
      }
      _notifyIfAlive();
      return updated.length;
    });
  }

  Future<void> updateCategory(String id, String newCategory) async {
    await _initialization;
    if (_ledgerInitError != null) return;
    final index = _transactions.indexWhere((t) => t.id == id);
    if (index != -1) {
      final updated = _stampSyncMeta(_transactions[index].copyWith(
        category: newCategory,
        needsReview: false,
      ));
      _transactions[index] = updated;
      await _cache.put(updated);
      _notifyIfAlive();
    }
  }

  Future<void> updateTransaction(
    String id, {
    required int amount,
    required String merchant,
    required String category,
    required TransactionType type,
    required bool isExcluded,
    String? bank,
  }) async {
    await _initialization;
    if (_ledgerInitError != null) return;
    final index = _transactions.indexWhere((t) => t.id == id);
    if (index == -1) return;

    _transactions[index] = _stampSyncMeta(_transactions[index].copyWith(
      amountMinor: amount,
      merchant: merchant,
      category: category,
      type: type,
      isExcluded: isExcluded,
      needsReview: false,
      // A supplied value (including an empty string, which clears the bank)
      // wins; omitting it preserves whatever was already stored.
      bank: bank,
    ));
    await _cache.put(_transactions[index]);
    _notifyIfAlive();
  }

  Future<void> addTransaction(TransactionModel transaction) async {
    await _initialization;
    if (_ledgerInitError != null) return;
    final stamped = _stampSyncMeta(transaction);
    _transactions.add(stamped);
    _transactions.sort((a, b) => b.date.compareTo(a.date));
    await _cache.put(stamped);
    _notifyIfAlive();
  }

  /// Deterministic bank merge: a known bank is never replaced by an unknown one.
  /// Used where a later parsing path (AI) may lack the bank the local parser
  /// already found.
  TransactionModel _preferBank(
    TransactionModel primary,
    TransactionModel fallback,
  ) {
    if (BankRecognizer.isKnown(primary.bank)) return primary;
    if (BankRecognizer.isKnown(fallback.bank)) {
      return primary.copyWith(bank: fallback.bank);
    }
    return primary;
  }

  /// Adds the non-sensitive bill hint while the authorized SMS body is still
  /// in scope. This keeps detection working after the raw body is discarded.
  TransactionModel _withBillHint(TransactionModel tx, String sms) {
    final signal = const BillClassifier().classifyText(
      sms,
      merchant: tx.merchant,
      category: tx.category,
      amountMinor: tx.amountMinor,
      reference: tx.reference,
    );
    return tx.copyWith(
      billKindHint: signal.kind.name,
      billReminderHint: signal.reminderOnly,
    );
  }

  /// The salary cycle that is "now" for everything cycle-oriented: Home's
  /// headline total, the cycle-over-cycle pill, and the monthly budget.
  ///
  /// Uses the same `salary_day` preference [PeriodProvider] writes, loaded once
  /// during init, so services without a [BuildContext] — notably the budget
  /// monitor — compute exactly the boundary the dashboard shows.
  DateTimeRange get currentSalaryCycle =>
      PeriodMath.salaryCycle(salaryDay: _salaryDay);

  int _salaryDay = 1;

  /// How many SMS the scanner has skipped as "not a debit it understands".
  /// Only ids are kept for these messages, never their text.
  int get skippedMessageCount => _cache.rejectedCount;

  /// Lets the scanner look at every skipped message again, then rescans.
  /// Safe to repeat: saved transactions keep blocking re-import, so a message
  /// can be saved at most once. Returns how many skipped messages were
  /// reconsidered.
  Future<int> recheckSkippedMessages() async {
    await _initialization;
    final n = await _cache.clearRejected();
    _notifyIfAlive();
    if (n > 0) await syncFromSms();
    return n;
  }

  Future<void> clearAll() async {
    await _initialization;
    _transactions.clear();
    _lastSynced = null;
    _newThisSync = 0;
    await _cache.clearAll();
    _notifyIfAlive();
  }

  // ─── BACKUP EXPORT / IMPORT HELPERS ───────────────────────────────────────

  Future<String> exportBackupJson({bool includeSensitive = false}) async {
    await _initialization;
    return await _cache.exportToJsonString(
      includeSensitive: includeSensitive,
    );
  }

  Future<int> importBackupJson(String jsonString,
      {bool replace = false}) async {
    await _initialization;
    final count =
        await _cache.importFromJsonString(jsonString, replace: replace);
    await _loadFromCache();
    _notifyIfAlive();
    return count;
  }

  // Aliases for SettingsScreen compatibility
  Future<String> exportToJson({bool includeSensitive = false}) =>
      exportBackupJson(includeSensitive: includeSensitive);
  Future<int> importFromJson(String jsonString) => importBackupJson(jsonString);
}

/// Mutable accumulator produced by [TransactionProvider.statsBy].
class InstrumentStat {
  int spent = 0;
  int received = 0;
  int count = 0;
}

/// Why a sync attempt did not complete.
///
/// The two cases need different words and different actions: a denied
/// permission is fixed in Android settings, while a scan that threw is fixed by
/// retrying. Collapsing them into one "sync failed" message would leave the
/// user with no idea what to do.
enum SyncFailure {
  /// The SMS permission is not granted, so no inbox could be read.
  permissionDenied,

  /// The permission was granted but reading or parsing the inbox threw.
  scanFailed,
}
