import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spendsense/config/update_config.dart';
import 'package:spendsense/models/update_manifest.dart';
import 'package:spendsense/providers/update_provider.dart';
import 'package:spendsense/services/update_platform.dart';
import 'package:spendsense/services/update_service.dart';

/// Regression guards for three defects found in review:
///
/// 1. the manifest could be fetched over cleartext http;
/// 2. an unexpected exception in `checkForUpdates` stranded the provider in a
///    busy "checking" state, blocking every later check until restart;
/// 3. an unexpected exception during download left a partial APK on disk
///    despite the documented guarantee that every failure cleans up.
void main() {
  const cert =
      '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367';
  const appId = 'com.example.spendsense';

  UpdateConfig configWith(Uri manifestUri) => UpdateConfig(
        manifestUri: manifestUri,
        appId: appId,
        pinnedCertSha256: cert,
        approvedHosts: {manifestUri.host.toLowerCase()},
      );

  group('manifest transport security', () {
    test('a cleartext manifest URI is refused before any request', () async {
      // Defence in depth: constructing UpdateConfig directly bypasses the
      // factory, so the service itself must refuse http.
      final service = UpdateService(
        config:
            configWith(Uri.parse('http://updates.example.com/manifest.json')),
      );

      final result = await service.checkForUpdates(
        installed:
            const AppVersion(major: 1, minor: 0, patch: 0, buildNumber: 1),
      );

      expect(result.status, UpdateCheckStatus.notConfigured);
      expect(result.hasUpdate, isFalse);
    });
  });

  group('provider survives an unexpected failure', () {
    test('a throwing service does not leave the provider permanently busy',
        () async {
      final provider = UpdateProvider(
        service: _ThrowingService(),
        installedVersionLoader: () async =>
            const AppVersion(major: 1, minor: 0, patch: 0, buildNumber: 1),
      );

      await provider.check();

      expect(provider.isBusy, isFalse,
          reason: 'a stranded _busy would block every future check');
      expect(provider.state, UpdateUiState.error);

      // And a subsequent check must be able to run again.
      await provider.check();
      expect(provider.isBusy, isFalse);
    });
  });

  group('download cleanup on unexpected failure', () {
    test('an unmodelled exception still deletes the partial APK', () async {
      final dir = await Directory.systemTemp.createTemp('ota-cleanup-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final manifest = UpdateManifest.fromJsonString(
        '{"schemaVersion":1,"appId":"$appId",'
        '"latestVersion":"2.0.0","latestBuildNumber":21,'
        '"minimumSupportedVersion":"1.0.0",'
        '"downloadUrl":"https://updates.example.com/releases/app.apk",'
        '"sha256":"${'a' * 64}","signingCertSha256":"$cert"}',
        expectedAppId: appId,
        approvedHosts: const {'updates.example.com'},
      );

      final service = UpdateService(
        config:
            configWith(Uri.parse('https://updates.example.com/manifest.json')),
        platform: const _ThrowingPlatform(),
        clientFactory: _ThrowingClient.new,
      );

      await expectLater(
        service.downloadAndVerify(manifest, destinationDirectory: dir),
        throwsA(anything),
      );

      final updatesDir = Directory('${dir.path}/updates');
      if (await updatesDir.exists()) {
        final leftovers = updatesDir.listSync();
        expect(leftovers, isEmpty,
            reason: 'a failed download must not leave an APK behind');
      }
    });
  });
}

class _ThrowingService extends UpdateService {
  _ThrowingService()
      : super(
          config: UpdateConfig(
            manifestUri: Uri.parse('https://updates.example.com/manifest.json'),
            appId: 'com.example.spendsense',
            pinnedCertSha256:
                '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367',
            approvedHosts: const {'updates.example.com'},
          ),
        );

  @override
  Future<UpdateCheckResult> checkForUpdates({
    required AppVersion installed,
  }) async {
    throw StateError('unexpected');
  }
}

class _ThrowingPlatform implements UpdatePlatform {
  const _ThrowingPlatform();

  @override
  Future<ApkInfo?> inspectApk(String apkPath) async =>
      throw StateError('unexpected');

  @override
  Future<bool> canRequestPackageInstalls() async => false;

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<void> installApk(String apkPath) async =>
      throw const UpdateInstallException('error', 'error');
}

class _ThrowingClient extends http.BaseClient {
  _ThrowingClient();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw StateError('unexpected transport failure');
  }
}
