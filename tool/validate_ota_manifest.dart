// Validates a generated OTA manifest against the APK it describes.
//
// Run before publishing. It answers one question: "if an installed build reads
// this manifest, can it safely apply the update?" A manifest that names a
// different APK, a different hash, an unapproved host or a certificate that is
// not the pinned release certificate must never reach hosting.
//
// Usage:
//   dart run tool/validate_ota_manifest.dart \
//     --manifest ota/public/manifest.json \
//     --apk ota/public/releases/spendsense-2.0.3+32.apk \
//     --expect-host spendsense-ota-2026.web.app
//
// Exits non-zero on any failed check. Never prints signing material; the
// certificate fingerprint is a public identifier.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _pinnedCertSha256 =
    '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367';
const _appId = 'com.example.spendsense';
const _schemaVersion = 1;

void main(List<String> args) {
  final options = _Options.parse(args);
  final failures = <String>[];

  void check(bool ok, String message) {
    stdout.writeln('  ${ok ? "ok  " : "FAIL"}  $message');
    if (!ok) failures.add(message);
  }

  final manifestFile = File(options.manifestPath);
  if (!manifestFile.existsSync()) {
    _fail('Manifest not found: ${options.manifestPath}');
  }
  final apkFile = File(options.apkPath);
  if (!apkFile.existsSync()) {
    _fail('APK not found: ${options.apkPath}');
  }

  Map<String, dynamic> manifest;
  try {
    final decoded = jsonDecode(manifestFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      _fail('Manifest root is not a JSON object.');
    }
    manifest = decoded;
  } on FormatException catch (e) {
    _fail('Manifest is not valid JSON: ${e.message}');
  }

  stdout.writeln('Validating ${options.manifestPath}');

  check(manifest['schemaVersion'] == _schemaVersion,
      'schemaVersion is $_schemaVersion');
  check(manifest['appId'] == _appId, 'appId is $_appId');

  final digest = sha256.convert(apkFile.readAsBytesSync()).toString();
  final claimed = manifest['sha256'];
  check(claimed == digest, 'manifest sha256 matches the APK ($digest)');

  check(manifest['signingCertSha256'] == _pinnedCertSha256,
      'signingCertSha256 equals the pinned release certificate');

  final rawUrl = manifest['downloadUrl'];
  final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
  check(url != null, 'downloadUrl parses');
  if (url != null) {
    check(url.scheme == 'https', 'downloadUrl uses HTTPS');
    check(url.host.isNotEmpty, 'downloadUrl has a host');
    check(url.userInfo.isEmpty, 'downloadUrl carries no credentials');
    check(!url.pathSegments.any((s) => s == '..' || s == '.' || s.isEmpty),
        'downloadUrl has no traversal or empty segments');
    check(url.path.toLowerCase().endsWith('.apk'),
        'downloadUrl points at an .apk');
    if (options.expectHost != null) {
      check(url.host.toLowerCase() == options.expectHost!.toLowerCase(),
          'downloadUrl host is ${options.expectHost}');
    }
    final expectedName = apkFile.uri.pathSegments.last;
    check(url.pathSegments.last == expectedName,
        'downloadUrl filename matches the staged APK ($expectedName)');
  }

  final version = manifest['latestVersion'];
  final build = manifest['latestBuildNumber'];
  check(version is String && RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version),
      'latestVersion is a numeric semantic version');
  check(build is int && build > 0, 'latestBuildNumber is a positive integer');

  final minimum = manifest['minimumSupportedVersion'];
  check(minimum is String && RegExp(r'^\d+\.\d+\.\d+$').hasMatch(minimum),
      'minimumSupportedVersion is a numeric semantic version');

  stdout.writeln('');
  if (failures.isNotEmpty) {
    stderr.writeln('Manifest validation failed: ${failures.length} check(s)');
    for (final f in failures) {
      stderr.writeln('  - $f');
    }
    exit(1);
  }
  stdout.writeln('OK: manifest is safe to publish');
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(1);
}

class _Options {
  final String manifestPath;
  final String apkPath;
  final String? expectHost;

  const _Options({
    required this.manifestPath,
    required this.apkPath,
    this.expectHost,
  });

  static _Options parse(List<String> args) {
    String? manifest;
    String? apk;
    String? host;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--manifest':
          manifest = _value(args, ++i, '--manifest');
        case '--apk':
          apk = _value(args, ++i, '--apk');
        case '--expect-host':
          host = _value(args, ++i, '--expect-host');
        default:
          _fail('Unexpected argument: ${args[i]}');
      }
    }
    if (manifest == null) _fail('--manifest is required');
    if (apk == null) _fail('--apk is required');
    return _Options(manifestPath: manifest, apkPath: apk, expectHost: host);
  }

  static String _value(List<String> args, int index, String flag) {
    if (index >= args.length || args[index].startsWith('--')) {
      _fail('$flag requires a value');
    }
    return args[index];
  }
}
