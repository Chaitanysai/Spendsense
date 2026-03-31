// transaction_model.dart
// Add toJson() and fromJson() to your existing TransactionModel.
// Only the serialisation additions are shown — merge with your existing fields.

enum TransactionType { expense, income }

class TransactionModel {
  final String id;
  final double amount;
  final TransactionType type;
  final String merchant;
  final String category;
  final String paymentMethod;
  final DateTime date;
  final String time;
  final String originalSms;
  final bool isExcluded;

  const TransactionModel({
    required this.id,
    required this.amount,
    required this.type,
    required this.merchant,
    required this.category,
    required this.paymentMethod,
    required this.date,
    required this.time,
    required this.originalSms,
    required this.isExcluded,
  });

  // ─── SERIALISATION ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'type': type == TransactionType.income ? 'income' : 'expense',
        'merchant': merchant,
        'category': category,
        'paymentMethod': paymentMethod,
        'date': date.toIso8601String(),
        'time': time,
        'originalSms': originalSms,
        'isExcluded': isExcluded,
      };

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      amount: (json['amount'] as num).toDouble(),
      type: json['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense,
      merchant: json['merchant'] as String,
      category: json['category'] as String,
      paymentMethod: json['paymentMethod'] as String? ?? 'SMS',
      date: DateTime.parse(json['date'] as String),
      time: json['time'] as String,
      originalSms: json['originalSms'] as String? ?? '',
      isExcluded: json['isExcluded'] as bool? ?? false,
    );
  }

  // ─── COPY WITH ─────────────────────────────────────────────────────────────

  TransactionModel copyWith({
    String? id,
    double? amount,
    TransactionType? type,
    String? merchant,
    String? category,
    String? paymentMethod,
    DateTime? date,
    String? time,
    String? originalSms,
    bool? isExcluded,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      merchant: merchant ?? this.merchant,
      category: category ?? this.category,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      date: date ?? this.date,
      time: time ?? this.time,
      originalSms: originalSms ?? this.originalSms,
      isExcluded: isExcluded ?? this.isExcluded,
    );
  }
}
