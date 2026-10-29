import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/update_config.dart';
import '../models/update_manifest.dart';
import 'update_platform.dart';

enum UpdateCheckStatus {
  notConfigured,
  upToDate,
  optional,
  required,
  invalidManifest,
  networkError,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateManifest? manifest;
  final String? message;

  const UpdateCheckResult(this.status, {this.manifest, this.message});

  bool get hasUpdate =>
      status == UpdateCheckStatus.optional ||
      status == UpdateCheckStatus.required;
}

class DownloadProgress {
  final int receivedBytes;
  final int? totalBytes;

  const DownloadProgress({required this.receivedBytes, this.totalBytes});

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }
}

class UpdateDownloadException implements Exception {
  final String code;
  final String message;
  const UpdateDownloadException(this.code, this.message);

  @override
  String toString() => 'UpdateDownloadException($code): $message';
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();

  @override
  String toString() => 'Update cancelled';
}

/// Cooperative cancellation for in-flight downloads.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Fetches the raw manifest body. Abstracted so tests never touch the network.
abstract class ManifestTransport {
  Future<String> get(Uri uri, {required Duration timeout});
}

class HttpManifestTransport implements ManifestTransport {
  final http.Client Function() clientFactory;

  const HttpManifestTransport({this.clientFactory = http.Client.new});

  @override
  Future<String> get(Uri uri, {required Duration timeout}) async {
    final client = clientFactory();
    try {
      final response = await client.get(uri).timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateDownloadException(
          'http_${response.statusCode}',
          'Manifest request failed with HTTP ${response.statusCode}.',
        );
      }
      return response.body;
    } finally {
      client.close();
    }
  }
}

class UpdateService {
  final UpdateConfig config;
  final ManifestTransport transport;
  final UpdatePlatform platform;
  final http.Client Function() clientFactory;

  const UpdateService({
    required this.config,
    this.transport = const HttpManifestTransport(),
    this.platform = const MethodChannelUpdatePlatform(),
    this.clientFactory = http.Client.new,
  });

  /// Checks the remote manifest against the installed build.
  ///
  /// Never throws for expected conditions: every failure is mapped to an
  /// [UpdateCheckStatus] so the UI can render it without try/catch.
  Future<UpdateCheckResult> checkForUpdates({
    required AppVersion installed,
  }) async {
    final manifestUri = config.manifestUri;
    if (!config.isConfigured || manifestUri == null) {
      return const UpdateCheckResult(
        UpdateCheckStatus.notConfigured,
        message: 'No update channel is configured for this build.',
      );
    }
    // Defence in depth: UpdateConfig already drops a non-HTTPS URL, but a
    // directly constructed config must not bypass it either.
    if (manifestUri.scheme.toLowerCase() != 'https') {
      return const UpdateCheckResult(
        UpdateCheckStatus.notConfigured,
        message: 'No update channel is configured for this build.',
      );
    }

    try {
      final body =
          await transport.get(manifestUri, timeout: config.requestTimeout);
      final manifest = UpdateManifest.fromJsonString(
        body,
        expectedAppId: config.appId,
        approvedHosts: config.approvedHosts,
      );

      final claimed = UpdateManifest.normalizeFingerprint(
        manifest.signingCertSha256,
      );
      if (claimed == null ||
          !_constantTimeEquals(claimed, config.pinnedCertSha256)) {
        return const UpdateCheckResult(
          UpdateCheckStatus.invalidManifest,
          message:
              'The update channel is signed with an unexpected certificate and was rejected.',
        );
      }

      final decision =
          UpdatePolicy.decide(installed: installed, manifest: manifest);
      if (decision == UpdateDecision.upToDate) {
        return UpdateCheckResult(
          UpdateCheckStatus.upToDate,
          manifest: manifest,
        );
      }
      return UpdateCheckResult(
        decision == UpdateDecision.required
            ? UpdateCheckStatus.required
            : UpdateCheckStatus.optional,
        manifest: manifest,
      );
    } on ManifestValidationException catch (e) {
      return UpdateCheckResult(
        UpdateCheckStatus.invalidManifest,
        message: e.message,
      );
    } on UpdateDownloadException catch (e) {
      return UpdateCheckResult(
        UpdateCheckStatus.networkError,
        message: e.message,
      );
    } on TimeoutException {
      return const UpdateCheckResult(
        UpdateCheckStatus.networkError,
        message: 'The update server took too long to respond.',
      );
    } on SocketException {
      return const UpdateCheckResult(
        UpdateCheckStatus.networkError,
        message: 'Could not reach the update server. Check your connection.',
      );
    } on http.ClientException {
      return const UpdateCheckResult(
        UpdateCheckStatus.networkError,
        message: 'Could not reach the update server. Check your connection.',
      );
    } on FormatException {
      return const UpdateCheckResult(
        UpdateCheckStatus.invalidManifest,
        message: 'The update manifest could not be read.',
      );
    }
  }

  /// Downloads, hashes, and inspects the APK. Returns the verified file only.
  ///
  /// On any failure the partial/complete file is deleted before throwing, so a
  /// corrupted download can never reach the installer.
  Future<File> downloadAndVerify(
    UpdateManifest manifest, {
    required Directory destinationDirectory,
    void Function(DownloadProgress progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final claimed = UpdateManifest.normalizeFingerprint(
      manifest.signingCertSha256,
    );
    if (claimed == null ||
        !_constantTimeEquals(claimed, config.pinnedCertSha256)) {
      throw const UpdateDownloadException(
        'untrusted_manifest',
        'Manifest signing certificate does not match the pinned release certificate.',
      );
    }

    // Defence in depth: never trust a manifest object that bypassed the parser.
    final downloadUrl = manifest.downloadUrl;
    final host = downloadUrl.host.toLowerCase();
    final approved =
        config.approvedHosts.map((h) => h.toLowerCase()).contains(host);
    if (downloadUrl.scheme.toLowerCase() != 'https' ||
        !approved ||
        !downloadUrl.path.toLowerCase().endsWith('.apk') ||
        downloadUrl.pathSegments.any((s) => s == '..' || s == '.')) {
      throw const UpdateDownloadException(
        'untrusted_url',
        'Refusing to download from an unapproved location.',
      );
    }

    final updatesDir = Directory(p.join(destinationDirectory.path, 'updates'));
    await updatesDir.create(recursive: true);

    final versionName = manifest.latest.versionName;
    if (!RegExp(r'^[0-9A-Za-z.-]+$').hasMatch(versionName)) {
      throw const UpdateDownloadException(
        'invalid_version',
        'Refusing to use an unsafe release filename.',
      );
    }
    final file = File(
      p.join(
        updatesDir.path,
        'spendsense-$versionName+${manifest.latest.buildNumber}.apk',
      ),
    );
    if (await file.exists()) {
      await file.delete();
    }

    final client = clientFactory();
    try {
      final request = http.Request('GET', manifest.downloadUrl);
      final response =
          await client.send(request).timeout(config.downloadTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateDownloadException(
          'http_${response.statusCode}',
          'Download failed with HTTP ${response.statusCode}.',
        );
      }

      final total = response.contentLength;
      final sink = file.openWrite();
      final digestSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(digestSink);
      var received = 0;

      try {
        await for (final chunk
            in response.stream.timeout(config.downloadTimeout)) {
          if (cancelToken?.isCancelled ?? false) {
            throw const UpdateCancelled();
          }
          sink.add(chunk);
          hasher.add(chunk);
          received += chunk.length;
          onProgress?.call(
            DownloadProgress(receivedBytes: received, totalBytes: total),
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      hasher.close();

      final actualHash = digestSink.value.toString().toLowerCase();
      if (!_constantTimeEquals(actualHash, manifest.sha256)) {
        throw const UpdateDownloadException(
          'hash_mismatch',
          'The downloaded update failed its integrity check.',
        );
      }

      final info = await platform.inspectApk(file.path);
      if (info == null) {
        throw const UpdateDownloadException(
          'unreadable_apk',
          'The downloaded file is not a readable APK.',
        );
      }
      if (info.packageName != config.appId) {
        throw UpdateDownloadException(
          'wrong_package',
          'The downloaded APK is for "${info.packageName}", not SpendSense.',
        );
      }
      final signer = UpdateManifest.normalizeFingerprint(info.signerSha256);
      if (signer == null ||
          !_constantTimeEquals(signer, config.pinnedCertSha256)) {
        throw const UpdateDownloadException(
          'signature_mismatch',
          'The downloaded APK is not signed by the SpendSense release key.',
        );
      }

      return file;
    } on UpdateCancelled {
      await _safeDelete(file);
      rethrow;
    } on UpdateDownloadException {
      await _safeDelete(file);
      rethrow;
    } on TimeoutException {
      await _safeDelete(file);
      throw const UpdateDownloadException(
        'timeout',
        'The download timed out. Try again on a stronger connection.',
      );
    } on SocketException {
      await _safeDelete(file);
      throw const UpdateDownloadException(
        'network',
        'The download failed because the connection was lost.',
      );
    } on http.ClientException {
      await _safeDelete(file);
      throw const UpdateDownloadException(
        'network',
        'The download failed because the connection was lost.',
      );
    } on FileSystemException {
      await _safeDelete(file);
      throw const UpdateDownloadException(
        'storage',
        'The update could not be saved. Free up device storage and retry.',
      );
    } catch (_) {
      // The doc comment promises the partial file is deleted on every failure.
      // An unmodelled exception would otherwise reach `finally` (which only
      // closes the client) and leave a stale APK in cache/updates.
      await _safeDelete(file);
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<bool> canInstallPackages() => platform.canRequestPackageInstalls();

  Future<void> openInstallPermissionSettings() =>
      platform.openInstallPermissionSettings();

  Future<void> install(File apk) async {
    if (!await platform.canRequestPackageInstalls()) {
      throw const UpdateInstallException(
        'permission_required',
        'Allow SpendSense to install updates, then try again.',
      );
    }
    await platform.installApk(apk.path);
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cleanup is best-effort; never mask the original failure.
    }
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Decodes a manifest body for callers that only need the typed object.
UpdateManifest decodeManifest(
  String body, {
  required String appId,
  required Set<String> hosts,
}) =>
    UpdateManifest.fromJsonString(body,
        expectedAppId: appId, approvedHosts: hosts);

String manifestToJson(UpdateManifest manifest) => jsonEncode({
      'schemaVersion': manifest.schemaVersion,
      'appId': manifest.appId,
      'latestVersion': manifest.latest.versionName,
      'latestBuildNumber': manifest.latest.buildNumber,
      'minimumSupportedVersion': manifest.minimum.versionName,
      'downloadUrl': manifest.downloadUrl.toString(),
      'releaseNotes': manifest.releaseNotes,
      'sha256': manifest.sha256,
      'signingCertSha256': manifest.signingCertSha256,
      if (manifest.publishedAt != null)
        'publishedAt': manifest.publishedAt!.toIso8601String(),
    });
