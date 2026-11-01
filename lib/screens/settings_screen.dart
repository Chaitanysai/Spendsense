import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../providers/auth_provider.dart';
import '../services/auth/auth_service.dart';
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
import '../widgets/glass_card.dart';
import '../widgets/gradient_hero_card.dart';
import '../widgets/page_entry.dart';
import '../widgets/sound_scope.dart';
import '../widgets/pressable.dart';
import '../widgets/icon_well.dart';
import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import 'ai_settings_screen.dart';
import 'appearance_screen.dart';
import 'assistant_privacy_screen.dart';
import 'assistant_screen.dart';
import 'budgets_screen.dart';
import 'email_import_screen.dart';
import 'recurring_screen.dart';
import 'sound_settings_screen.dart';
import 'summary_screen.dart';
import 'update_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// Every palette role a `_SettingsTile` paints its glyph in.
  ///
  /// Each lands on a 12%/22% tint of itself, so each must resolve through
  /// [AppColors.inkOn]. These are the roles used *today* — the test asserts the
  /// list matches the file exactly, so a new `iconColor: AppColors.x` fails the
  /// build until it is audited here. Keys whose raw-on-tint ratio is below
  /// 4.5:1 are recorded in `test/settings_icon_contrast_test.dart`.
  static const List<String> tileRoles = [
    'brand',
    'azure',
    'brandBright',
    'danger',
    'warning',
    'incomeGreen',
    'textTertiary',
  ];

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

    // ── Icon colour semantics ────────────────────────────────────────────────
    // Colour answers exactly one question: which part of the app is this row
    // about? One colour per section, stated once so it can be extended:
    //
    //   Personalisation    brand        — who the app greets and how it looks
    //   Spending & budgets incomeGreen  — money in, money out, money plans
    //   Data sources       azure        — where entries come from (SMS,
    //                                   email, AI keys) and the connection
    //                                   they travel over
    //   Assistant          brandBright  — the Gemini features
    //   Backup             warning      — file operations that deserve care
    //
    // Two global exceptions override any section colour: destructive rows are
    // always `danger` (Sign out, Clear transaction database) and read-only
    // rows are always `textTertiary` (Signed in as, App version). Glyphs are
    // uniformly the outlined weight of the rounded family — switching weight
    // row by row read as unfinished — and every glyph rides IconWell →
    // AppColors.inkOn; the audited set lives in SettingsScreen.tileRoles.

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
                        const SizedBox(height: AppSpacing.xs),
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

            // Identity and look: the rows that change how SpendSense talks to
            // you. Previously five of these lived in a 13-row "Preferences"
            // dumping ground and "Personalisation" held one tile.
            _section(context, 'Personalisation', 1, [
              _SettingsTile(
                icon: Icons.person_outlined,
                iconColor: AppColors.brand,
                title: 'Your name',
                subtitle: auth.greetingName.isEmpty
                    ? 'Used in your Home greeting'
                    : 'Greeting you as ${auth.name}',
                onTap: () => _editName(context, auth),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.photo_camera_back_outlined,
                iconColor: AppColors.brand,
                title: 'Profile photo',
                subtitle: auth.hasProfileImage
                    ? 'Change your profile photo'
                    : 'Add your profile photo',
                onTap: () => _pickProfilePhoto(context),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.palette_outlined,
                iconColor: AppColors.brand,
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
                icon: Icons.graphic_eq_outlined,
                iconColor: AppColors.brand,
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
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  // Same plate and lifted ink as every _SettingsTile row:
                  // a bare 24dp glyph in the raw palette role was the one
                  // icon in this card that read as a different weight.
                  secondary: IconWell(
                    icon: Icons.history_outlined,
                    color: AppColors.brand,
                  ),
                  title: Text(
                    'Include transaction history',
                    style: AppText.bodyStrong(context),
                  ),
                  subtitle: Text(
                    theme.includeHistory
                        ? 'Home also shows earlier cycles'
                        : 'Home shows the current cycle',
                    style: AppText.bodySmall(context),
                  ),
                  value: theme.includeHistory,
                  onChanged: theme.setIncludeHistory,
                ),
              ),
            ]),

            // Everything that produces a number the ledger depends on: the
            // cycle boundary, the gauge, per-category budgets and repeat
            // payments. One colour says these rows all move money.
            _section(context, 'Spending & budgets', 2, [
              // Salary day drives every "per cycle" figure (Home total, the
              // budget gauge, Insights' cycle range). It is edited here and
              // only here, so this tile is the single entry point.
              Consumer<PeriodProvider>(
                builder: (context, period, _) => _SettingsTile(
                  icon: Icons.event_repeat_outlined,
                  iconColor: AppColors.incomeGreen,
                  title: 'Salary day',
                  subtitle: 'Cycle starts on day ${period.salaryDay}',
                  onTap: () => SalaryDayPrompt.show(context),
                ),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.savings_outlined,
                iconColor: AppColors.incomeGreen,
                title: 'Monthly budget',
                subtitle: transactions.monthlyBudget > 0
                    ? '${Formatters.currency.format(transactions.monthlyBudget)} per cycle'
                    : 'Needed by the Home gauge',
                onTap: () => _editBudget(context, transactions),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.donut_small_outlined,
                iconColor: AppColors.incomeGreen,
                title: 'Budgets & alerts',
                subtitle: 'Per-category limits and alerts',
                onTap: () {
                  Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const BudgetsScreen()),
                  );
                },
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.repeat_outlined,
                iconColor: AppColors.incomeGreen,
                title: 'Recurring expenses',
                subtitle: 'Repeat payments from your SMS',
                onTap: () {
                  Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const RecurringScreen()),
                  );
                },
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.summarize_outlined,
                iconColor: AppColors.incomeGreen,
                title: 'Financial summary',
                subtitle: 'Income, spending and cash flow',
                onTap: () {
                  Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const SummaryScreen()),
                  );
                },
              ),
            ]),

            // Where entries come from and the pipe they travel through: the
            // connection, bank SMS, bank alert email and the optional keys
            // that parse them.
            _section(context, 'Data sources', 3, [
              _SettingsTile(
                icon: _isConnected ? Icons.wifi_outlined : Icons.wifi_off_outlined,
                iconColor: AppColors.azure,
                title: 'Internet connection',
                subtitle: _isConnected
                    ? 'Connected via $_connectionType'
                    : 'No internet connection',
                onTap: _checkConnectivity,
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.sms_outlined,
                iconColor: AppColors.azure,
                title: 'SMS start date',
                subtitle: scanStart == null ? 'Not set' : 'From $scanLabel',
                onTap: () => SmsImportPrompt.show(context),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.mail_outlined,
                iconColor: AppColors.azure,
                title: 'Email import',
                subtitle: 'Read bank alert emails',
                onTap: () {
                  Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const EmailImportScreen()),
                  );
                },
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.key_outlined,
                iconColor: AppColors.azure,
                title: 'SMS parsing AI keys',
                subtitle: 'Optional keys for SMS parsing',
                onTap: () {
                  Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const AISettingsScreen()),
                  );
                },
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.manage_search_outlined,
                iconColor: AppColors.azure,
                title: 'Recheck skipped messages',
                subtitle: transactions.skippedMessageCount == 0
                    ? 'No messages are being skipped'
                    : 'Scan ${transactions.skippedMessageCount} skipped '
                        'messages again',
                onTap: transactions.skippedMessageCount == 0
                    ? null
                    : () => _recheckSkipped(context, transactions),
              ),
            ]),

            // The Gemini feature and its one governing screen.
            _section(context, 'Assistant', 4, [
              _SettingsTile(
                icon: Icons.auto_awesome_outlined,
                iconColor: AppColors.brandBright,
                title: 'SpendSense Assistant',
                subtitle: 'Your private money assistant',
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
                icon: Icons.shield_outlined,
                iconColor: AppColors.brandBright,
                title: 'Assistant privacy & Gemini',
                subtitle: 'What may be sent to Gemini',
                onTap: () {
                  Navigator.push(
                    context,
                    AppPageRoute(
                      builder: (_) => const AssistantPrivacyScreen(),
                    ),
                  );
                },
              ),
            ]),

            // File-level operations on the ledger itself. The destructive row
            // keeps its danger ink wherever it sits — the one exception that
            // overrides a section colour.
            _section(context, 'Backup', 5, [
              _SettingsTile(
                icon: Icons.upload_file_outlined,
                iconColor: AppColors.warning,
                title: 'Export JSON backup',
                subtitle: 'Save a JSON backup file',
                onTap: () => _exportBackup(context, transactions),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.download_outlined,
                iconColor: AppColors.warning,
                title: 'Import JSON backup',
                subtitle: 'Restore a JSON backup file',
                onTap: () => _importBackup(context, transactions),
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.delete_sweep_outlined,
                iconColor: AppColors.danger,
                title: 'Clear transaction database',
                subtitle: 'Deletes all stored transactions',
                onTap: () => _showClearCacheDialog(context),
              ),
            ]),

            // Account identity only makes sense once Firebase auth is wired
            // and the user is actually signed in; hiding it otherwise keeps
            // the local-only experience unchanged.
            if (auth.isFirebaseAvailable && auth.isSignedIn)
              _section(context, 'Account', 6, [
                // Read-only: the email is managed by Firebase, so the tile
                // has no onTap and no arrow.
                _SettingsTile(
                  icon: Icons.mail_outlined,
                  iconColor: AppColors.textTertiary(context),
                  title: 'Signed in as',
                  subtitle: auth.email,
                  onTap: null,
                  showArrow: false,
                ),
                _divider(context),
                // No SnackBar on success: AuthGate in main.dart swaps to
                // the auth screen the moment isSignedIn flips to false.
                _SettingsTile(
                  icon: Icons.logout_outlined,
                  iconColor: AppColors.danger,
                  title: 'Sign out',
                  subtitle: 'End this session on this device',
                  // Disabled while a sign-in/out is already in flight so
                  // the destructive action cannot be double-submitted.
                  onTap: auth.isBusy ? null : () => _confirmSignOut(context),
                ),
                _divider(context),
                // Required by Google Play for any app with accounts, and the
                // privacy policy already promises this flow.
                _SettingsTile(
                  icon: Icons.delete_forever_outlined,
                  iconColor: AppColors.danger,
                  title: 'Delete account',
                  subtitle: 'Permanently deletes your account and data',
                  onTap: auth.isBusy
                      ? null
                      : () => _confirmDeleteAccount(context, auth),
                ),
              ]),

            _section(context, 'About', 7, [
              _SettingsTile(
                icon: Icons.system_update_alt_outlined,
                iconColor: AppColors.textTertiary(context),
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
                icon: Icons.info_outlined,
                iconColor: AppColors.textTertiary(context),
                title: 'App version',
                subtitle: _installedVersionLabel(update),
                onTap: null,
                showArrow: false,
              ),
              _divider(context),
              // The only route to a human. Before this there was none: the
              // About section ended at "App version", so a user with a bug had
              // no way to tell anyone. Tapping copies the address rather than
              // launching a mail app, because a device with no mail client
              // configured would otherwise do nothing at all with no feedback.
              _SettingsTile(
                icon: Icons.support_agent_outlined,
                iconColor: AppColors.textTertiary(context),
                title: 'Contact support',
                subtitle: _supportEmail,
                onTap: () => _copySupportEmail(context),
                showArrow: false,
              ),
              _divider(context),
              _SettingsTile(
                icon: Icons.gavel_outlined,
                iconColor: AppColors.textTertiary(context),
                title: 'Privacy & terms',
                subtitle: 'What we store, and what leaves this device',
                onTap: () => _copyLegalUrl(context),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// A labelled card of rows. Every section here groups related rows so no
  /// card ever holds a single orphan tile or becomes an unlabelled basket —
  /// both were the sloppiness this rewrite replaced.
  Widget _section(
    BuildContext context,
    String label,
    int entranceIndex,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xxl),
        _sectionLabel(label),
        const SizedBox(height: AppSpacing.sm),
        _SettingsCard(
          entranceIndex: entranceIndex,
          children: children,
        ),
      ],
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

  /// The public contact address. One constant so the Settings row, the Play
  /// Store listing and (later) the legal pages cannot drift apart.
  static const _supportEmail = 'chaitanyasaikandula@gmail.com';

  /// The published legal page. Kept as one constant next to [_supportEmail] so
  /// the in-app link, the Play Store listing and the GitHub release text cannot
  /// drift apart.
  static const _legalUrl = 'https://spendsense-ota-2026.web.app/legal/';

  /// Copies the address instead of launching a mail app. A device with no mail
  /// client would otherwise appear to do nothing, and the user still needs the
  /// address to write from wherever they do have mail.
  Future<void> _copySupportEmail(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(const ClipboardData(text: _supportEmail));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Support email copied: $_supportEmail'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Copies the policy URL for the same reason: no url_launcher dependency, no
  /// silent no-op on a device without a browser, and the URL is the part a user
  /// needs in order to hand it to whatever they do have.
  Future<void> _copyLegalUrl(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(const ClipboardData(text: _legalUrl));
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Privacy & terms link copied: $_legalUrl'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      UpdateUiState.readyToInstall => 'Verified — ready to install',
      UpdateUiState.downloading => 'Downloading update…',
      UpdateUiState.installing => 'Opening the installer…',
      UpdateUiState.checking => 'Checking for updates…',
      UpdateUiState.verifying => 'Verifying the download…',
      UpdateUiState.upToDate => 'Up to date',
      UpdateUiState.error => 'Last check failed — tap to retry',
      UpdateUiState.idle => update.isConfigured
          ? 'Check for the latest release'
          : 'Release channel not configured',
    };
  }

  /// The divider aligns with the text column: tile padding, one well, one gap.
  Widget _divider(BuildContext context) => Divider(
        height: 1,
        indent:
            AppSpacing.lg + AppSpacing.wellSize + AppSpacing.md,
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
            hintText: 'Your name',
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

  /// Confirms account deletion, then collects the password if Firebase wants a
  /// recent sign-in, and finally wipes the account and every local trace.
  ///
  /// The password step is not paranoia: Firebase refuses `delete()` on an older
  /// session, and re-prompting inside a destructive flow is friendlier than
  /// making someone sign out and back in to find the row again.
  Future<void> _confirmDeleteAccount(
    BuildContext context,
    AuthProvider auth,
  ) async {
    final transactions = context.read<TransactionProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete account?', style: AppText.title(ctx)),
        content: const Text(
          'This permanently deletes your SpendSense account, your sign-in, and '
          'every transaction stored on this device. It cannot be undone.\n\n'
          'Your expenses are not backed up anywhere, so they cannot be '
          'restored afterwards.',
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
              'Delete everything',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    Future<void> run({String? password}) async {
      await auth.deleteAccount(
        password: password,
        clearLocalLedger: transactions.clearAll,
      );
    }

    try {
      await run();
    } on ReauthenticationRequiredException {
      if (!context.mounted) return;
      final password = await _promptPassword(context);
      if (password == null || password.isEmpty || !context.mounted) return;
      try {
        await run(password: password);
      } catch (_) {
        if (!context.mounted) return;
        _showDeleteFailed(context);
      }
      return;
    } catch (_) {
      if (!context.mounted) return;
      _showDeleteFailed(context);
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Your account and data were deleted.')),
    );
  }

  Future<String?> _promptPassword(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm your password', style: AppText.title(ctx)),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Password'),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Delete account'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showDeleteFailed(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your account could not be deleted. Please try again.'),
      ),
    );
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
      child: GlassCard(
        padding: EdgeInsets.zero,
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
              IconWell(icon: icon, color: iconColor),
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
