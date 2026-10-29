// Prints the OTA certificate pin from lib/config/update_config.dart.
//
//   dart run tool/read_ota_pin.dart [--file lib/config/update_config.dart]
//
// Prints exactly one 64-character lowercase hex fingerprint on stdout and exits
// 0. Exits 1 with a diagnostic on stderr if the pin is missing, malformed, or
// ambiguous.
//
// All matching lives in tool/ota_pin_parser.dart; this file only does argument
// handling, I/O and exit codes, so the tests exercise the same code the
// workflow runs.
import 'dart:io';

import 'ota_pin_parser.dart';

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

  final result = parseOtaPinFile(path);
  final fingerprint = result.fingerprint;
  if (fingerprint == null) {
    _fail(result.detail ?? 'could not read the pinned fingerprint');
  }
  stdout.writeln(fingerprint);
}

Never _fail(String message) {
  stderr.writeln('read_ota_pin: $message');
  exit(1);
}
