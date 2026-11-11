import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'app_surface.dart';
import 'icon_well.dart';
import 'pressable.dart';

/// One row of a list or a settings group.
///
/// PanelUI `item` (+ `field` for the two-line form): a leading glyph on its
/// measured plate, a title, one muted supporting line, and a trailing slot that
/// is either a value, a chevron, a switch or any widget the caller supplies.
///
/// The row owns its height and its hit area, not its surface: rows are stacked
/// inside one [AppSurface] and separated by [AppSeparator], so a settings group
/// is one card with hairlines rather than a stack of cards — the
/// card-inside-card pattern the redesign explicitly avoids.
class AppListRow extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Glyph for the leading well. Ignored when [leading] is given.
  final IconData? leadingIcon;

  /// Fully custom leading widget (avatar, swatch, badge).
  final Widget? leading;

  /// Palette role for the well tint. Defaults to the readable brand ink.
  final Color? leadingTone;

  /// Custom trailing widget (switch, avatar group, stepper).
  final Widget? trailing;

  /// Plain trailing value, rendered in tabular figures and right-aligned.
  final String? trailingText;

  final VoidCallback? onTap;

  /// Paints the title, the well and any default chevron in the danger tone, for
  /// the destructive action at the bottom of a settings group.
  final bool destructive;

  /// Draws a hairline under the row. Off for the last row of a group.
  final bool showDivider;

  /// Tighter height for dense lists (filters, pickers).
  final bool dense;

  /// Overrides the announced label; defaults to "title, subtitle".
  final String? semanticLabel;

  /// The row is the current choice in a single-choice list (a filter sheet).
  /// Announced as selected, and drawn with a trailing check when nothing else
  /// occupies the trailing slot, so the choice never rests on tint alone.
  final bool selected;

  /// Draw the trailing chevron on a tappable row. On by default, because a
  /// tappable row usually opens something. Off for the rows of a pick-one list:
  /// there a chevron says "opens", and the only thing to say is which row is
  /// chosen (the check).
  final bool showChevron;

  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.leading,
    this.leadingTone,
    this.trailing,
    this.trailingText,
    this.onTap,
    this.destructive = false,
    this.showDivider = false,
    this.dense = false,
    this.semanticLabel,
    this.selected = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final tone = destructive
        ? AppColors.danger
        : (leadingTone ?? AppColors.brandInk(context));
    final titleStyle = AppText.weight(
      AppText.title(context),
      FontWeight.w600,
    ).copyWith(
      fontSize: 15,
      color: destructive ? AppColors.danger : AppColors.textPrimary(context),
    );

    final lead = leading ??
        (leadingIcon == null
            ? null
            : IconWell(icon: leadingIcon!, color: tone));

    final tail = trailing ??
        (trailingText != null
            ? Text(
                trailingText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.amount(
                  context,
                  size: 14,
                  weight: FontWeight.w600,
                  color: AppColors.textSecondary(context),
                ),
              )
            : (selected
                ? Icon(Icons.check_circle_rounded, size: 22, color: tone)
                : (onTap == null || !showChevron
                    ? null
                    : Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppColors.textTertiary(context),
                      ))));

    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: dense ? 44 : (subtitle == null ? 56 : 64),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: dense ? AppSpacing.xs : AppSpacing.md,
        ),
        child: Row(
          children: [
            if (lead != null) ...[
              lead,
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.bodySmall(context).copyWith(
                        fontSize: 12.5,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (tail != null) ...[
              const SizedBox(width: AppSpacing.md),
              tail,
            ],
          ],
        ),
      ),
    );

    final announced =
        semanticLabel ?? (subtitle == null ? title : '$title, $subtitle');
    final row = onTap == null
        ? content
        : Semantics(
            button: true,
            selected: selected,
            label: announced,
            excludeSemantics: true,
            onTap: onTap,
            child: Pressable(
              onTap: onTap,
              borderRadius: BorderRadius.zero,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  child: content,
                ),
              ),
            ),
          );

    if (!showDivider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        // Indented past the well so the hairline starts under the text, the
        // same rhythm the transaction feed uses.
        AppListDivider(
          indent:
              lead == null ? AppSpacing.lg : AppSpacing.lg + 40 + AppSpacing.md,
        ),
      ],
    );
  }
}

/// Hairline between rows of one group.
class AppListDivider extends StatelessWidget {
  final double indent;

  const AppListDivider({super.key, this.indent = 0});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        indent: indent,
        endIndent: AppSpacing.md,
        color: AppColors.border(context).withValues(alpha: 0.72),
      );
}

/// A stack of [AppListRow]s on one raised surface.
///
/// PanelUI `Item.Group` + `Item.Separator`: one card, hairlines between rows,
/// and the group announced as a list. This is what replaces the
/// card-inside-a-card pattern — a settings or bills section is one plane, not a
/// column of eleven.
class AppListGroup extends StatelessWidget {
  final List<Widget> rows;

  /// Optional heading announced before the rows (not rendered visually — the
  /// screen's own section header does that).
  final String? semanticLabel;

  const AppListGroup({
    super.key,
    required this.rows,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: AppSurface(
        level: AppSurfaceLevel.raised,
        // Rows own their horizontal padding so their hairline can be indented
        // past the leading well; the group only clips the corners.
        padding: EdgeInsets.zero,
        child: Column(mainAxisSize: MainAxisSize.min, children: rows),
      ),
    );
  }
}
