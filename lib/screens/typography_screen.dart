import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/app_typography.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';

/// Settings → Appearance → Font style.
///
/// Choosing a preset only *previews* it; nothing changes app-wide until Apply.
/// Typography is a display preference stored in ordinary preferences — it never
/// touches the ledger, its encryption, or any money value.
class TypographyScreen extends StatefulWidget {
  const TypographyScreen({super.key});

  @override
  State<TypographyScreen> createState() => _TypographyScreenState();
}

class _TypographyScreenState extends State<TypographyScreen> {
  FontPreset? _pending;

  static String scaleLabel(double s) => switch (s) {
        <= 0.9 => 'Small',
        <= 1.05 => 'Default',
        <= 1.2 => 'Large',
        _ => 'Largest',
      };

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final selected = _pending ?? theme.fontPreset;
    final changed = selected.id != theme.fontPreset.id;
    final atDefault = theme.fontPreset.id == FontPreset.standard.id &&
        theme.fontScale == FontScale.standard;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Font style')),
      body: AppBackground(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              MediaQuery.paddingOf(context).bottom + AppSpacing.xxxl,
            ),
            children: [
              const SectionHeader(title: 'Preview'),
              for (final preset in FontPreset.all)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _PresetCard(
                    preset: preset,
                    selected: preset.id == selected.id,
                    active: preset.id == theme.fontPreset.id,
                    onTap: () => setState(() => _pending = preset),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: changed
                      ? () async {
                          await theme.setFontPreset(selected);
                          if (mounted) setState(() => _pending = null);
                        }
                      : null,
                  child:
                      Text(changed ? 'Apply "${selected.label}"' : 'Applied'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const SectionHeader(title: 'Text size'),
              GlassCard(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final step in FontScale.steps)
                      ChoiceChip(
                        label: Text(
                            '${scaleLabel(step)} · ${(step * 100).round()}%'),
                        selected: theme.fontScale == step,
                        onSelected: (_) => theme.setFontScale(step),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Text size multiplies your phone\'s own font size setting.',
                style: AppText.bodySmall(context),
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
                          Text('SpendSense Default · 100%',
                              style: AppText.body(context)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: atDefault && _pending == null
                          ? null
                          : () async {
                              await theme.resetTypography();
                              if (mounted) setState(() => _pending = null);
                            },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Fonts are open-licensed (SIL Open Font License 1.1) and are '
                'downloaded once, then kept on this device. If a font cannot '
                'be loaded, a readable system font is used instead. '
                'Nothing here is an official Nothing, Samsung or Google font.',
                style: AppText.bodySmall(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final FontPreset preset;
  final bool selected;
  final bool active;
  final VoidCallback onTap;

  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ink = AppColors.textPrimary(context);
    final sub = AppColors.textSecondary(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.label}${active ? ', current' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.border(context),
              width: selected ? 1.6 : 1,
            ),
            color: AppColors.surfaceColor(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(preset.label,
                        style: AppText.title(context).copyWith(fontSize: 14.5)),
                  ),
                  if (active)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Text('CURRENT', style: AppText.overline(context)),
                    ),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: selected
                        ? AppColors.brand
                        : AppColors.textTertiary(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Samples are resolved against THIS preset, not the active one.
              Text(
                '₹12,345.50',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.resolve(
                  preset: preset,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: ink,
                  fontFeatures: AppTypography.tabular,
                ),
              ),
              Text(
                'Monthly budget',
                style: AppTypography.resolve(
                  preset: preset,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Spent ₹1,240.00 on Food this week · 38% used',
                style: AppTypography.resolve(
                  preset: preset,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                  color: sub,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(preset.description,
                  style: AppText.caption(context)),
            ],
          ),
        ),
      ),
    );
  }
}
