import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Raised when App Check cannot be started.
///
/// [code] is stable for logging; [message] is safe to show and never includes
/// exception details (which can carry Firebase configuration).
class AppCheckBootstrapException implements Exception {
  final String code;
  final String message;

  const AppCheckBootstrapException(this.code, this.message);

  @override
  String toString() => 'AppCheckBootstrapException($code)';
}

/// The activation seam used by [AppCheckBootstrap].
///
/// Tests inject a fake so provider selection can be observed without touching
/// platform channels. The default implementation wraps
/// `FirebaseAppCheck.instance.activate`.
typedef AppCheckActivation = Future<void> Function({
  required AndroidAppCheckProvider providerAndroid,
});

/// The single mechanism that starts App Check.
///
/// Implemented by [AppCheckBootstrap] and injected into the assistant token
/// provider, so both app startup and the assistant share one activation.
abstract interface class AppCheckGate {
  /// Activates App Check once and only once. A failed activation is not cached,
  /// so a later call may retry; the failure is never replaced by a debug
  /// provider in a release build.
  Future<void> ensureActivated();
}

/// One-shot, idempotent App Check activation shared by app startup and the
/// assistant token provider.
///
/// Provider selection:
/// * release builds always use Play Integrity;
/// * debug builds use the debug provider only when a debug token is explicitly
///   supplied through `--dart-define=FIREBASE_APP_CHECK_DEBUG_TOKEN` (never
///   committed); otherwise they also use Play Integrity.
class AppCheckBootstrap implements AppCheckGate {
  AppCheckBootstrap({
    AppCheckActivation? activation,
    bool? debugBuild,
    String? debugToken,
    bool Function()? firebaseAvailable,
  })  : _activation = activation ?? _activateWithSdk,
        _debugBuild = debugBuild ?? kDebugMode,
        _debugToken = debugToken ??
            const String.fromEnvironment('FIREBASE_APP_CHECK_DEBUG_TOKEN'),
        _firebaseAvailable =
            firebaseAvailable ?? (() => Firebase.apps.isNotEmpty);

  /// The process-wide instance used by startup and the assistant provider.
  static final AppCheckBootstrap shared = AppCheckBootstrap();

  final AppCheckActivation _activation;
  final bool _debugBuild;
  final String _debugToken;
  final bool Function() _firebaseAvailable;
  Future<void>? _pending;

  @override
  Future<void> ensureActivated() {
    final existing = _pending;
    if (existing != null) return existing;
    final created = _activate();
    _pending = created;
    created.then<void>(
      (_) {},
      onError: (Object _) {
        // Keep the failure visible to this caller but allow a later retry.
        _pending = null;
      },
    );
    return created;
  }

  AndroidAppCheckProvider _androidProvider() {
    final token = _debugToken.trim();
    if (_debugBuild && token.isNotEmpty) {
      return AndroidDebugProvider(debugToken: token);
    }
    return const AndroidPlayIntegrityProvider();
  }

  Future<void> _activate() async {
    if (!_firebaseAvailable()) {
      throw const AppCheckBootstrapException(
        'app_check_not_configured',
        'Secure app verification is not configured in this build.',
      );
    }
    try {
      await _activation(providerAndroid: _androidProvider());
    } on AppCheckBootstrapException {
      rethrow;
    } catch (_) {
      // Never include exception details: they can contain Firebase config.
      throw const AppCheckBootstrapException(
        'app_check_activation_failed',
        'Secure app verification could not start.',
      );
    }
  }

  static Future<void> _activateWithSdk({
    required AndroidAppCheckProvider providerAndroid,
  }) {
    return FirebaseAppCheck.instance.activate(
      providerAndroid: providerAndroid,
    );
  }
}
