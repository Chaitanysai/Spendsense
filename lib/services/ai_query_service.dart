import '../utils/formatters.dart';
import '../utils/money_parser.dart';
import '../models/transaction_model.dart';

class AIQueryService {
  /// Returns null if the query is not understood locally,
  /// so the caller can fall back to cloud AI.
  String? tryAnswer(String query, List<TransactionModel> txs) {
    final q = query.toLowerCase();

    if (txs.isEmpty) return "No transactions found.";

    final now = DateTime.now();

    // Filter to current month, non-excluded transactions
    final currentMonthTx = txs
        .where((t) =>
            t.date.month == now.month &&
            t.date.year == now.year &&
            !t.isExcluded)
        .toList();

    final expenseTx =
        currentMonthTx.where((t) => t.type == TransactionType.expense).toList();
    final incomeTx =
        currentMonthTx.where((t) => t.type == TransactionType.income).toList();

    final list = expenseTx.isNotEmpty
        ? expenseTx
        : txs
            .where((t) => !t.isExcluded && t.type == TransactionType.expense)
            .toList();

    bool hasAny(List<String> phrases) => phrases.any(q.contains);
    bool asksAveragePerDay = (q.contains("average") || q.contains("avg")) &&
        (q.contains("per day") || q.contains("daily") || q.contains("a day"));
    bool asksTotalSpent = hasAny([
      "total spent",
      "how much did i spend",
      "how much have i spent",
      "what did i spend",
      "what is my total spend",
      "show total spend",
    ]);

    if (q.contains("salary") ||
        q.contains("income") ||
        q.contains("credited")) {
      final totalIncome =
          incomeTx.fold<int>(0, (sum, t) => sum + t.amountMinor);
      if (totalIncome == 0) {
        return "I couldn't find any income transactions this month.";
      }
      return "Your income recorded this month is ${Formatters.currency.format(totalIncome)}.";
    }

    if (asksAveragePerDay) {
      if (expenseTx.isEmpty) {
        return "I couldn't find any spending transactions this month.";
      }
      final total = expenseTx.fold<int>(0, (sum, t) => sum + t.amountMinor);
      final uniqueDays = expenseTx
          .map((t) => DateTime(t.date.year, t.date.month, t.date.day))
          .toSet()
          .length;
      final average = roundPaiseDivision(total, uniqueDays);
      return "Your average spending per active day this month is ${Formatters.currency.format(average)}.";
    }

    // ─── 1. HIGHEST TRANSACTION ───────────────────────────────────────────────
    if (q.contains("largest") ||
        q.contains("highest") ||
        q.contains("maximum") ||
        q.contains("max")) {
      final maxTx =
          list.reduce((a, b) => a.amountMinor > b.amountMinor ? a : b);
      return "Your highest transaction is ${Formatters.currency.format(maxTx.amountMinor)}"
          " at ${maxTx.merchant}.";
    }

    // ─── 2. LOWEST TRANSACTION ───────────────────────────────────────────────
    if (q.contains("lowest") ||
        q.contains("smallest") ||
        q.contains("minimum") ||
        q.contains("min")) {
      final minTx =
          list.reduce((a, b) => a.amountMinor < b.amountMinor ? a : b);
      return "Your lowest transaction is ${Formatters.currency.format(minTx.amountMinor)}"
          " at ${minTx.merchant}.";
    }

    // ─── 3. PETROL / FUEL ────────────────────────────────────────────────────
    if ((q.contains("petrol") || q.contains("fuel")) &&
        (q.contains("spend") || q.contains("spent") || q.contains("much"))) {
      final fuelTx =
          expenseTx.where((t) => t.category.toLowerCase() == "fuel").toList();
      final total = fuelTx.fold<int>(0, (sum, t) => sum + t.amountMinor);
      return "You spent ${Formatters.currency.format(total)} on fuel this month.";
    }

    // ─── 4. FOOD ─────────────────────────────────────────────────────────────
    if ((q.contains("food") || q.contains("swiggy") || q.contains("zomato")) &&
        (q.contains("spend") || q.contains("spent") || q.contains("much"))) {
      final foodTx =
          expenseTx.where((t) => t.category.toLowerCase() == "food").toList();
      final total = foodTx.fold<int>(0, (sum, t) => sum + t.amountMinor);
      return "You spent ${Formatters.currency.format(total)} on food this month.";
    }

    // ─── 5. TOTAL SPENT ──────────────────────────────────────────────────────
    if (asksTotalSpent) {
      final total = expenseTx.fold<int>(0, (sum, t) => sum + t.amountMinor);
      return "You spent ${Formatters.currency.format(total)} this month.";
    }

    // ─── 6. CATEGORY ANALYSIS ────────────────────────────────────────────────
    if (q.contains("category")) {
      final Map<String, int> map = {};
      for (var t in expenseTx) {
        map[t.category] = (map[t.category] ?? 0) + t.amountMinor;
      }
      if (map.isEmpty) return "No category data found.";
      final top = map.entries.reduce((a, b) => a.value > b.value ? a : b);
      return "Your top category is ${top.key}"
          " with ${Formatters.currency.format(top.value)}.";
    }

    // ─── 7. TRANSACTION COUNT ────────────────────────────────────────────────
    if (q.contains("how many") || q.contains("count")) {
      return "You have ${expenseTx.length} spending transactions this month.";
    }

    // Return null → caller should escalate to cloud AI
    return null;
  }
}
