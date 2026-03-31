import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';

/// Handles two layers of caching:
///
/// 1. **Transaction cache** — the full parsed list, loaded instantly on app open.
/// 2. **Parsed SMS ID set** — tracks which SMS IDs have already been sent to AI,
///    so we never waste tokens re-parsing the same message.
class CacheService {
  static const _txKey = 'cached_transactions_v1';
  static const _parsedIdsKey = 'parsed_sms_ids_v1';

  // ─── TRANSACTION CACHE ────────────────────────────────────────────────────

  /// Save the full transaction list to disk.
  Future<void> saveTransactions(List<TransactionModel> txs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(txs.map((t) => _txToJson(t)).toList());
      await prefs.setString(_txKey, encoded);
    } catch (e) {
      print('⚠️ Cache save error: $e');
    }
  }

  /// Load the transaction list from disk. Returns [] if nothing cached yet.
  Future<List<TransactionModel>> loadTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_txKey);
      if (raw == null || raw.isEmpty) return [];

      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _txFromJson(e as Map<String, dynamic>))
          .whereType<TransactionModel>()
          .toList();
    } catch (e) {
      print('⚠️ Cache load error: $e');
      return [];
    }
  }

  Future<void> clearTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_txKey);
  }

  // ─── PARSED SMS ID TRACKING ───────────────────────────────────────────────

  /// Returns the set of SMS IDs that have already been parsed by AI.
  Future<Set<String>> loadParsedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_parsedIdsKey) ?? [];
      return raw.toSet();
    } catch (e) {
      return {};
    }
  }

  /// Marks a batch of SMS IDs as parsed. Merges with existing set.
  Future<void> markParsed(Set<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_parsedIdsKey) ?? [];
      final merged = {...existing, ...ids}.toList();

      // Cap at 2000 entries — oldest IDs are dropped to prevent unbounded growth
      if (merged.length > 2000) {
        merged.removeRange(0, merged.length - 2000);
      }

      await prefs.setStringList(_parsedIdsKey, merged);
    } catch (e) {
      print('⚠️ markParsed error: $e');
    }
  }

  Future<void> clearParsedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_parsedIdsKey);
  }

  // ─── SERIALIZATION ────────────────────────────────────────────────────────

  Map<String, dynamic> _txToJson(TransactionModel t) => {
        'id': t.id,
        'amount': t.amount,
        'type': t.type == TransactionType.income ? 'income' : 'expense',
        'merchant': t.merchant,
        'category': t.category,
        'paymentMethod': t.paymentMethod,
        'date': t.date.toIso8601String(),
        'time': t.time,
        'originalSms': t.originalSms,
        'isExcluded': t.isExcluded,
      };

  TransactionModel? _txFromJson(Map<String, dynamic> j) {
    try {
      return TransactionModel(
        id: j['id'] as String,
        amount: (j['amount'] as num).toDouble(),
        type: j['type'] == 'income'
            ? TransactionType.income
            : TransactionType.expense,
        merchant: j['merchant'] as String? ?? 'Unknown',
        category: j['category'] as String? ?? 'Other',
        paymentMethod: j['paymentMethod'] as String? ?? 'SMS',
        date: DateTime.parse(j['date'] as String),
        time: j['time'] as String? ?? '00:00',
        originalSms: j['originalSms'] as String? ?? '',
        isExcluded: j['isExcluded'] as bool? ?? false,
      );
    } catch (e) {
      print('⚠️ Failed to deserialize transaction: $e');
      return null;
    }
  }
}
