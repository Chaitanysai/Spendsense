// Generates a release `manifest.json` from an already built, signed APK.
//
// Usage:
//   dart run tool/generate_ota_manifest.dart \
//     --apk ota/public/releases/spendsense-2.0.0+20.apk \
//     --base-url https://spendsense.example \
//     --out ota/public/manifest.json \
//     --notes "Faster insight cards" \
//     --notes "Fixed SMS import edge case"
//
// Version and build number are read from pubspec.yaml unless overridden with
// --version / --build-number. Nothing is uploaded or published by this script.
//
// The script never prints signing material. The certificate fingerprint is a
// public identifier and is pinned in lib/config/update_config.dart as well.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _pinnedCertSha256 =
    '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367';
const _appId = 'com.example.spendsense';

void main(List<String> args) {
  final options = _Options.parse(args);

  final apk = File(options.apkPath);
  if (!apk.existsSync()) {
    _fail('APK not found: ${options.apkPath}');
  }

  final (:versionName, :buildNumber) = options.versionName != null
      ? (versionName: options.versionName!, buildNumber: options.buildNumber!)
      : _readPubspecVersion(File('pubspec.yaml'));

  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(versionName)) {
    _fail('Version must be numeric semantic version (x.y.z): $versionName');
  }
  if (buildNumber <= 0) {
    _fail('Build number must be positive.');
  }

  final minimum = options.minimumVersion ?? versionName;
  if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(minimum)) {
    _fail('--minimum must be x.y.z: $minimum');
  }
  if (_compareVersions(minimum, versionName) > 0) {
    _fail('--minimum ($minimum) cannot be newer than $versionName.');
  }

  final baseUrl = Uri.tryParse(options.baseUrl);
  if (baseUrl == null ||
      baseUrl.scheme != 'https' ||
      baseUrl.host.isEmpty ||
      baseUrl.hasQuery ||
      baseUrl.hasFragment) {
    _fail(
        '--base-url must be a plain HTTPS origin, e.g. https://spendsense.example');
  }
  final base = options.baseUrl.replaceAll(RegExp(r'/+$'), '');
  final downloadUrl = '$base/releases/spendsense-$versionName+$buildNumber.apk';

  final sha256Hex = options.sha256 ?? _sha256Of(apk);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Hex)) {
    _fail('APK SHA-256 must be 64 lowercase hex characters.');
  }

  final cert = options.certSha256 ?? _pinnedCertSha256;
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(cert)) {
    _fail('Certificate fingerprint must be 64 lowercase hex characters.');
  }

  final publishedAt =
      options.publishedAt ?? DateTime.now().toUtc().toIso8601String();

  final manifest = <String, Object?>{
    'schemaVersion': 1,
    'appId': _appId,
    'latestVersion': versionName,
    'latestBuildNumber': buildNumber,
    'minimumSupportedVersion': minimum,
    'downloadUrl': downloadUrl,
    'releaseNotes': options.notes,
    'sha256': sha256Hex,
    'signingCertSha256': cert,
    'publishedAt': publishedAt,
  };

  final output = File(options.outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );

  stdout
    ..writeln('Wrote ${output.path}')
    ..writeln('  version:  $versionName+$buildNumber')
    ..writeln('  apk:      ${apk.path} (${apk.lengthSync()} bytes)')
    ..writeln('  sha256:   $sha256Hex')
    ..writeln('  url:      $downloadUrl');
}

({String versionName, int buildNumber}) _readPubspecVersion(File pubspec) {
  if (!pubspec.existsSync()) {
    _fail('pubspec.yaml not found; run from the repository root.');
  }
  final source = pubspec.readAsStringSync();
  final match = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$',
    multiLine: true,
  ).firstMatch(source);
  if (match == null) {
    _fail('Could not read "version:" from pubspec.yaml.');
  }
  return (
    versionName: '${match.group(1)}.${match.group(2)}.${match.group(3)}',
    buildNumber: int.parse(match.group(4) ?? '0'),
  );
}

String _sha256Of(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();

int _compareVersions(String a, String b) {
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    final cmp = pa[i].compareTo(pb[i]);
    if (cmp != 0) return cmp;
  }
  return 0;
}

Never _fail(String message) {
  stderr.writeln('error: $message');
  exit(64);
}

class _Options {
  final String apkPath;
  final String baseUrl;
  final String outputPath;
  final String? versionName;
  final int? buildNumber;
  final String? minimumVersion;
  final String? sha256;
  final String? certSha256;
  final String? publishedAt;
  final List<String> notes;

  const _Options({
    required this.apkPath,
    required this.baseUrl,
    required this.outputPath,
    required this.versionName,
    required this.buildNumber,
    required this.minimumVersion,
    required this.sha256,
    required this.certSha256,
    required this.publishedAt,
    required this.notes,
  });

  factory _Options.parse(List<String> args) {
    String? apk;
    String? baseUrl;
    var output = 'ota/public/manifest.json';
    String? version;
    int? build;
    String? minimum;
    String? sha;
    String? cert;
    String? published;
    final notes = <String>[];

    String valueOf(int index, String flag) {
      if (index + 1 >= args.length) _fail('$flag requires a value.');
      return args[index + 1];
    }

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      switch (arg) {
        case '--apk':
          apk = valueOf(i, arg);
          i++;
        case '--base-url':
          baseUrl = valueOf(i, arg);
          i++;
        case '--out':
          output = valueOf(i, arg);
          i++;
        case '--version':
          version = valueOf(i, arg);
          i++;
        case '--build-number':
          build = int.tryParse(valueOf(i, arg));
          if (build == null) _fail('--build-number must be an integer.');
          i++;
        case '--minimum':
          minimum = valueOf(i, arg);
          i++;
        case '--sha256':
          sha = valueOf(i, arg).toLowerCase();
          i++;
        case '--cert':
          cert = valueOf(i, arg)
              .replaceAll(':', '')
              .replaceAll(RegExp(r'\s'), '')
              .toLowerCase();
          i++;
        case '--published-at':
          published = valueOf(i, arg);
          i++;
        case '--notes':
          notes.add(valueOf(i, arg));
          i++;
        case '--help':
        case '-h':
          stdout.writeln(
            'Usage: dart run tool/generate_ota_manifest.dart '
            '--apk <path> --base-url <https origin> [--out <path>] '
            '[--version x.y.z] [--build-number n] [--minimum x.y.z] '
            '[--sha256 <hex>] [--cert <hex>] [--published-at <iso>] '
            '[--notes <text>]...',
          );
          exit(0);
        default:
          _fail('Unknown argument: $arg');
      }
    }

    if (apk == null || apk.isEmpty) _fail('--apk is required.');
    if (baseUrl == null || baseUrl.isEmpty) _fail('--base-url is required.');
    if ((version == null) != (build == null)) {
      _fail('--version and --build-number must be supplied together.');
    }

    return _Options(
      apkPath: apk,
      baseUrl: baseUrl,
      outputPath: output,
      versionName: version,
      buildNumber: build,
      minimumVersion: minimum,
      sha256: sha,
      certSha256: cert,
      publishedAt: published,
      notes: List.unmodifiable(notes),
    );
  }
}
