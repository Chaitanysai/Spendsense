import '../models/transaction_model.dart';

class RecurringTransaction {
  final String merchant;
  final String category;
  final double averageAmount;
  final int occurrenceCount;
  final DateTime firstOccurrence;
  final DateTime lastOccurrence;
  final RecurrenceFrequency frequency;
  final List<TransactionModel> transactions;

  RecurringTransaction({
    required this.merchant,
    required this.category,
    required this.averageAmount,
    required this.occurrenceCount,
    required this.firstOccurrence,
    required this.lastOccurrence,
    required this.frequency,
    required this.transactions,
  });

  String get frequencyLabel {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return 'Daily';
      case RecurrenceFrequency.weekly:
        return 'Weekly';
      case RecurrenceFrequency.biWeekly:
        return 'Bi-weekly';
      case RecurrenceFrequency.monthly:
        return 'Monthly';
      case RecurrenceFrequency.irregular:
        return 'Irregular';
    }
  }
}

enum RecurrenceFrequency { daily, weekly, biWeekly, monthly, irregular }

class RecurringDetectorService {
  /// Detects recurring transactions from the transaction list
  List<RecurringTransaction> detectRecurring(
      List<TransactionModel> transactions) {
    if (transactions.isEmpty) return [];

    // Group by merchant
    final Map<String, List<TransactionModel>> byMerchant = {};
    for (var tx in transactions) {
      byMerchant.putIfAbsent(tx.merchant, () => []).add(tx);
    }

    final recurring = <RecurringTransaction>[];

    for (var entry in byMerchant.entries) {
      final merchantTx = entry.value;

      // Need at least 2 occurrences to detect recurring
      if (merchantTx.length < 2) continue;

      // Sort by date
      merchantTx.sort((a, b) => a.date.compareTo(b.date));

      // Calculate intervals between transactions
      final intervals = <int>[];
      for (int i = 1; i < merchantTx.length; i++) {
        final daysDiff =
            merchantTx[i].date.difference(merchantTx[i - 1].date).inDays;
        if (daysDiff > 0) intervals.add(daysDiff);
      }

      if (intervals.isEmpty) continue;

      // Calculate average interval
      final avgInterval = intervals.reduce((a, b) => a + b) / intervals.length;

      // Determine frequency
      RecurrenceFrequency frequency;
      if (avgInterval <= 2) {
        frequency = RecurrenceFrequency.daily;
      } else if (avgInterval <= 9) {
        frequency = RecurrenceFrequency.weekly;
      } else if (avgInterval <= 18) {
        frequency = RecurrenceFrequency.biWeekly;
      } else if (avgInterval <= 35) {
        frequency = RecurrenceFrequency.monthly;
      } else {
        frequency = RecurrenceFrequency.irregular;
      }

      // Only include if it's a recognizable pattern (not irregular with many gaps)
      if (frequency == RecurrenceFrequency.irregular && intervals.length > 3) {
        // Check if intervals are somewhat consistent (within 50% variance)
        final variance = intervals.fold<double>(
                0, (sum, d) => sum + (d - avgInterval).abs()) /
            intervals.length;
        if (variance > avgInterval * 0.5) continue;
      }

      // Calculate average amount
      final totalAmount =
          merchantTx.fold<double>(0, (sum, tx) => sum + tx.amount);
      final avgAmount = totalAmount / merchantTx.length;

      recurring.add(RecurringTransaction(
        merchant: entry.key,
        category: merchantTx.first.category,
        averageAmount: avgAmount,
        occurrenceCount: merchantTx.length,
        firstOccurrence: merchantTx.first.date,
        lastOccurrence: merchantTx.last.date,
        frequency: frequency,
        transactions: merchantTx,
      ));
    }

    // Sort by occurrence count (most frequent first)
    recurring.sort((a, b) => b.occurrenceCount.compareTo(a.occurrenceCount));

    return recurring;
  }

  /// Get estimated monthly cost of all recurring transactions
  double getEstimatedMonthlyCost(List<RecurringTransaction> recurring) {
    double monthly = 0;

    for (var r in recurring) {
      switch (r.frequency) {
        case RecurrenceFrequency.daily:
          monthly += r.averageAmount * 30;
          break;
        case RecurrenceFrequency.weekly:
          monthly += r.averageAmount * 4.33;
          break;
        case RecurrenceFrequency.biWeekly:
          monthly += r.averageAmount * 2.17;
          break;
        case RecurrenceFrequency.monthly:
        case RecurrenceFrequency.irregular:
          monthly += r.averageAmount;
          break;
      }
    }

    return monthly;
  }

  /// Find potential subscriptions (monthly recurring payments)
  List<RecurringTransaction> findSubscriptions(
      List<RecurringTransaction> recurring) {
    return recurring
        .where((r) =>
            r.frequency == RecurrenceFrequency.monthly ||
            (r.frequency == RecurrenceFrequency.irregular &&
                r.occurrenceCount >= 3))
        .toList();
  }
}
