import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../../utils/app_spacing.dart';
import '../../utils/app_text_styles.dart';
import '../../utils/formatters.dart';
import '../animated_amount.dart';
import '../app_kpi_card.dart';
import '../app_surface.dart';
import '../pressable.dart';

/// The dashboard's financial overview — D1 solid-surface restyle.
///
/// Before this stage the hero was a dark navy `GradientHeroCard` — the loudest
/// object on the page. The references show white KPI cards, no gradient slab.
/// D1 (spec §5) keeps every figure and all existing calculations; only the
/// paint changes:
///
/// - The containing surface is `AppSurface(raised)` — a solid, palette-aware
///   card that fits into the neutral visual vocabulary alongside the section
///   cards below it.
/// - The balance figure is a large ink number, not white-on-dark.
/// - Income, Expenses and Net are shown as [AppKpiCard]s in a horizontal
///   scrolling [AppKpiRow] — the PanelUI `Kpi.Group` pattern from the reference.
/// - The budget bar is not repeated here: the "Monthly budget" section below
///   owns it. With no budget set, the hero offers the one setup action.
///
/// Nothing here touches [availableBalance], [totalIncomeForPeriod],
/// [totalExpensesForPeriod]; all provider getters are
/// called by [_HeroSection] in `home_screen.dart` and passed in.
class BalanceHero extends StatelessWidget {
  /// Net across all non-excluded transactions (income − expenses). This is the
  /// app's existing `availableBalance` definition, not a new one.
  final int balanceMinor;

  /// Income and expenses for the selected period.
  final int incomeMinor;
  final int expenseMinor;

  /// Expenses in the comparable previous period, or null when the period mode
  /// has no predecessor. Null suppresses the KPI-row trend indicators.
  final int? previousExpenseMinor;

  /// Previous period income, for the income KPI trend.
  final int? previousIncomeMinor;

  /// Monthly budget in paise. Zero means "no budget set".
  final int budgetMinor;

  final String periodLabel;
  final DateTime periodEnd;

  final bool visible;
  final VoidCallback onToggleVisibility;
  final VoidCallback onSetBudget;

  /// True when the encrypted ledger failed closed. The hero then shows a
  /// recovery message instead of figures that would look like a real zero.
  final bool ledgerError;

  const BalanceHero({
    super.key,
    required this.balanceMinor,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.budgetMinor,
    required this.periodLabel,
    required this.periodEnd,
    required this.visible,
    required this.onToggleVisibility,
    required this.onSetBudget,
    this.previousExpenseMinor,
    this.previousIncomeMinor,
    this.ledgerError = false,
  });

  bool get _hasBudget => budgetMinor > 0;

  /// Net balance for the current period (income − expenses).
  int get _netMinor => incomeMinor - expenseMinor;

  /// Percentage change in expenses vs. the previous equivalent period. Null
  /// when there is no comparable, non-empty predecessor.
  double? get _expenseDelta {
    final previous = previousExpenseMinor;
    if (previous == null || previous <= 0) return null;
    return (expenseMinor - previous) * 100.0 / previous;
  }

  /// Percentage change in income vs. the previous equivalent period.
  double? get _incomeDelta {
    final previous = previousIncomeMinor;
    if (previous == null || previous <= 0) return null;
    return (incomeMinor - previous) * 100.0 / previous;
  }

  @override
  Widget build(BuildContext context) {
    final inkPrimary = AppColors.textPrimary(context);
    final inkSecondary = AppColors.textSecondary(context);
    final inkTertiary = AppColors.textTertiary(context);
    // Two siblings on the page, never a card inside a card (PanelUI: depth
    // comes from the surface ladder, not from nesting raised surfaces): the
    // balance card, then the Income / Expenses / Net KPI row directly on the
    // canvas, as in the reference Overview.
    return Semantics(
      container: true,
      label: _summary(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSurface(
              level: AppSurfaceLevel.raised,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Available balance',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(context).copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: inkSecondary,
                          ),
                        ),
                      ),
                      _VisibilityToggle(
                        visible: visible,
                        onTap: onToggleVisibility,
                      ),
                    ],
                  ),
                  if (ledgerError)
                    Text(
                      'Ledger unavailable',
                      style: AppText.amount(
                        context,
                        size: 32,
                        weight: FontWeight.w600,
                        color: inkPrimary,
                      ),
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: visible
                          ? AnimatedAmount(
                              value: balanceMinor.toDouble(),
                              format: (v) => Formatters.currency.format(v),
                              style: AppText.amount(
                                context,
                                size: 32,
                                weight: FontWeight.w600,
                                color: inkPrimary,
                              ),
                            )
                          : Text(
                              '\u2022\u2022\u2022\u2022\u2022\u2022',
                              style: AppText.amount(
                                context,
                                size: 32,
                                weight: FontWeight.w600,
                                color: inkPrimary,
                              ).copyWith(letterSpacing: 2),
                            ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    ledgerError
                        ? 'Your saved transactions are still on this device.'
                        : 'Net across all transactions',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppText.caption(context).copyWith(color: inkTertiary),
                  ),
                  // The gap exists only when something follows it. A bare spacer
                  // left 12dp of dead space under the caption on every Home
                  // that already has a budget.
                  if (ledgerError) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Nothing was deleted. Reopen the app or retry from the '
                      'transactions list.',
                      style: AppText.bodySmall(context)
                          .copyWith(color: inkTertiary),
                    ),
                  ] else if (!_hasBudget) ...[
                    // The budget itself is the "Monthly budget" section's job.
                    // Here only the missing setup is offered, as an action.
                    const SizedBox(height: AppSpacing.md),
                    _SetBudgetButton(onTap: onSetBudget),
                  ],
                ],
              ),
            ),
            if (!ledgerError) ...[
              const SizedBox(height: AppSpacing.lg),
              // The period belongs to the three cards below, not to the
              // all-time balance above, so it labels them.
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Overview',
                    style: AppText.h2(context).copyWith(fontSize: 17),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      periodLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppText.caption(context)
                          .copyWith(color: inkTertiary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AppKpiRow(
                cards: [
                  AppKpiCard(
                    icon: Icons.north_east_rounded,
                    label: 'Income',
                    value: visible
                        ? Formatters.currency.format(incomeMinor)
                        : '\u2022\u2022\u2022\u2022',
                    trendValue: _incomeDelta,
                    trendGoodIsUp: true,
                  ),
                  AppKpiCard(
                    icon: Icons.south_west_rounded,
                    label: 'Expenses',
                    value: visible
                        ? Formatters.currency.format(expenseMinor)
                        : '\u2022\u2022\u2022\u2022',
                    trendValue: _expenseDelta,
                    trendGoodIsUp: false,
                  ),
                  AppKpiCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Net',
                    value: visible
                        ? Formatters.currency.format(_netMinor)
                        : '\u2022\u2022\u2022\u2022',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _summary() {
    if (!visible) return 'Balance hidden.';
    if (ledgerError) {
      return 'Balance unavailable. Your saved transactions could not be read.';
    }
    final balance = Formatters.currency.format(balanceMinor);
    final income = Formatters.currency.format(incomeMinor);
    final expenses = Formatters.currency.format(expenseMinor);
    final base = 'Available balance $balance. Income $income, '
        'expenses $expenses for $periodLabel.';
    final delta = _expenseDelta;
    if (delta == null) return base;
    if (delta.abs() <= 0.05) return '$base Same as the previous period.';
    return '$base ${delta.abs().toStringAsFixed(1)} percent '
        '${delta > 0 ? 'more' : 'less'} than the previous period.';
  }
}

// ── _VisibilityToggle ─────────────────────────────────────────────────────────

class _VisibilityToggle extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;

  const _VisibilityToggle({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: visible ? 'Hide balance' : 'Show balance',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 18,
            color: AppColors.textSecondary(context),
          ),
        ),
      ),
    );
  }
}

// ── _SetBudgetButton ──────────────────────────────────────────────────────────

class _SetBudgetButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SetBudgetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final inkColor = AppColors.brandInk(context);
    final border = AppColors.border(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 15, color: inkColor),
              const SizedBox(width: 6),
              Text(
                'Set a budget',
                style: AppText.label(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: inkColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
