import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spendsense/config/update_config.dart';
import 'package:spendsense/models/update_manifest.dart';
import 'package:spendsense/providers/update_provider.dart';
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

String _body(
        {String latest = '2.0.1', int build = 21, String minimum = '2.0.0'}) =>
    '''
{
  "schemaVersion": 1,
  "appId": "$_appId",
  "latestVersion": "$latest",
  "latestBuildNumber": $build,
  "minimumSupportedVersion": "$minimum",
  "downloadUrl": "https://updates.example.com/releases/spendsense-$latest+$build.apk",
  "releaseNotes": ["Provider test"],
  "sha256": "${'a' * 64}",
  "signingCertSha256": "$_cert"
}
''';

class _CountingTransport implements ManifestTransport {
  final String body;
  int calls = 0;
  final Completer<void>? _gate;

  _CountingTransport(this.body, {Completer<void>? gate}) : _gate = gate;

  @override
  Future<String> get(Uri uri, {required Duration timeout}) async {
    calls++;
    final gate = _gate;
    if (gate != null && !gate.isCompleted) {
      await gate.future;
    }
    return body;
  }
}

class _NoopPlatform implements UpdatePlatform {
  @override
  Future<ApkInfo?> inspectApk(String apkPath) async => null;

  @override
  Future<bool> canRequestPackageInstalls() async => true;

  @override
  Future<void> openInstallPermissionSettings() async {}

  @override
  Future<void> installApk(String apkPath) async {}
}

void main() {
  test('loads the installed version without any network access', () async {
    final transport = _CountingTransport(_body());
    final provider = UpdateProvider(
      service: UpdateService(
        config: UpdateConfig(
          manifestUri: null,
          appId: _appId,
          pinnedCertSha256: _cert,
          approvedHosts: const <String>{},
        ),
        transport: transport,
        platform: _NoopPlatform(),
        clientFactory: http.Client.new,
      ),
      installedVersionLoader: () async =>
          AppVersion.tryParse('2.0.0', buildNumber: 20)!,
    );

    await provider.init();
    expect(provider.installed?.buildNumber, 20);
    expect(provider.isConfigured, isFalse);
    expect(transport.calls, 0);
    expect(provider.state, UpdateUiState.idle);
  });

  test('collapses overlapping checks into one request', () async {
    final gate = Completer<void>();
    final transport = _CountingTransport(_body(), gate: gate);
    final provider = UpdateProvider(
      service: UpdateService(
        config: _config,
        transport: transport,
        platform: _NoopPlatform(),
        clientFactory: http.Client.new,
      ),
      installedVersionLoader: () async =>
          AppVersion.tryParse('2.0.0', buildNumber: 20)!,
    );
    provider.installed = AppVersion.tryParse('2.0.0', buildNumber: 20)!;

    final first = provider.check();
    final second = provider.check();
    expect(provider.state, UpdateUiState.checking);

    gate.complete();
    await Future.wait([first, second]);

    expect(transport.calls, 1);
    expect(provider.state, UpdateUiState.available);
    expect(provider.lastStatus, UpdateCheckStatus.optional);
    expect(provider.manifest?.latest.versionName, '2.0.1');
  });

  test('maps a required update into the available state', () async {
    final provider = UpdateProvider(
      service: UpdateService(
        config: _config,
        transport: _CountingTransport(
          _body(latest: '2.0.1', build: 21, minimum: '2.0.0'),
        ),
        platform: _NoopPlatform(),
        clientFactory: http.Client.new,
      ),
      installedVersionLoader: () async =>
          AppVersion.tryParse('1.0.0', buildNumber: 5)!,
    );
    provider.installed = AppVersion.tryParse('1.0.0', buildNumber: 5)!;

    await provider.check();
    expect(provider.state, UpdateUiState.available);
    expect(provider.lastStatus, UpdateCheckStatus.required);
  });
}
