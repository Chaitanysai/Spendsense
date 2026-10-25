import 'package:flutter/material.dart';

import '../providers/assistant_controller.dart';
import '../services/assistant/assistant_audit.dart';
import '../services/assistant/assistant_auth.dart';
import '../services/assistant/assistant_settings.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';

class AssistantPrivacyScreen extends StatefulWidget {
  final AssistantController? controller;

  const AssistantPrivacyScreen({super.key, this.controller});

  @override
  State<AssistantPrivacyScreen> createState() => _AssistantPrivacyScreenState();
}

class _AssistantPrivacyScreenState extends State<AssistantPrivacyScreen> {
  final _store = PreferencesAssistantConsentStore();
  bool _loading = true;
  bool _consent = false;
  bool _clearingAudit = false;

  bool get _configured =>
      widget.controller?.cloudConfigured ??
      (AssistantConfig.isCloudConfigured &&
          const FirebaseAppCheckTokenProvider().isConfigured &&
          const FirebaseAssistantIdentityTokenProvider().isConfigured);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = widget.controller;
    final value = controller != null
        ? controller.cloudConsent
        : await _store.hasCloudConsent();
    if (!mounted) return;
    setState(() {
      _consent = value;
      _loading = false;
    });
  }

  Future<void> _setConsent(bool value) async {
    if (widget.controller != null) {
      await widget.controller!.setCloudConsent(value);
    } else {
      await _store.setCloudConsent(value);
    }
    if (!mounted) return;
    setState(() => _consent = value);
  }

  Future<void> _confirmEnable() async {
    final allow = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable Gemini assistance?'),
        content: const SingleChildScrollView(
          child: Text(
            '${AssistantPrivacy.summary}\n\n'
            'Only the matching rows needed for your question are sent, never '
            'your full ledger, raw SMS, account numbers or keys. The Gemini API '
            'key stays on the SpendSense backend. You can turn this off at any '
            'time. Local commands keep working offline.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep off'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Allow cloud assistance'),
          ),
        ],
      ),
    );
    if (allow == true) await _setConsent(true);
  }

  Future<void> _clearAudit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear assistant audit trail?'),
        content: const Text(
          'This deletes the encrypted local history of assistant-initiated '
          'changes, including undo copies. Existing transactions are not '
          'changed. Past assistant changes can no longer be undone after this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear audit trail'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearingAudit = true);
    try {
      await EncryptedAssistantAuditRepository().clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assistant audit trail cleared')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The audit trail could not be cleared')),
      );
    } finally {
      if (mounted) setState(() => _clearingAudit = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Assistant privacy')),
      body: AppBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.page,
                  AppSpacing.sm,
                  AppSpacing.page,
                  AppSpacing.xxl,
                ),
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _configured
                                  ? Icons.cloud_done_rounded
                                  : Icons.cloud_off_rounded,
                              color: _configured
                                  ? AppColors.incomeGreen
                                  : AppColors.textTertiary(context),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _configured
                                    ? 'Secure proxy + App Check configured'
                                    : 'Gemini cloud assistance not configured',
                                style: AppText.title(context)
                                    .copyWith(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _configured
                              ? 'The Gemini API key is held by the SpendSense '
                                  'backend, never in this app. Requests carry a '
                                  'short-lived Firebase App Check token proving '
                                  'this app installation plus a short-lived '
                                  'Firebase sign-in ID token for your account. '
                                  'SpendSense sends only the minimum context '
                                  'described below.'
                              : 'This build is missing the secure backend URL '
                                  'and/or Firebase authentication configuration, '
                                  'so no cloud request is sent. Deterministic '
                                  'local commands remain fully available. See the '
                                  'setup report for the required configuration.',
                          style: AppText.body(context).copyWith(height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                        AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _consent,
                      onChanged: !_configured
                          ? null
                          : (value) async {
                              if (value) {
                                await _confirmEnable();
                              } else {
                                await _setConsent(false);
                              }
                            },
                      title: Text('Allow Gemini cloud assistance',
                          style: AppText.title(context).copyWith(fontSize: 14)),
                      subtitle: Text(
                        'Off by default. Local commands never need this.',
                        style: AppText.body(context).copyWith(fontSize: 11.5),
                      ),
                      activeThumbColor: AppColors.brand,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _sectionLabel('What is sent when enabled'),
                  const SizedBox(height: AppSpacing.sm),
                  _BulletCard(
                    icon: Icons.upload_rounded,
                    color: AppColors.amber,
                    items: AssistantPrivacy.sent,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _sectionLabel('What is never sent'),
                  const SizedBox(height: AppSpacing.sm),
                  _BulletCard(
                    icon: Icons.shield_outlined,
                    color: AppColors.incomeGreen,
                    items: AssistantPrivacy.neverSent,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _sectionLabel('Your controls'),
                  const SizedBox(height: AppSpacing.sm),
                  GlassCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Financial data stays local by default.',
                            style:
                                AppText.title(context).copyWith(fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          'Server-side rate limits, request caps, a maximum of '
                          '4 tool rounds and a timeout apply to cloud '
                          'requests. The backend does not persist prompts or '
                          'transactions.',
                          style: AppText.body(context)
                              .copyWith(fontSize: 11.5, height: 1.4),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton.icon(
                          onPressed: _clearingAudit ? null : _clearAudit,
                          icon:
                              const Icon(Icons.delete_sweep_outlined, size: 18),
                          label: Text(_clearingAudit
                              ? 'Clearing…'
                              : 'Clear encrypted assistant audit trail'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: AppText.overline(context),
      );
}

class _BulletCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final List<String> items;

  const _BulletCard({
    required this.icon,
    required this.color,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: AppSpacing.sm),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(item,
                        style: AppText.body(context)
                            .copyWith(fontSize: 11.5, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
