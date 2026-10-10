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
import '../widgets/profile_avatar.dart';
import 'ai_settings_screen.dart';

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
      backgroundColor: AppColors.scaffold(context),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: AppColors.primaryPurple,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: _ProfileHeader(auth: auth),
            ),
            title: const Text(
              'Settings',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Preferences'),
                  const SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.photo_camera_back_rounded,
                        iconColor: const Color(0xFF0F766E),
                        title: 'Profile Photo',
                        subtitle: auth.hasProfileImage
                            ? 'Change your profile image'
                            : 'Add your profile image',
                        onTap: () => _pickProfilePhoto(context),
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.sms_rounded,
                        iconColor: const Color(0xFFC2185B),
                        title: 'SMS Start Date',
                        subtitle: 'Currently checking messages from $scanLabel',
                        onTap: () => SmsImportPrompt.show(context),
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.palette_outlined,
                        iconColor: const Color(0xFF7C3AED),
                        title: 'Theme',
                        subtitle: theme.isDarkMode ? 'Dark' : 'Light',
                        onTap: theme.toggle,
                        trailing: Switch.adaptive(
                          value: theme.isDarkMode,
                          onChanged: theme.setDarkMode,
                          activeThumbColor: AppColors.primaryPurple,
                        ),
                        showArrow: false,
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.key_rounded,
                        iconColor: const Color(0xFFEA580C),
                        title: 'AI Provider Settings',
                        subtitle: 'Configure API keys for AI parsing',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const AISettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel('Network'),
                  const SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: _isConnected ? Icons.wifi : Icons.wifi_off,
                        iconColor: _isConnected
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                        title: 'Internet Connection',
                        subtitle: _isConnected
                            ? 'Connected via $_connectionType'
                            : 'No internet connection',
                        onTap: _checkConnectivity,
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.cloud_outlined,
                        iconColor: const Color(0xFF6366F1),
                        title: 'AI Services',
                        subtitle: 'Groq & Gemini Fallback API configured',
                        onTap: null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel('Data & Backup'),
                  const SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.upload_file_rounded,
                        iconColor: const Color(0xFF2563EB),
                        title: 'Export JSON Backup',
                        subtitle: 'Save all transactions to backup JSON',
                        onTap: () => _exportBackup(context, transactions),
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.download_rounded,
                        iconColor: const Color(0xFF059669),
                        title: 'Import JSON Backup',
                        subtitle: 'Restore transactions from backup JSON',
                        onTap: () => _importBackup(context, transactions),
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.delete_sweep_outlined,
                        iconColor: const Color(0xFFDC2626),
                        title: 'Clear Transaction Database',
                        subtitle: 'Remove locally stored transaction data',
                        onTap: () => _showClearCacheDialog(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _sectionLabel('About'),
                  const SizedBox(height: 10),
                  _SettingsCard(
                    children: const [
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        iconColor: Color(0xFF6B7280),
                        title: 'App Version',
                        subtitle: '2.0.0 (Local-First)',
                        onTap: null,
                        showArrow: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary(context),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        indent: 56,
        color: AppColors.border(context),
      );

  Future<void> _exportBackup(BuildContext context, TransactionProvider provider) async {
    final jsonStr = await provider.exportToJson();
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Export JSON Backup'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Copy your backup JSON data below:'),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonStr,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
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
            child: const Text('Copy to Clipboard'),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Import JSON Backup'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Paste your backup JSON data below:'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: '{"version": 2, "transactions": [...]}',
                  border: OutlineInputBorder(),
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
              final count = await provider.importFromJson(text);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Successfully imported $count transactions!')),
              );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear Database?'),
        content: const Text(
          'This will remove all locally stored transactions. Your SMS inbox is unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: const StadiumBorder(),
            ),
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

class _ProfileHeader extends StatelessWidget {
  final AuthProvider auth;

  const _ProfileHeader({required this.auth});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryPurple, AppColors.primaryPink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54, width: 2),
                ),
                child: ClipOval(
                  child: ProfileAvatar(
                    imageBytes: auth.profileImageBytes,
                    name: auth.name,
                    radius: 31,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      auth.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      auth.email,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showArrow = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (showArrow && onTap != null)
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }
}
