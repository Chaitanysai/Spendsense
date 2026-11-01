import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth/auth_service.dart';
import '../services/auth/user_profile_repository.dart';

/// Account state for SpendSense.
///
/// Firebase Authentication (Email/Password) is the account system; Firestore
/// `users/{uid}` holds the profile. The expense ledger itself stays local and
/// encrypted, so the app still opens, records and reports with no connection.
///
/// Every Firebase touch is optional: when Firebase is not initialized (unit
/// tests, previews) the provider reports `isFirebaseAvailable == false` and the
/// app falls back to its offline-only behaviour instead of failing.
class AuthProvider with ChangeNotifier {
  AuthProvider({AuthService? auth, UserProfileRepository? profiles})
      : _auth = auth ?? const AuthService(),
        _profiles = profiles ?? const UserProfileRepository() {
    // A persisted session is known synchronously, so the first frame already
    // renders the right tree instead of flashing the sign-in screen.
    final user = _auth.currentUser;
    _user = user;
    _isSignedIn = user != null;
    if (user != null) {
      _email = user.email ?? '';
      _name = user.displayName ?? '';
    }
    _subscription = _auth.authStateChanges().listen(
          _onAuthStateChanged,
          onError: (Object _) {
            // A broken auth channel must not take the local app down with it.
          },
        );
    _restoreLocalProfile();
  }

  /// Neutral placeholder shown when the user has not set a personal name. It is
  /// never used as a greeting name.
  static const String defaultName = 'SpendSense User';
  static const String guestName = 'Guest';

  static const String _nameKey = 'name';
  static const String _emailKey = 'email';
  static const String _imageKey = 'profileImageBase64';

  /// Sign-in and profile writes can hang on a flaky network; the UI must not.
  static const Duration _requestTimeout = Duration(seconds: 30);

  final AuthService _auth;
  final UserProfileRepository _profiles;
  StreamSubscription<User?>? _subscription;

  User? _user;
  bool _isSignedIn = false;
  bool _isBusy = false;
  bool _isResolved = false;
  String _name = '';
  String _email = '';
  String? _profileImageBase64;
  String? _errorMessage;

  bool get isFirebaseAvailable => _auth.isAvailable;

  bool get isSignedIn => _isSignedIn;

  /// Legacy name kept for call sites that predate Firebase accounts.
  bool get isLoggedIn => _isSignedIn;

  /// False until the first auth-state event (or the initial cached session)
  /// has settled; the app gate uses it to avoid a wrong-tree flash.
  bool get isResolved => _isResolved;

  bool get isBusy => _isBusy;

  /// User-safe failure text for the last failed action, or null.
  String? get errorMessage => _errorMessage;

  String? get uid => _user?.uid;

  /// Profile name: the trimmed stored value, or [defaultName] when the user has
  /// not set (or has cleared) a name.
  String get name {
    final trimmed = _name.trim();
    return trimmed.isEmpty ? defaultName : trimmed;
  }

  /// Name suitable for a personalised greeting, or '' when no personal name is
  /// set — letting callers omit the suffix instead of printing "User".
  String get greetingName {
    final trimmed = _name.trim();
    if (trimmed.isEmpty || trimmed == defaultName || trimmed == guestName) {
      return '';
    }
    return trimmed;
  }

  /// Signed-in address, or the offline placeholder when there is no account.
  String get email {
    final trimmed = _email.trim();
    return trimmed.isEmpty ? 'user@spendsense.local' : trimmed;
  }

  String? get profileImageBase64 => _profileImageBase64;

  bool get hasProfileImage =>
      _profileImageBase64 != null && _profileImageBase64!.isNotEmpty;

  Uint8List? get profileImageBytes =>
      hasProfileImage ? base64Decode(_profileImageBase64!) : null;

  void clearError() {
    if (_errorMessage == null) return;
    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> signIn({required String email, required String password}) {
    return _run(() async {
      final user = await _auth
          .signIn(email: email, password: password)
          .timeout(_requestTimeout);
      await _adoptUser(user, persistLocal: true);
    });
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String displayName,
  }) {
    return _run(() async {
      final trimmedName = displayName.trim();
      final user = await _auth
          .signUp(
            email: email,
            password: password,
            displayName: trimmedName,
          )
          .timeout(_requestTimeout);
      _name = trimmedName;
      _email = user.email ?? email.trim();
      await _adoptUser(user, persistLocal: true);
    });
  }

  Future<bool> sendPasswordReset(String email) {
    return _run(() async {
      await _auth.sendPasswordReset(email).timeout(_requestTimeout);
    });
  }

  Future<void> signOut() async {
    _setBusy(true);
    try {
      await _auth.signOut().timeout(_requestTimeout);
    } catch (_) {
      // Local state is cleared regardless: never leave a person stranded in an
      // account they asked to leave.
    } finally {
      _user = null;
      _isSignedIn = false;
      _name = '';
      _email = '';
      _errorMessage = null;
      _setBusy(false);
      await _cacheProfile(name: '', email: '');
    }
  }

  /// Permanently deletes the account and everything of the person's on the
  /// device.
  ///
  /// Order matters: the Firebase account is deleted first, so a network failure
  /// cannot leave a deleted-account shell that can never be signed into again.
  /// Only after the account is truly gone does the local ledger and profile get
  /// cleared — an account deletion that left financial data on the phone would
  /// be worse than not deleting at all.
  ///
  /// Throws [ReauthenticationRequiredException] when Firebase wants a fresh
  /// sign-in; the caller re-authenticates and calls this again.
  Future<void> deleteAccount({
    required Future<void> Function() clearLocalLedger,
    String? password,
  }) async {
    _setBusy(true);
    _errorMessage = null;
    try {
      if (password != null) {
        await _auth
            .reauthenticate(email: email, password: password)
            .timeout(_requestTimeout);
      }
      await _auth.deleteAccount().timeout(_requestTimeout);

      // Account is gone; remove every local trace.
      await clearLocalLedger();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_nameKey);
      await prefs.remove(_emailKey);
      await prefs.remove(_imageKey);
    } on ReauthenticationRequiredException {
      _errorMessage = 'Enter your password to confirm deletion.';
      rethrow;
    } catch (_) {
      _errorMessage = 'Your account could not be deleted. Try again.';
      rethrow;
    } finally {
      _user = null;
      _isSignedIn = false;
      _name = '';
      _email = '';
      _setBusy(false);
    }
  }

  /// Saves the user's preferred display name. An empty value clears it back to
  /// the neutral placeholder; the greeting then drops the name suffix.
  Future<void> updateName(String value) async {
    final trimmed = value.trim();
    _name = trimmed;
    notifyListeners();
    await _cacheProfile(name: trimmed);
    final user = _user;
    if (user == null) return;
    // Both writes are best-effort and independent: the local name is already
    // applied, and the cloud copy catches up when the network allows.
    await _auth.updateDisplayName(trimmed).catchError((Object _) {});
    await _profiles.updateDisplayName(uid: user.uid, displayName: trimmed);
  }

  Future<void> updateProfileImage(String? base64Image) async {
    final prefs = await SharedPreferences.getInstance();
    if (base64Image == null || base64Image.isEmpty) {
      await prefs.remove(_imageKey);
      _profileImageBase64 = null;
    } else {
      await prefs.setString(_imageKey, base64Image);
      _profileImageBase64 = base64Image;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (_isBusy) return false;
    _errorMessage = null;
    _setBusy(true);
    try {
      await action();
      return true;
    } catch (error) {
      _errorMessage = authMessageForError(error);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    _isBusy = value;
    notifyListeners();
  }

  /// Applies the account identity locally, then lets the cloud profile refine
  /// it. Ordered so the UI is correct even when Firestore is unreachable.
  Future<void> _adoptUser(User user, {required bool persistLocal}) async {
    _user = user;
    _isSignedIn = true;
    _email = user.email ?? _email;
    _name = user.displayName ?? _name;
    if (_name.trim().isEmpty || _email.trim().isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      _name = _name.trim().isEmpty ? (prefs.getString(_nameKey) ?? '') : _name;
      _email =
          _email.trim().isEmpty ? (prefs.getString(_emailKey) ?? '') : _email;
    }
    if (persistLocal) {
      await _cacheProfile(name: _name, email: _email);
    }
    notifyListeners();

    final profile = await _profiles.loadProfile(user.uid);
    if (profile != null && profile.displayName.isNotEmpty) {
      _name = profile.displayName;
      notifyListeners();
      await _cacheProfile(name: _name);
    } else {
      await _profiles.saveProfile(
        uid: user.uid,
        displayName: _name,
        email: _email,
      );
    }
  }

  void _onAuthStateChanged(User? user) {
    _isResolved = true;
    if (user == null) {
      _user = null;
      _isSignedIn = false;
      if (_name.isNotEmpty || _email.isNotEmpty) {
        // Transient session loss (token revocation, sign-out elsewhere) must
        // not silently keep showing the previous account's identity.
        _name = '';
        _email = '';
        _cacheProfile(name: '', email: '');
      }
      notifyListeners();
      return;
    }
    if (_user?.uid == user.uid && _isSignedIn) {
      _user = user;
      notifyListeners();
      return;
    }
    _isSignedIn = true;
    _adoptUser(user, persistLocal: true);
    notifyListeners();
  }

  Future<void> _restoreLocalProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _profileImageBase64 = prefs.getString(_imageKey);
      if (_name.trim().isEmpty) _name = prefs.getString(_nameKey) ?? '';
      if (_email.trim().isEmpty) _email = prefs.getString(_emailKey) ?? '';
    } catch (_) {
      // No plugin/backing store (widget tests, previews): the in-memory values
      // are still valid, so nothing needs to be reported.
    }
    _isResolved = true;
    notifyListeners();
  }

  Future<void> _cacheProfile({String? name, String? email}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (name != null) {
        if (name.isEmpty) {
          await prefs.remove(_nameKey);
        } else {
          await prefs.setString(_nameKey, name);
        }
      }
      if (email != null) {
        if (email.isEmpty) {
          await prefs.remove(_emailKey);
        } else {
          await prefs.setString(_emailKey, email);
        }
      }
    } catch (_) {
      // Caching is an optimisation for the next cold start, never a
      // requirement for the current session.
    }
  }
}
