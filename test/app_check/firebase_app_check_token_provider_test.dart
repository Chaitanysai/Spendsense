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
      // Keep the post-activation token read from blocking a unit test; it has
      // no platform channel here and resolves to a safe failure.
      timeout: const Duration(milliseconds: 200),
    );
  }

  test('the token provider reuses the shared App Check gate', () async {
    final gate = _CountingGate();

    await expectLater(
      providerWith(gate).getToken(),
      throwsA(isA<AssistantAuthException>()),
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
}
