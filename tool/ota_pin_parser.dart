// Parsing logic for the OTA certificate pin constant.
//
// Separated from the CLI so the matching rules can be unit-tested directly.
// The earlier version tested them by spawning `Platform.resolvedExecutable`,
// which deadlocks under `flutter_test` (the executable is `flutter_tester`, not
// `dart`). The logic under test is string parsing, so it takes a String.
//
// The parser exists because the constant spans two lines
//
//   static const String pinnedSigningCertSha256 =
//       '42c8f876...d367';
//
// and its name also appears later as a *usage*
// (`pinnedCertSha256: pinnedSigningCertSha256,`). A single-line match returns
// nothing, and a loose grep sees two candidates. Both failure modes produced a
// false "pin mismatch" in CI.
import 'dart:io';

/// Why a source text did not yield a usable pin.
enum OtaPinError {
  /// No `pinnedSigningCertSha256 = '...'` declaration was found.
  missing,

  /// More than one declaration: refuse to guess which is authoritative.
  ambiguous,

  /// The value is empty, non-hex, or not exactly 64 characters.
  malformed,
}

/// The outcome of [parseOtaPin].
///
/// Exactly one of [fingerprint] and [error] is non-null.
class OtaPinResult {
  final String? fingerprint;
  final OtaPinError? error;
  final String? detail;

  const OtaPinResult.ok(String this.fingerprint)
      : error = null,
        detail = null;

  const OtaPinResult.failure(OtaPinError this.error, String this.detail)
      : fingerprint = null;

  bool get isOk => fingerprint != null;
}

/// Extracts the pinned certificate fingerprint from Dart source text.
///
/// Accepts LF, CRLF or CR line endings. Requires exactly one declaration whose
/// value is exactly 64 lowercase hexadecimal characters; uppercase is rejected
/// rather than normalised, so the stored constant and the compared value are
/// always byte-identical.
OtaPinResult parseOtaPin(String source) {
  // Normalise line endings first: a CRLF file would otherwise defeat every
  // pattern, which is precisely the bug this parser exists to prevent.
  final text = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  final pattern = RegExp(
    r"""static\s+const\s+String\s+pinnedSigningCertSha256\s*=\s*'([^']*)'""",
  );
  final matches = pattern.allMatches(text).toList();

  if (matches.isEmpty) {
    return const OtaPinResult.failure(
      OtaPinError.missing,
      'No pinnedSigningCertSha256 declaration with a quoted value found',
    );
  }
  if (matches.length > 1) {
    return OtaPinResult.failure(
      OtaPinError.ambiguous,
      'Found ${matches.length} pinnedSigningCertSha256 declarations; '
      'refusing to guess which is authoritative',
    );
  }

  final value = matches.single.group(1)!.trim();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    return OtaPinResult.failure(
      OtaPinError.malformed,
      'Pinned fingerprint is malformed: expected 64 lowercase hex characters, '
      'got ${value.length} character(s)'
      '${value.isEmpty ? ' (empty)' : ''}',
    );
  }

  return OtaPinResult.ok(value);
}

/// Reads [path] and parses it. Kept here so the CLI and any future caller share
/// one entry point.
OtaPinResult parseOtaPinFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return OtaPinResult.failure(OtaPinError.missing, 'File not found: $path');
  }
  return parseOtaPin(file.readAsStringSync());
}
