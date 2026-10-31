import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/app_spacing.dart';
import '../utils/app_text_styles.dart';
import '../utils/formatters.dart';
import 'animated_amount.dart';
import 'animated_progress_bar.dart';
import 'cycle_ring.dart';
import 'pressable.dart';

/// The dashboard's single instrument: where this salary cycle stands.
///
/// The composition is lifted from two references, not copied from either:
/// GO Club's one-metric hero (a ring, one enormous number, a three-stat strip
/// underneath) and Suno's editorial confidence (a quiet canvas, one accent, and
/// type doing the hierarchy). The ring is the only loud object; everything else
/// on the screen is neutral surface.
///
/// Over budget is a full ring plus the error tone — never a bar that wraps past
/// 100% — because a progress control that visually exceeds its own track reads
/// as a layout bug. The real percentage and the overspend amount still live in
/// the budget section below, where the user can act on them.
class CycleHero extends StatelessWidget {
  /// Spending in paise for the current salary cycle.
  final int spentMinor;

  /// Monthly budget in paise. Zero means "no budget", which is a prompt, not a
  /// divide-by-zero.
  final int budgetMinor;

  /// Empty-ledger count and leading category, used when there is no budget to
  /// compare against. Never fabricated: both come from the tracked ledger.
  final int transactionCount;
  final String topCategory;

  final String periodLabel;
  final DateTime periodEnd;

  /// Spending in the comparable previous cycle, or null when the period mode
  /// has no predecessor. Null suppresses the cycle-over-cycle pill.
  final int? previousSpentMinor;

  final bool visible;
  final VoidCallback onToggleVisibility;
  final VoidCallback onSetBudget;
  final bool ledgerError;

  const CycleHero({
    super.key,
    required this.spentMinor,
    required this.budgetMinor,
    required this.transactionCount,
    required this.topCategory,
    required this.periodLabel,
    required this.periodEnd,
    required this.visible,
    required this.onToggleVisibility,
    required this.onSetBudget,
    this.previousSpentMinor,
    this.ledgerError = false,
  });

  bool get _hasBudget => budgetMinor > 0;

  double get _fraction =>
      _hasBudget ? (spentMinor / budgetMinor).clamp(0.0, 1.0) : 0.0;

  bool get _over => _hasBudget && spentMinor > budgetMinor;

  bool get _nearLimit =>
      _hasBudget && !_over && spentMinor / budgetMinor >= 0.8;

  /// Days remaining in the cycle, inclusive of today. Calendar arithmetic in
  /// UTC so a DST shift can never move the answer by a day.
  int get _daysLeft {
    final now = DateTime.now();
    final end = DateTime.utc(periodEnd.year, periodEnd.month, periodEnd.day);
    final today = DateTime.utc(now.year, now.month, now.day);
    final diff = end.difference(today).inDays + 1;
    return diff < 1 ? 1 : diff;
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // At large text sizes the ring and its label fight for the same pixels.
    // Keeping the ring but shrinking the type would defeat the setting, so the
    // hero changes shape instead: same information, a linear track.
    final compact = scale > 1.35;
    final dark = AppColors.isDark(context);

    final tone = _over
        ? AppColors.expenseRed
        : _nearLimit
            ? AppColors.amber
            : AppColors.brand;
    final ringEnd = _over
        ? AppColors.expenseRed
        : _nearLimit
            ? AppColors.amber
            : AppColors.brandBright;
    final head = _over
        ? AppColors.expenseRed
        : _nearLimit
            ? AppColors.amber
            : (dark ? AppColors.lime : AppColors.brand);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Cap the dial so it never becomes a dinner plate on a tablet; on a
        // normal phone it uses the page width.
        final ringSize =
            width < 240 ? width : (width - 16).clamp(200.0, 280.0).toDouble();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PeriodRow(
              periodLabel: periodLabel,
              visible: visible,
              onToggleVisibility: onToggleVisibility,
            ),
            const SizedBox(height: AppSpacing.md),
            if (compact)
              _compactBody(context, tone)
            else ...[
              Center(
                child: Semantics(
                  container: true,
                  label: _summary(),
                  child: ExcludeSemantics(
                    child: CycleRing(
                      fraction: _fraction,
                      size: ringSize,
                      // The track has to be visible as a complete circle, or
                      // the dial reads as a crescent. A tinted track carries
                      // the brand in light mode without turning into a second
                      // accent.
                      trackColor: dark
                          ? Colors.white.withValues(alpha: 0.16)
                          : AppColors.brand.withValues(alpha: 0.16),
                      startColor: tone,
                      endColor: ringEnd,
                      headColor: head,
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: ringSize * 0.1),
                        child: _center(context),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _stats(context, compact: false),
            ],
            if (!_hasBudget && !ledgerError) ...[
              const SizedBox(height: AppSpacing.md),
              Center(child: _setBudgetButton(context)),
            ],
          ],
        );
      },
    );
  }

  String _summary() {
    // The default reads only the visible state. A screen-reader user who chose
    // to hide the figure must not have it announced on the next rebuild.
    if (!visible) return 'Balance hidden.';
    if (ledgerError) {
      return 'Spending summary unavailable. Your saved transactions could not '
          'be read.';
    }
    if (!_hasBudget) {
      return _withDelta('Spent ${Formatters.currency.format(spentMinor)} this '
          'cycle. No budget set.');
    }
    final left = budgetMinor - spentMinor;
    if (left < 0) {
      return _withDelta('Spent ${Formatters.currency.format(spentMinor)} this '
          'cycle, ${Formatters.currency.format(-left)} over the '
          '${Formatters.currency.format(budgetMinor)} budget.');
    }
    return _withDelta('Spent ${Formatters.currency.format(spentMinor)} this '
        'cycle of a ${Formatters.currency.format(budgetMinor)} budget. '
        '${Formatters.currency.format(left)} left.');
  }

  /// Adds the cycle-over-cycle sentence to the dial's spoken label. The pill
  /// itself is inside an ExcludeSemantics subtree, so without this a screen
  /// reader would never hear the comparison.
  String _withDelta(String base) {
    final previous = previousSpentMinor;
    if (previous == null || previous <= 0) return base;
    final delta = (spentMinor - previous) * 100.0 / previous;
    if (delta.abs() <= 0.05) return '$base Same as the previous cycle.';
    return '$base ${delta.abs().toStringAsFixed(1)} percent '
        '${delta > 0 ? 'more' : 'less'} than the previous cycle.';
  }

  Widget _center(BuildContext context) {
    final amount = AppText.amount(
      context,
      size: 40,
      weight: FontWeight.w800,
      letterSpacing: -1.4,
    );
    final caption = ledgerError
        ? 'Couldn\'t load your ledger'
        : _hasBudget
            ? (visible
                ? 'of ${Formatters.currency.format(budgetMinor)} budget'
                : 'budget hidden')
            : 'No budget set';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Total spent this cycle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.overline(context).copyWith(
            fontSize: 9.5,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: visible
              ? AnimatedAmount(
                  value: spentMinor.toDouble(),
                  format: (v) => Formatters.currency.format(v),
                  style: amount,
                )
              : Text(
                  '••••••',
                  style: amount.copyWith(letterSpacing: 1.5),
                ),
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppText.caption(context),
        ),
        if (visible &&
            previousSpentMinor != null &&
            previousSpentMinor! > 0) ...[
          const SizedBox(height: 10),
          _DeltaPill(
            currentMinor: spentMinor,
            previousMinor: previousSpentMinor!,
          ),
        ],
      ],
    );
  }

  Widget _compactBody(BuildContext context, Color tone) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: _summary(),
            child: ExcludeSemantics(child: _center(context)),
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedProgressBar(
            fraction: _fraction,
            height: 9,
            gradient: LinearGradient(colors: [
              tone,
              AppColors.isDark(context)
                  ? AppColors.lime
                  : AppColors.brandBright,
            ]),
            trackColor: AppColors.border(context),
            semanticLabel: 'Budget used',
          ),
          const SizedBox(height: AppSpacing.lg),
          _stats(context, compact: true),
        ],
      ),
    );
  }

  Widget _setBudgetButton(BuildContext context) {
    return Pressable(
      onTap: onSetBudget,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: AppColors.brandInk(context).withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_rounded,
              size: 16,
              color: AppColors.brandInk(context),
            ),
            const SizedBox(width: 6),
            Text(
              'Set a budget',
              style: AppText.label(context).copyWith(
                color: AppColors.brandInk(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stats(BuildContext context, {required bool compact}) {
    final entries = <_HeroStat>[];
    if (!ledgerError) {
      if (_hasBudget) {
        final left = budgetMinor - spentMinor;
        final days = _daysLeft;
        entries
          ..add(_HeroStat(
            left >= 0 || !visible ? 'Left' : 'Over',
            visible
                ? Formatters.currency.format(left >= 0 ? left : -left)
                : '••••',
          ))
          ..add(_HeroStat(
            'Per day',
            visible
                ? Formatters.currency.format(left > 0 ? left ~/ days : 0)
                : '••••',
          ))
          ..add(_HeroStat('Days left', '$days'));
      } else {
        entries
          ..add(_HeroStat('Activity', '$transactionCount'))
          ..add(_HeroStat(
            'Top category',
            topCategory.isEmpty ? '—' : topCategory,
          ))
          ..add(_HeroStat('Days left', '$_daysLeft'));
      }
    }

    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surfaceColor(context),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.gpp_maybe_rounded,
              size: 18,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Your saved transactions are still on this device. '
                'Nothing was deleted.',
                style: AppText.bodySmall(context),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.md : AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceColor(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: compact
          ? Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: AppSpacing.md,
                      color: AppColors.border(context),
                    ),
                  _StatRow(stat: entries[i]),
                ],
              ],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0)
                      Container(
                        width: 1,
                        color: AppColors.border(context),
                      ),
                    Expanded(child: _StatCell(stat: entries[i])),
                  ],
                ],
              ),
            ),
    );
  }
}

class _HeroStat {
  final String label;
  final String value;
  const _HeroStat(this.label, this.value);
}

class _StatCell extends StatelessWidget {
  final _HeroStat stat;
  const _StatCell({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.overline(context).copyWith(fontSize: 9.5),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              stat.value,
              maxLines: 1,
              style: AppText.amount(context, size: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final _HeroStat stat;
  const _StatRow({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            stat.label,
            style: AppText.overline(context).copyWith(fontSize: 10),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            stat.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppText.amount(context, size: 15),
          ),
        ),
      ],
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final String periodLabel;
  final bool visible;
  final VoidCallback onToggleVisibility;

  const _PeriodRow({
    required this.periodLabel,
    required this.visible,
    required this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor(context),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppColors.border(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: AppColors.textTertiary(context),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    periodLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(context).copyWith(
                      fontSize: 10.5,
                      color: AppColors.textSecondary(context),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Semantics(
          button: true,
          label: visible ? 'Hide balance' : 'Show balance',
          excludeSemantics: true,
          child: Pressable(
            onTap: onToggleVisibility,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Cycle-over-cycle change, shown as the one saturated pill on the canvas.
///
/// It only renders when the previous window is comparable and non-empty. A
/// fabricated "up this month" is worse than silence.
class _DeltaPill extends StatelessWidget {
  final int currentMinor;
  final int previousMinor;

  const _DeltaPill({
    required this.currentMinor,
    required this.previousMinor,
  });

  @override
  Widget build(BuildContext context) {
    final delta = (currentMinor - previousMinor) * 100.0 / previousMinor;
    final rising = delta > 0.05;
    final falling = delta < -0.05;
    final label = !rising && !falling
        ? 'Same as last cycle'
        : '${delta.abs().toStringAsFixed(1)}% '
            '${rising ? 'more' : 'less'} than last cycle';
    final icon = rising
        ? Icons.trending_up_rounded
        : falling
            ? Icons.trending_down_rounded
            : Icons.remove_rounded;

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.lime,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.onLime(context)),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(context).copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onLime(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
