// Pre-flight: will the manifest we are about to publish actually be offered?
//
// The update decision is made entirely on the client:
//
//   UpdatePolicy.decide -> manifest.latest.isNewerThan(installed)
//                       -> AppVersion.compareTo(...) > 0
//
// Nothing on the server ever compares a candidate against what is live, and
// tool/validate_ota_manifest.dart is deliberately offline — it validates a
// manifest against its own APK, not against the site. So a candidate whose
// version does not sort strictly above the live one passes every existing gate,
// publishes cleanly, and is then silently never offered to anybody. The build
// succeeds, the site updates, and no device moves.
//
// That failure is worth a step of its own because it is invisible from both
// ends: CI is green, and the app reports "up to date" without an error.
//
// This tool reads the live manifest (or is given one) and mirrors
// AppVersion.compareTo exactly — major, minor, patch, then release-before-
// pre-release, then dot-split pre-release parts, then build number. It
// deliberately does NOT re-derive the comparison with `sort -V`, which
// disagrees with the app on pre-release ordering and on equal-version-different-
// -build, i.e. exactly on rebuilds of the current release.
//
// Usage:
//   dart run tool/check_ota_monotonicity.dart \
//     --candidate ota/public/manifest.json \
//     --live-url https://spendsense-ota-2026.web.app/staging/manifest.json
//
//   # or, for a run with no network (and for the tests):
//   dart run tool/check_ota_monotonicity.dart \
//     --candidate candidate.json --live-file live.json
//
// Exits:
//   0  the candidate sorts strictly above the live manifest (or there is no
//      live manifest yet, which is the first publish on a new channel)
//   1  the candidate would not be offered; the run must not publish
//   2  the arguments or an input file are unusable
import 'dart:convert';
import 'dart:io';

/// Mirrors `AppVersion` from lib/models/update_manifest.dart.
///
/// Kept as a local copy rather than an import: this tool runs under plain
/// `dart run` in CI and must not pull in Flutter. [compareTo] is a line-for-line
/// transcription; `tool/check_ota_monotonicity_test.dart` pins it against the
/// real class so the two cannot drift.
class _AppVersion {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;
  final int buildNumber;

  const _AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.preRelease,
    required this.buildNumber,
  });

  /// Parses `x.y.z` (optionally `-prerelease`) plus an explicit build number.
  /// Accepts a leading `v` so a git tag can be passed directly.
  static _AppVersion? tryParse(String value, {required int buildNumber}) {
    var text = value.trim();
    if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z][0-9A-Za-z.-]*))?$',
    ).firstMatch(text);
    if (match == null) return null;
    if (buildNumber < 0) return null;
    return _AppVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      preRelease: match.group(4),
      buildNumber: buildNumber,
    );
  }

  /// Parses `x.y.z+build`, the form pubspec.yaml and the manifest use.
  static _AppVersion? tryParseWithBuild(String value) {
    final text = value.trim();
    final plus = text.lastIndexOf('+');
    if (plus < 0) return null;
    final build = int.tryParse(text.substring(plus + 1).trim());
    if (build == null) return null;
    return tryParse(text.substring(0, plus), buildNumber: build);
  }

  /// Convenience for the two places that hold an `x.y.z+build` string.
  ///
  /// Not the parser: `_readVersion` returns that same string, and the one caller
  /// that needs a comparable version turns it with [tryParseWithBuild]. Kept
  /// here so both live next to the class they parse for.
  static _AppVersion parseOrFail(String value, String source) {
    final parsed = tryParseWithBuild(value);
    if (parsed == null) {
      _fail('$source: "$value" is not an x.y.z+build version');
    }
    return parsed;
  }

  int compareTo(_AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // A release (no pre-release) is newer than any pre-release of the same core.
    final a = preRelease;
    final b = other.preRelease;
    if (a == null && b == null) return buildNumber.compareTo(other.buildNumber);
    if (a == null) return 1;
    if (b == null) return -1;
    final partsA = a.split('.');
    final partsB = b.split('.');
    for (var i = 0; i < partsA.length && i < partsB.length; i++) {
      final na = int.tryParse(partsA[i]);
      final nb = int.tryParse(partsB[i]);
      final cmp = (na != null && nb != null)
          ? na.compareTo(nb)
          : partsA[i].compareTo(partsB[i]);
      if (cmp != 0) return cmp;
    }
    final lengthCmp = partsA.length.compareTo(partsB.length);
    if (lengthCmp != 0) return lengthCmp;
    return buildNumber.compareTo(other.buildNumber);
  }

  String get versionName =>
      '$major.$minor.$patch${preRelease == null ? '' : '-$preRelease'}';

  @override
  String toString() => '$versionName+$buildNumber';
}

Never _fail(String message) {
  stderr.writeln('error: $message');
  exit(2);
}

void main(List<String> args) async {
  final options = _Options.parse(args);

  final candidate = _AppVersion.parseOrFail(
      _readVersion(options.candidatePath, '--candidate'),
      options.candidatePath);

  String? liveRaw;
  if (options.liveFile != null) {
    final file = File(options.liveFile!);
    if (!file.existsSync()) {
      _fail('Live manifest not found: ${options.liveFile}');
    }
    liveRaw = file.readAsStringSync();
  } else {
    liveRaw = await _fetch(options.liveUrl!);
  }

  if (liveRaw == null) {
    // No live manifest is not a failure: it is the first publish on a channel
    // that has never had one. Say so loudly, because it also covers a typo in
    // --live-url, and a URL that 404s must not read as "nothing to compare".
    stdout.writeln(
        'note: no live manifest at ${options.source}; nothing to compare against.');
    stdout.writeln(
        '      A first publish on a new channel is expected to land here — but so is a');
    stdout.writeln(
        '      mistyped --live-url, so confirm the channel has genuinely never been published.');
    stdout.writeln('OK: monotonicity not applicable (no live manifest)');
    return;
  }

  final live = _AppVersion.parseOrFail(
      _readLiveVersion(liveRaw, options.source), options.source);

  final cmp = candidate.compareTo(live);
  stdout.writeln('live      : $live');
  stdout.writeln('candidate : $candidate');

  if (cmp > 0) {
    stdout.writeln('OK: candidate is newer than live; it will be offered');
    return;
  }

  if (cmp == 0) {
    stderr.writeln(
        'error: candidate $candidate is the same version+build as the live manifest.');
    stderr.writeln(
        '       Every gate would pass and the publish would succeed, but no installed');
    stderr.writeln(
        '       build would ever see an update: UpdatePolicy compares with isNewerThan,');
    stderr.writeln('       which requires strictly greater.');
    stderr.writeln(
        '       Bump the build number (pubspec version -> x.y.z+<next build>) and rebuild.');
    exit(1);
  }

  stderr.writeln(
      'error: candidate $candidate is OLDER than the live manifest $live.');
  stderr.writeln(
      '       Publishing it would move the channel backwards. Android also refuses to');
  stderr.writeln(
      '       install a lower versionCode over a higher one, so even a forced download');
  stderr.writeln(
      '       could not be applied. Never reuse or lower a build number.');
  exit(1);
}

/// Reads the candidate's version out of a manifest, or out of pubspec.yaml.
String _readVersion(String path, String flag) {
  final file = File(path);
  if (!file.existsSync()) _fail('$flag not found: $path');
  final text = file.readAsStringSync();

  if (path.endsWith('.yaml') || path.endsWith('.yml')) {
    final match =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(text);
    if (match == null) {
      _fail('$path has no top-level `version:` line');
    }
    return match.group(1)!;
  }

  final version = _manifestVersion(text, path);
  return version;
}

/// Extracts `latestVersion` + `latestBuildNumber` as an `x.y.z+build` string.
String _manifestVersion(String raw, String source) {
  Map<String, dynamic> decoded;
  try {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic>) {
      _fail('$source is not a JSON object');
    }
    decoded = value;
  } on FormatException catch (e) {
    _fail('$source is not valid JSON: ${e.message}');
  }

  final name = decoded['latestVersion'];
  final build = decoded['latestBuildNumber'];
  if (name is! String || build is! int) {
    _fail(
        '$source has no usable latestVersion/latestBuildNumber; is it an OTA manifest?');
  }
  return '$name+$build';
}

/// Same as [_manifestVersion] but reports the URL as the source.
String _readLiveVersion(String raw, String source) =>
    _manifestVersion(raw, source);

/// Fetches the live manifest. Returns null on 404 (channel never published);
/// any other failure is fatal, so a network blip cannot read as "no live
/// manifest" and let a non-monotonic build through.
Future<String?> _fetch(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    _fail('--live-url must be an absolute https URL (got "$url")');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode == 404) {
      // Drain and release the connection before returning.
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != 200) {
      _fail('GET $url returned HTTP ${response.statusCode}');
    }
    return await response.transform(utf8.decoder).join();
  } on SocketException catch (e) {
    _fail('Could not reach $url: ${e.message}');
  } on HttpException catch (e) {
    _fail('Could not read $url: ${e.message}');
  } finally {
    client.close(force: true);
  }
}

class _Options {
  final String candidatePath;
  final String? liveFile;
  final String? liveUrl;

  const _Options({
    required this.candidatePath,
    this.liveFile,
    this.liveUrl,
  });

  String get source => liveFile ?? liveUrl!;

  static _Options parse(List<String> args) {
    String? candidate;
    String? liveFile;
    String? liveUrl;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--candidate':
          candidate = _value(args, ++i, '--candidate');
        case '--live-file':
          liveFile = _value(args, ++i, '--live-file');
        case '--live-url':
          liveUrl = _value(args, ++i, '--live-url');
        case '--help':
        case '-h':
          stdout.writeln('See the header of tool/check_ota_monotonicity.dart');
          exit(0);
        default:
          _fail('Unexpected argument: ${args[i]}');
      }
    }
    if (candidate == null) _fail('--candidate is required');
    if (liveFile == null && liveUrl == null) {
      _fail('One of --live-file or --live-url is required');
    }
    if (liveFile != null && liveUrl != null) {
      _fail('Pass --live-file or --live-url, not both');
    }
    return _Options(
      candidatePath: candidate,
      liveFile: liveFile,
      liveUrl: liveUrl,
    );
  }

  static String _value(List<String> args, int index, String flag) {
    if (index >= args.length || args[index].startsWith('--')) {
      _fail('$flag requires a value');
    }
    return args[index];
  }
}
