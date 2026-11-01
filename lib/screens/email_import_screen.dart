import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/transaction_provider.dart';
import '../services/email/gmail_email_source.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';

/// Gmail import settings.
///
/// This is a separate, explicit consent from SMS cloud parsing: enabling it
/// reads the user's own bank alert emails on-device with a read-only scope.
/// Nothing is sent to SpendSense servers; the Gmail token stays in the app
/// process and is discarded on disconnect.
class EmailImportScreen extends StatefulWidget {
  const EmailImportScreen({super.key});

  @override
  State<EmailImportScreen> createState() => _EmailImportScreenState();
}

class _EmailImportScreenState extends State<EmailImportScreen> {
  final _source = GmailEmailSource();
  final _senderController = TextEditingController();

  bool _loading = true;
  bool _consent = false;
  bool _busy = false;
  String? _connectedEmail;
  DateTime? _lastSync;
  List<String> _domains = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _senderController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final consent = await _source.hasConsent();
    final email = await _source.connectedEmail();
    final last = await _source.lastScanAt();
    final domains = await _source.senderDomains();
    if (!mounted) return;
    setState(() {
      _consent = consent;
      _connectedEmail = email;
      _lastSync = last;
      _domains = domains;
      _loading = false;
    });
  }

  Future<bool> _confirmConsent() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect Gmail?'),
        content: const Text(
          'SpendSense will ask Google for read-only access to your Gmail '
          '(gmail.readonly). It searches only messages from the bank sender '
          'domains below for transaction alerts.\n\n'
          'Messages are read on this device. The raw email body is not stored '
          'in the ledger. SpendSense cannot send, delete or modify email, and '
          'does not upload your mailbox to its servers.\n\n'
          'You can disconnect at any time; disconnecting clears this consent '
          'and signs out of Google. If this device is managed by an '
          'organisation, its policies may also apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('I understand, connect'),
          ),
        ],
      ),
    );
    return accepted == true;
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _confirmConsent()) return;
      await _source.setConsent(true);
      final email = await _source.connect();
      if (!mounted) return;
      setState(() {
        _consent = true;
        _connectedEmail = email;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gmail connected')),
      );
    } on EmailAuthUnavailableException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // Never surface provider/exception text; it can contain account detail.
      if (mounted) {
        setState(() => _error = 'Gmail could not be connected.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      await _source.disconnect();
      if (!mounted) return;
      setState(() {
        _consent = false;
        _connectedEmail = null;
        _lastSync = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gmail disconnected')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNow() async {
    final transactions = context.read<TransactionProvider>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final imported = await transactions.importFromGmail(source: _source);
      final last = await _source.lastScanAt();
      if (!mounted) return;
      setState(() => _lastSync = last);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported == 0
                ? 'No new bank emails'
                : 'Imported $imported email transaction(s)',
          ),
        ),
      );
    } on EmailImportBusyException {
      if (mounted) {
        setState(() => _error = 'Another sync is running. Try again shortly.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Email sync failed. Try again later.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSender() async {
    final value = _senderController.text.trim();
    if (value.isEmpty) return;
    final rejected = await _source.setSenderDomains([..._domains, value]);
    final updated = await _source.senderDomains();
    if (!mounted) return;
    setState(() {
      _domains = updated;
      // Only clear the field when the entry was actually accepted, so a typo
      // stays on screen to be corrected instead of vanishing.
      if (rejected.isEmpty) _senderController.clear();
    });
    if (rejected.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '“$value” is not an email domain. Try a domain such as '
            'red.slice.bank.in, or paste the full sender address.',
          ),
        ),
      );
    }
  }

  Future<void> _removeSender(String domain) async {
    await _source.setSenderDomains(
      _domains.where((d) => d != domain).toList(),
    );
    final updated = await _source.senderDomains();
    if (!mounted) return;
    setState(() => _domains = updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold(context),
      appBar: AppBar(
        title: const Text('Email import'),
        backgroundColor: Colors.transparent,
      ),
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
                  _infoCard(
                    context,
                    'Bank emails are read on this device with read-only Gmail '
                    'access. This is separate from SMS cloud parsing and stays '
                    'off until you connect.',
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: AppText.bodySmall(context)
                            .copyWith(color: AppColors.danger),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  _card(
                    context,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _consent
                                ? Icons.mark_email_read_rounded
                                : Icons.mail_outline_rounded,
                            color:
                                _consent ? AppColors.incomeGreen : AppColors.brand,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _consent
                                      ? 'Gmail connected'
                                      : 'Gmail not connected',
                                  style: AppText.title(context),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _connectedEmail ??
                                      (_consent
                                          ? 'Read-only Gmail access'
                                          : 'No email access'),
                                  style: AppText.bodySmall(context),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        _lastSync == null
                            ? 'Last sync: never'
                            : 'Last sync: ${_lastSync!.toLocal()}',
                        style: AppText.bodySmall(context),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (!_consent)
                        FilledButton.icon(
                          onPressed: _busy ? null : _connect,
                          icon: const Icon(Icons.login_rounded, size: 18),
                          label: const Text('Connect Gmail'),
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _syncNow,
                                icon: const Icon(Icons.sync_rounded, size: 18),
                                label: const Text('Sync now'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            OutlinedButton(
                              onPressed: _busy ? null : _disconnect,
                              child: const Text('Disconnect'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Bank sender domains', style: AppText.label(context)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Only exact domains are accepted. Add a bank only after '
                    'checking the sender address in a real alert email.',
                    style: AppText.bodySmall(context),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _card(
                    context,
                    children: [
                      TextField(
                        controller: _senderController,
                        decoration: const InputDecoration(
                          hintText: 'alerts.bank.example',
                          suffixIcon: Icon(Icons.add_rounded),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addSender(),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final domain in _domains)
                            InputChip(
                              label: Text(domain),
                              onDeleted: _busy
                                  ? null
                                  : () => _removeSender(domain),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _infoCard(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.brand.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: AppColors.brand, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: AppText.body(context).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
