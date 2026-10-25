import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ledger_encryption_service.dart';

/// A deletion marker for the sync layer: the row identified by [syncId] was
/// removed locally at [deletedAtMs]. A later pull must not resurrect it.
@immutable
class LedgerTombstone {
  final String syncId;
  final String id;
  final int deletedAtMs;

  const LedgerTombstone({
    required this.syncId,
    required this.id,
    required this.deletedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'syncId': syncId,
        'id': id,
        'deletedAtMs': deletedAtMs,
      };

  static LedgerTombstone? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final syncId = raw['syncId'];
    final id = raw['id'];
    final deletedAtMs = raw['deletedAtMs'];
    if (syncId is! String || syncId.isEmpty || id is! String || id.isEmpty) {
      return null;
    }
    return LedgerTombstone(
      syncId: syncId,
      id: id,
      deletedAtMs: deletedAtMs is int ? deletedAtMs : 0,
    );
  }
}

/// Durable, encrypted store of deletion tombstones.
///
/// Tombstones are metadata for the sync layer only: they are never rendered
/// and never counted in totals. Like the ledger, contents are encrypted with
/// the shared ledger key. Everything here fails soft — if the key or storage
/// is unavailable the last error is recorded on [lastError] and an empty list
/// is returned, because recording a tombstone must never block removing data.
class LedgerTombstoneStore {
  /// Outside the `tx_` record namespace so no record id can collide.
  static const storeKey = 'tx_tombstones_enc_v1';

  static const defaultRetention = Duration(days: 30);

  final LedgerEncryptionService _encryption;

  /// The failure from the most recent [readAll]/[addAll], if any, surfaced the
  /// same way the ledger surfaces its own load errors.
  Object? lastError;

  LedgerTombstoneStore({LedgerEncryptionService? encryption})
      : _encryption = encryption ?? LedgerEncryptionService();

  /// Appends [tombstones], skipping entries whose [LedgerTombstone.syncId] is
  /// already recorded. Returns how many new entries were written.
  Future<int> addAll(Iterable<LedgerTombstone> tombstones) async {
    try {
      final existing = await readAll();
      final known = existing.map((t) => t.syncId).toSet();
      final fresh = <LedgerTombstone>[];
      for (final t in tombstones) {
        if (t.syncId.isEmpty || known.contains(t.syncId)) continue;
        known.add(t.syncId);
        fresh.add(t);
      }
      if (fresh.isEmpty) return 0;
      await _writeAll([...existing, ...fresh]);
      return fresh.length;
    } catch (error) {
      lastError = error;
      debugPrint('⚠️ Tombstone write failed (${error.runtimeType})');
      return 0;
    }
  }

  /// All tombstones, oldest deletion first. Fail-soft: unreadable or corrupt
  /// contents yield an empty list with [lastError] set.
  Future<List<LedgerTombstone>> readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storeKey);
      if (raw == null) return [];
      final clear = await _encryption.decryptText(raw);
      final decoded = jsonDecode(clear);
      if (decoded is! List) {
        throw const FormatException('tombstone list invalid');
      }
      final tombstones = decoded
          .map(LedgerTombstone.tryParse)
          .whereType<LedgerTombstone>()
          .toList();
      tombstones.sort((a, b) => a.deletedAtMs.compareTo(b.deletedAtMs));
      lastError = null;
      return tombstones;
    } catch (error) {
      lastError = error;
      debugPrint('⚠️ Tombstone read failed (${error.runtimeType})');
      return [];
    }
  }

  /// Drops tombstones older than [retention] (30 days by default). Returns
  /// how many were pruned.
  Future<int> pruneOlderThan({
    Duration retention = defaultRetention,
    DateTime? now,
  }) async {
    final all = await readAll();
    if (all.isEmpty) return 0;
    final cutoff =
        (now ?? DateTime.now()).millisecondsSinceEpoch - retention.inMilliseconds;
    final kept = [
      for (final t in all)
        if (t.deletedAtMs >= cutoff) t
    ];
    if (kept.length == all.length) return 0;
    await _writeAll(kept);
    return all.length - kept.length;
  }

  Future<void> _writeAll(List<LedgerTombstone> tombstones) async {
    final prefs = await SharedPreferences.getInstance();
    final encrypted = await _encryption.encryptText(
      jsonEncode([for (final t in tombstones) t.toJson()]),
    );
    if (!await prefs.setString(storeKey, encrypted)) {
      throw StateError('tombstone_write_failed');
    }
  }
}
