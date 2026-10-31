import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/category_style.dart';
import '../utils/formatters.dart';

/// A horizontal rail of category cards — the dashboard's one direct borrow from
/// Suno's cover-art carousel, translated to data rather than decoration.
///
/// Each card is a ranked fact, not a chart: icon, share, category, amount, and a
/// hairline bar at the same scale on every card. The rail peeks the next card at
/// the screen edge, which is what tells the thumb it can scroll. Colour is
/// confined to the category glyph and the bar, so the page keeps its single
/// accent: category hues are data encoding, not chrome.
class CategoryRail extends StatelessWidget {
  /// Category name → spending in paise.
  final Map<String, int> totalsMinor;

  /// How many cards before the remainder is summarised.
  final int maxCards;

  const CategoryRail({
    super.key,
    required this.totalsMinor,
    this.maxCards = 6,
  });

  @override
  Widget build(BuildContext context) {
    final entries = totalsMinor.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) return const _CategoryRailEmpty();

    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    if (total <= 0) return const _CategoryRailEmpty();

    final shown = entries.take(maxCards).toList();
    final hidden = entries.length - shown.length;

    final scale =
        (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.6);
    final height = 148 + (scale - 1) * 70;
    final width = 156 + (scale - 1) * 26;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: height,
          // One or two categories do not need a scroll gesture: a short static
          // row is calmer, and it keeps the dashboard from owning a second
          // Scrollable when there is nothing to scroll.
          child: shown.length <= 2
              ? Row(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _CategoryCard(
                          category: shown[i].key,
                          amountMinor: shown[i].value,
                          share: shown[i].value / total,
                          featured: i == 0,
                        ),
                      ),
                    ],
                  ],
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: shown.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.md),
                  itemBuilder: (context, index) => SizedBox(
                    width: width,
                    child: _CategoryCard(
                      category: shown[index].key,
                      amountMinor: shown[index].value,
                      share: shown[index].value / total,
                      featured: index == 0,
                    ),
                  ),
                ),
        ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '+$hidden more ${hidden == 1 ? 'category' : 'categories'}',
              style: AppText.label(context).copyWith(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String category;
  final int amountMinor;
  final double share;
  final bool featured;

  const _CategoryCard({
    required this.category,
    required this.amountMinor,
    required this.share,
    required this.featured,
  });

  @override
  Widget build(BuildContext context) {
    final color = CategoryStyle.color(category);
    final percent = (share * 100).round();
    final dark = AppColors.isDark(context);

    return Semantics(
      container: true,
      label: '$category, ${Formatters.currency.format(amountMinor)}, '
          '$percent percent of spending',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: featured
                ? color.withValues(alpha: dark ? 0.42 : 0.34)
                : AppColors.border(context),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: dark ? 0.20 : 0.13),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CategoryStyle.icon(category),
                    size: 17,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  '$percent%',
                  style: AppText.label(context).copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(context).copyWith(
                fontSize: 11.5,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Formatters.currency.format(amountMinor),
                maxLines: 1,
                style: AppText.amount(context, size: 18),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: color.withValues(alpha: 0.13),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRailEmpty extends StatelessWidget {
  const _CategoryRailEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt(context),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              Icons.pie_chart_outline_rounded,
              size: 21,
              color: AppColors.textTertiary(context),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No spending this cycle',
                  style: AppText.bodyStrong(context),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add a transaction and the breakdown fills in automatically.',
                  style: AppText.bodySmall(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
