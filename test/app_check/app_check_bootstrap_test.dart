import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/services/app_check/app_check_bootstrap.dart';

void main() {
  AndroidAppCheckProvider? lastProvider;
  var activations = 0;

  Future<void> record({
    required AndroidAppCheckProvider providerAndroid,
  }) async {
    activations++;
    lastProvider = providerAndroid;
  }

  setUp(() {
    lastProvider = null;
    activations = 0;
  });

  AppCheckBootstrap build({
    bool debugBuild = false,
    String debugToken = '',
    bool firebaseAvailable = true,
    AppCheckActivation? activation,
  }) {
    return AppCheckBootstrap(
      activation: activation ?? record,
      debugBuild: debugBuild,
      debugToken: debugToken,
      firebaseAvailable: () => firebaseAvailable,
    );
  }

  test('release builds use Play Integrity even with a debug token present',
      () async {
    await build(debugBuild: false, debugToken: 'debug-token').ensureActivated();

    expect(activations, 1);
    expect(lastProvider, isA<AndroidPlayIntegrityProvider>());
  });

  test('debug builds use the debug provider only when a token is configured',
      () async {
    await build(debugBuild: true, debugToken: '  debug-token  ')
        .ensureActivated();

    expect(activations, 1);
    expect(lastProvider, isA<AndroidDebugProvider>());
    expect((lastProvider! as AndroidDebugProvider).debugToken, 'debug-token');
  });

  test('debug builds without a token fall back to Play Integrity', () async {
    await build(debugBuild: true, debugToken: '   ').ensureActivated();

    expect(lastProvider, isA<AndroidPlayIntegrityProvider>());
  });

  test('activation is idempotent across concurrent and later callers',
      () async {
    final bootstrap = build();

    await Future.wait([
      bootstrap.ensureActivated(),
      bootstrap.ensureActivated(),
      bootstrap.ensureActivated(),
    ]);
    await bootstrap.ensureActivated();

    expect(activations, 1);
  });

  test('a failed activation surfaces a safe error and can be retried',
      () async {
    var calls = 0;
    final bootstrap = build(
      activation: ({
        required AndroidAppCheckProvider providerAndroid,
      }) async {
        calls++;
        if (calls == 1) {
          throw StateError('contains-firebase-config');
        }
      },
    );

    await expectLater(
      bootstrap.ensureActivated(),
      throwsA(
        isA<AppCheckBootstrapException>()
            .having(
                (error) => error.code, 'code', 'app_check_activation_failed')
            .having(
              (error) => error.message,
              'message',
              isNot(contains('config')),
            ),
      ),
    );

    await bootstrap.ensureActivated();
    expect(calls, 2);
  });

  test('missing Firebase fails closed without attempting activation', () async {
    final bootstrap = build(firebaseAvailable: false);

    await expectLater(
      bootstrap.ensureActivated(),
      throwsA(
        isA<AppCheckBootstrapException>()
            .having((error) => error.code, 'code', 'app_check_not_configured'),
      ),
    );
    expect(activations, 0);
  });
}
