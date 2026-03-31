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

    final list = currentMonthTx.isNotEmpty ? currentMonthTx : txs;

    // ─── 1. HIGHEST TRANSACTION ───────────────────────────────────────────────
    if (q.contains("largest") ||
        q.contains("highest") ||
        q.contains("maximum") ||
        q.contains("max")) {
      final maxTx = list.reduce((a, b) => a.amount > b.amount ? a : b);
      return "Your highest transaction is ₹${maxTx.amount.toStringAsFixed(0)}"
          " at ${maxTx.merchant}.";
    }

    // ─── 2. LOWEST TRANSACTION ───────────────────────────────────────────────
    if (q.contains("lowest") ||
        q.contains("smallest") ||
        q.contains("minimum") ||
        q.contains("min")) {
      final minTx = list.reduce((a, b) => a.amount < b.amount ? a : b);
      return "Your lowest transaction is ₹${minTx.amount.toStringAsFixed(0)}"
          " at ${minTx.merchant}.";
    }

    // ─── 3. PETROL / FUEL ────────────────────────────────────────────────────
    if (q.contains("petrol") || q.contains("fuel")) {
      final fuelTx = currentMonthTx
          .where((t) => t.category.toLowerCase() == "fuel")
          .toList();
      final total = fuelTx.fold(0.0, (sum, t) => sum + t.amount);
      return "You spent ₹${total.toStringAsFixed(0)} on fuel this month.";
    }

    // ─── 4. FOOD ─────────────────────────────────────────────────────────────
    if (q.contains("food") || q.contains("swiggy") || q.contains("zomato")) {
      final foodTx = currentMonthTx
          .where((t) => t.category.toLowerCase() == "food")
          .toList();
      final total = foodTx.fold(0.0, (sum, t) => sum + t.amount);
      return "You spent ₹${total.toStringAsFixed(0)} on food this month.";
    }

    // ─── 5. TOTAL SPENT ──────────────────────────────────────────────────────
    if (q.contains("total") || q.contains("spent")) {
      final total = currentMonthTx.fold(0.0, (sum, t) => sum + t.amount);
      return "You spent ₹${total.toStringAsFixed(0)} this month.";
    }

    // ─── 6. CATEGORY ANALYSIS ────────────────────────────────────────────────
    if (q.contains("category")) {
      final Map<String, double> map = {};
      for (var t in currentMonthTx) {
        map[t.category] = (map[t.category] ?? 0) + t.amount;
      }
      if (map.isEmpty) return "No category data found.";
      final top = map.entries.reduce((a, b) => a.value > b.value ? a : b);
      return "Your top category is ${top.key}"
          " with ₹${top.value.toStringAsFixed(0)}.";
    }

    // ─── 7. TRANSACTION COUNT ────────────────────────────────────────────────
    if (q.contains("how many") || q.contains("count")) {
      return "You have ${currentMonthTx.length} transactions this month.";
    }

    // Return null → caller should escalate to cloud AI
    return null;
  }
}
