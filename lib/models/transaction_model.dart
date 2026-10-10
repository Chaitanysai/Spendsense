import 'package:flutter/foundation.dart';

enum TransactionType { expense, income }

class TransactionModel {
  final String id;
  final int amount;
  final TransactionType type;
  final String merchant;
  final String category;
  final String paymentMethod;
  final DateTime date;
  final String time;
  final String originalSms;
  final bool isExcluded;
  
  // ── SpendSense 2.0 New Fields ──────────────────────────────────────────────
  final String? bank;
  final String? account;
  final String? reference;
  final String source; // e.g., "SMS-Parser", "SMS-AI", "Manual"
  final double confidence; // 0.0 to 1.0
  final bool needsReview;

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
    this.bank,
    this.account,
    this.reference,
    this.source = 'SMS-Parser',
    this.confidence = 1.0,
    this.needsReview = false,
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
        'bank': bank,
        'account': account,
        'reference': reference,
        'source': source,
        'confidence': confidence,
        'needsReview': needsReview,
      };

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String? ?? UniqueKey().toString(),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      type: json['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense,
      merchant: json['merchant'] as String? ?? 'Unknown',
      category: json['category'] as String? ?? 'Other',
      paymentMethod: json['paymentMethod'] as String? ?? 'SMS',
      date: json['date'] != null 
          ? DateTime.tryParse(json['date'] as String) ?? DateTime.now() 
          : DateTime.now(),
      time: json['time'] as String? ?? '00:00',
      originalSms: json['originalSms'] as String? ?? '',
      isExcluded: json['isExcluded'] as bool? ?? false,
      bank: json['bank'] as String?,
      account: json['account'] as String?,
      reference: json['reference'] as String?,
      source: json['source'] as String? ?? 'SMS-Parser',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      needsReview: json['needsReview'] as bool? ?? false,
    );
  }

  // ─── COPY WITH ─────────────────────────────────────────────────────────────

  TransactionModel copyWith({
    String? id,
    int? amount,
    TransactionType? type,
    String? merchant,
    String? category,
    String? paymentMethod,
    DateTime? date,
    String? time,
    String? originalSms,
    bool? isExcluded,
    String? bank,
    String? account,
    String? reference,
    String? source,
    double? confidence,
    bool? needsReview,
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
      bank: bank ?? this.bank,
      account: account ?? this.account,
      reference: reference ?? this.reference,
      source: source ?? this.source,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
    );
  }
}
