import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../widgets/app_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/section_header.dart';
import '../widgets/sound_scope.dart';

/// Settings → Sound effects.
///
/// Three switches, matching the two cue categories plus the master gate. Every
/// control writes straight through [SoundProvider], so a change is audible (or
/// silent) on the very next interaction and survives a restart.
///
/// Confirmation cues fired from here go through the same preference gate as any
/// other cue, so turning a switch *off* is silent while turning one *on*
/// confirms itself.
class SoundSettingsScreen extends StatelessWidget {
  const SoundSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Subscribing keeps the switch positions in step with the stored values,
    // including changes made from elsewhere.
    final sound = SoundScope.watch(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Sound effects')),
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
              SectionHeader(title: 'Sound effects'),
              const SizedBox(height: AppSpacing.sm),
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  children: [
                    _SoundSwitch(
                      icon: Icons.volume_up_rounded,
                      title: 'Sound effects',
                      subtitle: 'Master switch for every cue',
                      value: sound?.masterEnabled ?? false,
                      onChanged: (value) async {
                        await sound?.setMasterEnabled(value);
                        SoundScope.playOn(
                            sound, SoundEventType.selectionChanged);
                      },
                    ),
                    _divider(context),
                    _SoundSwitch(
                      icon: Icons.touch_app_rounded,
                      title: 'Interaction sounds',
                      subtitle: 'Taps and selection changes',
                      value: sound?.uiEnabled ?? false,
                      onChanged: (value) async {
                        await sound?.setUiEnabled(value);
                        SoundScope.playOn(
                            sound, SoundEventType.selectionChanged);
                      },
                    ),
                    _divider(context),
                    _SoundSwitch(
                      icon: Icons.receipt_long_rounded,
                      title: 'Transaction & success sounds',
                      subtitle: 'Saved transactions, successes and milestones',
                      value: sound?.transactionsEnabled ?? false,
                      onChanged: (value) async {
                        await sound?.setTransactionsEnabled(value);
                        SoundScope.playOn(
                            sound, SoundEventType.selectionChanged);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              GlassCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: AppColors.textTertiary(context)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Cues are short and quietly mastered, and they follow '
                        'your device volume. Interaction sounds can be turned '
                        'off on their own without affecting transaction cues.',
                        style: AppText.body(context).copyWith(
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
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

  Widget _divider(BuildContext context) => Divider(
        height: 1,
        indent: 60,
        color: AppColors.border(context),
      );
}

class _SoundSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SoundSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The switch row sits inside a decorated GlassCard, so it needs its own
    // Material for Flutter to paint the tile's ink splashes on; without it
    // Flutter reports "ListTile background color or ink splashes may be
    // invisible". Transparency keeps the card's own background showing.
    return Material(
      type: MaterialType.transparency,
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        secondary: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, size: 19, color: AppColors.brand),
        ),
        title: Text(
          title,
          style: AppText.bodyStrong(context),
        ),
        subtitle: Text(
          subtitle,
          style: AppText.bodySmall(context),
        ),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
