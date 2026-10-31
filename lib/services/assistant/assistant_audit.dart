import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/assistant_models.dart';
import '../../models/transaction_model.dart';
import '../ledger_encryption_service.dart';

class AssistantAuditException implements Exception {
  final String message;
  const AssistantAuditException(this.message);

  @override
  String toString() => 'AssistantAuditException: $message';
}

/// One AI-initiated change. Contains no prompt text.
///
/// Sensitive snapshots are stored only inside the encrypted audit record; they
/// exist so a deletion can be undone and remain local.
class AssistantAuditEntry {
  final String id;
  final AssistantChangeType type;
  final DateTime createdAt;
  final int affectedCount;
  final int totalMinor;
  final List<String> transactionIds;
  final Map<String, bool> previousExcluded;
  final List<Map<String, dynamic>> deletedSnapshots;
  final bool undone;

  const AssistantAuditEntry({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.affectedCount,
    required this.totalMinor,
    required this.transactionIds,
    required this.previousExcluded,
    required this.deletedSnapshots,
    this.undone = false,
  });

  AssistantAuditEntry copyWith({bool? undone}) => AssistantAuditEntry(
        id: id,
        type: type,
        createdAt: createdAt,
        affectedCount: affectedCount,
        totalMinor: totalMinor,
        transactionIds: transactionIds,
        previousExcluded: previousExcluded,
        deletedSnapshots: deletedSnapshots,
        undone: undone ?? this.undone,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'createdAt': createdAt.toIso8601String(),
        'affectedCount': affectedCount,
        'totalMinor': totalMinor,
        'transactionIds': transactionIds,
        'previousExcluded': previousExcluded,
        'deletedSnapshots': deletedSnapshots,
        'undone': undone,
      };

  static AssistantAuditEntry fromJson(Map<String, dynamic> json) {
    final type = AssistantChangeType.values
        .where((t) => t.name == json['type'])
        .firstOrNull;
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (type == null ||
        createdAt == null ||
        json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        json['affectedCount'] is! int ||
        json['totalMinor'] is! int ||
        json['transactionIds'] is! List ||
        json['previousExcluded'] is! Map ||
        json['deletedSnapshots'] is! List) {
      throw const AssistantAuditException(
          'The assistant audit record is invalid.');
    }
    final ids = (json['transactionIds'] as List).whereType<String>().toList();
    final previous = <String, bool>{};
    for (final entry in (json['previousExcluded'] as Map).entries) {
      if (entry.key is! String || entry.value is! bool) {
        throw const AssistantAuditException(
            'The assistant audit record is invalid.');
      }
      previous[entry.key as String] = entry.value as bool;
    }
    final snapshots = <Map<String, dynamic>>[];
    for (final snapshot in json['deletedSnapshots'] as List) {
      if (snapshot is! Map) {
        throw const AssistantAuditException(
            'The assistant audit record is invalid.');
      }
      snapshots.add(Map<String, dynamic>.from(snapshot));
    }
    return AssistantAuditEntry(
      id: json['id'] as String,
      type: type,
      createdAt: createdAt,
      affectedCount: json['affectedCount'] as int,
      totalMinor: json['totalMinor'] as int,
      transactionIds: ids,
      previousExcluded: previous,
      deletedSnapshots: snapshots,
      undone: json['undone'] == true,
    );
  }
}

abstract interface class AssistantAuditRepository {
  Future<List<AssistantAuditEntry>> load();

  Future<void> append(AssistantAuditEntry entry);

  Future<void> markUndone(String id);

  Future<void> clear();
}

/// Encrypted audit repository. AES-256-GCM with the existing ledger key and a
/// record-bound envelope; never plaintext SharedPreferences.
class EncryptedAssistantAuditRepository implements AssistantAuditRepository {
  static const prefsKey = 'assistant_audit_enc_v1';
  static const recordId = 'assistant.audit.v1';
  static const maxEntries = 20;

  final LedgerEncryptionService _encryption;
  Future<void> _lock = Future.value();

  EncryptedAssistantAuditRepository({LedgerEncryptionService? encryption})
      : _encryption = encryption ?? LedgerEncryptionService();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _lock.then((_) => action());
    _lock = run.then((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<List<AssistantAuditEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    // Must be growable: append() calls entries.add on the result, and a
    // const [] would throw on the first append to an empty store.
    if (raw == null || raw.isEmpty) return <AssistantAuditEntry>[];
    try {
      final clear = await _encryption.decryptText(
        raw,
        expectedRecordId: recordId,
      );
      final decoded = jsonDecode(clear);
      if (decoded is! Map ||
          decoded['schemaVersion'] != 1 ||
          decoded['entries'] is! List) {
        throw const AssistantAuditException(
            'The assistant audit record is invalid.');
      }
      final entries = <AssistantAuditEntry>[];
      for (final item in decoded['entries'] as List) {
        if (item is! Map) {
          throw const AssistantAuditException(
              'The assistant audit record is invalid.');
        }
        entries.add(
          AssistantAuditEntry.fromJson(Map<String, dynamic>.from(item)),
        );
      }
      entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return entries;
    } on AssistantAuditException {
      rethrow;
    } catch (_) {
      throw const AssistantAuditException(
          'The assistant audit record could not be read.');
    }
  }

  @override
  Future<void> append(AssistantAuditEntry entry) => _serialized(() async {
        final entries = await load();
        entries.add(entry);
        final retained = entries.length <= maxEntries
            ? entries
            : entries.sublist(entries.length - maxEntries);
        await _write(retained);
      });

  @override
  Future<void> markUndone(String id) => _serialized(() async {
        final entries = await load();
        final index = entries.indexWhere((e) => e.id == id);
        if (index == -1) {
          throw const AssistantAuditException(
              'That change is no longer available to undo.');
        }
        entries[index] = entries[index].copyWith(undone: true);
        await _write(entries);
      });

  @override
  Future<void> clear() => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(prefsKey);
      });

  Future<void> _write(List<AssistantAuditEntry> entries) async {
    final encoded = await _encryption.encryptText(
      jsonEncode({
        'schemaVersion': 1,
        'entries': [for (final e in entries) e.toJson()],
      }),
      recordId: recordId,
    );
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(prefsKey, encoded)) {
      throw const AssistantAuditException(
          'The assistant audit record could not be saved.');
    }
    // Read back to prove the record was stored and is decryptable.
    final check =
        await _encryption.decryptText(encoded, expectedRecordId: recordId);
    if (check.isEmpty) {
      throw const AssistantAuditException(
          'The assistant audit record failed verification.');
    }
  }
}

/// Shared mapping for the encrypted audit copy of a deleted row.
Map<String, dynamic> auditSnapshot(TransactionModel tx) => tx.toJson();

TransactionModel transactionFromAuditSnapshot(Map<String, dynamic> json) =>
    TransactionModel.fromJson(json);
