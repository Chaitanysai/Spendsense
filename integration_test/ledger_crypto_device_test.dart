// On-device verification of the ledger crypto path (P0 optimization,
// docs/performance/P0_LEDGER_OPTIMIZATION.md).
//
// Runs on REAL hardware — `flutter test integration_test -d <device>` — where
// `FlutterAesGcm` actually dispatches to the platform's OS-provided AES
// (Android Keystore provider / iOS CommonCrypto). The VM test suite cannot
// exercise that path: there the Flutter codec routes to its Dart fallback.
//
// IMPORTANT: cryptography_flutter only dispatches to the platform channel
// when `FlutterCipher.defaultChannelPolicy` matches the payload length
// (minLength: 2000 by default). Every payload below therefore exceeds that
// threshold and the test ASSERTS the policy matched — if the plugin's
// threshold changes, this test fails loudly instead of silently testing the
// Dart fallback again.
//
// What is pinned here:
//   1. FlutterAesGcm (device OS crypto) ↔ DartAesGcm cross-decryption, both
//      directions, on the exact envelope LedgerEncryptionService produces.
//   2. Envelope field-for-field compatibility (schemaVersion, algorithm,
//      nonce/ciphertext/mac) and AAD-bound tamper detection on the OS path.
//   3. A LedgerEncryptionService round trip through the real secure key
//      store, plus a fresh-instance decrypt of the same envelope — the
//      restart-persistence shape (new service instance, same stored key).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:spendsense/services/ledger_encryption_service.dart';

/// Long enough that BOTH the encrypt path (measured on the plaintext) and
/// the decrypt path (measured on the ciphertext) clear the plugin's
/// default 2000-byte dispatch threshold.
final Uint8List _bigPayload =
    utf8.encode('{"schemaVersion":2,"currency":"INR","amountMinor":123456,'
        '"id":"device-1","pad":"${'x' * 2400}"}');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('FlutterAesGcm uses the OS path and cross-decrypts with Dart',
      (tester) async {
    expect(
      FlutterCipher.defaultChannelPolicy.matches(length: _bigPayload.length),
      isTrue,
      reason: 'payload must clear the plugin dispatch threshold, or this '
          'test silently exercises only the Dart fallback',
    );

    final aad = utf8.encode(
        jsonEncode({'schemaVersion': 2, 'algorithm': 'AES-256-GCM'}));
    final flutter = FlutterAesGcm.with256bits();
    final dart = AesGcm.with256bits();
    final key = await dart.newSecretKey();
    final keyBytes = Uint8List.fromList(await key.extractBytes());

    Map<String, dynamic> envelope(SecretBox box) => {
          'schemaVersion': 2,
          'algorithm': 'AES-256-GCM',
          'nonce': base64UrlEncode(box.nonce),
          'ciphertext': base64UrlEncode(box.cipherText),
          'mac': base64UrlEncode(box.mac.bytes),
        };

    // OS crypto encrypts → Dart decrypts.
    final osBox =
        await flutter.encrypt(_bigPayload, secretKey: key, aad: aad);
    expect(
      FlutterCipher.defaultChannelPolicy.matches(length: osBox.cipherText.length),
      isTrue,
      reason: 'decrypt-side dispatch must also clear the threshold',
    );
    final dartClear = await LedgerEncryptionService.decryptWithKeyBytes(
      jsonEncode(envelope(osBox)),
      keyBytes,
      algorithm: dart,
    );
    expect(dartClear, utf8.decode(_bigPayload));

    // Dart encrypts → OS crypto decrypts.
    final dartBox =
        await dart.encrypt(_bigPayload, secretKey: key, aad: aad);
    final osClear = await LedgerEncryptionService.decryptWithKeyBytes(
      jsonEncode(envelope(dartBox)),
      keyBytes,
      algorithm: flutter,
    );
    expect(osClear, utf8.decode(_bigPayload));

    // Tampering fails closed on the OS path too.
    final brokenEnvelope = envelope(osBox);
    final cipher = brokenEnvelope['ciphertext'] as String;
    brokenEnvelope['ciphertext'] =
        '${cipher.substring(0, cipher.length - 2)}AA';
    await expectLater(
      LedgerEncryptionService.decryptWithKeyBytes(
        jsonEncode(brokenEnvelope),
        keyBytes,
        algorithm: flutter,
      ),
      throwsA(isA<LedgerKeyUnavailableException>()),
    );
  });

  testWidgets('LedgerEncryptionService round-trips through the device key store',
      (tester) async {
    final first = LedgerEncryptionService();
    await first.createKeyIfMissing();

    const payload = '{"schemaVersion":2,"amountMinor":9900,"id":"persist-1"}';
    final envelope = await first.encryptText(payload, recordId: 'persist-1');
    expect(await first.decryptText(envelope, expectedRecordId: 'persist-1'),
        payload);

    // A brand-new instance resolves the same stored key and reads the same
    // envelope — the restart-persistence shape.
    final second = LedgerEncryptionService();
    expect(await second.decryptText(envelope, expectedRecordId: 'persist-1'),
        payload);
  });
}
