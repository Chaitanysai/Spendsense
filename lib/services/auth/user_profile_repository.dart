import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// The signed-in person's cloud profile: `users/{uid}` in Firestore.
///
/// This document is the account record, not the ledger. Financial data stays in
/// the local encrypted database; only identity fields live here.
class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.email,
    this.createdAt,
    this.updatedAt,
  });

  final String displayName;
  final String email;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class UserProfileRepository {
  const UserProfileRepository({
    this.timeout = const Duration(seconds: 10),
  });

  /// Bounds every network call so an offline device never leaves the UI
  /// spinning; callers treat a timeout as "cloud copy unavailable".
  final Duration timeout;

  static const String _collection = 'users';

  bool get isAvailable => Firebase.apps.isNotEmpty;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      FirebaseFirestore.instance.collection(_collection).doc(uid);

  /// Creates the profile on first sign-in and refreshes `lastSeenAt` after.
  ///
  /// `createdAt` is written only when the document is new, so returning users
  /// keep their original join date. Entirely best-effort: a failure here never
  /// blocks sign-in, because the account itself is already valid.
  Future<void> saveProfile({
    required String uid,
    required String displayName,
    required String email,
  }) async {
    if (!isAvailable) return;
    try {
      final doc = _doc(uid);
      final existing = await doc.get().timeout(timeout);
      final now = FieldValue.serverTimestamp();
      final fields = <String, Object?>{
        'displayName': displayName.trim(),
        'email': email.trim(),
        'lastSeenAt': now,
        'updatedAt': now,
      };
      if (!existing.exists) {
        fields['createdAt'] = now;
        fields['schemaVersion'] = 1;
      }
      await doc.set(fields, SetOptions(merge: true)).timeout(timeout);
    } catch (_) {
      // Offline or rules-denied: the local profile mirror remains authoritative
      // until the next successful connection.
    }
  }

  /// Returns the cloud profile, or null when it cannot be read (offline, no
  /// document yet, or Firebase not initialized).
  Future<UserProfile?> loadProfile(String uid) async {
    if (!isAvailable) return null;
    try {
      final snapshot = await _doc(uid).get().timeout(timeout);
      final data = snapshot.data();
      if (data == null) return null;
      return UserProfile(
        displayName: (data['displayName'] as String? ?? '').trim(),
        email: (data['email'] as String? ?? '').trim(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
        updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Best-effort name update. A failure is not fatal: the local value is kept
  /// and retried on the next sign-in.
  Future<bool> updateDisplayName({
    required String uid,
    required String displayName,
  }) async {
    if (!isAvailable) return false;
    try {
      await _doc(uid).set(<String, Object?>{
        'displayName': displayName.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
