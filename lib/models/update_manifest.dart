import 'dart:convert';

/// A strict, numeric semantic version with an Android build number.
///
/// Versions are **never** compared lexicographically: `1.10.0` must sort higher
/// than `1.9.9`, and the build number breaks ties for rebuilds of the same
/// version name.
class AppVersion implements Comparable<AppVersion> {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;
  final int buildNumber;

  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.buildNumber,
    this.preRelease,
  });

  /// Parses `x.y.z` (optionally `-prerelease`) and an explicit build number.
  /// Returns null for anything that is not a fully numeric version.
  static AppVersion? tryParse(String value, {required int buildNumber}) {
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z][0-9A-Za-z.-]*))?$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    if (buildNumber < 0) return null;
    return AppVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      preRelease: match.group(4),
      buildNumber: buildNumber,
    );
  }

  String get versionName =>
      '$major.$minor.$patch${preRelease == null ? '' : '-$preRelease'}';

  @override
  int compareTo(AppVersion other) {
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

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;
  bool isAtLeast(AppVersion other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease, buildNumber);

  @override
  String toString() => '$versionName+$buildNumber';
}

/// Stable identifiers for every way a manifest can be rejected.
enum ManifestError {
  invalidJson,
  notAnObject,
  missingField,
  unsupportedSchema,
  wrongAppId,
  invalidVersion,
  invalidBuildNumber,
  invalidMinimumVersion,
  invalidDownloadUrl,
  insecureDownloadUrl,
  unapprovedHost,
  invalidApkPath,
  invalidSha256,
  invalidCertFingerprint,
  invalidReleaseNotes,
  invalidPublishedAt,
}

class ManifestValidationException implements Exception {
  final ManifestError error;
  final String message;
  const ManifestValidationException(this.error, this.message);

  @override
  String toString() => 'ManifestValidationException(${error.name}): $message';
}

/// A validated remote update manifest.
///
/// Parsing is intentionally strict: every field is checked before the manifest
/// is allowed to influence update policy. A manifest is untrusted input.
class UpdateManifest {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final String appId;
  final AppVersion latest;
  final AppVersion minimum;
  final Uri downloadUrl;
  final List<String> releaseNotes;
  final String sha256;
  final String signingCertSha256;
  final DateTime? publishedAt;

  const UpdateManifest({
    required this.schemaVersion,
    required this.appId,
    required this.latest,
    required this.minimum,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.sha256,
    required this.signingCertSha256,
    required this.publishedAt,
  });

  /// Normalises a SHA-256 fingerprint to lowercase hex without separators.
  static String? normalizeFingerprint(String? value) {
    if (value == null) return null;
    final cleaned = value.replaceAll(':', '').replaceAll(RegExp(r'\s'), '');
    final lower = cleaned.toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(lower)) return null;
    return lower;
  }

  static UpdateManifest fromJsonString(
    String source, {
    required String expectedAppId,
    required Set<String> approvedHosts,
  }) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ManifestValidationException(
        ManifestError.invalidJson,
        'Manifest is not valid JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ManifestValidationException(
        ManifestError.notAnObject,
        'Manifest must be a JSON object.',
      );
    }
    return fromMap(decoded,
        expectedAppId: expectedAppId, approvedHosts: approvedHosts);
  }

  static UpdateManifest fromMap(
    Map<String, dynamic> json, {
    required String expectedAppId,
    required Set<String> approvedHosts,
  }) {
    T require<T>(String key) {
      if (!json.containsKey(key) || json[key] == null) {
        throw ManifestValidationException(
          ManifestError.missingField,
          'Manifest is missing required field "$key".',
        );
      }
      final value = json[key];
      if (value is! T) {
        throw ManifestValidationException(
          ManifestError.missingField,
          'Manifest field "$key" has the wrong type.',
        );
      }
      return value;
    }

    final schemaVersion = require<int>('schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw ManifestValidationException(
        ManifestError.unsupportedSchema,
        'Unsupported manifest schemaVersion $schemaVersion '
        '(expected $currentSchemaVersion).',
      );
    }

    final appId = require<String>('appId').trim();
    if (appId != expectedAppId) {
      throw ManifestValidationException(
        ManifestError.wrongAppId,
        'Manifest is for "$appId", not "$expectedAppId".',
      );
    }

    final latestVersionRaw = require<String>('latestVersion');
    final latestBuildNumber = require<int>('latestBuildNumber');
    if (latestBuildNumber <= 0) {
      throw const ManifestValidationException(
        ManifestError.invalidBuildNumber,
        'latestBuildNumber must be a positive integer.',
      );
    }
    final latest =
        AppVersion.tryParse(latestVersionRaw, buildNumber: latestBuildNumber);
    if (latest == null) {
      throw ManifestValidationException(
        ManifestError.invalidVersion,
        'latestVersion "$latestVersionRaw" is not a valid semantic version.',
      );
    }

    final minimumRaw = require<String>('minimumSupportedVersion');
    final minimum = AppVersion.tryParse(minimumRaw, buildNumber: 0);
    if (minimum == null) {
      throw ManifestValidationException(
        ManifestError.invalidMinimumVersion,
        'minimumSupportedVersion "$minimumRaw" is not a valid version.',
      );
    }
    // Compare version names only: the minimum is a floor, not a build pin.
    final minimumByName = AppVersion(
      major: minimum.major,
      minor: minimum.minor,
      patch: minimum.patch,
      preRelease: minimum.preRelease,
      buildNumber: 0,
    );
    final latestByName = AppVersion(
      major: latest.major,
      minor: latest.minor,
      patch: latest.patch,
      preRelease: latest.preRelease,
      buildNumber: 0,
    );
    if (minimumByName.isNewerThan(latestByName)) {
      throw const ManifestValidationException(
        ManifestError.invalidMinimumVersion,
        'minimumSupportedVersion cannot be newer than latestVersion.',
      );
    }

    final urlRaw = require<String>('downloadUrl').trim();
    final url = Uri.tryParse(urlRaw);
    if (url == null || !url.hasScheme || url.host.isEmpty) {
      throw const ManifestValidationException(
        ManifestError.invalidDownloadUrl,
        'downloadUrl is not an absolute URL.',
      );
    }
    if (url.scheme.toLowerCase() != 'https') {
      throw const ManifestValidationException(
        ManifestError.insecureDownloadUrl,
        'downloadUrl must use HTTPS.',
      );
    }
    if (url.userInfo.isNotEmpty) {
      throw const ManifestValidationException(
        ManifestError.invalidDownloadUrl,
        'downloadUrl must not contain credentials.',
      );
    }
    final host = url.host.toLowerCase();
    if (!approvedHosts.map((h) => h.toLowerCase()).contains(host)) {
      throw ManifestValidationException(
        ManifestError.unapprovedHost,
        'downloadUrl host "$host" is not in the approved host list.',
      );
    }
    final segments = url.pathSegments;
    if (segments.any((s) => s == '..' || s == '.')) {
      throw const ManifestValidationException(
        ManifestError.invalidApkPath,
        'downloadUrl must not contain traversal segments.',
      );
    }
    if (!url.path.toLowerCase().endsWith('.apk')) {
      throw const ManifestValidationException(
        ManifestError.invalidApkPath,
        'downloadUrl must point at an .apk file.',
      );
    }

    final sha256 = normalizeFingerprint(require<String>('sha256'));
    if (sha256 == null) {
      throw const ManifestValidationException(
        ManifestError.invalidSha256,
        'sha256 must be 64 hexadecimal characters.',
      );
    }

    final cert = normalizeFingerprint(require<String>('signingCertSha256'));
    if (cert == null) {
      throw const ManifestValidationException(
        ManifestError.invalidCertFingerprint,
        'signingCertSha256 must be 64 hexadecimal characters.',
      );
    }

    final notesRaw = json['releaseNotes'];
    final releaseNotes = <String>[];
    if (notesRaw != null) {
      if (notesRaw is! List) {
        throw const ManifestValidationException(
          ManifestError.invalidReleaseNotes,
          'releaseNotes must be a list of strings.',
        );
      }
      for (final note in notesRaw) {
        if (note is! String) {
          throw const ManifestValidationException(
            ManifestError.invalidReleaseNotes,
            'releaseNotes must be a list of strings.',
          );
        }
        releaseNotes.add(note);
      }
    }

    DateTime? publishedAt;
    final publishedRaw = json['publishedAt'];
    if (publishedRaw != null) {
      if (publishedRaw is! String) {
        throw const ManifestValidationException(
          ManifestError.invalidPublishedAt,
          'publishedAt must be an ISO-8601 timestamp string.',
        );
      }
      publishedAt = DateTime.tryParse(publishedRaw)?.toUtc();
      if (publishedAt == null) {
        throw const ManifestValidationException(
          ManifestError.invalidPublishedAt,
          'publishedAt is not a valid ISO-8601 timestamp.',
        );
      }
    }

    return UpdateManifest(
      schemaVersion: schemaVersion,
      appId: appId,
      latest: latest,
      minimum: minimum,
      downloadUrl: url,
      releaseNotes: List.unmodifiable(releaseNotes),
      sha256: sha256,
      signingCertSha256: cert,
      publishedAt: publishedAt,
    );
  }
}

/// Remote policy decision for an installed build.
enum UpdateDecision {
  upToDate,
  optional,
  required,
}

class UpdatePolicy {
  const UpdatePolicy._();

  static UpdateDecision decide({
    required AppVersion installed,
    required UpdateManifest manifest,
  }) {
    if (!manifest.latest.isNewerThan(installed)) {
      return UpdateDecision.upToDate;
    }
    final minimumByName = AppVersion(
      major: manifest.minimum.major,
      minor: manifest.minimum.minor,
      patch: manifest.minimum.patch,
      preRelease: manifest.minimum.preRelease,
      buildNumber: 0,
    );
    final installedByName = AppVersion(
      major: installed.major,
      minor: installed.minor,
      patch: installed.patch,
      preRelease: installed.preRelease,
      buildNumber: 0,
    );
    if (!installedByName.isAtLeast(minimumByName)) {
      return UpdateDecision.required;
    }
    return UpdateDecision.optional;
  }
}
