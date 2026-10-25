import 'package:firebase_auth/firebase_auth.dart'
    show FirebaseAuthException, User;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/auth_provider.dart';
import 'package:spendsense/services/auth/auth_service.dart';

/// Stands in for a build with no Firebase configuration.
class _UnavailableAuthService extends AuthService {
  const _UnavailableAuthService();

  @override
  bool get isAvailable => false;

  @override
  Future<User> signIn({required String email, required String password}) {
    throw const AuthUnavailableException();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('authMessageForError', () {
    test('never distinguishes a missing account from a wrong password', () {
      final missing = authMessageForError(
        FirebaseAuthException(code: 'user-not-found'),
      );
      final wrong = authMessageForError(
        FirebaseAuthException(code: 'wrong-password'),
      );
      final invalid = authMessageForError(
        FirebaseAuthException(code: 'invalid-credential'),
      );

      expect(missing, wrong);
      expect(wrong, invalid);
    });

    test('maps the codes a person can act on', () {
      expect(
        authMessageForError(FirebaseAuthException(code: 'email-already-in-use')),
        contains('already exists'),
      );
      expect(
        authMessageForError(FirebaseAuthException(code: 'weak-password')),
        contains('8 characters'),
      );
      expect(
        authMessageForError(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
        contains('connection'),
      );
    });

    test('falls back to neutral copy for anything unknown', () {
      expect(
        authMessageForError(FirebaseAuthException(code: 'some-new-code')),
        'Something went wrong. Please try again.',
      );
      expect(authMessageForError(StateError('boom')), isNotEmpty);
    });

    test('reports that accounts are unavailable rather than blaming the user',
        () {
      expect(
        authMessageForError(const AuthUnavailableException()),
        contains('offline'),
      );
    });
  });

  group('AuthProvider without Firebase', () {
    test('reports accounts as unavailable instead of crashing', () {
      final provider = AuthProvider(auth: const _UnavailableAuthService());
      addTearDown(provider.dispose);

      expect(provider.isFirebaseAvailable, isFalse);
      expect(provider.isSignedIn, isFalse);
    });

    test('keeps the offline profile defaults when signed out', () {
      final provider = AuthProvider(auth: const _UnavailableAuthService());
      addTearDown(provider.dispose);

      expect(provider.name, AuthProvider.defaultName);
      expect(provider.greetingName, isEmpty);
      expect(provider.email, 'user@spendsense.local');
      expect(provider.hasProfileImage, isFalse);
    });

    test('a failed sign-in surfaces one message and clears the busy flag',
        () async {
      final provider = AuthProvider(auth: const _UnavailableAuthService());
      addTearDown(provider.dispose);

      final ok = await provider.signIn(
        email: 'person@example.com',
        password: 'correct horse',
      );

      expect(ok, isFalse);
      expect(provider.isSignedIn, isFalse);
      expect(provider.isBusy, isFalse);
      expect(provider.errorMessage, isNotNull);

      provider.clearError();
      expect(provider.errorMessage, isNull);
    });
  });
}
