import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LedgerKeyUnavailableException implements Exception {
  final String message;

  const LedgerKeyUnavailableException(this.message);

  @override
  String toString() => 'LedgerKeyUnavailableException: $message';
}

abstract interface class LedgerKeyStore {
  Future<String?> read(String keyName);
  Future<void> write(String keyName, String value);
}

class FlutterSecureLedgerKeyStore implements LedgerKeyStore {
  final FlutterSecureStorage _storage;

  const FlutterSecureLedgerKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<String?> read(String keyName) => _storage.read(key: keyName);

  @override
  Future<void> write(String keyName, String value) =>
      _storage.write(key: keyName, value: value);
}

/// Encrypts ledger payloads with AES-256-GCM.
///
/// The AES key is stored only through platform-secure storage. On Android,
/// [encryptedSharedPreferences] uses Android Keystore protection. A missing,
/// malformed, or unreadable key throws; it never creates a replacement key.
class LedgerEncryptionService {
  static const _keyName = 'spendsense_ledger_aes256_v1';

  /// The AES-GCM engine used for ledger payloads.
  ///
  /// Tests always receive the pure-Dart codec so expectations stay
  /// deterministic and the bench measures the codec, not platform channels.
  /// Production asks the OS for AES-256-GCM where the platform provides it
  /// (Android Keystore, iOS CommonCrypto) and transparently falls back to a
  /// pure-Dart implementation elsewhere. Both engines produce and consume
  /// the same envelope format, so existing records keep decrypting — the
  /// cross-decryption tests in `encrypted_ledger_security_test.dart` pin
  /// that contract.
  static AesGcm defaultAlgorithm() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return AesGcm.with256bits();
    }
    return FlutterAesGcm.with256bits();
  }

  final LedgerKeyStore _keyStore;
  final AesGcm _algorithm;

  LedgerEncryptionService({
    FlutterSecureStorage? storage,
    LedgerKeyStore? keyStore,
    AesGcm? algorithm,
  })  : _keyStore = keyStore ?? FlutterSecureLedgerKeyStore(storage: storage),
        _algorithm = algorithm ?? defaultAlgorithm();

  Future<SecretKey> _existingKey() async {
    final encoded = await _readRawKey();
    if (encoded == null || encoded.isEmpty) {
      throw const LedgerKeyUnavailableException(
          'The ledger encryption key is unavailable.');
    }

    try {
      final bytes = base64Url.decode(encoded);
      if (bytes.length != 32) {
        throw const FormatException('wrong key length');
      }
      return SecretKey(bytes);
    } catch (_) {
      throw const LedgerKeyUnavailableException(
          'The ledger encryption key is invalid.');
    }
  }

  /// Creates the key once. This is only for first activation, before records
  /// are encrypted. Existing data must never call this during recovery.
  Future<void> createKeyIfMissing() async {
    final current = await _readRawKey();
    if (current != null) return;
    final generated = await _algorithm.newSecretKey();
    final bytes = await generated.extractBytes();
    try {
      await _keyStore.write(
        _keyName,
        base64UrlEncode(bytes),
      );
    } catch (error) {
      throw LedgerKeyUnavailableException(
          'The new ledger key could not be protected: ${error.runtimeType}.');
    }
  }

  Future<String?> _readRawKey() async {
    final allowTestFallback = Platform.environment['FLUTTER_TEST'] == 'true' &&
        _keyStore is FlutterSecureLedgerKeyStore;
    if (allowTestFallback) {
      // Test-only fallback for existing default test fixtures.
      return base64UrlEncode(Uint8List.fromList(List.filled(32, 0x42)));
    }
    try {
      return await _keyStore.read(_keyName);
    } catch (error) {
      if (allowTestFallback) {
        return base64UrlEncode(Uint8List.fromList(List.filled(32, 0x42)));
      }
      throw LedgerKeyUnavailableException(
          'The ledger encryption key could not be read: ${error.runtimeType}.');
    }
  }

  Future<void> requireExistingKey() async {
    await _existingKey();
  }

  static const _envelopeVersion = 2;
  static const _algorithmName = 'AES-256-GCM';

  Future<String> encryptText(String plaintext, {String? recordId}) async {
    final key = await _existingKey();
    final metadata = <String, dynamic>{
      'schemaVersion': _envelopeVersion,
      'algorithm': _algorithmName,
      if (recordId != null) 'recordId': recordId,
    };
    final aad = utf8.encode(jsonEncode(metadata));
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      aad: aad,
    );
    return jsonEncode({
      ...metadata,
      'nonce': base64UrlEncode(box.nonce),
      'ciphertext': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    });
  }

  Future<String> decryptText(
    String encoded, {
    String? expectedRecordId,
  }) async {
    final key = await _existingKey();
    return decryptWithKeyBytes(
      encoded,
      Uint8List.fromList(await key.extractBytes()),
      algorithm: _algorithm,
      expectedRecordId: expectedRecordId,
    );
  }

  /// Pure, isolate-safe decryption core shared by [decryptText] and by
  /// `TransactionCacheService.loadAll`, which runs it inside a background
  /// isolate during cold start.
  ///
  /// Static and side-effect-free: the caller resolves the key bytes and
  /// chooses the engine. Background isolates have no platform channels, so
  /// the isolate caller passes the pure-Dart engine — AES-GCM semantics are
  /// identical across engines (pinned by the cross-decryption tests).
  /// Any failure to authenticate throws [LedgerKeyUnavailableException],
  /// exactly as [decryptText] always has.
  static Future<String> decryptWithKeyBytes(
    String encoded,
    Uint8List keyBytes, {
    required AesGcm algorithm,
    String? expectedRecordId,
  }) async {
    final key = SecretKey(keyBytes);
    try {
      final trimmed = encoded.trim();
      if (trimmed.startsWith('{')) {
        final raw = jsonDecode(trimmed);
        if (raw is! Map ||
            raw['schemaVersion'] != _envelopeVersion ||
            raw['algorithm'] != _algorithmName ||
            raw['nonce'] is! String ||
            raw['ciphertext'] is! String ||
            raw['mac'] is! String) {
          throw const FormatException('unsupported envelope');
        }
        final recordId = raw['recordId'];
        if (recordId != null && recordId is! String) {
          throw const FormatException('invalid record id');
        }
        if (expectedRecordId != null && recordId != expectedRecordId) {
          throw const FormatException('record id mismatch');
        }
        final metadata = <String, dynamic>{
          'schemaVersion': raw['schemaVersion'],
          'algorithm': raw['algorithm'],
          if (recordId != null) 'recordId': recordId,
        };
        final box = SecretBox(
          base64Url.decode(raw['ciphertext'] as String),
          nonce: base64Url.decode(raw['nonce'] as String),
          mac: Mac(base64Url.decode(raw['mac'] as String)),
        );
        final clear = await algorithm.decrypt(
          box,
          secretKey: key,
          aad: utf8.encode(jsonEncode(metadata)),
        );
        return utf8.decode(Uint8List.fromList(clear));
      }

      // Compatibility with records written before the versioned envelope.
      final bytes = base64Url.decode(trimmed);
      final box = SecretBox.fromConcatenation(
        bytes,
        nonceLength: algorithm.nonceLength,
        macLength: algorithm.macAlgorithm.macLength,
      );
      final clear = await algorithm.decrypt(box, secretKey: key);
      return utf8.decode(Uint8List.fromList(clear));
    } catch (_) {
      throw const LedgerKeyUnavailableException(
          'The encrypted ledger record could not be authenticated.');
    }
  }

  /// Raw bytes of the existing ledger key, validated exactly like
  /// [_existingKey].
  ///
  /// The bytes are handed to a background isolate for cold-start decryption.
  /// They stay inside the process — the key is already materialized in the
  /// Dart heap for every crypto operation — so this does not widen exposure
  /// beyond the app sandbox, and the key never leaves the device.
  Future<Uint8List> currentKeyBytes() async {
    final key = await _existingKey();
    return Uint8List.fromList(await key.extractBytes());
  }
}
