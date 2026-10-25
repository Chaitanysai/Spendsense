import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// Thin, testable wrapper around Firebase Authentication.
///
/// Only Email/Password is supported. Everything here is optional at runtime:
/// when Firebase has not been initialized (unit tests, previews, a build with
/// no platform configuration) [isAvailable] is false and the caller falls back
/// to local-only behaviour instead of crashing.
class AuthService {
  const AuthService();

  /// True once `Firebase.initializeApp` has completed for this process.
  bool get isAvailable => Firebase.apps.isNotEmpty;

  FirebaseAuth get _auth {
    if (!isAvailable) {
      throw const AuthUnavailableException();
    }
    return FirebaseAuth.instance;
  }

  User? get currentUser => isAvailable ? FirebaseAuth.instance.currentUser : null;

  /// Emits on sign-in, sign-out and token refresh. Completes when Firebase is
  /// unavailable so callers can await it unconditionally.
  Stream<User?> authStateChanges() {
    if (!isAvailable) return const Stream<User?>.empty();
    return FirebaseAuth.instance.authStateChanges();
  }

  Future<User> signIn({required String email, required String password}) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) throw const AuthUnavailableException();
    return user;
  }

  Future<User> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw const AuthUnavailableException();
    }
    // A failed display-name write must never block an otherwise valid account.
    try {
      await user.updateDisplayName(displayName.trim());
    } on FirebaseAuthException {
      // Cosmetic only; the name still lives in the Firestore profile document.
    }
    return user;
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> updateDisplayName(String displayName) async {
    final user = currentUser;
    if (user == null) return;
    await user.updateDisplayName(displayName.trim());
  }
}

/// Raised when an auth call is attempted before Firebase is initialized.
class AuthUnavailableException implements Exception {
  const AuthUnavailableException();

  @override
  String toString() => 'AuthUnavailableException';
}

/// Maps Firebase's machine codes to copy a person can act on.
///
/// The raw exception is never surfaced: codes are stable, messages are not,
/// and provider messages can leak account-enumeration detail. Sign-in failures
/// deliberately share one message for "no such user" and "wrong password".
String authMessageForError(Object error) {
  if (error is AuthUnavailableException) {
    return 'Accounts are unavailable in this build. You can keep using '
        'SpendSense offline.';
  }
  if (error is TimeoutException) {
    return 'That took too long. Check your connection and try again.';
  }
  if (error is! FirebaseAuthException) {
    return 'Something went wrong. Please try again.';
  }
  switch (error.code) {
    case 'invalid-email':
      return 'That email address does not look right.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email or password is incorrect.';
    case 'email-already-in-use':
      return 'An account already exists for that email. Sign in instead.';
    case 'weak-password':
      return 'Choose a password with at least 8 characters.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a moment, then try again.';
    case 'network-request-failed':
      return 'No connection. Check your network and try again.';
    case 'operation-not-allowed':
      return 'Email accounts are not enabled for this app.';
    case 'requires-recent-login':
      return 'Sign in again to continue.';
    default:
      return 'Something went wrong. Please try again.';
  }
}
