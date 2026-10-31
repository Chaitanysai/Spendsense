import 'package:flutter/material.dart';

import '../services/sound_service.dart';
import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';
import 'quick_action_tile.dart';

/// The dashboard's floating command dock.
///
/// GO Club's home puts the actions the app exists for in one floating capsule
/// at the thumb, not in four separate outlined boxes. Suno does the same with
/// its composer: one solid surface, one accented primary, everything else quiet.
/// This is that dock. It is the only glass-adjacent surface on the page besides
/// the navigation pill, so it reads as chrome rather than as another card.
class HomeActionDock extends StatelessWidget {
  final List<QuickAction> actions;

  const HomeActionDock({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // Four slots only survive a genuinely large text setting as two rows.
    final columns = scale > 1.3 ? 2 : 4;

    final rows = <List<QuickAction>>[
      for (var i = 0; i < actions.length; i += columns)
        actions.sublist(i, (i + columns).clamp(0, actions.length)),
    ];

    final dark = AppColors.isDark(context);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.05),
                    AppColors.surfaceColor(context),
                  ),
                  AppColors.surfaceColor(context),
                ]
              : [
                  Colors.white,
                  AppColors.surfaceColor(context),
                ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow(context),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: AppColors.border(context).withValues(alpha: 0.7),
              ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var c = 0; c < columns; c++) ...[
                    if (c > 0)
                      VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppColors.border(context).withValues(alpha: 0.7),
                      ),
                    Expanded(
                      child: c < rows[r].length
                          ? _DockSlot(
                              action: rows[r][c],
                              primary: r == 0 && c == 0,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DockSlot extends StatelessWidget {
  final QuickAction action;
  final bool primary;

  const _DockSlot({required this.action, required this.primary});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final iconColor = primary ? Colors.white : AppColors.brandInk(context);

    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: Pressable(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        sound: SoundEventType.buttonTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: primary ? AppColors.actionGradient : null,
                    color: primary
                        ? null
                        : AppColors.brand.withValues(alpha: dark ? 0.20 : 0.11),
                    border: primary
                        ? Border.all(
                            color: Colors.white.withValues(alpha: 0.22),
                          )
                        : null,
                  ),
                  child: Icon(action.icon, size: 18, color: iconColor),
                ),
                const SizedBox(height: 6),
                Text(
                  action.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppText.label(context).copyWith(
                    fontSize: 10.5,
                    height: 1.15,
                    fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
                    color: primary
                        ? AppColors.textPrimary(context)
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
