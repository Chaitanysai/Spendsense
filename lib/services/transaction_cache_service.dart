import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';

/// SpendSense 2.0 Local Database & Repository
/// Persists parsed transactions locally so the app never re-parses or
/// re-calls the AI for SMS messages already processed.
/// Also supports JSON export and import for backup/restore.
class TransactionCacheService {
  static const _idsKey = 'tx_cache_ids';
  static const _rejectedIdsKey = 'tx_rejected_ids';
  static const _metaKey = 'tx_cache_meta';
  static const _prefix = 'tx_';

  late SharedPreferences _prefs;
  final Set<String> _cachedIds = {};
  final Set<String> _rejectedIds = {};
  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_idsKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<String>();
      _cachedIds.addAll(list);
    }
    final rawRejected = _prefs.getString(_rejectedIdsKey);
    if (rawRejected != null) {
      final list = (jsonDecode(rawRejected) as List).cast<String>();
      _rejectedIds.addAll(list);
    }
    _initialised = true;
    debugPrint(
        '📦 Local DB init — ${_cachedIds.length} txs, ${_rejectedIds.length} rejected');
  }

  bool contains(String smsId) =>
      _cachedIds.contains(smsId) || _rejectedIds.contains(smsId);

  Set<String> get cachedIds => Set.unmodifiable(_cachedIds);

  Future<TransactionModel?> get(String smsId) async {
    _assertInit();
    final raw = _prefs.getString('$_prefix$smsId');
    if (raw == null) return null;
    try {
      return TransactionModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('⚠️ DB corrupt for $smsId — evicting');
      await _evict(smsId);
      return null;
    }
  }

  Future<List<TransactionModel>> loadAll() async {
    _assertInit();
    final results = <TransactionModel>[];
    for (final id in _cachedIds) {
      final tx = await get(id);
      if (tx != null) results.add(tx);
    }
    results.sort((a, b) => b.date.compareTo(a.date));
    debugPrint('📦 Local DB loaded ${results.length} transactions');
    return results;
  }

  Future<void> put(TransactionModel tx) async {
    _assertInit();
    await _prefs.setString('$_prefix${tx.id}', jsonEncode(tx.toJson()));
    if (_cachedIds.add(tx.id)) {
      await _flushIds();
    }
  }

  Future<void> putAll(List<TransactionModel> txs) async {
    _assertInit();
    bool dirty = false;
    for (final tx in txs) {
      await _prefs.setString('$_prefix${tx.id}', jsonEncode(tx.toJson()));
      if (_cachedIds.add(tx.id)) dirty = true;
    }
    if (dirty) await _flushIds();
    debugPrint('📦 Local DB saved ${txs.length} transactions');
  }

  Future<void> remove(String smsId) async {
    _assertInit();
    await _evict(smsId);
  }

  Future<void> markRejected(String smsId) async {
    _assertInit();
    if (_rejectedIds.add(smsId)) {
      if (_rejectedIds.length > 5000) {
        final list = _rejectedIds.toList();
        _rejectedIds.clear();
        _rejectedIds.addAll(list.skip(1000));
      }
      await _prefs.setString(
          _rejectedIdsKey, jsonEncode(_rejectedIds.toList()));
    }
  }

  Future<void> clearAll() async {
    _assertInit();
    for (final id in List.of(_cachedIds)) {
      await _prefs.remove('$_prefix$id');
    }
    _cachedIds.clear();
    await _prefs.remove(_idsKey);
    await _prefs.remove(_metaKey);
    debugPrint('🗑️ Local DB cleared');
  }

  Future<void> updateSyncMeta() async {
    _assertInit();
    await _prefs.setString(
      _metaKey,
      jsonEncode({
        'lastSyncMs': DateTime.now().millisecondsSinceEpoch,
        'count': _cachedIds.length,
      }),
    );
  }

  DateTime? get lastSyncTime {
    final raw = _prefs.getString(_metaKey);
    if (raw == null) return null;
    final ms = (jsonDecode(raw) as Map)['lastSyncMs'] as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int get cachedCount => _cachedIds.length;

  // ─── JSON EXPORT / IMPORT BACKUP ──────────────────────────────────────────

  /// Exports all stored transactions as a formatted JSON string.
  Future<String> exportToJsonString() async {
    _assertInit();
    final allTxs = await loadAll();
    final exportData = {
      'version': '2.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'count': allTxs.length,
      'transactions': allTxs.map((t) => t.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  /// Imports transactions from a JSON backup string, merging or replacing.
  Future<int> importFromJsonString(String jsonString,
      {bool replace = false}) async {
    _assertInit();
    try {
      final decoded = jsonDecode(jsonString);
      List<dynamic> txList;
      if (decoded is Map && decoded.containsKey('transactions')) {
        txList = decoded['transactions'] as List<dynamic>;
      } else if (decoded is List) {
        txList = decoded;
      } else {
        throw FormatException('Invalid backup format');
      }

      if (replace) {
        await clearAll();
      }

      final importedTxs = txList
          .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
          .toList();

      await putAll(importedTxs);
      debugPrint('📥 Successfully imported ${importedTxs.length} transactions');
      return importedTxs.length;
    } catch (e) {
      debugPrint('❌ Import backup error: $e');
      rethrow;
    }
  }

  // ─── PRIVATE ────────────────────────────────_______________

  Future<void> _evict(String smsId) async {
    await _prefs.remove('$_prefix$smsId');
    if (_cachedIds.remove(smsId)) await _flushIds();
  }

  Future<void> _flushIds() async {
    await _prefs.setString(_idsKey, jsonEncode(_cachedIds.toList()));
  }

  void _assertInit() {
    assert(_initialised, 'Call TransactionCacheService.init() before using it');
  }
}
