import 'package:flutter/services.dart';

/// Metadata extracted from an APK archive on the device.
class ApkInfo {
  final String packageName;

  /// Lowercase hex SHA-256 of the signing certificate's DER bytes, matching
  /// `keytool`/`apksigner` output. Null when the archive is unsigned or the
  /// platform could not read it.
  final String? signerSha256;

  const ApkInfo({required this.packageName, required this.signerSha256});
}

class UpdateInstallException implements Exception {
  final String code;
  final String message;
  const UpdateInstallException(this.code, this.message);

  @override
  String toString() => 'UpdateInstallException($code): $message';
}

/// Platform operations that must live in Android (APK inspection and the
/// system package installer). Kept behind an interface so update logic is
/// unit-testable without a device.
abstract class UpdatePlatform {
  Future<ApkInfo?> inspectApk(String apkPath);
  Future<bool> canRequestPackageInstalls();
  Future<void> openInstallPermissionSettings();
  Future<void> installApk(String apkPath);
}

class MethodChannelUpdatePlatform implements UpdatePlatform {
  static const MethodChannel _channel = MethodChannel('spendsense/update');

  const MethodChannelUpdatePlatform();

  @override
  Future<ApkInfo?> inspectApk(String apkPath) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getApkInfo',
      <String, dynamic>{'path': apkPath},
    );
    if (result == null) return null;
    final packageName = result['packageName'];
    if (packageName is! String || packageName.isEmpty) return null;
    final signer = result['signerSha256'];
    return ApkInfo(
      packageName: packageName,
      signerSha256: signer is String ? signer : null,
    );
  }

  @override
  Future<bool> canRequestPackageInstalls() async {
    final result =
        await _channel.invokeMethod<bool>('canRequestPackageInstalls');
    return result ?? false;
  }

  @override
  Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  @override
  Future<void> installApk(String apkPath) async {
    final result = await _channel.invokeMethod<String>(
      'installApk',
      <String, dynamic>{'path': apkPath},
    );
    if (result != 'started') {
      throw UpdateInstallException(
        result ?? 'unknown',
        switch (result) {
          'permission_required' =>
            'Install permission is required to apply this update.',
          'missing_file' => 'The downloaded update file is missing.',
          'untrusted_path' =>
            'The update file is outside the app-controlled cache directory.',
          _ => 'The Android installer could not be opened.',
        },
      );
    }
  }
}
