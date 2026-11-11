import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/formatters.dart';
import 'category_spending_bars.dart';
import 'glass_card.dart';

/// The dashboard's "Spending by category" surface.
///
/// One card, one reading: the cycle total, the composition strip, and every
/// category in ranked rows. Tapping a row (or the strip's legend below it)
/// emphasises that category in both places, which is how a 3-pixel slice in the
/// strip can still be identified.
///
/// Nothing is discarded when the list is long: the first [collapsedRows] rows are
/// shown, and "Show all" reveals the rest from the same data. The composition
/// strip always includes every category, so the total is never a lie.
class CategoryBreakdownCard extends StatefulWidget {
  /// Category name → spending in paise.
  final Map<String, int> totalsMinor;

  /// Rows shown before "Show all".
  final int collapsedRows;

  const CategoryBreakdownCard({
    super.key,
    required this.totalsMinor,
    this.collapsedRows = 5,
  });

  @override
  State<CategoryBreakdownCard> createState() => _CategoryBreakdownCardState();
}

class _CategoryBreakdownCardState extends State<CategoryBreakdownCard> {
  bool _expanded = false;
  String? _selected;

  @override
  void didUpdateWidget(covariant CategoryBreakdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A category that disappears (its transactions were excluded or moved to
    // another cycle) must not stay selected.
    final selected = _selected;
    if (selected != null &&
        !widget.totalsMinor.entries
            .any((e) => e.key == selected && e.value > 0)) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries =
        widget.totalsMinor.entries.where((e) => e.value > 0).toList();
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    final count = entries.length;
    final canExpand = count > widget.collapsedRows;
    final selected = _selected;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Wrap, not a Row: at 320dp with 2x text the total and the count
          // pill together are wider than the card, and a Row has nowhere to put
          // the pill but off the edge (measured: 25dp over). The pill now drops
          // to its own line when it does not fit beside the total.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Spent this cycle',
                    style: AppText.label(context).copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Formatters.currency.format(total),
                        style: AppText.amount(
                          context,
                          size: 24,
                          weight: FontWeight.w600,
                          letterSpacing: -0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceTertiary(context),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.border(context)),
                ),
                child: Text(
                  count == 1 ? '1 category' : '$count categories',
                  style: AppText.label(context).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          CategorySpendingBars(
            totalsMinor: widget.totalsMinor,
            maxRows: _expanded ? count : widget.collapsedRows,
            selectedCategory: selected,
            // With one category the strip and its single row draw the same bar
            // twice; the row already says everything the strip would.
            showComposition: count > 1,
            onSelect: (next) => setState(() => _selected = next),
            onShowAll: canExpand && !_expanded
                ? () => setState(() => _expanded = true)
                : null,
          ),
          if (canExpand && _expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _expanded = false),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.brandInk(context),
                ),
                child: Text(
                  'Show less',
                  style: AppText.weight(AppText.label(context), FontWeight.w700)
                      .copyWith(
                    fontSize: 11.5,
                    color: AppColors.brandInk(context),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
