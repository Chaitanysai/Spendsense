import 'dart:math' as math;

/// The warning thresholds a user may enable, as whole percentages of a budget.
const List<int> kBudgetThresholdChoices = [50, 80, 100];

/// Default enabled thresholds.
const List<int> kDefaultBudgetThresholds = [50, 80, 100];

/// Integer-paise budget arithmetic. No floating point is used for any
/// comparison or percentage; [ringFraction] is the single presentation-boundary
/// conversion (an arc sweep) and is never compared against money.
///
/// Rounding rule for [percentUsed]: round half up to a whole percent, except
/// that a budget which has *not* been reached never displays as 100% (it is
/// held at 99%), and one that has been exceeded displays its true value
/// (e.g. 150%), uncapped.
class BudgetProgress {
  final int spentMinor;
  final int budgetMinor;

  const BudgetProgress({required int spentMinor, required this.budgetMinor})
      : spentMinor = spentMinor < 0 ? 0 : spentMinor;

  bool get hasBudget => budgetMinor > 0;

  /// Negative when over budget.
  int get remainingMinor => budgetMinor - spentMinor;

  bool get isOver => hasBudget && spentMinor > budgetMinor;

  /// Amount above the budget; zero unless [isOver].
  int get overMinor => isOver ? spentMinor - budgetMinor : 0;

  /// Whole percent of the budget used (see class docs). Zero without a budget.
  int get percentUsed {
    if (!hasBudget) return 0;
    final scaled = spentMinor * 100;
    final rounded = (scaled * 2 + budgetMinor) ~/ (budgetMinor * 2);
    if (spentMinor < budgetMinor) return math.min(rounded, 99);
    return rounded;
  }

  /// Whole percent above the budget, e.g. 150% used => 50. Zero unless [isOver].
  int get overPercent => isOver ? math.max(percentUsed - 100, 0) : 0;

  /// Ring fill in 0..1 for drawing. An exceeded budget fills the whole ring.
  double get ringFraction {
    if (!hasBudget) return 0;
    if (spentMinor >= budgetMinor) return 1;
    return spentMinor / budgetMinor;
  }

  /// The highest enabled threshold already reached, or null. Comparisons are
  /// exact integer cross-multiplication: `spent * 100 >= budget * t`.
  int? crossedThreshold(Iterable<int> enabled) {
    if (!hasBudget) return null;
    int? best;
    for (final t in enabled) {
      if (t <= 0) continue;
      if (spentMinor * 100 >= budgetMinor * t && (best == null || t > best)) {
        best = t;
      }
    }
    return best;
  }
}

/// Validates a stored threshold list: only the supported choices, de-duplicated
/// and sorted. Unknown values are dropped rather than trusted.
List<int> normalizeBudgetThresholds(Iterable<Object?> raw) {
  final set = <int>{
    for (final v in raw)
      if (v is int && kBudgetThresholdChoices.contains(v)) v,
  };
  return set.toList()..sort();
}
