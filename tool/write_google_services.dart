// Firebase configuration for local and CI builds.
//
// `lib/firebase_options.dart` is tracked on purpose and already public: it holds
// the Firebase client identifier, which ships inside every APK regardless and
// is not a credential. The project's *native* config is a separate file that is
// gitignored, so it is never committed.
//
// Gradle's `com.google.gms.google-services` plugin requires
// `android/app/google-services.json`, which the tracked options file does not
// replace. Rather than committing it, this script writes it from the
// environment at build time:
//
//   FIREBASE_ANDROID_GOOGLE_SERVICES  the JSON content, or base64 of it
//
// If the variable is unset and the file is absent, it writes nothing and fails
// the build with an actionable message. It never embeds a value in this file.

import 'dart:convert';
import 'dart:io';

const _envVar = 'FIREBASE_ANDROID_GOOGLE_SERVICES';
const _target = 'android/app/google-services.json';

void main(List<String> args) {
  final target = File(_target);

  if (!args.contains('--force') && target.existsSync()) {
    stdout.writeln('$_target already exists; leaving it untouched.');
    return;
  }

  final raw = Platform.environment[_envVar]?.trim() ?? '';
  if (raw.isEmpty) {
    stderr.writeln(
      'Missing Firebase Android config: $_target does not exist and '
      '$_envVar is not set.\n'
      'Set $_envVar to the content of google-services.json (or its base64 '
      'encoding) for the Firebase project, then re-run.',
    );
    exit(1);
  }

  var content = raw;
  if (!raw.startsWith('{')) {
    try {
      content = utf8.decode(base64.decode(raw.replaceAll(RegExp(r'\s'), '')));
    } on FormatException {
      stderr.writeln(
        '$_envVar is neither JSON nor valid base64; refusing to write '
        '$_target.',
      );
      exit(1);
    }
  }

  // Parse before writing so a malformed value fails here, not inside Gradle.
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['project_info'] == null) {
      stderr.writeln(
        '$_envVar is not a google-services.json document '
        '(no "project_info").',
      );
      exit(1);
    }
  } on FormatException {
    stderr.writeln('$_envVar does not contain valid JSON.');
    exit(1);
  }

  target.createSync(recursive: true);
  target.writeAsStringSync(content.endsWith('\n') ? content : '$content\n');
  stdout.writeln(
    'Wrote $_target from $_envVar. '
    'It is gitignored; do not commit it.',
  );
}
