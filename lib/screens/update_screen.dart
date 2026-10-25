import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/update_provider.dart';
import '../services/update_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';
import '../widgets/app_button.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

/// Settings → Software update.
///
/// Read-only diagnostics plus the three user actions: check, download, install.
/// Nothing here runs automatically except the quiet check the provider already
/// started at app launch; opening this screen never fires a sound cue.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  @override
  void initState() {
    super.initState();
    // If launch-time check was skipped (no channel configured) or already
    // finished, a manual open is the natural place to refresh. The provider
    // guards against overlapping checks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<UpdateProvider>();
      if (provider.isConfigured &&
          provider.state == UpdateUiState.idle &&
          !provider.isBusy) {
        provider.check();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UpdateProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Software update')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
              AppSpacing.page,
              AppSpacing.xxxl,
            ),
            children: [
              const SectionHeader(title: 'Installed version'),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.installed == null
                          ? 'Reading version…'
                          : provider.installed!.versionName,
                      style: AppText.display(context),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      provider.installed == null
                          ? 'SpendSense for Android'
                          : 'Build ${provider.installed!.buildNumber} · '
                              'com.example.spendsense',
                      style: AppText.body(context),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _StatusPill(provider: provider),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Update status'),
              _StatusBody(provider: provider),
              if (provider.manifest != null &&
                  provider.state == UpdateUiState.available) ...[
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: "What's new"),
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${provider.manifest!.latest.versionName} '
                        '(build ${provider.manifest!.latest.buildNumber})',
                        style: AppText.title(context),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (provider.manifest!.releaseNotes.isEmpty)
                        Text(
                          'No release notes were provided.',
                          style: AppText.body(context),
                        )
                      else
                        ...provider.manifest!.releaseNotes.map(
                          (note) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    right: AppSpacing.sm,
                                  ),
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: AppColors.brand,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child:
                                      Text(note, style: AppText.body(context)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'How updates are verified'),
              GlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.verified_user_outlined,
                      color: Color(0xFF2E7D5B),
                      size: 22,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Checked twice, then handed to Android',
                            style: AppText.title(context),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'SpendSense downloads the APK over HTTPS, verifies '
                            'its SHA-256, and confirms it is signed by the '
                            'pinned SpendSense release certificate before the '
                            'system installer opens. A failed check deletes the '
                            'file; nothing is installed silently.',
                            style: AppText.body(context),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Certificate '
                            '42c8:f876:…:d367',
                            style: AppText.overline(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your transactions stay on this device. Updating does not '
                'uninstall the app, and you can export a backup from Settings '
                'at any time. Removing the app would delete local data.',
                style: AppText.label(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final UpdateProvider provider;

  const _StatusPill({required this.provider});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (provider.state) {
      UpdateUiState.checking => ('Checking…', AppColors.brand),
      UpdateUiState.upToDate => ('Up to date', AppColors.incomeGreen),
      UpdateUiState.available =>
        provider.lastStatus == UpdateCheckStatus.required
            ? ('Required update', AppColors.danger)
            : ('Update available', AppColors.brand),
      UpdateUiState.downloading => ('Downloading…', AppColors.brand),
      UpdateUiState.verifying => ('Verifying…', AppColors.brand),
      UpdateUiState.readyToInstall => (
          'Ready to install',
          AppColors.incomeGreen
        ),
      UpdateUiState.installing => ('Installing…', AppColors.brand),
      UpdateUiState.error => ('Update check failed', AppColors.danger),
      UpdateUiState.idle => (
          'Not checked yet',
          AppColors.textTertiary(context)
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: AppText.label(context).copyWith(color: color),
      ),
    );
  }
}

class _StatusBody extends StatelessWidget {
  final UpdateProvider provider;

  const _StatusBody({required this.provider});

  @override
  Widget build(BuildContext context) {
    switch (provider.state) {
      case UpdateUiState.checking:
        return const _MessageCard(
          icon: Icons.sync_rounded,
          title: 'Checking for updates…',
          body: 'This only takes a moment and never interrupts your work.',
          showSpinner: true,
        );

      case UpdateUiState.idle:
        return _MessageCard(
          icon: Icons.cloud_off_outlined,
          title: 'No update channel configured',
          body: provider.isConfigured
              ? 'Tap below to check for a new version.'
              : 'This build was compiled without an update manifest URL, so '
                  'there is nothing to check. Install a release build to '
                  'receive updates.',
          action: provider.isConfigured
              ? AppPrimaryButton(
                  label: 'Check for updates',
                  icon: Icons.refresh_rounded,
                  onPressed: () => provider.check(),
                )
              : null,
        );

      case UpdateUiState.upToDate:
        return _MessageCard(
          icon: Icons.check_circle_outline_rounded,
          title: "You're up to date",
          body: provider.installed == null
              ? 'The latest available version is installed.'
              : 'Version ${provider.installed!.versionName} '
                  '(build ${provider.installed!.buildNumber}) is the latest '
                  'release.',
          action: AppGhostButton(
            label: 'Check again',
            icon: Icons.refresh_rounded,
            onPressed: () => provider.check(),
          ),
        );

      case UpdateUiState.available:
        final manifest = provider.manifest;
        final required = provider.lastStatus == UpdateCheckStatus.required;
        return _MessageCard(
          icon: required ? Icons.warning_amber_rounded : Icons.system_update,
          title: required
              ? 'This version is no longer supported'
              : 'Version ${manifest?.latest.versionName ?? ''} is available',
          body: required
              ? 'Version ${provider.installed?.versionName ?? ''} is below the '
                  'minimum supported version. Update to keep receiving fixes. '
                  'You can keep using the app and export your data from '
                  'Settings at any time — updating never deletes transactions.'
              : 'Download and install the latest SpendSense release. Your data '
                  'stays on this device.',
          tint: required ? AppColors.danger : null,
          action: Column(
            children: [
              if (required) ...[
                const _RequiredNotice(),
                const SizedBox(height: AppSpacing.md),
              ],
              AppPrimaryButton(
                label: 'Download update',
                icon: Icons.download_rounded,
                onPressed: () => provider.download(),
              ),
            ],
          ),
        );

      case UpdateUiState.downloading:
        return _MessageCard(
          icon: Icons.downloading_rounded,
          title: 'Downloading update…',
          body: _progressLabel(provider.progress),
          progress: provider.progress?.fraction,
          action: AppGhostButton(
            label: 'Cancel download',
            icon: Icons.close_rounded,
            onPressed: provider.cancelDownload,
          ),
        );

      case UpdateUiState.verifying:
        return const _MessageCard(
          icon: Icons.fingerprint_rounded,
          title: 'Verifying the download',
          body: 'Checking the SHA-256 digest and the APK signing certificate.',
          showSpinner: true,
        );

      case UpdateUiState.readyToInstall:
        return _MessageCard(
          icon: Icons.install_mobile_rounded,
          title: 'Update ready to install',
          body: provider.message ??
              'Android will ask you to confirm the install. SpendSense cannot '
                  'install anything without that confirmation.',
          action: AppPrimaryButton(
            label: 'Install update',
            icon: Icons.system_update_alt_rounded,
            onPressed: () => _startInstall(context, provider),
          ),
        );

      case UpdateUiState.installing:
        return const _MessageCard(
          icon: Icons.install_mobile_rounded,
          title: 'Opening the installer…',
          body: 'Follow the prompts from Android to finish the update.',
          showSpinner: true,
        );

      case UpdateUiState.error:
        return _MessageCard(
          icon: Icons.error_outline_rounded,
          title: 'Update check failed',
          body: provider.message ?? 'Something went wrong. Try again.',
          tint: AppColors.danger,
          action: AppPrimaryButton(
            label: provider.manifest == null ? 'Try again' : 'Download again',
            icon: Icons.refresh_rounded,
            onPressed: () {
              if (provider.manifest == null) {
                provider.check();
              } else {
                provider.download();
              }
            },
          ),
        );
    }
  }

  Future<void> _startInstall(
    BuildContext context,
    UpdateProvider provider,
  ) async {
    final allowed = await provider.hasInstallPermission();
    if (!context.mounted) return;
    if (!allowed) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Allow installs from SpendSense'),
          content: const Text(
            'Android requires your permission before any app can install an '
            'APK. Tap Continue, enable "Allow from this source", then come '
            'back and tap Install again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (proceed == true) {
        await provider.requestInstallPermission();
      }
      return;
    }
    await provider.install();
  }

  static String _progressLabel(DownloadProgress? progress) {
    if (progress == null) return 'Starting the download…';
    final fraction = progress.fraction;
    final receivedMb = progress.receivedBytes / (1024 * 1024);
    if (fraction == null) {
      return '${receivedMb.toStringAsFixed(1)} MB downloaded';
    }
    return '${(fraction * 100).toStringAsFixed(0)}% · '
        '${receivedMb.toStringAsFixed(1)} MB';
  }
}

class _RequiredNotice extends StatelessWidget {
  const _RequiredNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, size: 18, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'This update is recommended for security. If you choose not to '
              'update now, SpendSense keeps working and your data stays '
              'exportable from Settings.',
              style: AppText.label(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final double? progress;
  final bool showSpinner;
  final Color? tint;

  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.progress,
    this.showSpinner = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppColors.brand;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.title(context)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(body, style: AppText.body(context)),
                  ],
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
          if (showSpinner) ...[
            const SizedBox(height: AppSpacing.md),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
