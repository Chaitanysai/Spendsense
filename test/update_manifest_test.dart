import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/models/update_manifest.dart';

const _appId = 'com.example.spendsense';
const _cert =
    '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367';
const _hosts = {'updates.example.com'};

final _sha = 'a' * 64;

Map<String, dynamic> _json({
  int schemaVersion = 1,
  String appId = _appId,
  String latestVersion = '2.0.1',
  int latestBuildNumber = 21,
  String minimumSupportedVersion = '2.0.0',
  String downloadUrl =
      'https://updates.example.com/releases/spendsense-2.0.1+21.apk',
  Object? releaseNotes = const ['Faster insight cards'],
  String sha256 = '',
  String signingCertSha256 = _cert,
  Object? publishedAt = '2026-10-21T09:00:00Z',
}) =>
    {
      'schemaVersion': schemaVersion,
      'appId': appId,
      'latestVersion': latestVersion,
      'latestBuildNumber': latestBuildNumber,
      'minimumSupportedVersion': minimumSupportedVersion,
      'downloadUrl': downloadUrl,
      'releaseNotes': releaseNotes,
      'sha256': sha256.isEmpty ? _sha : sha256,
      'signingCertSha256': signingCertSha256,
      'publishedAt': publishedAt,
    };

UpdateManifest _parse(Map<String, dynamic> json) => UpdateManifest.fromMap(
      json,
      expectedAppId: _appId,
      approvedHosts: _hosts,
    );

Matcher _throwsManifestError(ManifestError error) => throwsA(
      isA<ManifestValidationException>().having((e) => e.error, 'error', error),
    );

void main() {
  group('AppVersion', () {
    test('compares numeric segments, not strings', () {
      final older = AppVersion.tryParse('1.9.9', buildNumber: 1)!;
      final newer = AppVersion.tryParse('1.10.0', buildNumber: 1)!;
      expect(newer.compareTo(older), greaterThan(0));
      expect(older.compareTo(newer), lessThan(0));
    });

    test('build number breaks a version-name tie', () {
      final a = AppVersion.tryParse('2.0.0', buildNumber: 19)!;
      final b = AppVersion.tryParse('2.0.0', buildNumber: 20)!;
      expect(b.isNewerThan(a), isTrue);
      expect(a.isNewerThan(b), isFalse);
    });

    test('release outranks its pre-release', () {
      final beta = AppVersion.tryParse('2.0.0-beta.2', buildNumber: 5)!;
      final release = AppVersion.tryParse('2.0.0', buildNumber: 1)!;
      expect(release.isNewerThan(beta), isTrue);
      expect(beta.isNewerThan(release), isFalse);
    });

    test('rejects non-numeric and malformed versions', () {
      for (final bad in ['v2.0.0', '2.0', '2.0.0.1', '', 'two.0.0']) {
        expect(
          AppVersion.tryParse(bad, buildNumber: 1),
          isNull,
          reason: '"$bad" must be rejected',
        );
      }
    });
  });

  group('UpdateManifest parsing', () {
    test('accepts a fully valid manifest', () {
      final manifest = _parse(_json());
      expect(manifest.appId, _appId);
      expect(manifest.latest.versionName, '2.0.1');
      expect(manifest.latest.buildNumber, 21);
      expect(manifest.releaseNotes, hasLength(1));
      expect(manifest.downloadUrl.host, 'updates.example.com');
      expect(manifest.publishedAt, isNotNull);
    });

    test('normalises a colon/uppercase certificate fingerprint', () {
      final manifest = _parse(
        _json(signingCertSha256: _cert.toUpperCase().split('').join()),
      );
      expect(manifest.signingCertSha256, _cert);
      expect(
        UpdateManifest.normalizeFingerprint(
          '42:C8:F8:76:55:97:AE:0F:D7:C4:30:34:6D:17:78:D6:'
          'F1:35:57:34:95:77:32:1C:C8:A1:E7:98:CB:20:D3:67',
        ),
        _cert,
      );
    });

    test('rejects invalid JSON', () {
      expect(
        () => UpdateManifest.fromJsonString(
          '{not json',
          expectedAppId: _appId,
          approvedHosts: _hosts,
        ),
        _throwsManifestError(ManifestError.invalidJson),
      );
    });

    test('rejects a non-object root', () {
      expect(
        () => UpdateManifest.fromJsonString(
          '[]',
          expectedAppId: _appId,
          approvedHosts: _hosts,
        ),
        _throwsManifestError(ManifestError.notAnObject),
      );
    });

    test('rejects an unsupported schema version', () {
      expect(
        () => _parse(_json(schemaVersion: 2)),
        _throwsManifestError(ManifestError.unsupportedSchema),
      );
    });

    test('rejects a manifest for another application', () {
      expect(
        () => _parse(_json(appId: 'com.evil.clone')),
        _throwsManifestError(ManifestError.wrongAppId),
      );
    });

    test('rejects missing fields', () {
      final json = _json()..remove('sha256');
      expect(
        () => _parse(json),
        _throwsManifestError(ManifestError.missingField),
      );
    });

    test('rejects a malformed version', () {
      expect(
        () => _parse(_json(latestVersion: 'latest')),
        _throwsManifestError(ManifestError.invalidVersion),
      );
    });

    test('rejects a non-positive build number', () {
      expect(
        () => _parse(_json(latestBuildNumber: 0)),
        _throwsManifestError(ManifestError.invalidBuildNumber),
      );
    });

    test('rejects a minimum version newer than the latest', () {
      expect(
        () => _parse(_json(minimumSupportedVersion: '2.1.0')),
        _throwsManifestError(ManifestError.invalidMinimumVersion),
      );
    });

    test('rejects insecure or relative download URLs', () {
      expect(
        () => _parse(
          _json(downloadUrl: 'http://updates.example.com/a.apk'),
        ),
        _throwsManifestError(ManifestError.insecureDownloadUrl),
      );
      expect(
        () => _parse(_json(downloadUrl: '/releases/a.apk')),
        _throwsManifestError(ManifestError.invalidDownloadUrl),
      );
    });

    test('rejects unapproved hosts and credentials in the URL', () {
      expect(
        () => _parse(_json(downloadUrl: 'https://evil.example/a.apk')),
        _throwsManifestError(ManifestError.unapprovedHost),
      );
      expect(
        () => _parse(
          _json(downloadUrl: 'https://user:pass@updates.example.com/a.apk'),
        ),
        _throwsManifestError(ManifestError.invalidDownloadUrl),
      );
    });

    test('normalises traversal and rejects non-APK paths', () {
      // Dart's Uri normalises dot segments (including percent-encoded ones),
      // so a traversal attempt collapses to an in-host path. The local
      // download filename is generated separately and never derived from this
      // path.
      final normalised = _parse(
        _json(
          downloadUrl: 'https://updates.example.com/%2e%2e/secret.apk',
        ),
      );
      expect(normalised.downloadUrl.path, '/secret.apk');

      expect(
        () => _parse(_json(downloadUrl: 'https://updates.example.com/a.json')),
        _throwsManifestError(ManifestError.invalidApkPath),
      );
    });

    test('rejects malformed hashes and certificate fingerprints', () {
      expect(
        () => _parse(_json(sha256: 'abc')),
        _throwsManifestError(ManifestError.invalidSha256),
      );
      expect(
        () => _parse(_json(signingCertSha256: 'zz' * 32)),
        _throwsManifestError(ManifestError.invalidCertFingerprint),
      );
    });

    test('rejects malformed release notes and timestamps', () {
      expect(
        () => _parse(_json(releaseNotes: ['ok', 42])),
        _throwsManifestError(ManifestError.invalidReleaseNotes),
      );
      expect(
        () => _parse(_json(publishedAt: 'yesterday')),
        _throwsManifestError(ManifestError.invalidPublishedAt),
      );
    });
  });

  group('UpdatePolicy', () {
    UpdateManifest manifest(
            {String latest = '2.0.1', int build = 21, String min = '2.0.0'}) =>
        _parse(
          _json(
            latestVersion: latest,
            latestBuildNumber: build,
            minimumSupportedVersion: min,
          ),
        );

    test('up to date when installed equals latest', () {
      final decision = UpdatePolicy.decide(
        installed: AppVersion.tryParse('2.0.1', buildNumber: 21)!,
        manifest: manifest(),
      );
      expect(decision, UpdateDecision.upToDate);
    });

    test('up to date when installed is newer than the channel', () {
      final decision = UpdatePolicy.decide(
        installed: AppVersion.tryParse('2.0.2', buildNumber: 30)!,
        manifest: manifest(),
      );
      expect(decision, UpdateDecision.upToDate);
    });

    test('optional when below latest but above the minimum', () {
      final decision = UpdatePolicy.decide(
        installed: AppVersion.tryParse('2.0.0', buildNumber: 20)!,
        manifest: manifest(),
      );
      expect(decision, UpdateDecision.optional);
    });

    test('required when below the minimum supported version', () {
      final decision = UpdatePolicy.decide(
        installed: AppVersion.tryParse('1.9.0', buildNumber: 30)!,
        manifest: manifest(),
      );
      expect(decision, UpdateDecision.required);
    });
  });
}
