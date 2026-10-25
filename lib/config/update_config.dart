/// Compile-time OTA configuration.
///
/// The manifest URL and approved download hosts are supplied with
/// `--dart-define` so no environment-specific values are hardcoded in source:
///
/// ```sh
/// flutter build apk --release \
///   --dart-define=OTA_MANIFEST_URL=https://your-host.example/manifest.json
/// ```
///
/// The signing certificate is **not** configurable at runtime: it is a pinned,
/// audited constant in this file. Changing it requires a code review.
class UpdateConfig {
  /// SpendSense's release signing certificate (SHA-256 of the DER certificate).
  ///
  /// Verified locally and in CI:
  ///   42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367
  static const String pinnedSigningCertSha256 =
      '42c8f8765597ae0fd7c430346d1778d6f13557349577321cc8a1e798cb20d367';

  static const String applicationId = 'com.example.spendsense';

  final Uri? manifestUri;
  final String appId;
  final String pinnedCertSha256;
  final Set<String> approvedHosts;
  final Duration requestTimeout;
  final Duration downloadTimeout;

  const UpdateConfig({
    required this.manifestUri,
    required this.appId,
    required this.pinnedCertSha256,
    required this.approvedHosts,
    this.requestTimeout = const Duration(seconds: 10),
    this.downloadTimeout = const Duration(seconds: 30),
  });

  factory UpdateConfig.fromEnvironment() {
    const rawManifestUrl = String.fromEnvironment('OTA_MANIFEST_URL');
    const rawExtraHosts = String.fromEnvironment('OTA_DOWNLOAD_HOSTS');

    final manifestUri = rawManifestUrl.trim().isEmpty
        ? null
        : Uri.tryParse(rawManifestUrl.trim());

    final hosts = <String>{};
    if (manifestUri != null && manifestUri.host.isNotEmpty) {
      hosts.add(manifestUri.host.toLowerCase());
    }
    if (rawExtraHosts.trim().isNotEmpty) {
      for (final host in rawExtraHosts.split(',')) {
        final trimmed = host.trim().toLowerCase();
        if (trimmed.isNotEmpty) hosts.add(trimmed);
      }
    }

    return UpdateConfig(
      manifestUri: manifestUri,
      appId: applicationId,
      pinnedCertSha256: pinnedSigningCertSha256,
      approvedHosts: Set.unmodifiable(hosts),
    );
  }

  bool get isConfigured => manifestUri != null && approvedHosts.isNotEmpty;
}
