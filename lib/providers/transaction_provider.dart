import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';
import '../utils/bank_recognizer.dart';
import '../services/sms_service.dart';
import '../services/smart_parser.dart';
import '../services/gemini_service.dart';
import '../services/transaction_cache_service.dart';
import '../services/budget_monitor_service.dart';

class TransactionProvider with ChangeNotifier {
  static const _smsScanStartKey = 'sms_scan_start_date';

  List<TransactionModel> _transactions = [];
  bool _isSyncing = false;
  bool _isLoadingCache = true;
  DateTime? _lastSynced;
  DateTime? _smsScanStartDate;
  double _monthlyBudget = 20000.0;
  int _newThisSync = 0;

  final TransactionCacheService _cache = TransactionCacheService();
  final BudgetMonitorService _budgetMonitor = BudgetMonitorService();
  late final Future<void> _initialization;

  List<TransactionModel> get transactions => _transactions;

  /// Replaces the in-memory list without touching the database or SMS pipeline,
  /// so aggregation behaviour can be tested without platform plugins.
  @visibleForTesting
  void debugSeed(List<TransactionModel> seed) {
    _transactions = List.of(seed);
    notifyListeners();
  }

  bool get isSyncing => _isSyncing;
  bool get isLoadingCache => _isLoadingCache;
  DateTime? get lastSynced => _lastSynced;
  DateTime? get smsScanStartDate => _smsScanStartDate;
  bool get hasSmsScanStartDate => _smsScanStartDate != null;
  double get monthlyBudget => _monthlyBudget;
  int get newThisSync => _newThisSync;

  TransactionProvider() {
    _initialization = _init();
  }

  Future<void> _init() async {
    await _cache.init();
    await Future.wait([_loadBudget(), _loadFromCache()]);
    _lastSynced = _cache.lastSyncTime;
    _isLoadingCache = false;
    notifyListeners();
  }

  Future<void> _loadFromCache() async {
    final cached = await _cache.loadAll();
    if (cached.isNotEmpty) {
      _transactions = cached;
      debugPrint('📦 Loaded ${cached.length} transactions from local DB');
    }
  }

  Future<void> _loadBudget() async {
    final prefs = await SharedPreferences.getInstance();
    _monthlyBudget = prefs.getDouble('monthly_budget') ?? 20000.0;
    final startRaw = prefs.getString(_smsScanStartKey);
    _smsScanStartDate = startRaw == null ? null : DateTime.tryParse(startRaw);
  }

  Future<void> setMonthlyBudget(double amount) async {
    _monthlyBudget = amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('monthly_budget', amount);
    notifyListeners();
  }

  Future<void> setSmsScanStartDate(
    DateTime date, {
    bool resync = true,
  }) async {
    final normalized = DateTime(date.year, date.month, date.day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_smsScanStartKey, normalized.toIso8601String());
    _smsScanStartDate = normalized;
    notifyListeners();

    if (resync) {
      await forceFullResync();
    }
  }

  Iterable<TransactionModel> expensesInPeriod(DateTimeRange? period) {
    if (period == null) {
      final now = DateTime.now();
      return _transactions.where((t) =>
          t.type == TransactionType.expense &&
          !t.isExcluded &&
          _isLocalMonth(t.date, now));
    }

    final exactStart =
        DateTime(period.start.year, period.start.month, period.start.day);
    final exactEnd = DateTime(period.end.year, period.end.month, period.end.day)
        .add(const Duration(days: 1));

    return _transactions.where((t) =>
        t.type == TransactionType.expense &&
        !t.isExcluded &&
        !_localDate(t.date).isBefore(exactStart) &&
        _localDate(t.date).isBefore(exactEnd));
  }

  DateTime _localDate(DateTime date) => date.toLocal();

  bool _isLocalMonth(DateTime value, DateTime day) {
    final local = _localDate(value);
    return local.year == day.year && local.month == day.month;
  }

  double totalExpensesForPeriod(DateTimeRange? period) =>
      expensesInPeriod(period).fold(0.0, (sum, t) => sum + t.amount);

  double get totalExpenses => totalExpensesForPeriod(null);

  String topCategoryForPeriod(DateTimeRange? period) {
    if (_transactions.isEmpty) return "None";
    final Map<String, double> totals = {};
    for (final t in expensesInPeriod(period)) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
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

  double get totalTrackedExpenses =>
      trackedExpenses.fold(0.0, (sum, t) => sum + t.amount);

  String get topTrackedCategory {
    final totals = <String, double>{};
    for (final t in trackedExpenses) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    if (totals.isEmpty) return 'None';
    return totals.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  /// Roll-up of tracked transactions by a payment attribute — method, bank or
  /// account. Kept here so the grouping rule (excluded transactions never
  /// count, a blank attribute means "Other") has a single owner.
  Map<String, InstrumentStat> statsBy(
      String? Function(TransactionModel transaction) keyOf) {
    final stats = <String, InstrumentStat>{};
    for (final t in trackedTransactions) {
      final raw = keyOf(t)?.trim();
      // Null, blank and the literal unknown label (case-insensitive) all share
      // the existing 'Other' bucket, so a stored "Others" never splits off.
      final key = (raw == null ||
              raw.isEmpty ||
              raw.toLowerCase() ==
                  TransactionModel.unknownBankLabel.toLowerCase())
          ? 'Other'
          : raw;
      final stat = stats.putIfAbsent(key, InstrumentStat.new);
      stat.count++;
      if (t.type == TransactionType.income) {
        stat.received += t.amount;
      } else {
        stat.spent += t.amount;
      }
    }
    return stats;
  }

  Future<void> syncFromSms() async {
    await _initialization;
    _isSyncing = true;
    _newThisSync = 0;
    notifyListeners();

    try {
      final smsService = SmsService();
      final smartParser = SmartParser();
      final aiParser = GeminiService();

      final hasPermission = await smsService.requestPermissions();
      if (!hasPermission) {
        _isSyncing = false;
        notifyListeners();
        return;
      }

      final messages = await smsService.fetchTransactionSms(
        fromDate: _smsScanStartDate,
      );

      final newMessages = messages
          .where((msg) => msg.id.isNotEmpty && !_cache.contains(msg.id))
          .toList();

      debugPrint('📩 SMS fetched: ${messages.length}');
      debugPrint('🆕 New to process: ${newMessages.length}');

      if (newMessages.isEmpty) {
        _lastSynced = DateTime.now();
        await _cache.updateSyncMeta();
        _isSyncing = false;
        notifyListeners();
        return;
      }

      final newTxs = <TransactionModel>[];

      for (final msg in newMessages) {
        if (!SmartParser.isDebitExpenseSms(msg.body)) {
          debugPrint(
            'SMS FILTER: REJECT reason=${SmartParser.debitSmsRejectionReason(msg.body)}',
          );
          await _cache.markRejected(msg.id);
          continue;
        }
        final localResult = await smartParser.parse(msg.body, msg.id, msg.date);

        TransactionModel? finalResult;
        if (localResult != null && localResult.confidence >= 0.8) {
          finalResult = localResult;
          debugPrint(
              '⚡ Local High-Confidence (${localResult.confidence}): ${localResult.merchant} ₹${localResult.amount}');
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
          newTxs.add(finalResult);
          final newIds = {finalResult.id};
          _transactions.removeWhere((t) => newIds.contains(t.id));
          _transactions.add(finalResult);
          _transactions.sort((a, b) => b.date.compareTo(a.date));
          _newThisSync++;
          await _cache.put(finalResult);
          notifyListeners(); // Yield to UI
        } else {
          // Both local and AI rejected this valid-looking debit
          await _cache.markRejected(msg.id);
        }
      }

      await Future.wait([
        _cache.updateSyncMeta(),
      ]);

      _lastSynced = DateTime.now();
      debugPrint(
          '✅ Sync complete — ${newTxs.length} new transactions saved locally');

      await _budgetMonitor.checkBudgetAlert(this);
    } catch (e) {
      debugPrint('❌ Sync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> forceFullResync() async {
    await _initialization;
    // A rescan can only rebuild transactions that came from SMS. Manually added
    // entries have no source message to re-parse, so keep them rather than
    // destroying user data when the scan date is changed.
    final manual = _transactions
        .where((t) => t.source == 'Manual')
        .toList(growable: false);
    await _cache.clearAll();
    _transactions.clear();
    _lastSynced = null;
    if (manual.isNotEmpty) {
      _transactions.addAll(manual);
      await _cache.putAll(manual);
    }
    notifyListeners();
    await syncFromSms();
  }

  Future<void> toggleExclude(String id) async {
    await _initialization;
    final index = _transactions.indexWhere((t) => t.id == id);
    if (index != -1) {
      _transactions[index] = _transactions[index].copyWith(
        isExcluded: !_transactions[index].isExcluded,
      );
      await _cache.put(_transactions[index]);
      notifyListeners();
    }
  }

  Future<void> updateCategory(String id, String newCategory) async {
    await _initialization;
    final index = _transactions.indexWhere((t) => t.id == id);
    if (index != -1) {
      _transactions[index] = _transactions[index].copyWith(
        category: newCategory,
        needsReview: false,
      );
      await _cache.put(_transactions[index]);
      notifyListeners();
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
    final index = _transactions.indexWhere((t) => t.id == id);
    if (index == -1) return;

    _transactions[index] = _transactions[index].copyWith(
      amount: amount,
      merchant: merchant,
      category: category,
      type: type,
      isExcluded: isExcluded,
      needsReview: false,
      // A supplied value (including an empty string, which clears the bank)
      // wins; omitting it preserves whatever was already stored.
      bank: bank,
    );
    await _cache.put(_transactions[index]);
    notifyListeners();
  }

  Future<void> addTransaction(TransactionModel transaction) async {
    await _initialization;
    _transactions.add(transaction);
    _transactions.sort((a, b) => b.date.compareTo(a.date));
    await _cache.put(transaction);
    notifyListeners();
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

  Future<void> clearAll() async {
    await _initialization;
    _transactions.clear();
    _lastSynced = null;
    _newThisSync = 0;
    await _cache.clearAll();
    notifyListeners();
  }

  // ─── BACKUP EXPORT / IMPORT HELPERS ───────────────────────────────────────

  Future<String> exportBackupJson() async {
    await _initialization;
    return await _cache.exportToJsonString();
  }

  Future<int> importBackupJson(String jsonString,
      {bool replace = false}) async {
    await _initialization;
    final count =
        await _cache.importFromJsonString(jsonString, replace: replace);
    await _loadFromCache();
    notifyListeners();
    return count;
  }

  // Aliases for SettingsScreen compatibility
  Future<String> exportToJson() => exportBackupJson();
  Future<int> importFromJson(String jsonString) => importBackupJson(jsonString);
}

/// Mutable accumulator produced by [TransactionProvider.statsBy].
class InstrumentStat {
  double spent = 0;
  double received = 0;
  int count = 0;
}
