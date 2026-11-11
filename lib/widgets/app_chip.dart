import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import 'pressable.dart';

/// One filter/selection chip.
///
/// PanelUI `chip`: a single pill with `selected`, `disabled` and an optional
/// leading glyph. The selected state is never carried by hue alone — the label
/// gains weight, a check glyph appears when there is no other leading icon, and
/// the hairline strengthens — so the control still reads with a colour-vision
/// deficiency or in high-contrast mode.
///
/// The visual is 34dp tall inside a 44dp tap target, matching the rest of the
/// app's controls: a filter row may look dense without shrinking what the
/// finger has to hit.
class AppChip extends StatelessWidget {
  final String label;

  /// Optional trailing count (`+3`, `12`), shown dimmed beside the label.
  final String? count;

  final bool selected;
  final bool enabled;
  final IconData? leading;
  final VoidCallback? onTap;

  /// Overrides the announced label. Defaults to [label] (+ [count]).
  final String? semanticLabel;

  const AppChip({
    super.key,
    required this.label,
    this.count,
    this.selected = false,
    this.enabled = true,
    this.leading,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final ink = selected ? AppColors.brandInk(context) : AppColors.textSecondary(context);
    final fill = selected
        // Opaque blend rather than a translucent tint: a chip may sit on the
        // canvas, on a grouped surface or on a raised card, and its selected
        // weight must not change with what is behind it.
        ? Color.alphaBlend(
            AppColors.brand.withValues(alpha: dark ? 0.26 : 0.16),
            AppColors.surfaceColor(context),
          )
        : AppColors.surfaceAlt(context);
    final edge = selected
        ? AppColors.brandInk(context).withValues(alpha: 0.42)
        : AppColors.border(context);

    final glyph = leading ?? (selected ? Icons.check_rounded : null);
    final announced = semanticLabel ??
        [label, if (count != null) count].whereType<String>().join(', ');

    final pill = AnimatedContainer(
      duration: AppMotion.respect(context, AppMotion.fast),
      curve: AppMotion.easeOut,
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: edge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            Icon(glyph, size: 13, color: ink),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.weight(
                AppText.label(context),
                selected ? FontWeight.w700 : FontWeight.w600,
              ).copyWith(fontSize: 12.5, color: ink),
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 5),
            Text(
              count!,
              maxLines: 1,
              style: AppText.caption(context).copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: ink.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );

    if (!enabled || onTap == null) {
      // PanelUI only announces a chip as a control when it can be pressed; a
      // static attribute tag gets no button role at all, so a reader does not
      // offer an action that does not exist.
      final interactive = onTap != null;
      return Semantics(
        button: interactive,
        selected: selected,
        enabled: interactive ? false : null,
        label: announced,
        excludeSemantics: true,
        child: Opacity(opacity: 0.45, child: pill),
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      enabled: true,
      label: announced,
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}
