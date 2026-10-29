// ignore: avoid_relative_lib_imports
import '../tool/ota_pin_parser.dart';

import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the OTA certificate-pin parser.
///
/// These call `parseOtaPin` directly. The previous version spawned
/// `Platform.resolvedExecutable`, which is `flutter_tester` under
/// `flutter_test`; that deadlocked and all ten tests timed out without ever
/// exercising the parser.
void main() {
  const pin =
      '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367';

  group('parses a valid declaration', () {
    test('the real repository file yields exactly the pinned fingerprint', () {
      final result = parseOtaPinFile('lib/config/update_config.dart');

      expect(result.isOk, isTrue, reason: result.detail);
      expect(result.fingerprint, pin);
    });

    test('a wrapped declaration spanning two lines', () {
      final result = parseOtaPin(
        'class C {\n'
        '  static const String pinnedSigningCertSha256 =\n'
        "      '$pin';\n"
        '}\n',
      );

      expect(result.isOk, isTrue, reason: result.detail);
      expect(result.fingerprint, pin);
    });

    test('a CRLF file with a wrapped declaration', () {
      final result = parseOtaPin(
        'class C {\r\n'
        '  static const String pinnedSigningCertSha256 =\r\n'
        "      '$pin';\r\n"
        '}\r\n',
      );

      expect(result.isOk, isTrue, reason: result.detail);
      expect(result.fingerprint, pin);
    });

    test('an LF file with the value on the same line', () {
      final result = parseOtaPin(
        "static const String pinnedSigningCertSha256 = '$pin';\n",
      );

      expect(result.isOk, isTrue, reason: result.detail);
      expect(result.fingerprint, pin);
    });

    test('a usage reference elsewhere does not create ambiguity', () {
      final result = parseOtaPin(
        'class C {\n'
        '  static const String pinnedSigningCertSha256 =\n'
        "      '$pin';\n"
        '  void f() { x = pinnedSigningCertSha256; }\n'
        '}\n',
      );

      expect(result.isOk, isTrue, reason: result.detail);
      expect(result.fingerprint, pin);
    });
  });

  group('fails closed', () {
    test('when the declaration is absent', () {
      final result = parseOtaPin('class C { void f() {} }\n');

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.missing);
    });

    test('when only a usage reference exists', () {
      final result = parseOtaPin(
        'class C { void f() { x = pinnedSigningCertSha256; } }\n',
      );

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.missing);
    });

    test('when the value is empty', () {
      final result = parseOtaPin(
        "static const String pinnedSigningCertSha256 = '';\n",
      );

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.malformed);
    });

    test('when the value is not hexadecimal', () {
      final result = parseOtaPin(
        "static const String pinnedSigningCertSha256 = 'NOT-A-HEX-VALUE';\n",
      );

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.malformed);
    });

    test('when the value is 63 characters', () {
      final result = parseOtaPin(
        "static const String pinnedSigningCertSha256 = '${pin.substring(0, 63)}';\n",
      );

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.malformed);
    });

    test('when the value is 65 characters', () {
      final result = parseOtaPin(
        "static const String pinnedSigningCertSha256 = '${pin}a';\n",
      );

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.malformed);
    });

    test('when the value uses uppercase hex', () {
      final result = parseOtaPin(
        "static const String pinnedSigningCertSha256 = '${pin.toUpperCase()}';\n",
      );

      expect(result.isOk, isFalse,
          reason: 'uppercase must be rejected rather than silently normalised, '
              'so the stored constant and the compared value stay identical');
      expect(result.error, OtaPinError.malformed);
    });

    test('when separators are present', () {
      final result = parseOtaPin(
        "static const String pinnedSigningCertSha256 = "
        "'42:c8:f8:76:55:97:ae:0f:d7:c4:30:34:6d:17:78:d6';\n",
      );

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.malformed);
    });

    test('when two declarations exist, rather than guessing', () {
      final result = parseOtaPin(
        "static const String pinnedSigningCertSha256 = '$pin';\n"
        "static const String pinnedSigningCertSha256 = '${'b' * 64}';\n",
      );

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.ambiguous);
    });

    test('when the file does not exist', () {
      final result = parseOtaPinFile('/nonexistent/update_config.dart');

      expect(result.isOk, isFalse);
      expect(result.error, OtaPinError.missing);
    });
  });
}
