import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_palette.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/dashboard_sections.dart';
import '../widgets/app_background.dart';
import '../widgets/app_page_route.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import '../widgets/pressable.dart';
import '../services/sound_service.dart';
import '../widgets/sound_scope.dart';
import 'typography_screen.dart';

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
                child: IntrinsicHeight(
                  // Equal widths come from `Expanded`; equal heights need the
                  // row to measure its tallest child and stretch the rest to it,
                  // so no pill can be shorter than its neighbour.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
              ),
              const SizedBox(height: AppSpacing.xl),
              SectionHeader(
                title: 'Theme colours',
                actionLabel: 'Tap to apply',
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
                        const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Font style'),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                onTap: () => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => const TypographyScreen()),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(theme.fontPreset.label,
                              style: AppText.title(context)),
                          const SizedBox(height: 2),
                          Text(
                            'Text size ${(theme.fontScale * 100).round()}% · '
                            'tap to preview',
                            style: AppText.body(context),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textTertiary(context)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Dashboard sections'),
              const SizedBox(height: AppSpacing.md),
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                // ListTiles paint their ink on the nearest Material. The glass
                // fill is a DecoratedBox, so without this transparent Material
                // Flutter warns that taps and splashes are invisible.
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (final id in DashboardSection.ids)
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          title: Text(DashboardSection.label(id),
                              style: AppText.bodyStrong(context)),
                          value: theme.isSectionVisible(id),
                          onChanged: (on) => theme.setSectionVisible(id, on),
                        ),
                    ],
                  ),
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
                          Text(
                            '${AppPalette.defaultPalette.label} · Light',
                            style: AppText.body(context),
                          ),
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
        content: Text(
          'Theme colours return to ${AppPalette.defaultPalette.label} and '
          'appearance returns to Light.',
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
      child: Pressable(
        onTap: () {
          if (!selected) {
            SoundScope.play(context, SoundEventType.selectionChanged);
          }
          onTap();
        },
        sound: null,
        child: ConstrainedBox(
          // Every pill must be the same box, in both axes.
          //
          // Height: without a floor the container shrink-wrapped its content, so
          // "System" and "Light" (y/g descenders) came out taller than "Dark".
          // Width: `Expanded` sizes the *slot* equally, but a loose ConstrainedBox
          // hands the child loose constraints, so the container shrink-wrapped
          // its label instead and the three pills painted at 91.5 / 79.3 / 67.0.
          // `stretch` passes the slot's tight width down, and the centred column
          // keeps the glyph pair centred inside it.
          constraints: const BoxConstraints(
            minHeight: AppSpacing.wellTouchTarget + AppSpacing.xl,
            minWidth: double.infinity,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm,
              horizontal: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              // Selection must read as *more* present than an unselected pill in
              // both themes. In light mode a 12% brand wash is darker than the
              // white card and reads correctly. In dark mode it is not: the card
              // is already dark, so washing the (also dark) brand over it landed
              // *below* the unselected pill — measured #1F2E38 selected against
              // #23313D unselected, i.e. selection looked switched off. Dark mode
              // lightens instead, and the border carries the brand hue.
              color: !selected
                  ? Colors.transparent
                  : AppColors.isDark(context)
                      ? Colors.white.withValues(alpha: 0.10)
                      : AppColors.brand.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                // A constant width keeps the three boxes identical: a 1.5dp
                // selected border used to change the content box by 0.5dp,
                // which was enough to shift the label relative to its
                // neighbours.
                color: selected ? AppColors.brand : AppColors.border(context),
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _icons[mode],
                  size: 20,
                  // Selected sits on a 12%-brand capsule, not the canvas, so the
                  // glyph uses capsule-aware ink; navSelected measured against
                  // the canvas was too dim there.
                  color: selected
                      ? AppColors.brandWellInk(context)
                      : AppColors.textSecondary(context),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppearanceScreen.modeLabel(mode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppText.body(context).copyWith(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? AppColors.brandWellInk(context)
                        : AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
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
      child: Pressable(
        onTap: () {
          if (!selected) {
            SoundScope.play(context, SoundEventType.selectionChanged);
          }
          onTap();
        },
        sound: null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                // Swatch shows the palette's own ramp, so the preview never
                // depends on the currently active tokens.
                // Swatch shows the palette's own ramp, so the preview never
                // depends on the currently active tokens. It is always a light
                // wash, so it needs an edge that reads on a dark glass card as
                // well as on a light one: the theme border alone disappears on
                // dark, hence the inset hairline drawn in the swatch's own ink.
                Container(
                  width: 46,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    gradient: palette.brandGradient,
                    border: Border.all(
                      color: AppColors.isDark(context)
                          ? Colors.white.withValues(alpha: 0.28)
                          : AppColors.border(context),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          palette.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title(context),
                        ),
                      ),
                      // The chip is a fixed-size marker, not flexible content:
                      // as a `Flexible` sibling it competed with the name for
                      // the same space, so "Premium Blue" ellipsised to
                      // "Premium Bl…" while the chip still needed its room.
                      // Letting the name take the remaining width only — and
                      // the chip keep its intrinsic size — keeps both intact.
                      if (palette.id == AppPalette.defaultPalette.id) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm / 2),
                          ),
                          child: Text(
                            'DEFAULT',
                            maxLines: 1,
                            softWrap: false,
                            // 8.5 was below the legibility floor at font scale
                            // 1.0 and unreadable once the system scales text.
                            style: AppText.label(context).copyWith(
                              fontSize: 11,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brandWellInk(context),
                            ),
                          ),
                        ),
                      ],
                    ],
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
      ),
    );
  }
}
