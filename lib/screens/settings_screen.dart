import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/transaction_provider.dart';
import '../widgets/sms_import_prompt.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/app_page_route.dart';
import '../widgets/gradient_hero_card.dart';
import '../utils/formatters.dart';
import 'ai_settings_screen.dart';
import 'appearance_screen.dart';
import 'recurring_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isConnected = true;
  String _connectionType = 'WiFi';

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() {
      _isConnected = result != ConnectivityResult.none;
      _connectionType =
          _isConnected ? _getConnectionLabel(result) : 'No Connection';
    });
  }

  String _getConnectionLabel(ConnectivityResult result) {
    switch (result) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'Mobile Data';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.bluetooth:
        return 'Bluetooth';
      case ConnectivityResult.vpn:
        return 'VPN';
      case ConnectivityResult.other:
      case ConnectivityResult.none:
        return 'No Connection';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = context.watch<ThemeProvider>();
    final transactions = context.watch<TransactionProvider>();
    final scanStart = transactions.smsScanStartDate;
    final scanLabel = scanStart == null
        ? 'Not set'
        : DateFormat('dd MMM yyyy').format(scanStart);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.fabClearance,
          ),
          children: [
            Text('Settings', style: AppText.h1(context)),
            const SizedBox(height: AppSpacing.lg),

            // ── Profile hero ───────────────────────────────────────────────
            GradientHeroCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.6), width: 2),
                    ),
                    child: ClipOval(
                      child: ProfileAvatar(
                        imageBytes: auth.profileImageBytes,
                        name: auth.name,
                        radius: 31,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(auth.name,
                            style: AppText.onGradient(
                                size: 18, weight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(auth.email,
                            style: AppText.onGradient(size: 12, opacity: 0.88)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),
            _sectionLabel('Personalisation'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.person_outline_rounded,
                  iconColor: AppColors.brand,
                  title: 'Your name',
                  subtitle: auth.greetingName.isEmpty
                      ? 'Not set — used in your Home greeting'
                      : 'Greeting you as ${auth.name}',
                  onTap: () => _editName(context, auth),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),
            _sectionLabel('Preferences'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.photo_camera_back_rounded,
                  iconColor: AppColors.brand,
                  title: 'Profile photo',
                  subtitle: auth.hasProfileImage
                      ? 'Change your profile image'
                      : 'Add your profile image',
                  onTap: () => _pickProfilePhoto(context),
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.sms_rounded,
                  iconColor: AppColors.cyan,
                  title: 'SMS start date',
                  subtitle: 'Checking messages from $scanLabel',
                  onTap: () => SmsImportPrompt.show(context),
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.palette_outlined,
                  iconColor: AppColors.azure,
                  title: 'Appearance',
                  subtitle:
                      '${theme.palette.label} · ${AppearanceScreen.modeLabel(theme.themeMode)}',
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(builder: (_) => const AppearanceScreen()),
                    );
                  },
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.key_rounded,
                  iconColor: AppColors.amber,
                  title: 'AI provider settings',
                  subtitle: 'Configure API keys for AI parsing',
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(builder: (_) => const AISettingsScreen()),
                    );
                  },
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.savings_rounded,
                  iconColor: AppColors.incomeGreen,
                  title: 'Monthly budget',
                  subtitle: transactions.monthlyBudget > 0
                      ? '${Formatters.currency.format(transactions.monthlyBudget)} per cycle'
                      : 'Not set — the dashboard gauge needs one',
                  onTap: () => _editBudget(context, transactions),
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.repeat_rounded,
                  iconColor: AppColors.brandBright,
                  title: 'Recurring expenses',
                  subtitle: 'Review repeat payments detected from your SMS',
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(builder: (_) => const RecurringScreen()),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),
            _sectionLabel('Network'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: _isConnected ? Icons.wifi : Icons.wifi_off,
                  iconColor:
                      _isConnected ? AppColors.incomeGreen : AppColors.danger,
                  title: 'Internet connection',
                  subtitle: _isConnected
                      ? 'Connected via $_connectionType'
                      : 'No internet connection',
                  onTap: _checkConnectivity,
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.cloud_outlined,
                  iconColor: AppColors.brand,
                  title: 'AI services',
                  subtitle: 'Groq & Gemini fallback configured',
                  onTap: null,
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),
            _sectionLabel('Data & backup'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.upload_file_rounded,
                  iconColor: AppColors.brand,
                  title: 'Export JSON backup',
                  subtitle: 'Save all transactions to backup JSON',
                  onTap: () => _exportBackup(context, transactions),
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.download_rounded,
                  iconColor: AppColors.incomeGreen,
                  title: 'Import JSON backup',
                  subtitle: 'Restore transactions from backup JSON',
                  onTap: () => _importBackup(context, transactions),
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.delete_sweep_outlined,
                  iconColor: AppColors.danger,
                  title: 'Clear transaction database',
                  subtitle: 'Remove locally stored transaction data',
                  onTap: () => _showClearCacheDialog(context),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),
            _sectionLabel('About'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              children: const [
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: Color(0xFF8FA3C4),
                  title: 'App version',
                  subtitle: '2.0.0 (Local-First)',
                  onTap: null,
                  showArrow: false,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(label.toUpperCase(), style: AppText.overline(context)),
      );

  Widget _divider(BuildContext context) => Divider(
        height: 1,
        indent: 60,
        color: AppColors.border(context),
      );

  Future<void> _editName(BuildContext context, AuthProvider auth) async {
    final controller = TextEditingController(text: auth.greetingName);
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Your name', style: AppText.title(context)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Chaitanya',
            helperText:
                'Shown in your Home greeting. Leave blank to remove it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (saved == null || !context.mounted) return;
    await auth.updateName(saved);
  }

  Future<void> _editBudget(
      BuildContext context, TransactionProvider provider) async {
    final controller = TextEditingController(
      text: provider.monthlyBudget > 0
          ? provider.monthlyBudget.toStringAsFixed(0)
          : '',
    );
    final saved = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Monthly budget', style: AppText.title(context)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            hintText: 'e.g. 25000',
            helperText: 'Used for the dashboard budget gauge.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (saved == null || !context.mounted) return;
    if (saved <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a budget greater than zero')),
      );
      return;
    }
    await provider.setMonthlyBudget(saved.toDouble());
  }

  Future<void> _exportBackup(
      BuildContext context, TransactionProvider provider) async {
    final jsonStr = await provider.exportToJson();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export JSON backup', style: AppText.title(ctx)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Copy your backup JSON data below:'),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt(ctx),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonStr,
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Backup copied to clipboard!')),
              );
            },
            child: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  void _importBackup(BuildContext context, TransactionProvider provider) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Import JSON backup', style: AppText.title(ctx)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Paste your backup JSON data below:'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: '{"version": 2, "transactions": [...]}',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty) return;
              try {
                final count = await provider.importFromJson(text);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Successfully imported $count transactions!')),
                );
              } catch (_) {
                // A malformed backup must fail loudly instead of throwing an
                // uncaught error and leaving the user with no feedback.
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Import failed — the backup JSON could not be read.'),
                  ),
                );
              }
            },
            child: const Text('Restore'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear database?', style: AppText.title(ctx)),
        content: const Text(
          'This will remove all locally stored transactions. Your SMS inbox is unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<TransactionProvider>().clearAll();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Database cleared')),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickProfilePhoto(BuildContext context) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    await context.read<AuthProvider>().updateProfileImage(base64Encode(bytes));
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showArrow;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 19, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppText.title(context).copyWith(fontSize: 14)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: AppText.body(context).copyWith(fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (showArrow && onTap != null)
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary(context), size: 20),
          ],
        ),
      ),
    );
  }
}
