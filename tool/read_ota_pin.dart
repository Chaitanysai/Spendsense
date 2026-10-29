// Reads the OTA certificate pin out of lib/config/update_config.dart.
//
// Exists because a shell one-liner silently extracted nothing: the constant is
// declared across two lines
//
//   static const String pinnedSigningCertSha256 =
//       '42c8f876...d367';
//
// and the name also appears later as a *usage*
// (`pinnedCertSha256: pinnedSigningCertSha256,`), so a loose grep sees two
// candidates. This parser anchors on the declaration, joins its continuation
// lines, and refuses anything ambiguous.
//
// Usage:
//   dart run tool/read_ota_pin.dart --file lib/config/update_config.dart
//
// Prints exactly one 64-character lowercase hex fingerprint on stdout.
// Exits non-zero if the pin is missing, malformed, or appears more than once.

import 'dart:io';

void main(List<String> args) {
  var path = 'lib/config/update_config.dart';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--file') {
      if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
        _fail('--file requires a path');
      }
      path = args[i + 1];
      i++;
    } else {
      _fail('Unexpected argument: ${args[i]}');
    }
  }

  final file = File(path);
  if (!file.existsSync()) {
    _fail('File not found: $path');
  }

  // Normalise encoding/line endings before matching: a CRLF file would
  // otherwise defeat every pattern, which is precisely the failure this tool
  // exists to make impossible.
  final raw = file.readAsStringSync();
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Match the declaration only: `const String pinnedSigningCertSha256 =`
  // followed by optional whitespace and exactly one quoted hex literal.
  // `[\s\S]` spans lines so a wrapped declaration is handled, while the
  // anchor on `= '` prevents matching the bare usage reference.
  final pattern = RegExp(
    r"""static\s+const\s+String\s+pinnedSigningCertSha256\s*=\s*'([^']*)'""",
    multiLine: true,
  );
  final matches = pattern.allMatches(text).toList();

  if (matches.isEmpty) {
    _fail('No pinnedSigningCertSha256 declaration with a quoted value found');
  }
  if (matches.length > 1) {
    _fail('Found ${matches.length} pinnedSigningCertSha256 declarations; '
        'refusing to guess which is authoritative');
  }

  final value = matches.single.group(1)!.trim();

  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    // Report the shape, never a partial secret - this value is public anyway,
    // but the rule is uniform.
    _fail('Pinned fingerprint is malformed: expected 64 lowercase hex '
        'characters, got ${value.length} character(s) '
        '${value.isEmpty ? '(empty)' : "(first char '${value[0]}')"}');
  }

  stdout.writeln(value);
}

Never _fail(String message) {
  stderr.writeln('read_ota_pin: $message');
  exit(1);
}
