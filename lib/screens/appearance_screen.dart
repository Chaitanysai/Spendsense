import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_palette.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';
import '../widgets/app_states.dart';
import '../widgets/glass_card.dart';
import '../widgets/glossy_pill.dart';
import '../widgets/pressable.dart';
import '../widgets/section_header.dart';
import '../widgets/sound_scope.dart';

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
              // Segmented track, styled like the expense/income selector in
              // Add Transaction, so every select-one control in the app reads
              // the same: a recessed track under one glossy selected segment.
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt(context),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Row(
                  children: [
                    for (final mode in ThemeMode.values) ...[
                      Expanded(
                        child: _ModeChoice(
                          mode: mode,
                          selected: theme.themeMode == mode,
                          onTap: () {
                            if (theme.themeMode != mode) {
                              SoundScope.play(
                                  context, SoundEventType.selectionChanged);
                            }
                            theme.setThemeMode(mode);
                          },
                        ),
                      ),
                      if (mode != ThemeMode.values.last)
                        const SizedBox(width: AppSpacing.xs),
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
                        onTap: () {
                          if (theme.palette.id != AppPalette.all[i].id) {
                            SoundScope.play(
                                context, SoundEventType.selectionChanged);
                          }
                          theme.setPalette(AppPalette.all[i]);
                        },
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

  /// Navy → brand gloss for the chosen mode.
  ///
  /// Deliberately darker than the electric gradient the nav badge and buttons
  /// ride: this segment carries a 12px label, and white on the lighter electric
  /// stops falls under the 4.5:1 AA floor. On this ramp the white label clears
  /// it at every stop, in both themes.
  LinearGradient get _selectedGradient => LinearGradient(
        colors: [AppColors.brand, AppColors.navyDeep],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: AppearanceScreen.modeLabel(mode),
      excludeSemantics: true,
      child: GlossyPill(
        selected: selected,
        // Bare while unselected so only the chosen mode carries the gloss, and
        // the same pill renders both states so the treatment animates in.
        bareWhenUnselected: true,
        // The track is a Row of Expanded segments, so the pill has to claim the
        // full width; otherwise its highlight Stack shrink-wraps the label and
        // the fill stops short of the segment edge.
        width: double.infinity,
        selectedGradient: _selectedGradient,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        // The screen fires selectionChanged only when the mode actually
        // changes, so a cue here would double it on the active segment.
        sound: null,
        onTap: onTap,
        child: Column(
          children: [
            Icon(
              _icons[mode],
              size: 20,
              color: selected ? Colors.white : AppColors.textSecondary(context),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppearanceScreen.modeLabel(mode),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(context).copyWith(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color:
                    selected ? Colors.white : AppColors.textSecondary(context),
              ),
            ),
          ],
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
    final dark = AppColors.isDark(context);
    return Semantics(
      button: true,
      selected: selected,
      label: palette.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        // The screen fires selectionChanged only when the palette actually
        // changes, so the press cue lives there rather than here.
        sound: null,
        child: AnimatedContainer(
          duration: AppMotion.respect(context, AppMotion.fast),
          curve: AppMotion.easeOut,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            // A restrained brand wash on the chosen palette, so the active
            // theme is legible at a glance and not only from the tick.
            color: selected
                ? AppColors.brand.withValues(alpha: dark ? 0.16 : 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppColors.brand.withValues(alpha: dark ? 0.45 : 0.28)
                  : Colors.transparent,
            ),
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
              // Cross-faded rather than swapped: picking a palette is a state
              // change, and an instant icon flip read as a glitch.
              AppStateSwap(
                state: selected ? 'on' : 'off',
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 22,
                  color: selected
                      ? AppColors.navSelected(context)
                      : AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
