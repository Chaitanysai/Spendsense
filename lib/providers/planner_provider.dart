import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recurring_plan.dart';
import '../models/transaction_model.dart';
import '../services/ledger_encryption_service.dart';
import '../utils/budget_math.dart';
import '../utils/period_math.dart';

/// Category budget progress for one spending category.
class CategoryBudgetStatus {
  final String category;
  final BudgetProgress progress;

  const CategoryBudgetStatus(this.category, this.progress);
}

/// Owns user-defined planning data: category budgets, warning thresholds and
/// recurring bill plans.
///
/// * Budgets and plans contain financial amounts, so they are stored ENCRYPTED
///   with the same AES-256-GCM service and key as the ledger (record-bound
///   authenticated envelopes). They are never written as plaintext.
/// * Fail-closed: if stored data cannot be decrypted or parsed, [loadError] is
///   set and every write is refused — existing data is never overwritten with
///   an empty state. This provider never creates an encryption key; the ledger
///   owns key creation.
/// * Everything shown from here is derived from, or planned alongside, the
///   ledger. Nothing here writes to the ledger.
class PlannerProvider with ChangeNotifier {
  static const _budgetsPrefsKey = 'planner_category_budgets_enc_v1';
  static const _plansPrefsKey = 'planner_recurring_plans_enc_v1';
  static const _thresholdsPrefsKey = 'budget_alert_thresholds';
  static const budgetsRecordId = 'planner.category_budgets.v1';
  static const plansRecordId = 'planner.recurring_plans.v1';

  /// Largest accepted budget (₹100 crore).
  static const int maxBudgetMinor = 100000000000;

  final LedgerEncryptionService _encryption;

  Map<String, int> _categoryBudgets = {};
  List<RecurringPlan> _plans = [];
  List<int> _thresholds = List.of(kDefaultBudgetThresholds);
  Object? _loadError;
  bool _isLoaded = false;
  bool _disposed = false;
  Future<void> _writeLock = Future.value();
  late final Future<void> _initialization;

  PlannerProvider({LedgerEncryptionService? encryption})
      : _encryption = encryption ?? LedgerEncryptionService() {
    _initialization = _load();
  }

  @visibleForTesting
  Future<void> get ready => _initialization;

  bool get isLoaded => _isLoaded;

  /// Non-null when stored planner data could not be read; writes are refused.
  Object? get loadError => _loadError;
  bool get hasLoadError => _loadError != null;

  Map<String, int> get categoryBudgets => Map.unmodifiable(_categoryBudgets);
  List<RecurringPlan> get plans => List.unmodifiable(_plans);

  /// Enabled warning thresholds (whole percentages), sorted.
  List<int> get thresholds => List.unmodifiable(_thresholds);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _thresholds = _readThresholds(prefs);

      final budgets =
          await _readRecord(prefs, _budgetsPrefsKey, budgetsRecordId);
      if (budgets != null) _categoryBudgets = _decodeBudgets(budgets);

      final plans = await _readRecord(prefs, _plansPrefsKey, plansRecordId);
      if (plans != null) _plans = _decodePlans(plans);
    } catch (error) {
      // Leave in-memory state empty but LOCKED: nothing on disk is touched.
      _loadError = error;
      debugPrint('🔒 Planner data unreadable (${error.runtimeType}) — kept');
    }
    _isLoaded = true;
    _notify();
  }

  List<int> _readThresholds(SharedPreferences prefs) {
    final stored = prefs.getStringList(_thresholdsPrefsKey);
    if (stored == null) return List.of(kDefaultBudgetThresholds);
    return normalizeBudgetThresholds(stored.map(int.tryParse));
  }

  Future<Object?> _readRecord(
    SharedPreferences prefs,
    String prefsKey,
    String recordId,
  ) async {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return null;
    final clear =
        await _encryption.decryptText(raw, expectedRecordId: recordId);
    return jsonDecode(clear);
  }

  Map<String, int> _decodeBudgets(Object raw) {
    if (raw is! Map ||
        raw['schemaVersion'] != 1 ||
        raw['currency'] != 'INR' ||
        raw['budgets'] is! Map) {
      throw const FormatException('Budget record is invalid.');
    }
    final out = <String, int>{};
    for (final e in (raw['budgets'] as Map).entries) {
      final key = e.key;
      final value = e.value;
      if (key is! String ||
          key.trim().isEmpty ||
          value is! int ||
          value <= 0 ||
          value > maxBudgetMinor) {
        throw const FormatException('Budget entry is invalid.');
      }
      out[key] = value;
    }
    return out;
  }

  List<RecurringPlan> _decodePlans(Object raw) {
    if (raw is! Map ||
        raw['schemaVersion'] != 1 ||
        raw['currency'] != 'INR' ||
        raw['plans'] is! List) {
      throw const FormatException('Plan record is invalid.');
    }
    final plans = [
      for (final p in raw['plans'] as List) RecurringPlan.fromJson(p),
    ];
    if (plans.map((p) => p.id).toSet().length != plans.length) {
      throw const FormatException('Duplicate plan ids.');
    }
    return plans;
  }

  // ── Writing ───────────────────────────────────────────────────────────────

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _writeLock.then((_) => action());
    _writeLock = run.then((_) {}, onError: (_) {});
    return run;
  }

  void _requireWritable() {
    if (_loadError != null) {
      throw StateError(
          'Planner data could not be read, so changes are disabled to avoid '
          'overwriting it.');
    }
  }

  Future<void> _writeRecord(
      String prefsKey, String recordId, Object json) async {
    final encrypted =
        await _encryption.encryptText(jsonEncode(json), recordId: recordId);
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(prefsKey, encrypted)) {
      throw StateError('Planner data could not be saved.');
    }
  }

  Object _budgetsJson(Map<String, int> budgets) => {
        'schemaVersion': 1,
        'currency': 'INR',
        'budgets': budgets,
      };

  Object _plansJson(List<RecurringPlan> plans) => {
        'schemaVersion': 1,
        'currency': 'INR',
        'plans': [for (final p in plans) p.toJson()],
      };

  /// Sets or replaces the budget for [category]. Persist first, then commit
  /// in memory, so a failed write leaves the visible state unchanged.
  Future<void> setCategoryBudget(String category, int amountMinor) =>
      _serialized(() async {
        await _initialization;
        _requireWritable();
        final name = category.trim();
        if (name.isEmpty) throw ArgumentError.value(category, 'category');
        if (amountMinor <= 0 || amountMinor > maxBudgetMinor) {
          throw ArgumentError.value(amountMinor, 'amountMinor');
        }
        final next = {..._categoryBudgets, name: amountMinor};
        await _writeRecord(
            _budgetsPrefsKey, budgetsRecordId, _budgetsJson(next));
        _categoryBudgets = next;
        _notify();
      });

  Future<void> removeCategoryBudget(String category) => _serialized(() async {
        await _initialization;
        _requireWritable();
        if (!_categoryBudgets.containsKey(category)) return;
        final next = {..._categoryBudgets}..remove(category);
        await _writeRecord(
            _budgetsPrefsKey, budgetsRecordId, _budgetsJson(next));
        _categoryBudgets = next;
        _notify();
      });

  /// Warning thresholds are percentages, not amounts, so they live in ordinary
  /// preferences. Only the supported choices are accepted.
  Future<void> setThresholds(Iterable<int> values) async {
    await _initialization;
    final next = normalizeBudgetThresholds(values);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _thresholdsPrefsKey, [for (final t in next) t.toString()]);
    _thresholds = next;
    _notify();
  }

  Future<void> addPlan(RecurringPlan plan) => _serialized(() async {
        await _initialization;
        _requireWritable();
        plan.validate();
        if (_plans.any((p) => p.id == plan.id)) {
          throw ArgumentError.value(plan.id, 'plan.id', 'already exists');
        }
        final next = [..._plans, plan];
        await _writeRecord(_plansPrefsKey, plansRecordId, _plansJson(next));
        _plans = next;
        _notify();
      });

  Future<void> updatePlan(RecurringPlan plan) => _serialized(() async {
        await _initialization;
        _requireWritable();
        plan.validate();
        final index = _plans.indexWhere((p) => p.id == plan.id);
        if (index == -1) return;
        final next = [..._plans]..[index] = plan;
        await _writeRecord(_plansPrefsKey, plansRecordId, _plansJson(next));
        _plans = next;
        _notify();
      });

  Future<void> removePlan(String id) => _serialized(() async {
        await _initialization;
        _requireWritable();
        if (!_plans.any((p) => p.id == id)) return;
        final next = _plans.where((p) => p.id != id).toList();
        await _writeRecord(_plansPrefsKey, plansRecordId, _plansJson(next));
        _plans = next;
        _notify();
      });

  /// Moves a plan to its following due date. This only reschedules the plan;
  /// it never creates a ledger transaction.
  Future<void> markPlanPaid(String id) async {
    final plan = _plans.where((p) => p.id == id).firstOrNull;
    if (plan == null) return;
    await updatePlan(plan.advanced());
  }

  // ── Derived data ──────────────────────────────────────────────────────────

  /// Plans ordered by due date (soonest, including overdue, first).
  List<RecurringPlan> get upcomingPlans =>
      [..._plans]..sort((a, b) => a.nextDue.compareTo(b.nextDue));

  /// Estimated monthly commitment from all plans, in integer paise.
  int get plannedMonthlyCommitmentMinor =>
      _plans.fold<int>(0, (sum, p) => sum + p.monthlyEquivalentMinor);

  /// Plans due within [days] days of [today] (overdue included).
  List<RecurringPlan> dueWithin(DateTime today, int days) => [
        for (final p in upcomingPlans)
          if (p.daysUntilDue(today) <= days) p,
      ];

  /// Per-category budget progress for expenses in [period]. Excluded
  /// transactions never count; categories with a budget but no spending still
  /// appear (at zero).
  List<CategoryBudgetStatus> categoryStatuses(
    Iterable<TransactionModel> transactions,
    DateTimeRange period,
  ) =>
      computeCategoryStatuses(_categoryBudgets, transactions, period);
}

/// Pure, testable budget-vs-spend computation (integer paise only).
List<CategoryBudgetStatus> computeCategoryStatuses(
  Map<String, int> budgets,
  Iterable<TransactionModel> transactions,
  DateTimeRange period,
) {
  final spent = <String, int>{};
  for (final t in transactions) {
    if (t.type != TransactionType.expense || t.isExcluded) continue;
    if (!budgets.containsKey(t.category)) continue;
    if (!PeriodMath.containsLocalDate(period, t.date)) continue;
    spent[t.category] = (spent[t.category] ?? 0) + t.amountMinor;
  }
  final statuses = [
    for (final e in budgets.entries)
      CategoryBudgetStatus(
        e.key,
        BudgetProgress(spentMinor: spent[e.key] ?? 0, budgetMinor: e.value),
      ),
  ];
  // Most-used first so overspending surfaces at the top.
  statuses.sort((a, b) {
    final byPercent = b.progress.percentUsed.compareTo(a.progress.percentUsed);
    return byPercent != 0 ? byPercent : a.category.compareTo(b.category);
  });
  return statuses;
}
