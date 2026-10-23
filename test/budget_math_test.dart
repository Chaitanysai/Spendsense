import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/utils/budget_math.dart';

BudgetProgress p(int spent, int budget) =>
    BudgetProgress(spentMinor: spent, budgetMinor: budget);

void main() {
  group('BudgetProgress (integer paise)', () {
    test('zero or invalid budget never divides', () {
      for (final budget in [0, -1, -50000]) {
        final progress = p(1234, budget);
        expect(progress.hasBudget, isFalse);
        expect(progress.percentUsed, 0);
        expect(progress.ringFraction, 0);
        expect(progress.isOver, isFalse);
        expect(progress.overMinor, 0);
        expect(progress.crossedThreshold([50, 80, 100]), isNull);
      }
    });

    test('percent rounds half up and matches the existing 43% case', () {
      expect(p(4250, 10000).percentUsed, 43); // 42.5 -> 43
      expect(p(4249, 10000).percentUsed, 42);
      expect(p(2500, 10000).percentUsed, 25);
    });

    test('a budget not yet reached never displays 100%', () {
      // 99.6% of the budget used: rounds to 100 but the budget is not reached.
      final almost = p(9960, 10000);
      expect(almost.percentUsed, 99);
      expect(almost.isOver, isFalse);
      expect(almost.ringFraction, lessThan(1));
    });

    test('exactly full is 100% and not over', () {
      final full = p(10000, 10000);
      expect(full.percentUsed, 100);
      expect(full.isOver, isFalse);
      expect(full.overMinor, 0);
      expect(full.ringFraction, 1);
    });

    test('overspend reports the real percentage, amount and a full ring', () {
      final over = p(15050, 10000);
      expect(over.isOver, isTrue);
      expect(over.overMinor, 5050);
      expect(over.percentUsed, 151); // 150.5 -> 151
      expect(over.overPercent, 51);
      expect(over.remainingMinor, -5050);
      expect(over.ringFraction, 1);
      expect(p(30000, 10000).percentUsed, 300);
    });

    test('paise precision survives: ₹239.50 of ₹1,000', () {
      final progress = p(23950, 100000);
      expect(progress.percentUsed, 24); // 23.95 -> 24
      expect(progress.remainingMinor, 76050);
    });

    test('very large values do not overflow or lose precision', () {
      const budget = 100000000000; // ₹100 crore, the app maximum
      final progress = p(budget ~/ 2, budget);
      expect(progress.percentUsed, 50);
      expect(p(budget * 3, budget).percentUsed, 300);
    });

    test('negative spending is treated as zero', () {
      expect(p(-100, 10000).spentMinor, 0);
    });

    test('thresholds are exact integer comparisons', () {
      expect(p(4999, 10000).crossedThreshold([50, 80, 100]), isNull);
      expect(p(5000, 10000).crossedThreshold([50, 80, 100]), 50);
      expect(p(7999, 10000).crossedThreshold([50, 80, 100]), 50);
      expect(p(8000, 10000).crossedThreshold([50, 80, 100]), 80);
      expect(p(10000, 10000).crossedThreshold([50, 80, 100]), 100);
      // Only enabled thresholds count.
      expect(p(9000, 10000).crossedThreshold([100]), isNull);
      expect(p(9000, 10000).crossedThreshold([50]), 50);
    });

    test('stored thresholds are validated, de-duplicated and sorted', () {
      expect(normalizeBudgetThresholds([100, 50, 50, 70, null, 'x', -5]),
          [50, 100]);
      expect(normalizeBudgetThresholds(const []), isEmpty);
    });
  });
}
