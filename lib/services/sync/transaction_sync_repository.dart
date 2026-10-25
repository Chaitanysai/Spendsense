import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../models/transaction_model.dart';

/// One remote ledger row, either a live transaction or a deletion tombstone.
class RemoteTransaction {
  const RemoteTransaction({
    required this.syncId,
    required this.updatedAtMs,
    required this.deletedAtMs,
    required this.deviceId,
    this.data,
  });

  final String syncId;
  final int updatedAtMs;

  /// Non-null when the record was deleted on some device. Tombstones are kept
  /// so a pull cannot bring a deleted transaction back.
  final int? deletedAtMs;
  final String? deviceId;

  /// The transaction fields, or null for a tombstone.
  final Map<String, dynamic>? data;

  bool get isDeleted => deletedAtMs != null;
}

/// Firestore transport for the ledger: `users/{uid}/transactions/{syncId}`.
///
/// Deliberately dumb — it moves records and reports what changed. Ordering,
/// conflict resolution and local application live in the sync service, so this
/// class stays easy to reason about and to fake in tests.
class TransactionSyncRepository {
  const TransactionSyncRepository({
    this.timeout = const Duration(seconds: 20),
  });

  /// Firestore batches are capped at 500 writes; stay well under it so a large
  /// ledger is pushed in a few bounded round trips instead of one huge call.
  static const int _batchSize = 400;

  final Duration timeout;

  bool get isAvailable => Firebase.apps.isNotEmpty;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('transactions');

  /// Uploads the given records as authoritative copies.
  ///
  /// The raw bank message (`originalSms`) is never uploaded: it is empty for
  /// new records, and legacy copies can contain the whole SMS body including
  /// account fragments. Everything the ledger needs to render and total a
  /// transaction is included.
  Future<void> pushTransactions({
    required String uid,
    required List<TransactionModel> transactions,
    required String deviceId,
  }) async {
    if (transactions.isEmpty || !isAvailable) return;
    for (var start = 0; start < transactions.length; start += _batchSize) {
      final slice = transactions.skip(start).take(_batchSize);
      final batch = FirebaseFirestore.instance.batch();
      for (final transaction in slice) {
        final data = Map<String, dynamic>.from(transaction.toJson())
          ..remove('originalSms')
          ..['updatedAtMs'] = transaction.updatedAtMs
          ..['deviceId'] = deviceId;
        batch.set(_collection(uid).doc(transaction.syncId), data);
      }
      await batch.commit().timeout(timeout);
    }
  }

  /// Records a deletion so other devices and fresh installs learn about it.
  Future<void> pushDeletion({
    required String uid,
    required String syncId,
    required int deletedAtMs,
    required String deviceId,
  }) {
    if (!isAvailable) return Future<void>.value();
    return _collection(uid)
        .doc(syncId)
        .set(<String, Object?>{
          'syncId': syncId,
          'deletedAtMs': deletedAtMs,
          'updatedAtMs': deletedAtMs,
          'deviceId': deviceId,
        })
        .timeout(timeout);
  }

  /// Removes a tombstone once both sides are past the retention window.
  Future<void> deleteRecord({
    required String uid,
    required String syncId,
  }) {
    if (!isAvailable) return Future<void>.value();
    return _collection(uid).doc(syncId).delete().timeout(timeout);
  }

  /// Live view of the account's ledger. Firestore delivers the cached copy
  /// first when offline, then the server copy once the connection returns.
  Stream<List<RemoteTransaction>> watch(String uid) {
    if (!isAvailable) return const Stream<List<RemoteTransaction>>.empty();
    return _collection(uid).snapshots().map((snapshot) {
      final result = <RemoteTransaction>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final updatedAtMs = _asInt(data['updatedAtMs']);
        if (updatedAtMs == null) continue;
        final deletedAtMs = _asInt(data['deletedAtMs']);
        final syncId = (data['syncId'] as String?)?.trim();
        result.add(
          RemoteTransaction(
            syncId: (syncId == null || syncId.isEmpty) ? doc.id : syncId,
            updatedAtMs: updatedAtMs,
            deletedAtMs: deletedAtMs,
            deviceId: data['deviceId'] as String?,
            data: deletedAtMs == null ? data : null,
          ),
        );
      }
      return result;
    });
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    return null;
  }
}
