import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';

/// Persists parsed transactions locally so the app never re-parses or
/// re-calls the AI for SMS messages it has already processed.
///
/// Storage layout (SharedPreferences):
///   "tx_cache_ids"   → JSON list of all cached SMS IDs  (quick existence check)
///   "tx_<id>"        → JSON object for each transaction
///   "tx_cache_meta"  → JSON object { lastSyncMs, count }
///
/// Usage:
///   final cache = TransactionCacheService();
///   await cache.init();
///
///   // Check before parsing
///   if (await cache.contains(smsId)) {
///     final tx = await cache.get(smsId);
///     ...
///   }
///
///   // Save after parsing
///   await cache.put(transaction);
///
///   // Load everything on app start
///   final all = await cache.loadAll();
class TransactionCacheService {
  static const _idsKey = 'tx_cache_ids';
  static const _metaKey = 'tx_cache_meta';
  static const _prefix = 'tx_';

  late SharedPreferences _prefs;
  // In-memory ID set for O(1) lookups — avoids a prefs read per SMS
  final Set<String> _cachedIds = {};

  bool _initialised = false;

  // ─── INIT ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialised) return;
    _prefs = await SharedPreferences.getInstance();
    // Load the ID set into memory
    final raw = _prefs.getString(_idsKey);
    if (raw != null) {
      final list = (jsonDecode(raw) as List).cast<String>();
      _cachedIds.addAll(list);
    }
    _initialised = true;
    print('📦 Cache init — ${_cachedIds.length} transactions already cached');
  }

  // ─── EXISTENCE CHECK ───────────────────────────────────────────────────────

  /// O(1) check — uses in-memory set, no disk read.
  bool contains(String smsId) => _cachedIds.contains(smsId);

  /// Returns the IDs present in cache so the caller can skip them.
  Set<String> get cachedIds => Set.unmodifiable(_cachedIds);

  // ─── READ ──────────────────────────────────────────────────────────────────

  /// Loads a single cached transaction by SMS ID.
  /// Returns null if not found.
  Future<TransactionModel?> get(String smsId) async {
    _assertInit();
    final raw = _prefs.getString('$_prefix$smsId');
    if (raw == null) return null;
    try {
      return TransactionModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      print('⚠️ Cache corrupt for $smsId — evicting');
      await _evict(smsId);
      return null;
    }
  }

  /// Loads ALL cached transactions in one pass.
  /// Call this on app start to populate the provider immediately.
  Future<List<TransactionModel>> loadAll() async {
    _assertInit();
    final results = <TransactionModel>[];
    for (final id in _cachedIds) {
      final tx = await get(id);
      if (tx != null) results.add(tx);
    }
    print('📦 Cache loaded ${results.length} transactions');
    return results;
  }

  // ─── WRITE ─────────────────────────────────────────────────────────────────

  /// Persists a single transaction.
  Future<void> put(TransactionModel tx) async {
    _assertInit();
    await _prefs.setString('$_prefix${tx.id}', jsonEncode(tx.toJson()));
    if (_cachedIds.add(tx.id)) {
      // ID is new — persist the updated ID list
      await _flushIds();
    }
  }

  /// Batch-persist many transactions (more efficient than calling put() in a loop
  /// because _flushIds is called only once at the end).
  Future<void> putAll(List<TransactionModel> txs) async {
    _assertInit();
    bool dirty = false;
    for (final tx in txs) {
      await _prefs.setString('$_prefix${tx.id}', jsonEncode(tx.toJson()));
      if (_cachedIds.add(tx.id)) dirty = true;
    }
    if (dirty) await _flushIds();
    print('📦 Cache saved ${txs.length} new transactions');
  }

  // ─── INVALIDATION ──────────────────────────────────────────────────────────

  /// Removes a single transaction from cache (e.g. user manually deleted it).
  Future<void> remove(String smsId) async {
    _assertInit();
    await _evict(smsId);
  }

  /// Wipes the entire cache — use on "Clear data" in settings.
  Future<void> clearAll() async {
    _assertInit();
    for (final id in List.of(_cachedIds)) {
      await _prefs.remove('$_prefix$id');
    }
    _cachedIds.clear();
    await _prefs.remove(_idsKey);
    await _prefs.remove(_metaKey);
    print('🗑️ Cache cleared');
  }

  // ─── METADATA ──────────────────────────────────────────────────────────────

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

  /// Returns the DateTime of the last successful sync, or null if never synced.
  DateTime? get lastSyncTime {
    final raw = _prefs.getString(_metaKey);
    if (raw == null) return null;
    final ms = (jsonDecode(raw) as Map)['lastSyncMs'] as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  int get cachedCount => _cachedIds.length;

  // ─── PRIVATE ───────────────────────────────────────────────────────────────

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
