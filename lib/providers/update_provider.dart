import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../config/update_config.dart';
import '../models/update_manifest.dart';
import '../services/update_platform.dart';
import '../services/update_service.dart';

enum UpdateUiState {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  verifying,
  readyToInstall,
  installing,
  error,
}

/// Drives the update screen. All network/IO work is delegated to
/// [UpdateService]; this class owns UI state, duplicate-operation guards, and
/// cancellation.
class UpdateProvider extends ChangeNotifier {
  final UpdateService service;
  final Future<AppVersion> Function() installedVersionLoader;

  UpdateUiState state = UpdateUiState.idle;
  AppVersion? installed;
  UpdateManifest? manifest;
  UpdateCheckStatus? lastStatus;
  String? message;
  DownloadProgress? progress;
  File? downloadedFile;

  CancelToken? _cancelToken;
  bool _busy = false;
  bool _disposed = false;

  UpdateProvider({
    UpdateService? service,
    this.installedVersionLoader = _loadInstalledVersion,
  }) : service = service ??
            UpdateService(
              config: UpdateConfig.fromEnvironment(),
              platform: const MethodChannelUpdatePlatform(),
            );

  static Future<AppVersion> _loadInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      return AppVersion.tryParse(info.version, buildNumber: build) ??
          AppVersion(
            major: 0,
            minor: 0,
            patch: 0,
            buildNumber: build,
          );
    } catch (_) {
      return const AppVersion(major: 0, minor: 0, patch: 0, buildNumber: 0);
    }
  }

  bool get isConfigured => service.config.isConfigured;
  bool get isBusy => _busy;
  bool get canInstall => downloadedFile != null;

  /// Loads the installed version, then performs one silent check when an
  /// update channel is configured. Never blocks startup or shows a dialog.
  Future<void> init() async {
    installed = await installedVersionLoader();
    _notify();
    if (isConfigured) {
      await check(silent: true);
    }
  }

  Future<void> check({bool silent = false}) async {
    if (_busy && !silent) return;
    if (_busy) return;
    _busy = true;
    state = UpdateUiState.checking;
    message = null;
    _notify();

    final installedVersion = installed ?? await installedVersionLoader();
    installed = installedVersion;

    final result = await service.checkForUpdates(installed: installedVersion);
    lastStatus = result.status;
    manifest = result.manifest;
    message = result.message;

    switch (result.status) {
      case UpdateCheckStatus.notConfigured:
        state = UpdateUiState.idle;
        break;
      case UpdateCheckStatus.upToDate:
        state = UpdateUiState.upToDate;
        break;
      case UpdateCheckStatus.optional:
      case UpdateCheckStatus.required:
        state = UpdateUiState.available;
        break;
      case UpdateCheckStatus.invalidManifest:
      case UpdateCheckStatus.networkError:
        state = UpdateUiState.error;
        break;
    }

    _busy = false;
    _notify();
  }

  Future<void> download() async {
    final available = manifest;
    if (_busy || available == null) return;
    _busy = true;
    state = UpdateUiState.downloading;
    progress = const DownloadProgress(receivedBytes: 0);
    message = null;
    downloadedFile = null;
    _cancelToken = CancelToken();
    _notify();

    try {
      final temp = await getTemporaryDirectory();
      final file = await service.downloadAndVerify(
        available,
        destinationDirectory: temp,
        cancelToken: _cancelToken,
        onProgress: (p) {
          progress = p;
          _notify();
        },
      );
      downloadedFile = file;
      state = UpdateUiState.readyToInstall;
    } on UpdateCancelled {
      state = UpdateUiState.available;
      message = 'Download cancelled.';
    } on UpdateDownloadException catch (e) {
      state = UpdateUiState.error;
      message = e.message;
    } catch (_) {
      state = UpdateUiState.error;
      message = 'The update could not be downloaded. Try again.';
    } finally {
      _busy = false;
      _cancelToken = null;
      _notify();
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel();
  }

  Future<void> install() async {
    final file = downloadedFile;
    if (_busy || file == null) return;
    _busy = true;
    state = UpdateUiState.installing;
    message = null;
    _notify();

    try {
      await service.install(file);
      message = 'The Android installer was opened. Follow its prompts.';
      state = UpdateUiState.readyToInstall;
    } on UpdateInstallException catch (e) {
      message = e.message;
      state = UpdateUiState.readyToInstall;
    } catch (_) {
      message = 'The installer could not be opened.';
      state = UpdateUiState.readyToInstall;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> hasInstallPermission() => service.canInstallPackages();

  Future<void> requestInstallPermission() =>
      service.openInstallPermissionSettings();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelToken?.cancel();
    super.dispose();
  }
}
