import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Authentication failure that is safe to show (and log by code only).
class AssistantAuthException implements Exception {
  final String code;
  final String message;

  const AssistantAuthException(this.code, this.message);

  @override
  String toString() => 'AssistantAuthException($code)';
}

abstract interface class AssistantAuthTokenProvider {
  bool get isConfigured;

  /// Returns a short-lived Firebase App Check token, or throws
  /// [AssistantAuthException]. The token is sent only in a request header.
  Future<String> getToken();
}

abstract interface class AssistantIdentityTokenProvider {
  bool get isConfigured;

  /// Returns a fresh Firebase Authentication ID token for the signed-in user.
  /// The token is sent only in the Authorization header.
  Future<String> getIdToken();
}

/// Authentication build configuration.
///
/// Firebase itself is initialized once at app startup from
/// `firebase_options.dart`; the assistant reuses that app rather than requiring
/// duplicate project/app/key values through `--dart-define`.
abstract final class AssistantAuthConfig {
  /// Debug-only App Check token. Set it in the local build command after
  /// registering it in Firebase Console -> App Check -> Manage debug tokens.
  /// Never commit it.
  static const String debugToken =
      String.fromEnvironment('FIREBASE_APP_CHECK_DEBUG_TOKEN');

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

/// Firebase App Check + Play Integrity attestation for real Android builds.
///
/// This is app-integrity authentication, separate from the signed-in user's
/// Firebase Authentication identity. A request is accepted only after the
/// backend verifies both.
class FirebaseAppCheckTokenProvider implements AssistantAuthTokenProvider {
  static Future<void>? _initialization;
  final Duration timeout;

  const FirebaseAppCheckTokenProvider({
    this.timeout = const Duration(seconds: 15),
  });

  @override
  bool get isConfigured =>
      AssistantAuthConfig.isAndroid && Firebase.apps.isNotEmpty;

  static Future<void> _initialize() async {
    if (Firebase.apps.isEmpty) {
      throw const AssistantAuthException(
        'auth_not_configured',
        'Secure app authentication is not configured in this build.',
      );
    }
    final useDebugProvider =
        kDebugMode && AssistantAuthConfig.debugToken.trim().isNotEmpty;
    await FirebaseAppCheck.instance.activate(
      providerAndroid: useDebugProvider
          ? AndroidDebugProvider(
              debugToken: AssistantAuthConfig.debugToken.trim(),
            )
          : const AndroidPlayIntegrityProvider(),
    );
  }

  Future<void> _ensureInitialized() {
    final existing = _initialization;
    if (existing != null) return existing;
    final created = _initialize();
    _initialization = created;
    created.then<void>(
      (_) {},
      onError: (Object _) {
        // Allow a later attempt while preserving the safe error for this call.
        _initialization = null;
      },
    );
    return created;
  }

  @override
  Future<String> getToken() async {
    if (!isConfigured) {
      throw const AssistantAuthException(
        'auth_not_configured',
        'Secure app authentication is not configured in this build.',
      );
    }
    try {
      await _ensureInitialized().timeout(timeout);
      var token = await FirebaseAppCheck.instance.getToken().timeout(timeout);
      token ??= await FirebaseAppCheck.instance.getToken(true).timeout(timeout);
      if (token == null || token.trim().isEmpty) {
        throw const AssistantAuthException(
          'auth_unavailable',
          'The assistant could not verify this app installation.',
        );
      }
      return token;
    } on AssistantAuthException {
      rethrow;
    } on TimeoutException {
      throw const AssistantAuthException(
        'auth_timeout',
        'App verification timed out. Local assistant commands still work.',
      );
    } catch (_) {
      // Never include exception details: they can contain Firebase config.
      throw const AssistantAuthException(
        'auth_unavailable',
        'The assistant could not verify this app installation. Local '
            'assistant commands still work.',
      );
    }
  }
}

/// Firebase Authentication ID token for the currently signed-in SpendSense
/// account. This does not initiate sign-in or alter the existing account UX.
class FirebaseAssistantIdentityTokenProvider
    implements AssistantIdentityTokenProvider {
  final Duration timeout;

  const FirebaseAssistantIdentityTokenProvider({
    this.timeout = const Duration(seconds: 15),
  });

  @override
  bool get isConfigured =>
      AssistantAuthConfig.isAndroid && Firebase.apps.isNotEmpty;

  @override
  Future<String> getIdToken() async {
    if (!isConfigured) {
      throw const AssistantAuthException(
        'auth_not_configured',
        'Secure app authentication is not configured in this build.',
      );
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const AssistantAuthException(
        'not_signed_in',
        'Sign in to use the cloud assistant. Local commands still work.',
      );
    }
    try {
      // The SDK returns a cached token until it is near expiry and refreshes it
      // automatically; no token is cached or persisted by SpendSense itself.
      final token = await user.getIdToken().timeout(timeout);
      if (token == null || token.trim().isEmpty) {
        throw const AssistantAuthException(
          'auth_unavailable',
          'Your sign-in session could not be verified. Local commands still work.',
        );
      }
      return token;
    } on AssistantAuthException {
      rethrow;
    } on TimeoutException {
      throw const AssistantAuthException(
        'auth_timeout',
        'Sign-in verification timed out. Local commands still work.',
      );
    } catch (_) {
      // Never include exception details: they can contain token metadata.
      throw const AssistantAuthException(
        'auth_unavailable',
        'Your sign-in session could not be verified. Local commands still work.',
      );
    }
  }
}
