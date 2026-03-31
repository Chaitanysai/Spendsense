import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';
import '../services/sms_service.dart';
import '../services/smart_parser.dart';
import '../services/gemini_service.dart';
import '../services/transaction_cache_service.dart';

class TransactionProvider with ChangeNotifier {
  List<TransactionModel> _transactions = [];
  bool _isSyncing = false;
  bool _isLoadingCache = true; // true only during cold-boot cache read
  DateTime? _lastSynced;
  double _monthlyBudget = 20000.0;
  int _newThisSync = 0; // how many new messages were AI-parsed last sync

  final TransactionCacheService _cache = TransactionCacheService();
  late final Future<void> _initialization;

  List<TransactionModel> get transactions => _transactions;
  bool get isSyncing => _isSyncing;
  bool get isLoadingCache => _isLoadingCache;
  DateTime? get lastSynced => _lastSynced;
  double get monthlyBudget => _monthlyBudget;
  int get newThisSync => _newThisSync;

  TransactionProvider() {
    _initialization = _init();
  }

  // ─── INIT — instant cache load on startup ─────────────────────────────────

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
      print('📦 Loaded ${cached.length} transactions from cache');
    }
  }

  // ─── BUDGET ───────────────────────────────────────────────────────────────

  Future<void> _loadBudget() async {
    final prefs = await SharedPreferences.getInstance();
    _monthlyBudget = prefs.getDouble('monthly_budget') ?? 20000.0;
  }

  Future<void> setMonthlyBudget(double amount) async {
    _monthlyBudget = amount;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('monthly_budget', amount);
    notifyListeners();
  }

  // ─── COMPUTED GETTERS ─────────────────────────────────────────────────────

  double get totalExpenses {
    final now = DateTime.now();
    return _transactions
        .where((t) =>
            t.type == TransactionType.expense &&
            !t.isExcluded &&
            t.date.month == now.month &&
            t.date.year == now.year)
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  String get topCategory {
    if (_transactions.isEmpty) return "None";
    final now = DateTime.now();
    final Map<String, double> totals = {};
    for (var t in _transactions.where((t) =>
        t.type == TransactionType.expense &&
        !t.isExcluded &&
        t.date.month == now.month &&
        t.date.year == now.year)) {
      totals[t.category] = (totals[t.category] ?? 0) + t.amount;
    }
    if (totals.isEmpty) return "None";
    return totals.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  List<String> get availableCategories {
    final cats = _transactions.map((t) => t.category).toSet().toList();
    cats.sort();
    return cats;
  }

  // ─── INCREMENTAL SYNC ─────────────────────────────────────────────────────
  //
  // Flow:
  //   1. Load already-seen SMS IDs from disk
  //   2. Fetch inbox from device
  //   3. Keep ONLY IDs not seen before → these are genuinely new
  //   4. Parse new ones (regex → AI fallback)
  //   5. Merge into existing list
  //   6. Persist updated transactions + ID set to disk

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

      // 1. Fetch inbox
      final messages = await smsService.fetchTransactionSms();

      // 2. Financial filter
      final financial = messages.where((msg) {
        final body = msg.body.toLowerCase();
        final isDebit = body.contains("debited") ||
            body.contains("spent") ||
            body.contains("paid");
        final isInvalid = body.contains("otp") ||
            body.contains("credited") ||
            body.contains("refund");
        final hasAmount =
            body.contains("rs") || body.contains("₹") || body.contains("inr");
        return isDebit && !isInvalid && hasAmount;
      }).toList();

      // 3. New only
      final newMessages = financial
          .where((msg) => msg.id.isNotEmpty && !_cache.contains(msg.id))
          .toList();

      print('📩 Financial SMS total: ${financial.length}');
      print('🆕 New to parse: ${newMessages.length}');

      if (newMessages.isEmpty) {
        _lastSynced = DateTime.now();
        await _cache.updateSyncMeta();
        _isSyncing = false;
        notifyListeners();
        return;
      }

      // 4. Parse new messages
      final newTxs = <TransactionModel>[];

      for (final msg in newMessages) {
        TransactionModel? parsed;

        // Regex first (fast, no tokens)
        parsed = await smartParser.parse(msg.body, msg.id, msg.date);

        // AI if regex failed or got Unknown merchant
        if (parsed == null || parsed.merchant == "Unknown") {
          final aiResult = await aiParser.parseSms(msg.body, msg.id, msg.date);
          if (aiResult != null) parsed = aiResult;
        }

        if (parsed != null) {
          newTxs.add(parsed);
        }
      }

      // 5. Merge — remove stale duplicates then add new
      final newIds = newTxs.map((t) => t.id).toSet();
      _transactions.removeWhere((t) => newIds.contains(t.id));
      _transactions.addAll(newTxs);
      _transactions.sort((a, b) => b.date.compareTo(a.date));

      _newThisSync = newTxs.length;

      // 6. Persist cache and sync metadata
      await Future.wait([
        _cache.putAll(newTxs),
        _cache.updateSyncMeta(),
      ]);

      _lastSynced = DateTime.now();
      print('✅ Sync complete — ${newTxs.length} new transactions');
    } catch (e) {
      print('❌ Sync error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // ─── FORCE FULL RE-SYNC ───────────────────────────────────────────────────
  // Clears all caches and re-parses everything with AI.
  // Useful after prompt improvements or category changes.

  Future<void> forceFullResync() async {
    await _initialization;
    await _cache.clearAll();
    _transactions.clear();
    _lastSynced = null;
    notifyListeners();
    await syncFromSms();
  }

  // ─── MUTATIONS ────────────────────────────────────────────────────────────

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
      );
      await _cache.put(_transactions[index]);
      notifyListeners();
    }
  }

  Future<void> addTransaction(TransactionModel transaction) async {
    await _initialization;
    _transactions.add(transaction);
    _transactions.sort((a, b) => b.date.compareTo(a.date));
    await _cache.put(transaction);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _initialization;
    _transactions.clear();
    _lastSynced = null;
    _newThisSync = 0;
    await _cache.clearAll();
    notifyListeners();
  }
}
