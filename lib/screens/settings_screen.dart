import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/transaction_provider.dart';
import '../utils/app_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── COLLAPSIBLE HEADER ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.primaryPurple,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: _ProfileHeader(auth: auth),
            ),
            title: Text(
              'Settings',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),

          // ── BODY ─────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PREFERENCES SECTION
                  _sectionLabel('Preferences'),
                  SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.palette_outlined,
                        iconColor: Color(0xFF7C3AED),
                        title: 'Theme',
                        subtitle: 'Light',
                        onTap: () => _comingSoon(context, 'Theme'),
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.currency_rupee_rounded,
                        iconColor: Color(0xFF059669),
                        title: 'Currency',
                        subtitle: 'INR (₹)',
                        onTap: () => _comingSoon(context, 'Currency'),
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.language_rounded,
                        iconColor: Color(0xFF0284C7),
                        title: 'Language',
                        subtitle: 'English',
                        onTap: () => _comingSoon(context, 'Language'),
                      ),
                    ],
                  ),

                  SizedBox(height: 24),

                  // SMS & PRIVACY SECTION
                  _sectionLabel('SMS & Privacy'),
                  SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.sms_outlined,
                        iconColor: Color(0xFFD97706),
                        title: 'SMS Permissions',
                        subtitle: 'Manage access',
                        onTap: () => _comingSoon(context, 'SMS Permissions'),
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.delete_sweep_outlined,
                        iconColor: Color(0xFFDC2626),
                        title: 'Clear Transaction Cache',
                        subtitle: 'Remove locally stored data',
                        onTap: () => _showClearCacheDialog(context),
                      ),
                    ],
                  ),

                  SizedBox(height: 24),

                  // ABOUT SECTION
                  _sectionLabel('About'),
                  SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        iconColor: Color(0xFF6B7280),
                        title: 'App Version',
                        subtitle: '1.0.0',
                        onTap: null,
                        showArrow: false,
                      ),
                      _divider(),
                      _SettingsTile(
                        icon: Icons.privacy_tip_outlined,
                        iconColor: Color(0xFF6B7280),
                        title: 'Privacy Policy',
                        onTap: () => _comingSoon(context, 'Privacy Policy'),
                      ),
                    ],
                  ),

                  SizedBox(height: 32),

                  // LOGOUT BUTTON
                  _LogoutButton(
                    onPressed: () => _showLogoutDialog(context, auth),
                  ),

                  SizedBox(height: 20),
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
        color: Colors.grey[500],
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _divider() => Divider(height: 1, indent: 56, color: Colors.grey[100]);

  void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature — coming soon'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear Cache?'),
        content: Text('This will remove all locally stored transaction data. '
            'Your SMS inbox is unaffected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFDC2626),
              shape: StadiumBorder(),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<TransactionProvider>().clearAll();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Cache cleared')),
              );
            },
            child: Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Log out?'),
        content: Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: StadiumBorder(),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              auth.logout();
            },
            child: Text('Log out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─── PROFILE HEADER ────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final AuthProvider auth;
  const _ProfileHeader({super.key, required this.auth});

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
          padding: EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: Row(
            children: [
              // Avatar with initials
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.25),
                  border: Border.all(color: Colors.white54, width: 2),
                ),
                child: Center(
                  child: Text(
                    _initials(auth.name),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      auth.name,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      auth.email,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Edit profile button
              IconButton(
                icon: Icon(Icons.edit_outlined, color: Colors.white70),
                onPressed: () {},
                tooltip: 'Edit profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

// ─── SETTINGS CARD ─────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

// ─── SETTINGS TILE ─────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showArrow;

  const _SettingsTile({
    super.key,
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
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  if (subtitle != null) ...[
                    SizedBox(height: 2),
                    Text(subtitle!,
                        style:
                            TextStyle(color: Colors.grey[500], fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (showArrow && onTap != null)
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey[400], size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── LOGOUT BUTTON ─────────────────────────────────────────────────────────

class _LogoutButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _LogoutButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(Icons.logout_rounded, size: 18),
        label: Text('Log out', style: TextStyle(fontSize: 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Color(0xFFFEF2F2),
          foregroundColor: Color(0xFFDC2626),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Color(0xFFFECACA)),
          ),
        ),
      ),
    );
  }
}
