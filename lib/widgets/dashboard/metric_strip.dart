import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';

/// One cell in a [MetricStrip].
@immutable
class MetricItem {
  final String label;
  final String value;
  final Color? valueColor;

  const MetricItem(this.label, this.value, {this.valueColor});
}

/// A row of equal-width metrics separated by hairlines.
///
/// This is the PanelUI `Kpi` group translated to Flutter: label above value,
/// tabular figures, one alignment. It collapses to stacked rows when the text
/// scale is large or the width is narrow, so a metric never truncates its
/// number to keep a column.
class MetricStrip extends StatelessWidget {
  final List<MetricItem> items;

  /// Ink for the labels. Defaults to the tertiary text tier.
  final Color? labelColor;

  /// Ink for the values. Defaults to the primary text tier.
  final Color? valueColor;

  /// Force the stacked layout (used inside the hero on a gradient).
  final bool stacked;

  const MetricStrip({
    super.key,
    required this.items,
    this.labelColor,
    this.valueColor,
    this.stacked = false,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final narrow = MediaQuery.sizeOf(context).width < 340;
    final useColumn = stacked || scale > 1.3 || narrow;

    if (useColumn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: (labelColor ?? AppColors.textTertiary(context))
                      .withValues(alpha: 0.18),
                ),
              ),
            _MetricRow(
              item: items[i],
              labelColor: labelColor,
              valueColor: valueColor,
            ),
          ],
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                color: (labelColor ?? AppColors.textTertiary(context))
                    .withValues(alpha: 0.18),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? 0 : AppSpacing.md,
                  right: i == items.length - 1 ? 0 : AppSpacing.md,
                ),
                child: _MetricCell(
                  item: items[i],
                  labelColor: labelColor,
                  valueColor: valueColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final MetricItem item;
  final Color? labelColor;
  final Color? valueColor;

  const _MetricCell({
    required this.item,
    this.labelColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.overline(context).copyWith(
            fontSize: 9.5,
            letterSpacing: 1.0,
            color: labelColor ?? AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            item.value,
            maxLines: 1,
            style: AppText.amount(
              context,
              size: 15,
              weight: FontWeight.w700,
              color: item.valueColor ??
                  valueColor ??
                  AppColors.textPrimary(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  final MetricItem item;
  final Color? labelColor;
  final Color? valueColor;

  const _MetricRow({
    required this.item,
    this.labelColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            item.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.overline(context).copyWith(
              fontSize: 9.5,
              letterSpacing: 1.0,
              color: labelColor ?? AppColors.textTertiary(context),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppText.amount(
              context,
              size: 15,
              weight: FontWeight.w700,
              color: item.valueColor ??
                  valueColor ??
                  AppColors.textPrimary(context),
            ),
          ),
        ),
      ],
    );
  }
}
