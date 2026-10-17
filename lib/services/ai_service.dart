import '../models/ai_chat_message.dart';
import '../models/transaction_model.dart';
import '../utils/formatters.dart';

class AIService {
  Future<String> askAI(
    List<AIChatMessage> history,
    List<TransactionModel> txs,
  ) async {
    // Only use expenses that are not excluded
    final expenses = txs
        .where((t) => !t.isExcluded && t.type == TransactionType.expense)
        .toList();
    if (history.isEmpty) return "How can I help you with your spending?";

    final lastMessage = history.last.content.toLowerCase();

    // Check intents
    if (lastMessage.contains('average') || lastMessage.contains('per day')) {
      return _handleAverage(expenses);
    }

    if (lastMessage.contains('top category') ||
        (lastMessage.contains('category') && lastMessage.contains('most'))) {
      return _handleTopCategory(expenses);
    }

    if (lastMessage.contains('top merchant') ||
        (lastMessage.contains('merchant') && lastMessage.contains('most'))) {
      return _handleTopMerchant(expenses);
    }

    if (lastMessage.contains('yesterday')) {
      return _handleSpecificDate(expenses,
          DateTime.now().subtract(const Duration(days: 1)), "yesterday");
    }

    if (lastMessage.contains('today')) {
      return _handleSpecificDate(expenses, DateTime.now(), "today");
    }

    // Specific category lookup
    for (var cat in [
      'food',
      'travel',
      'shopping',
      'utilities',
      'entertainment',
      'health',
      'fuel'
    ]) {
      if (lastMessage.contains(cat)) {
        return _handleCategoryTotal(expenses, cat);
      }
    }

    if (lastMessage.contains('total') ||
        lastMessage.contains('spend') ||
        lastMessage.contains('much')) {
      return _handleTotal(expenses);
    }

    return "I can answer questions like:\n- What is my average spent per day?\n- What are my top categories?\n- Which merchant did I spend the most at?\n- How much did I spend on food?\n- How much did I spend yesterday?";
  }

  String _handleAverage(List<TransactionModel> txs) {
    if (txs.isEmpty) return "You haven't spent anything yet.";

    final now = DateTime.now();
    final thisMonthTxs = txs
        .where((t) => t.date.month == now.month && t.date.year == now.year)
        .toList();

    if (thisMonthTxs.isEmpty)
      return "No expenses recorded this month to calculate an average.";

    double total = thisMonthTxs.fold(0.0, (sum, t) => sum + t.amount);

    // Days with transactions
    final activeDays = thisMonthTxs
        .map((t) => "${t.date.day}-${t.date.month}-${t.date.year}")
        .toSet()
        .length;
    final calendarDays = now.day;

    return "This month, you spent an average of ${Formatters.currency.format(total / calendarDays)} per calendar day (${Formatters.currency.format(total / (activeDays > 0 ? activeDays : 1))} per active spending day).";
  }

  String _handleTotal(List<TransactionModel> txs) {
    final now = DateTime.now();
    final thisMonthTxs = txs
        .where((t) => t.date.month == now.month && t.date.year == now.year)
        .toList();
    double total = thisMonthTxs.fold(0.0, (sum, t) => sum + t.amount);
    return "You have spent a total of ${Formatters.currency.format(total)} this month.";
  }

  String _handleTopCategory(List<TransactionModel> txs) {
    if (txs.isEmpty) return "No transactions found.";
    final map = <String, double>{};
    for (var t in txs) {
      map[t.category] = (map[t.category] ?? 0) + t.amount;
    }
    if (map.isEmpty) return "No categories found.";

    var sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return "Your top spending category is ${sorted.first.key} with ${Formatters.currency.format(sorted.first.value)}.";
  }

  String _handleTopMerchant(List<TransactionModel> txs) {
    if (txs.isEmpty) return "No transactions found.";
    final map = <String, double>{};
    for (var t in txs) {
      map[t.merchant] = (map[t.merchant] ?? 0) + t.amount;
    }
    if (map.isEmpty) return "No merchants found.";

    var sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return "You've spent the most at ${sorted.first.key} (${Formatters.currency.format(sorted.first.value)}).";
  }

  String _handleSpecificDate(
      List<TransactionModel> txs, DateTime date, String alias) {
    final dayTxs = txs
        .where((t) =>
            t.date.year == date.year &&
            t.date.month == date.month &&
            t.date.day == date.day)
        .toList();
    if (dayTxs.isEmpty) return "You didn't spend anything $alias.";

    double total = dayTxs.fold(0.0, (sum, t) => sum + t.amount);
    return "You spent ${Formatters.currency.format(total)} $alias across ${dayTxs.length} transactions.";
  }

  String _handleCategoryTotal(List<TransactionModel> txs, String category) {
    final catTxs = txs
        .where((t) => t.category.toLowerCase() == category.toLowerCase())
        .toList();
    if (catTxs.isEmpty) return "You haven't spent anything on $category.";

    double total = catTxs.fold(0.0, (sum, t) => sum + t.amount);
    return "You've spent a total of ${Formatters.currency.format(total)} on $category.";
  }
}
