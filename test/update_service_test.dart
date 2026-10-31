import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spendsense/config/update_config.dart';
import 'package:spendsense/models/update_manifest.dart';
import 'package:spendsense/services/update_platform.dart';
import 'package:spendsense/services/update_service.dart';

const _appId = 'com.example.spendsense';
const _cert =
    '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367';

final _config = UpdateConfig(
  manifestUri: Uri.parse('https://updates.example.com/manifest.json'),
  appId: _appId,
  pinnedCertSha256: _cert,
  approvedHosts: const {'updates.example.com'},
);

UpdateManifest _manifest({
  String sha256 = '',
  String cert = _cert,
  Uri? downloadUrl,
}) =>
    UpdateManifest(
      schemaVersion: 1,
      appId: _appId,
      latest: const AppVersion(
        major: 2,
        minor: 0,
        patch: 1,
        buildNumber: 21,
      ),
      minimum: const AppVersion(
        major: 2,
        minor: 0,
        patch: 0,
        buildNumber: 0,
      ),
      downloadUrl: downloadUrl ??
          Uri.parse('https://updates.example.com/releases/app.apk'),
      releaseNotes: const ['Test release'],
      sha256: sha256.isEmpty ? 'a' * 64 : sha256,
      signingCertSha256: cert,
      publishedAt: DateTime.utc(2026, 10, 21),
    );

String _manifestBody({
  String sha256 = '',
  String cert = _cert,
  String latestVersion = '2.0.1',
  int latestBuildNumber = 21,
  String minimum = '2.0.0',
}) =>
    '''
{
  "schemaVersion": 1,
  "appId": "$_appId",
  "latestVersion": "$latestVersion",
  "latestBuildNumber": $latestBuildNumber,
  "minimumSupportedVersion": "$minimum",
  "downloadUrl": "https://updates.example.com/releases/spendsense-$latestVersion+$latestBuildNumber.apk",
  "releaseNotes": ["Test release"],
  "sha256": "${sha256.isEmpty ? 'a' * 64 : sha256}",
  "signingCertSha256": "$cert",
  "publishedAt": "2026-10-21T09:00:00Z"
}
''';

class _FakeTransport implements ManifestTransport {
  final Future<String> Function() _body;

  _FakeTransport(String body) : _body = (() async => body);
  _FakeTransport.error(Object error) : _body = (() async => throw error);

  @override
  Future<String> get(Uri uri, {required Duration timeout}) => _body();
}

class _RecordingTransport implements ManifestTransport {
  int calls = 0;

  @override
  Future<String> get(Uri uri, {required Duration timeout}) async {
    calls += 1;
    return _manifestBody();
  }
}

class _BytesClient extends http.BaseClient {
  final List<int> bytes;
  final int statusCode;

  _BytesClient(this.bytes, {this.statusCode = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      contentLength: bytes.length,
    );
  }
}

class _FakePlatform implements UpdatePlatform {
  ApkInfo? info;
  bool canInstall;
  bool installCalled = false;
  String? installedPath;
  int permissionSettingsOpened = 0;

  _FakePlatform({
    this.info = const ApkInfo(packageName: _appId, signerSha256: _cert),
    this.canInstall = true,
  });

  @override
  Future<ApkInfo?> inspectApk(String apkPath) async => info;

  @override
  Future<bool> canRequestPackageInstalls() async => canInstall;

  @override
  Future<void> openInstallPermissionSettings() async {
    permissionSettingsOpened++;
  }

  @override
  Future<void> installApk(String apkPath) async {
    installCalled = true;
    installedPath = apkPath;
  }
}

class _ErroringClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(
      Stream<List<int>>.error(const SocketException('connection lost')),
      200,
    );
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('spendsense_update_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  UpdateService serviceWith({
    ManifestTransport? transport,
    _FakePlatform? platform,
    http.Client Function()? clientFactory,
  }) =>
      UpdateService(
        config: _config,
        transport: transport ?? _FakeTransport(_manifestBody()),
        platform: platform ?? _FakePlatform(),
        clientFactory: clientFactory ?? () => _BytesClient(const [1, 2, 3]),
      );

  group('checkForUpdates', () {
    test('reports up to date', () async {
      final result = await serviceWith().checkForUpdates(
        installed: AppVersion.tryParse('2.0.1', buildNumber: 21)!,
      );
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.manifest, isNotNull);
    });

    test('reports an optional update', () async {
      final result = await serviceWith().checkForUpdates(
        installed: AppVersion.tryParse('2.0.0', buildNumber: 20)!,
      );
      expect(result.status, UpdateCheckStatus.optional);
      expect(result.hasUpdate, isTrue);
    });

    test('reports a required update below the minimum', () async {
      final result = await serviceWith(
        transport: _FakeTransport(_manifestBody(minimum: '2.0.0')),
      ).checkForUpdates(
        installed: AppVersion.tryParse('1.8.0', buildNumber: 41)!,
      );
      expect(result.status, UpdateCheckStatus.required);
    });

    test('rejects a manifest that claims an untrusted certificate', () async {
      final result = await serviceWith(
        transport: _FakeTransport(_manifestBody(cert: 'b' * 64)),
      ).checkForUpdates(
        installed: AppVersion.tryParse('1.0.0', buildNumber: 1)!,
      );
      expect(result.status, UpdateCheckStatus.invalidManifest);
      expect(result.message, contains('unexpected certificate'));
    });

    test('maps a malformed manifest to invalidManifest', () async {
      final result = await serviceWith(
        transport: _FakeTransport('{"schemaVersion": 99}'),
      ).checkForUpdates(
        installed: AppVersion.tryParse('1.0.0', buildNumber: 1)!,
      );
      expect(result.status, UpdateCheckStatus.invalidManifest);
    });

    test('maps timeouts and client failures to networkError', () async {
      final timeout = await serviceWith(
        transport: _FakeTransport.error(TimeoutException('slow')),
      ).checkForUpdates(
        installed: AppVersion.tryParse('1.0.0', buildNumber: 1)!,
      );
      expect(timeout.status, UpdateCheckStatus.networkError);

      final offline = await serviceWith(
        transport: _FakeTransport.error(http.ClientException('offline')),
      ).checkForUpdates(
        installed: AppVersion.tryParse('1.0.0', buildNumber: 1)!,
      );
      expect(offline.status, UpdateCheckStatus.networkError);
      expect(offline.message, contains('connection'));
    });

    test('does no network work when the channel is not configured', () async {
      final unconfigured = UpdateConfig(
        manifestUri: null,
        appId: _appId,
        pinnedCertSha256: _cert,
        approvedHosts: const <String>{},
      );
      // A transport that counts calls: asserting only a local flag could never
      // fail because nothing set it.
      final transport = _RecordingTransport();
      final result = await UpdateService(
        config: unconfigured,
        transport: transport,
      ).checkForUpdates(
        installed: AppVersion.tryParse('1.0.0', buildNumber: 1)!,
      );
      expect(transport.calls, 0);
      expect(result.status, UpdateCheckStatus.notConfigured);
    });
  });

  group('downloadAndVerify', () {
    test('accepts a hash- and signature-verified download', () async {
      final bytes = List<int>.generate(4096, (i) => i % 256);
      final sha = sha256.convert(bytes).toString();
      final platform = _FakePlatform();
      final service = serviceWith(
        platform: platform,
        clientFactory: () => _BytesClient(bytes),
      );

      final file = await service.downloadAndVerify(
        _manifest(sha256: sha),
        destinationDirectory: tempDir,
      );

      expect(await file.exists(), isTrue);
      expect(file.path, contains('updates'));
      expect(file.path, endsWith('spendsense-2.0.1+21.apk'));
      expect(await file.readAsBytes(), bytes);
    });

    test('deletes the file when the SHA-256 does not match', () async {
      final service = serviceWith(
        clientFactory: () => _BytesClient(const [9, 9, 9]),
      );

      await expectLater(
        service.downloadAndVerify(
          _manifest(sha256: 'c' * 64),
          destinationDirectory: tempDir,
        ),
        throwsA(
          isA<UpdateDownloadException>()
              .having((e) => e.code, 'code', 'hash_mismatch'),
        ),
      );

      final updates = Directory('${tempDir.path}/updates');
      expect(
        updates.existsSync() ? updates.listSync() : const [],
        isEmpty,
        reason: 'a corrupt APK must never be left for the installer',
      );
    });

    test('rejects an APK signed by a different certificate', () async {
      final bytes = [1, 2, 3, 4];
      final sha = sha256.convert(bytes).toString();
      final service = serviceWith(
        platform: _FakePlatform(
          info: const ApkInfo(packageName: _appId, signerSha256: ''),
        ),
        clientFactory: () => _BytesClient(bytes),
      );

      await expectLater(
        service.downloadAndVerify(
          _manifest(sha256: sha),
          destinationDirectory: tempDir,
        ),
        throwsA(
          isA<UpdateDownloadException>()
              .having((e) => e.code, 'code', 'signature_mismatch'),
        ),
      );
    });

    test('rejects an APK for a different package', () async {
      final bytes = [1, 2, 3, 4];
      final sha = sha256.convert(bytes).toString();
      final service = serviceWith(
        platform: _FakePlatform(
          info: const ApkInfo(
            packageName: 'com.evil.clone',
            signerSha256: _cert,
          ),
        ),
        clientFactory: () => _BytesClient(bytes),
      );

      await expectLater(
        service.downloadAndVerify(
          _manifest(sha256: sha),
          destinationDirectory: tempDir,
        ),
        throwsA(
          isA<UpdateDownloadException>()
              .having((e) => e.code, 'code', 'wrong_package'),
        ),
      );
    });

    test('refuses a manifest whose certificate is not pinned', () async {
      final service = serviceWith();
      await expectLater(
        service.downloadAndVerify(
          _manifest(cert: 'd' * 64),
          destinationDirectory: tempDir,
        ),
        throwsA(
          isA<UpdateDownloadException>()
              .having((e) => e.code, 'code', 'untrusted_manifest'),
        ),
      );
    });

    test('refuses an unapproved download URL', () async {
      final service = serviceWith();
      await expectLater(
        service.downloadAndVerify(
          _manifest(downloadUrl: Uri.parse('https://evil.example/app.apk')),
          destinationDirectory: tempDir,
        ),
        throwsA(
          isA<UpdateDownloadException>()
              .having((e) => e.code, 'code', 'untrusted_url'),
        ),
      );
    });

    test('honours cancellation and removes the partial file', () async {
      final bytes = List<int>.generate(2048, (i) => i % 256);
      final sha = sha256.convert(bytes).toString();
      final token = CancelToken()..cancel();
      final service = serviceWith(clientFactory: () => _BytesClient(bytes));

      await expectLater(
        service.downloadAndVerify(
          _manifest(sha256: sha),
          destinationDirectory: tempDir,
          cancelToken: token,
        ),
        throwsA(isA<UpdateCancelled>()),
      );

      final updates = Directory('${tempDir.path}/updates');
      expect(
        updates.existsSync() ? updates.listSync() : const [],
        isEmpty,
      );
    });

    test('never deletes unrelated files in the cache directory', () async {
      final sentinel = File('${tempDir.path}/transactions_export.json')
        ..writeAsStringSync('{"transactions":[1,2,3]}');
      final service = serviceWith(
        clientFactory: () => _BytesClient(const [7, 7, 7]),
      );

      await expectLater(
        service.downloadAndVerify(
          _manifest(sha256: 'e' * 64),
          destinationDirectory: tempDir,
        ),
        throwsA(isA<UpdateDownloadException>()),
      );

      expect(await sentinel.exists(), isTrue);
      expect(await sentinel.readAsString(), '{"transactions":[1,2,3]}');
    });

    test('cleans up when the connection drops mid-download', () async {
      final service = serviceWith(clientFactory: () => _ErroringClient());

      await expectLater(
        service.downloadAndVerify(
          _manifest(),
          destinationDirectory: tempDir,
        ),
        throwsA(
          isA<UpdateDownloadException>()
              .having((e) => e.code, 'code', 'network'),
        ),
      );

      final updates = Directory('${tempDir.path}/updates');
      expect(
        updates.existsSync() ? updates.listSync() : const [],
        isEmpty,
        reason: 'an interrupted download must not leave a partial APK',
      );
    });

    test('surfaces a non-200 server response', () async {
      final service = serviceWith(
        clientFactory: () => _BytesClient(const [], statusCode: 503),
      );
      await expectLater(
        service.downloadAndVerify(
          _manifest(),
          destinationDirectory: tempDir,
        ),
        throwsA(
          isA<UpdateDownloadException>()
              .having((e) => e.code, 'code', 'http_503'),
        ),
      );
    });
  });

  group('installer gating', () {
    test('does not open the installer without permission', () async {
      final platform = _FakePlatform(canInstall: false);
      final service = serviceWith(platform: platform);
      final apk = File('${tempDir.path}/updates/app.apk')
        ..createSync(recursive: true);

      await expectLater(
        service.install(apk),
        throwsA(
          isA<UpdateInstallException>()
              .having((e) => e.code, 'code', 'permission_required'),
        ),
      );
      expect(platform.installCalled, isFalse);
    });

    test('delegates to the platform installer when permitted', () async {
      final platform = _FakePlatform(canInstall: true);
      final service = serviceWith(platform: platform);
      final apk = File('${tempDir.path}/updates/app.apk')
        ..createSync(recursive: true);

      await service.install(apk);
      expect(platform.installCalled, isTrue);
      expect(platform.installedPath, apk.path);
    });
  });
}
