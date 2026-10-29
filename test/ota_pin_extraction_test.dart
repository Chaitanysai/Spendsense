import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs tool/read_ota_pin.dart as a child process, exactly as the workflow does.
///
/// The pin extraction failed in CI with an empty string, so the parser is
/// tested through its real CLI surface rather than by importing internals.
Future<ProcessResult> _run(String filePath) => Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/read_ota_pin.dart', '--file', filePath],
      stdoutEncoding: const SystemEncoding(),
      stderrEncoding: const SystemEncoding(),
    );

void main() {
  const pin =
      '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367';
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ota-pin-');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<ProcessResult> runOn(String name, String contents) {
    final f = File('${tmp.path}/$name')..writeAsStringSync(contents);
    return _run(f.path);
  }

  test('the repository file yields exactly the pinned fingerprint', () async {
    final result = await _run('lib/config/update_config.dart');
    expect(result.exitCode, 0, reason: result.stderr as String? ?? '');
    expect((result.stdout as String).trim(), pin);
  });

  test('a wrapped declaration on CRLF line endings is handled', () async {
    // The real declaration spans two lines, and its name is also used later as
    // a value reference. Both must be tolerated without ambiguity.
    final result = await runOn(
      'crlf.dart',
      'class C {\r\n'
          '  static const String pinnedSigningCertSha256 =\r\n'
          "      '$pin';\r\n"
          '  void f() { x = pinnedSigningCertSha256; }\r\n'
          '}\r\n',
    );
    expect(result.exitCode, 0, reason: result.stderr as String? ?? '');
    expect((result.stdout as String).trim(), pin);
  });

  test('an LF file is handled the same way', () async {
    final result = await runOn(
      'lf.dart',
      'static const String pinnedSigningCertSha256 =\n'
          "    '$pin';\n",
    );
    expect(result.exitCode, 0, reason: result.stderr as String? ?? '');
    expect((result.stdout as String).trim(), pin);
  });

  group('fails closed', () {
    test('when the declaration is absent', () async {
      final result = await runOn('missing.dart', 'class C { void f() {} }\n');
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
    });

    test('when only a usage reference exists', () async {
      final result = await runOn('usage.dart',
          'class C { void f() { x = pinnedSigningCertSha256; } }\n');
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
    });

    test('when the value is not 64 lowercase hex characters', () async {
      final result = await runOn(
        'malformed.dart',
        "static const String pinnedSigningCertSha256 = 'NOT-A-HEX-VALUE';\n",
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
    });

    test('when the value is empty', () async {
      final result = await runOn(
          'empty.dart', "static const String pinnedSigningCertSha256 = '';\n");
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
    });

    test('when the value is one character short', () async {
      final result = await runOn(
        'short.dart',
        "static const String pinnedSigningCertSha256 = '${pin.substring(0, 63)}';\n",
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
    });

    test('when the value uses uppercase hex', () async {
      final result = await runOn(
        'upper.dart',
        "static const String pinnedSigningCertSha256 = '${pin.toUpperCase()}';\n",
      );
      expect(result.exitCode, isNot(0),
          reason: 'uppercase must be rejected rather than silently normalised, '
              'so the stored pin and the comparison stay identical');
      expect(result.stdout, isEmpty);
    });

    test('when two declarations exist, rather than guessing', () async {
      final result = await runOn(
        'ambiguous.dart',
        "static const String pinnedSigningCertSha256 = '$pin';\n"
            "static const String pinnedSigningCertSha256 = '${'b' * 64}';\n",
      );
      expect(result.exitCode, isNot(0));
      expect(result.stdout, isEmpty);
    });
  });
}
