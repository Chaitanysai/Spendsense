import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction_model.dart';

/// Handles two layers of caching:
///
/// 1. **Transaction cache** — the full parsed list, loaded instantly on app open.
/// 2. **Parsed SMS ID set** — tracks which SMS IDs have already been sent to AI,
///    so we never waste tokens re-parsing the same message.
class LegacyCacheFormatException implements Exception {
  final String message;

  const LegacyCacheFormatException(this.message);

  @override
  String toString() => 'LegacyCacheFormatException: $message';
}

class CacheService {
  static const _txKey = 'cached_transactions_v1';
  static const _txKeyV2 = 'cached_transactions_v2';
  static const _legacyUnitKey = 'cached_transactions_v1_unit';
  static const _wholeRupeeMarker = 'INR_WHOLE_RUPEES_V1';
  static const _parsedIdsKey = 'parsed_sms_ids_v1';

  // ─── TRANSACTION CACHE ────────────────────────────────────────────────────

  /// Saves only the explicit v2 paise format.
  Future<void> saveTransactions(List<TransactionModel> txs) async {
    final prefs = await SharedPreferences.getInstance();
    final value = jsonEncode({
      'schemaVersion': 2,
      'currency': 'INR',
      'amountUnit': 'paise',
      'transactions': [for (final tx in txs) tx.toJson()],
    });
    if (!await prefs.setString(_txKeyV2, value)) {
      throw const LegacyCacheFormatException('The cache could not be saved.');
    }
  }

  /// Loads only records with an explicit v2 paise marker.
  Future<List<TransactionModel>> loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_txKeyV2);
    if (current != null) return _decodeV2(current);

    final legacy = prefs.getString(_txKey);
    if (legacy != null && legacy.isNotEmpty) {
      throw const LegacyCacheFormatException(
          'The legacy cache has no trusted money-unit marker.');
    }
    return [];
  }

  /// Converts old records only through this explicit whole-rupee operation.
  /// The old source key remains untouched after successful verification.
  Future<List<TransactionModel>> migrateLegacyWholeRupeeCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_txKey);
    if (raw == null || raw.isEmpty) return [];
    final existingMarker = prefs.getString(_legacyUnitKey);
    if (existingMarker != null && existingMarker != _wholeRupeeMarker) {
      throw const LegacyCacheFormatException(
          'The legacy cache unit marker is unsupported.');
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const LegacyCacheFormatException('The legacy cache is malformed.');
    }
    final converted = [
      for (final entry in decoded) _decodeLegacyWholeRupee(entry),
    ];
    final value = jsonEncode({
      'schemaVersion': 2,
      'currency': 'INR',
      'amountUnit': 'paise',
      'transactions': [for (final tx in converted) tx.toJson()],
    });
    if (!await prefs.setString(_txKeyV2, value)) {
      throw const LegacyCacheFormatException(
          'The migrated cache could not be saved.');
    }
    await prefs.setString(_legacyUnitKey, _wholeRupeeMarker);
    final verified = _decodeV2(prefs.getString(_txKeyV2)!);
    if (verified.length != converted.length ||
        !_sameTransactions(verified, converted)) {
      throw const LegacyCacheFormatException(
          'The migrated cache failed verification.');
    }
    return verified;
  }

  List<TransactionModel> _decodeV2(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded['schemaVersion'] != 2 ||
        decoded['currency'] != 'INR' ||
        decoded['amountUnit'] != 'paise' ||
        decoded['transactions'] is! List) {
      throw const LegacyCacheFormatException(
          'The cache money unit is missing or unsupported.');
    }
    final transactions = <TransactionModel>[];
    for (final entry in decoded['transactions'] as List) {
      if (entry is! Map) {
        throw const LegacyCacheFormatException(
            'The cache contains a malformed transaction.');
      }
      final tx = TransactionModel.fromJson(Map<String, dynamic>.from(entry));
      if (tx.amountMinor < 0) {
        throw const LegacyCacheFormatException('The cache amount is invalid.');
      }
      transactions.add(tx);
    }
    return transactions;
  }

  TransactionModel _decodeLegacyWholeRupee(Object? entry) {
    if (entry is! Map) {
      throw const LegacyCacheFormatException(
          'The legacy cache contains a malformed transaction.');
    }
    final json = Map<String, dynamic>.from(entry);
    if (json.containsKey('schemaVersion') || json.containsKey('amountMinor')) {
      throw const LegacyCacheFormatException(
          'The legacy cache contains mixed money schemas.');
    }
    final amount = json['amount'];
    if (json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        amount is! int ||
        amount < 0 ||
        (json['type'] != 'expense' && json['type'] != 'income') ||
        json['date'] is! String ||
        DateTime.tryParse(json['date'] as String) == null) {
      throw const LegacyCacheFormatException(
          'The legacy cache record is ambiguous.');
    }
    json
      ..remove('amount')
      ..['schemaVersion'] = 2
      ..['currency'] = 'INR'
      ..['amountMinor'] = amount * 100;
    try {
      return TransactionModel.fromJson(json);
    } catch (_) {
      throw const LegacyCacheFormatException(
          'The legacy cache record is invalid.');
    }
  }

  bool _sameTransactions(
      List<TransactionModel> left, List<TransactionModel> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (jsonEncode(left[i].toJson()) != jsonEncode(right[i].toJson())) {
        return false;
      }
    }
    return true;
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
      debugPrint('⚠️ markParsed error: $e');
    }
  }

  Future<void> clearParsedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_parsedIdsKey);
  }
}
