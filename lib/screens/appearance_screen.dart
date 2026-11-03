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
    // The Theme colours list is grouped once per build from the registry order
    // alone, so the sections can never disagree with [AppPalette.all].
    final paletteGroups = _paletteGroups();

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
                // Slightly tighter than the default card inset: nineteen rows
                // behind a 20dp gutter read as a narrow, unfocused list, and
                // the longest supplied names need the extra width.
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var g = 0; g < paletteGroups.length; g++) ...[
                      if (g > 0) const SizedBox(height: AppSpacing.md),
                      _PaletteSection(
                        group: paletteGroups[g],
                        selectedId: theme.palette.id,
                        onSelect: theme.setPalette,
                      ),
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
                  : AppColors.pillSelectedFillFor(AppColors.isDark(context)),
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
                // The preview shows the palette's own ramp, canvas and
                // highlight — never the active tokens — so a row keeps showing
                // the theme it names whatever is currently applied.
                _PalettePreview(palette: palette),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          palette.label,
                          // Two lines so the longest supplied names
                          // ("Midnight, Indigo, Vanilla", "Royal Blue + Light
                          // Cream") survive a narrow phone and a large text
                          // scale instead of being clipped to an ellipsis.
                          maxLines: 2,
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
                            style: AppText.weight(
                                    AppText.label(context), FontWeight.w800)
                                .copyWith(
                              fontSize: 11,
                              letterSpacing: 0.5,
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

/// One labelled block of the Theme colours list.
class _PaletteGroup {
  final String title;
  final List<AppPalette> palettes;

  const _PaletteGroup(this.title, this.palettes);
}

/// The Theme colours sections, derived from [AppPalette.all] alone.
///
/// Membership is by id and the order inside a section is the registry's own, so
/// [AppPalette.all] stays the single ordered source of truth: this decides only
/// which heading a palette appears under, never its order or its values. An id
/// that matches no section — a palette appended after this screen was written —
/// falls into the final section, so every entry is always shown exactly once
/// and a new palette can never be dropped from the screen.
List<_PaletteGroup> _paletteGroups() {
  const premiumIds = <String>{
    'premium_blue',
    'paper',
    'deep_navy',
    'soft_pastel_teal',
    'plum_blush',
    'midnight',
  };
  const additionalIds = <String>{
    'royal_blue_cream',
    'wine_sand',
    'orange_milk',
    'plum_milk',
    'midnight_indigo_vanilla',
    'cherry_alabaster',
  };

  final premium = <AppPalette>[];
  final additional = <AppPalette>[];
  final classic = <AppPalette>[];

  for (final palette in AppPalette.all) {
    if (premiumIds.contains(palette.id)) {
      premium.add(palette);
    } else if (additionalIds.contains(palette.id)) {
      additional.add(palette);
    } else {
      classic.add(palette);
    }
  }

  return [
    _PaletteGroup('Premium', premium),
    _PaletteGroup('Additional', additional),
    _PaletteGroup('Classic', classic),
  ];
}

/// One section of the Theme colours list: an eyebrow title and its rows.
class _PaletteSection extends StatelessWidget {
  final _PaletteGroup group;
  final String selectedId;
  final ValueChanged<AppPalette> onSelect;

  const _PaletteSection({
    required this.group,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PaletteGroupLabel(title: group.title),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < group.palettes.length; i++) ...[
          _PaletteRow(
            palette: group.palettes[i],
            selected: selectedId == group.palettes[i].id,
            onTap: () => onSelect(group.palettes[i]),
          ),
          if (i != group.palettes.length - 1)
            const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

/// Section eyebrow. Aligned with the swatch column so the rows stay one list.
class _PaletteGroupLabel extends StatelessWidget {
  final String title;

  const _PaletteGroupLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: Text(
        title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.overline(context),
      ),
    );
  }
}

/// A miniature of the palette's own light world: its identity ramp beside a
/// canvas swatch carrying the highlight.
///
/// Every colour is read from [palette] directly, never from the active tokens,
/// so the preview keeps showing the theme it names while another one is
/// applied. The composition is deliberately light in both modes; the dark-mode
/// hairline keeps its edge readable on a dark glass card, exactly as the plain
/// gradient swatch it replaces did.
class _PalettePreview extends StatelessWidget {
  final AppPalette palette;

  const _PalettePreview({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 34,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.isDark(context)
              ? Colors.white.withValues(alpha: 0.28)
              : AppColors.border(context),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The primary ramp: the palette's loudest identity, and the anchor the
          // neutral and highlight cells are read against.
          Expanded(
            flex: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: palette.brandGradient),
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: ColoredBox(color: palette.background)),
                Expanded(child: ColoredBox(color: palette.accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
