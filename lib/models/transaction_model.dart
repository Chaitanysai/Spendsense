import 'package:flutter/foundation.dart';

enum TransactionType { expense, income }

class TransactionModel {
  /// Display fallback used whenever the bank could not be identified.
  static const String unknownBankLabel = 'Others';

  final String id;

  /// Canonical INR value in paise.
  final int amountMinor;

  /// Canonical amount alias for legacy call sites during migration.
  /// All calculations now receive integer paise.
  @Deprecated('Use amountMinor for clarity.')
  int get amount => amountMinor;
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

  TransactionModel({
    required this.id,
    @Deprecated('Use amountMinor for new code.') int? amount,
    int? amountMinor,
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
  })  : assert((amount == null) != (amountMinor == null)),
        amountMinor = amountMinor ?? amount! * 100;

  /// Bank name for display. Falls back to [unknownBankLabel] when no bank was
  /// identified, so every caller renders the same value for the same state.
  ///
  /// [bank] stays the stored, nullable field; this getter never mutates it and
  /// keeps 'Others' out of the persisted data.
  String get bankName {
    final value = bank?.trim();
    if (value == null ||
        value.isEmpty ||
        value.toLowerCase() == unknownBankLabel.toLowerCase()) {
      return unknownBankLabel;
    }
    return value;
  }

  // ─── SERIALISATION ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'currency': 'INR',
        'amountMinor': amountMinor,
        'id': id,
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
    final schema = json['schemaVersion'];
    final minor = json['amountMinor'];
    final int amountMinor;
    if (schema == 2 && json['currency'] == 'INR' && minor is int) {
      amountMinor = minor;
    } else if (schema == null && json['amount'] is int) {
      final legacy = json['amount'] as int;
      if (legacy < 0) throw const FormatException('Negative legacy amount');
      amountMinor = legacy * 100;
    } else {
      throw const FormatException('Unsupported or ambiguous money schema');
    }
    if (amountMinor < 0) throw const FormatException('Negative amount');

    return TransactionModel(
      id: json['id'] as String? ?? UniqueKey().toString(),
      amountMinor: amountMinor,
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
    @Deprecated('Use amountMinor for new code.') int? amount,
    int? amountMinor,
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
      amountMinor:
          amountMinor ?? (amount == null ? this.amountMinor : amount * 100),
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
