import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../providers/auth_provider.dart';
import '../providers/period_provider.dart';
import '../providers/sound_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/transaction_provider.dart';
import '../providers/update_provider.dart';
import '../services/sound_service.dart';
import '../services/transaction_cache_service.dart' show LedgerImportException;
import '../widgets/sms_import_prompt.dart';
import '../widgets/salary_day_prompt.dart';
import '../widgets/amount_input_dialog.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/app_page_route.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/page_entry.dart';
import '../widgets/sound_scope.dart';
import '../widgets/pressable.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import 'ai_settings_screen.dart';
import 'appearance_screen.dart';
import 'assistant_privacy_screen.dart';
import 'assistant_screen.dart';
import 'budgets_screen.dart';
import 'recurring_screen.dart';
import 'sound_settings_screen.dart';
import 'summary_screen.dart';
import 'update_screen.dart';

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

  /// The shell keeps this screen alive across tab switches, so the connection
  /// status that used to refresh on every visit (a side effect of the screen
  /// being rebuilt) is refreshed here when the tab reappears.
  bool _tabActive = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.valuesOf(context).enabled;
    if (active && !_tabActive) _checkConnectivity();
    _tabActive = active;
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (!mounted) return;
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
    final sound = SoundScope.watch(context);
    // Nullable lookup keeps Settings renderable in isolation (widget tests,
    // previews) while still showing live update state in the real app.
    final update = context.watch<UpdateProvider?>();
    final scanStart = transactions.smsScanStartDate;
    final scanLabel = scanStart == null
        ? 'Not set'
        : DateFormat('dd MMM yyyy').format(scanStart);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.tabBottomInset(context),
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
                        color: Colors.white.withValues(alpha: 0.6),
                        width: 2,
                      ),
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
                        Text(
                          auth.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.onGradient(
                            size: 18,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          auth.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.onGradient(size: 12, opacity: 0.88),
                        ),
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
              entranceIndex: 1,
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

            // Account identity only makes sense once Firebase auth is wired
            // and the user is actually signed in; hiding it otherwise keeps
            // the local-only experience unchanged.
            if (auth.isFirebaseAvailable && auth.isSignedIn) ...[
              const SizedBox(height: AppSpacing.xxl),
              _sectionLabel('Account'),
              const SizedBox(height: AppSpacing.sm),
              _SettingsCard(
                entranceIndex: 2,
                children: [
                  // Read-only: the email is managed by Firebase, so the tile
                  // has no onTap and no arrow.
                  _SettingsTile(
                    icon: Icons.mail_outline_rounded,
                    iconColor: AppColors.azure,
                    title: 'Signed in as',
                    subtitle: auth.email,
                    onTap: null,
                    showArrow: false,
                  ),
                  _divider(context),
                  // No SnackBar on success: AuthGate in main.dart swaps to
                  // the auth screen the moment isSignedIn flips to false.
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    iconColor: AppColors.danger,
                    title: 'Sign out',
                    subtitle: 'End this session on this device',
                    // Disabled while a sign-in/out is already in flight so
                    // the destructive action cannot be double-submitted.
                    onTap: auth.isBusy ? null : () => _confirmSignOut(context),
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),
            _sectionLabel('Preferences'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              entranceIndex: 2,
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
                  iconColor: AppColors.brandBright,
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
                  icon: Icons.auto_awesome_rounded,
                  iconColor: AppColors.brand,
                  title: 'SpendSense Assistant',
                  subtitle:
                      'Ask questions, preview exclusions and undo changes',
                  onTap: () {
                    AppPageRoute.pushOnce(
                      context,
                      name: AssistantScreen.routeName,
                      builder: (_) => const AssistantScreen(),
                    );
                  },
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.key_rounded,
                  iconColor: AppColors.warning,
                  title: 'SMS parsing AI keys',
                  subtitle: 'Optional legacy keys for SMS parsing only; the '
                      'assistant never uses a key from this device',
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(builder: (_) => const AISettingsScreen()),
                    );
                  },
                ),
                _divider(context),
                // Salary day drives every "per cycle" figure (Home total, the
                // budget gauge, Insights' cycle range). It is edited here and
                // only here, so this tile is the single entry point.
                Consumer<PeriodProvider>(
                  builder: (context, period, _) => _SettingsTile(
                    icon: Icons.event_repeat_rounded,
                    iconColor: AppColors.brand,
                    title: 'Salary day',
                    subtitle: 'Cycle starts on day ${period.salaryDay}',
                    onTap: () => SalaryDayPrompt.show(context),
                  ),
                ),
                _divider(context),
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    secondary: Icon(
                      Icons.history_rounded,
                      color: AppColors.azure,
                    ),
                    title: Text(
                      'Include transaction history',
                      style: AppText.bodyStrong(context),
                    ),
                    subtitle: Text(
                      theme.includeHistory
                          ? 'Home shows earlier transactions outside this cycle'
                          : 'Home shows only the current salary cycle',
                      style: AppText.bodySmall(context),
                    ),
                    value: theme.includeHistory,
                    onChanged: theme.setIncludeHistory,
                  ),
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
                  icon: Icons.donut_small_rounded,
                  iconColor: AppColors.brand,
                  title: 'Budgets & alerts',
                  subtitle: 'Category budgets and warning levels',
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(builder: (_) => const BudgetsScreen()),
                    );
                  },
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.summarize_rounded,
                  iconColor: AppColors.azure,
                  title: 'Financial summary',
                  subtitle: 'Income, spending and net cash flow',
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(builder: (_) => const SummaryScreen()),
                    );
                  },
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.graphic_eq_rounded,
                  iconColor: AppColors.brandBright,
                  title: 'Sound effects',
                  subtitle: _soundSummary(sound),
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(builder: (_) => const SoundSettingsScreen()),
                    );
                  },
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
              entranceIndex: 3,
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
                  icon: Icons.shield_outlined,
                  iconColor: AppColors.incomeGreen,
                  title: 'Assistant privacy & Gemini',
                  subtitle: 'Review exactly what cloud assistance may send',
                  onTap: () {
                    Navigator.push(
                      context,
                      AppPageRoute(
                        builder: (_) => const AssistantPrivacyScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),
            _sectionLabel('Data & backup'),
            const SizedBox(height: AppSpacing.sm),
            _SettingsCard(
              entranceIndex: 4,
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
                  icon: Icons.manage_search_rounded,
                  iconColor: AppColors.brand,
                  title: 'Recheck skipped messages',
                  subtitle: transactions.skippedMessageCount == 0
                      ? 'No messages are being skipped'
                      : '${transactions.skippedMessageCount} messages were '
                          'skipped. Scan them again.',
                  onTap: transactions.skippedMessageCount == 0
                      ? null
                      : () => _recheckSkipped(context, transactions),
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
              entranceIndex: 5,
              children: [
                _SettingsTile(
                  icon: Icons.system_update_alt_rounded,
                  iconColor: AppColors.brand,
                  title: 'Software update',
                  subtitle: _updateSummary(update),
                  onTap: update == null
                      ? null
                      : () => Navigator.of(context).push(
                            AppPageRoute(builder: (_) => const UpdateScreen()),
                          ),
                ),
                _divider(context),
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: AppColors.textTertiary(context),
                  title: 'App version',
                  subtitle: _installedVersionLabel(update),
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

  /// One-line state for the Settings tile, so the current sound mode is legible
  /// without opening the sub-screen.
  String _soundSummary(SoundProvider? sound) {
    if (sound == null || !sound.masterEnabled) return 'Muted';
    final parts = <String>[
      if (sound.uiEnabled) 'taps',
      if (sound.transactionsEnabled) 'transactions',
    ];
    if (parts.isEmpty) return 'Muted';
    return 'On · ${parts.join(' & ')}';
  }

  String _installedVersionLabel(UpdateProvider? update) {
    final installed = update?.installed;
    if (installed == null) return 'SpendSense for Android';
    return '${installed.versionName} (build ${installed.buildNumber})';
  }

  String _updateSummary(UpdateProvider? update) {
    if (update == null) return 'SpendSense release channel';
    return switch (update.state) {
      UpdateUiState.available =>
        'Version ${update.manifest?.latest.versionName ?? ''} is available',
      UpdateUiState.readyToInstall => 'Update verified — ready to install',
      UpdateUiState.downloading => 'Downloading update…',
      UpdateUiState.installing => 'Opening the installer…',
      UpdateUiState.checking => 'Checking for updates…',
      UpdateUiState.verifying => 'Verifying the download…',
      UpdateUiState.upToDate => 'Up to date',
      UpdateUiState.error => 'Last check failed — tap to retry',
      UpdateUiState.idle => update.isConfigured
          ? 'Check for the latest release'
          : 'Update channel not configured in this build',
    };
  }

  Widget _divider(BuildContext context) =>
      Divider(height: 1, indent: 60, color: AppColors.border(context));

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

  // No SnackBar on success: the app gate swaps to the auth screen by itself
  // the moment isSignedIn flips to false.
  Future<void> _confirmSignOut(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign out?', style: AppText.title(ctx)),
        content: const Text(
          'Sign out of SpendSense? Your local expense data stays on this '
          'device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign out',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await auth.signOut();
  }

  Future<void> _editBudget(
    BuildContext context,
    TransactionProvider provider,
  ) async {
    // Validated inside the dialog, against the field, so a bad entry keeps the
    // dialog open with the typed text intact.
    final savedMinor = await showAmountDialog(
      context,
      title: 'Monthly budget',
      initialText: provider.monthlyBudgetMinor > 0
          ? formatPaise(provider.monthlyBudgetMinor, trimZeroPaise: true)
          : '',
      hintText: 'e.g. 25000',
      helperText: 'Used for the dashboard budget gauge.',
    );
    if (savedMinor == null || !context.mounted) return;
    await provider.setMonthlyBudgetMinor(savedMinor);
    if (!context.mounted) return;
    SoundScope.play(context, SoundEventType.actionSucceeded);
  }

  Future<void> _exportBackup(
    BuildContext context,
    TransactionProvider provider,
  ) async {
    final includeSensitive = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export JSON backup', style: AppText.title(ctx)),
        content: const Text(
          'Safe export includes dates, amounts, merchants, categories, and '
          'transaction types. Sensitive source fields stay out. Include raw '
          'SMS, account, and reference fields only when truly needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Safe export'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Include sensitive fields'),
          ),
        ],
      ),
    );
    if (includeSensitive == null || !context.mounted) return;

    try {
      final jsonStr = await provider.exportToJson(
        includeSensitive: includeSensitive,
      );
      final directory = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp(r'[:.]'), '-')
          .replaceAll('Z', '');
      final file = File(
        path.join(directory.path, 'spendsense-backup-$stamp.json'),
      );
      await file.writeAsString(jsonStr, flush: true);
      if (!context.mounted) return;
      SoundScope.play(context, SoundEventType.actionSucceeded);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            includeSensitive
                ? 'Sensitive backup saved in app storage.'
                : 'Safe backup saved in app storage.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      SoundScope.play(context, SoundEventType.actionFailed);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup could not be saved.')),
      );
    }
  }

  void _recheckSkipped(BuildContext context, TransactionProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Recheck skipped messages?', style: AppText.title(ctx)),
        content: const Text(
          'SpendSense will read your inbox again and look at the messages it '
          'skipped before. Transactions you already have are not duplicated. '
          'Nothing is deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final n = await provider.recheckSkippedMessages();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    n == 0
                        ? 'No skipped messages to recheck.'
                        : 'Rechecked $n skipped messages.',
                  ),
                ),
              );
            },
            child: const Text('Recheck'),
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
                SoundScope.play(context, SoundEventType.actionSucceeded);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Successfully imported $count transactions!'),
                  ),
                );
              } catch (e) {
                // A rejected backup must fail loudly, say why, and leave the
                // existing transactions untouched. The reason text is fixed
                // wording from LedgerImportException; it never echoes record
                // contents.
                if (!context.mounted) return;
                SoundScope.play(context, SoundEventType.actionFailed);
                final reason = e is LedgerImportException
                    ? ' ${e.message}'
                    : ' The backup JSON could not be read.';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Import failed. Your existing transactions are '
                      'unchanged.$reason',
                    ),
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
              SoundScope.play(context, SoundEventType.actionSucceeded);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Database cleared')));
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
  final int entranceIndex;

  const _SettingsCard({required this.children, this.entranceIndex = 0});

  @override
  Widget build(BuildContext context) {
    return PageEntrance(
      index: entranceIndex,
      child: Container(
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
      ),
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
    // A tap that actually navigates gets one generic tick. Tiles that write a
    // value through a dialog own a more specific cue instead, so `onTap` here
    // stays cue-free and this handles the plain "open a screen" case.
    final handleTap = onTap == null
        ? null
        : () {
            SoundScope.play(context, SoundEventType.buttonTap);
            onTap!();
          };

    return Semantics(
      button: onTap != null,
      enabled: onTap != null,
      label: title,
      excludeSemantics: true,
      child: Pressable(
        onTap: handleTap,
        sound: null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
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
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodyStrong(context),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodySmall(context),
                      ),
                    ],
                  ],
                ),
              ),
              if (showArrow && onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary(context),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
