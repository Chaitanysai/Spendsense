import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/services/app_check/app_check_bootstrap.dart';
import 'package:spendsense/services/assistant/assistant_auth.dart';

/// Counts activation requests without touching platform channels.
class _CountingGate implements AppCheckGate {
  _CountingGate({this.failure});

  final AppCheckBootstrapException? failure;
  var calls = 0;

  @override
  Future<void> ensureActivated() async {
    calls++;
    final error = failure;
    if (error != null) throw error;
  }
}

void main() {
  FirebaseAppCheckTokenProvider providerWith(AppCheckGate gate,
      {bool configured = true}) {
    return FirebaseAppCheckTokenProvider(
      appCheckGate: gate,
      configured: configured,
      // Keep the post-activation token read from blocking a unit test: there is
      // no Firebase plugin here, so the platform call fails immediately with a
      // sanitized auth_unavailable rather than waiting on an answer.
      timeout: const Duration(milliseconds: 200),
    );
  }

  test('the token provider reuses the shared App Check gate', () async {
    final gate = _CountingGate();

    // Pin the exact sanitized code. It proves the gate ran and control reached
    // the token read: before the token read the only failures are
    // auth_not_configured (asserted elsewhere) and the gate's own propagated
    // error. A regression that skipped the gate cannot produce this value.
    await expectLater(
      providerWith(gate).getToken(),
      throwsA(
        isA<AssistantAuthException>()
            .having((error) => error.code, 'code', 'auth_unavailable')
            .having(
              (error) => error.message,
              'message',
              'The assistant could not verify this app installation. Local '
                  'assistant commands still work.',
            ),
      ),
    );
    expect(gate.calls, 1);
  });

  test('an activation failure is surfaced as a safe assistant error', () async {
    final gate = _CountingGate(
      failure: const AppCheckBootstrapException(
        'app_check_activation_failed',
        'Secure app verification could not start.',
      ),
    );

    await expectLater(
      providerWith(gate).getToken(),
      throwsA(
        isA<AssistantAuthException>()
            .having(
                (error) => error.code, 'code', 'app_check_activation_failed')
            .having(
              (error) => error.message,
              'message',
              'Secure app verification could not start.',
            ),
      ),
    );
    expect(gate.calls, 1);
  });

  test('an unconfigured build never reaches the gate', () async {
    final gate = _CountingGate();

    await expectLater(
      providerWith(gate, configured: false).getToken(),
      throwsA(
        isA<AssistantAuthException>()
            .having((error) => error.code, 'code', 'auth_not_configured'),
      ),
    );
    expect(gate.calls, 0);
  });

  test(
      'without an explicit override the provider derives configuration from '
      'the platform and Firebase state', () async {
    // No `configured` override: this exercises the production default
    // (AssistantAuthConfig.isAndroid && Firebase.apps.isNotEmpty). Under the
    // test binding there is no Firebase app, so the provider must fail closed
    // before touching the gate. A regression that made the default permissive
    // would turn this into 'auth_timeout' and fail here.
    final gate = _CountingGate();

    await expectLater(
      FirebaseAppCheckTokenProvider(
        appCheckGate: gate,
        timeout: const Duration(milliseconds: 200),
      ).getToken(),
      throwsA(
        isA<AssistantAuthException>()
            .having((error) => error.code, 'code', 'auth_not_configured'),
      ),
    );
    expect(gate.calls, 0);
  });
}
