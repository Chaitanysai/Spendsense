import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/services/auth/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Account deletion is a Play Store requirement and the privacy policy already
/// promises it. The behaviour worth pinning is the **order**: the Firebase
/// account must be gone before local data is wiped. Otherwise a network failure
/// leaves either a deleted-account shell that wipes someone's ledger, or a
/// ledger that survives an account that no longer exists.
class _FakeAuth extends AuthService {
  _FakeAuth({this.deleteThrows, this.requiresReauth = false});

  final Object? deleteThrows;
  final bool requiresReauth;

  final List<String> calls = [];
  int deleteCount = 0;

  @override
  Future<void> deleteAccount() async {
    calls.add('deleteAccount');
    deleteCount++;
    if (requiresReauth) throw const ReauthenticationRequiredException();
    if (deleteThrows != null) throw deleteThrows!;
  }

  @override
  Future<void> reauthenticate({
    required String email,
    required String password,
  }) async {
    calls.add('reauthenticate:$password');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AuthProvider.deleteAccount', () {
    test('deletes the account before touching local data', () async {
      final auth = _FakeAuth();
      final provider = AuthProvider(auth: auth);
      var ledgerCleared = false;

      await provider.deleteAccount(
        clearLocalLedger: () async {
          // The account must already be gone when this runs.
          expect(auth.deleteCount, 1,
              reason: 'local data must not be wiped before the account is deleted');
          ledgerCleared = true;
        },
      );

      expect(ledgerCleared, isTrue);
      expect(auth.calls.first, 'deleteAccount');
    });

    test('a failed delete leaves local data untouched', () async {
      final auth = _FakeAuth(deleteThrows: StateError('network'));
      final provider = AuthProvider(auth: auth);
      var ledgerCleared = false;

      await expectLater(
        provider.deleteAccount(
          clearLocalLedger: () async => ledgerCleared = true,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        ledgerCleared,
        isFalse,
        reason: 'a failed delete must not wipe the ledger',
      );
    });

    test('a stale session surfaces as reauthentication, not deletion', () async {
      final auth = _FakeAuth(requiresReauth: true);
      final provider = AuthProvider(auth: auth);
      var ledgerCleared = false;

      await expectLater(
        provider.deleteAccount(
          clearLocalLedger: () async => ledgerCleared = true,
        ),
        throwsA(isA<ReauthenticationRequiredException>()),
      );

      expect(ledgerCleared, isFalse);
      expect(provider.errorMessage, contains('password'));
    });

    test('supplying a password re-authenticates first', () async {
      final auth = _FakeAuth();
      final provider = AuthProvider(auth: auth);

      await provider.deleteAccount(
        password: 'hunter2',
        clearLocalLedger: () async {},
      );

      expect(auth.calls, ['reauthenticate:hunter2', 'deleteAccount']);
    });
  });
}
