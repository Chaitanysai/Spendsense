import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_palette.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

/// Settings → Appearance: theme colours, light/dark/system, and reset.
///
/// Every control writes straight through [ThemeProvider]; the tokens are
/// re-resolved on the next build, so changes are visible immediately without
/// leaving this screen.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  static String modeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Appearance')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              AppSpacing.fabClearance,
            ),
            children: [
              SectionHeader(
                title: 'Appearance · ${modeLabel(theme.themeMode)}',
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    for (final mode in ThemeMode.values) ...[
                      Expanded(
                        child: _ModeChoice(
                          mode: mode,
                          selected: theme.themeMode == mode,
                          onTap: () => theme.setThemeMode(mode),
                        ),
                      ),
                      if (mode != ThemeMode.values.last)
                        const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: 'Theme colours',
                actionLabel: 'TAP TO APPLY',
              ),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < AppPalette.all.length; i++) ...[
                      _PaletteRow(
                        palette: AppPalette.all[i],
                        selected: theme.palette.id == AppPalette.all[i].id,
                        onTap: () => theme.setPalette(AppPalette.all[i]),
                      ),
                      if (i != AppPalette.all.length - 1)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              GlassCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reset to default',
                              style: AppText.title(context)),
                          const SizedBox(height: 2),
                          Text('Ocean Blue · Light',
                              style: AppText.body(context)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _confirmReset(context, theme),
                      child: const Text('Reset'),
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

  Future<void> _confirmReset(BuildContext context, ThemeProvider theme) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset appearance?'),
        content: const Text(
          'Theme colours return to Ocean Blue and appearance returns to Light.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await theme.resetToDefaults();
    }
  }
}

class _ModeChoice extends StatelessWidget {
  final ThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChoice({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  static const Map<ThemeMode, IconData> _icons = {
    ThemeMode.light: Icons.light_mode_rounded,
    ThemeMode.dark: Icons.dark_mode_rounded,
    ThemeMode.system: Icons.brightness_auto_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: AppearanceScreen.modeLabel(mode),
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.brand.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                _icons[mode],
                size: 20,
                color: selected
                    ? AppColors.navSelected(context)
                    : AppColors.textSecondary(context),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                AppearanceScreen.modeLabel(mode),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.body(context).copyWith(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? AppColors.navSelected(context)
                      : AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _PaletteRow({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: palette.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // Swatch shows the palette's own ramp, so the preview never
              // depends on the currently active tokens.
              Container(
                width: 46,
                height: 32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  gradient: palette.brandGradient,
                  border: Border.all(color: AppColors.border(context)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  palette.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title(context),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    size: 22, color: AppColors.navSelected(context))
              else
                Icon(Icons.circle_outlined,
                    size: 22, color: AppColors.textTertiary(context)),
            ],
          ),
        ),
      ),
    );
  }
}
