import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/transaction_model.dart';
import 'smart_parser.dart';

class _ParseProvider {
  final String name;
  final String url;
  final String apiKey;
  final String model;

  const _ParseProvider({
    required this.name,
    required this.url,
    required this.apiKey,
    required this.model,
  });

  Map<String, String> get headers => {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      };
}

class GeminiService {
  static List<_ParseProvider> get _providers => [
        _ParseProvider(
          name: 'Groq',
          url: 'https://api.groq.com/openai/v1/chat/completions',
          apiKey: AppConfig.groqKey,
          model: 'llama-3.3-70b-versatile',
        ),
        _ParseProvider(
          name: 'Gemini',
          url:
              'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
          apiKey: AppConfig.geminiKey,
          model: 'gemini-2.5-flash',
        ),
        _ParseProvider(
          name: 'OpenRouter',
          url: 'https://openrouter.ai/api/v1/chat/completions',
          apiKey: AppConfig.openRouterKey,
          model: 'meta-llama/llama-3.3-70b-instruct:free',
        ),
      ];

  /// Sanitizes SMS text by stripping sensitive data (OTP, PIN, CVV, full card/account numbers)
  /// before sending to cloud LLM providers (SpendSense 2.0 Privacy Mandate).
  String sanitizeSms(String sms) {
    String sanitized = sms;
    // Mask potential 4-6 digit OTPs
    sanitized = sanitized.replaceAll(RegExp(r'\b\d{4,6}\b'), '***');
    // Mask potential CVV/PIN
    sanitized = sanitized.replaceAll(
        RegExp(r'(?:cvv|pin)\s*[:=]?\s*\d{3,4}', caseSensitive: false),
        'cvv: ***');
    // Mask long card/account numbers leaving last 4 digits
    sanitized = sanitized.replaceAllMapped(RegExp(r'\b\d{10,16}\b'), (m) {
      final s = m.group(0)!;
      return '****${s.substring(s.length - 4)}';
    });
    return sanitized;
  }

  /// Parses one SMS through the provider fallback chain.
  /// Validates response JSON before constructing the TransactionModel.
  Future<TransactionModel?> parseSms(
    String sms,
    String id,
    DateTime smsDate,
  ) async {
    if (!SmartParser.isDebitExpenseSms(sms)) return null;
    final localParser = SmartParser();
    final local = await localParser.parse(sms, id, smsDate);
    if (local == null) return null;
    final confirmedAmount = localParser.extractDebitAmount(sms);
    if (confirmedAmount == null) return null;
    final cleanSms = sanitizeSms(sms);

    for (final provider in _providers) {
      if (provider.apiKey.isEmpty) continue;
      final result = await _tryProvider(
        provider,
        cleanSms,
        sms,
        id,
        smsDate,
        confirmedAmount,
      );
      if (result != null &&
          result.type == TransactionType.expense &&
          result.amount == local.amount) {
        debugPrint(
            '✅ AI parsed via ${provider.name}: ${result.merchant} ₹${result.amount}');
        return result;
      }
      debugPrint('⚠️ ${provider.name} failed — trying next…');
    }
    return null;
  }

  Future<TransactionModel?> _tryProvider(
    _ParseProvider provider,
    String cleanSms,
    String originalSms,
    String id,
    DateTime smsDate,
    double confirmedAmount,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(provider.url),
            headers: provider.headers,
            body: jsonEncode({
              'model': provider.model,
              'temperature': 0,
              'max_tokens': 200,
              'messages': [
                {
                  'role': 'system',
                  'content': _systemPrompt,
                },
                {
                  'role': 'user',
                  'content': _buildPrompt(cleanSms),
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 429) return null;
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>?;
      final choices = data?['choices'];
      if (choices == null || choices is! List || choices.isEmpty) return null;

      final text = (choices[0]['message']?['content'] as String? ?? '').trim();

      // Extract JSON object
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return null;

      final jsonString = text.substring(start, end + 1);
      final jsonData = jsonDecode(jsonString) as Map<String, dynamic>;

      // Validate JSON structure
      if (!jsonData.containsKey('amount') || !jsonData.containsKey('type')) {
        return null;
      }

      if (jsonData['type'] == 'not_financial') return null;

      return _toModel(
        jsonData,
        originalSms,
        id,
        smsDate,
        confirmedAmount: confirmedAmount,
      );
    } catch (e) {
      debugPrint('🔴 ${provider.name}: $e');
      return null;
    }
  }

  static const _systemPrompt =
      'You are parsing a confirmed debit/expense SMS. Return a transaction ONLY if the message describes money actually leaving the account. Preserve the locally identified debit amount exactly. '
      'You are a financial SMS parser for Indian bank and UPI messages. '
      'Return ONLY a single valid JSON object — no markdown, no explanation, no extra text. '
      'If the SMS is not a financial transaction, return exactly: {"type":"not_financial"}';

  String _buildPrompt(String sms) => '''
Parse this Indian bank/UPI SMS. Return ONLY this JSON:
{
  "amount": <number, no commas or symbols>,
  "type": "expense" | "income" | "not_financial",
  "merchant": "<merchant name>",
  "category": "<Food|Shopping|Fuel|Travel|Bills|Transfer|Cash|Entertainment|Health|Investment|Other>",
  "payment_method": "<UPI|NEFT|IMPS|RTGS|Credit Card|Debit Card|ATM|Net Banking|Wallet|SMS>",
  "bank": "<Bank name if present or null>",
  "account": "<Account ending digits or null>",
  "reference": "<UTR or Ref number or null>"
}

SMS: $sms
''';

  TransactionModel? _toModel(Map<String, dynamic> json, String originalSms,
      String id, DateTime smsDate,
      {required double confirmedAmount}) {
    double amount = 0;
    final rawAmt = json['amount'];
    if (rawAmt is num) {
      amount = rawAmt.toDouble();
    } else if (rawAmt is String) {
      amount =
          double.tryParse(rawAmt.replaceAll(',', '').replaceAll('₹', '')) ?? 0;
    }
    if (amount <= 0 ||
        amount != confirmedAmount ||
        (json['type'] as String?)?.toLowerCase() != 'expense' ||
        !SmartParser.isDebitExpenseSms(originalSms)) {
      return null;
    }

    String merchant = (json['merchant'] as String?)?.trim() ?? '';
    if (merchant.isEmpty || merchant.toLowerCase() == 'unknown') {
      merchant = 'SMS Transaction';
    }

    final typeStr = (json['type'] as String?)?.toLowerCase() ?? 'expense';
    final type =
        typeStr == 'income' ? TransactionType.income : TransactionType.expense;

    final validCategories = {
      'Food',
      'Shopping',
      'Fuel',
      'Travel',
      'Bills',
      'Transfer',
      'Cash',
      'Entertainment',
      'Health',
      'Investment',
      'Other',
    };
    String category = (json['category'] as String?)?.trim() ?? 'Other';
    if (!validCategories.contains(category)) category = 'Other';

    String paymentMethod = (json['payment_method'] as String?)?.trim() ?? 'SMS';
    String? bank = json['bank'] as String?;
    String? account = json['account'] as String?;
    String? reference = json['reference'] as String?;

    return TransactionModel(
      id: id,
      amount: amount.toInt(),
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: paymentMethod,
      date: smsDate,
      time:
          '${smsDate.hour.toString().padLeft(2, '0')}:${smsDate.minute.toString().padLeft(2, '0')}',
      originalSms: originalSms,
      isExcluded: false,
      bank: bank,
      account: account,
      reference: reference,
      source: 'SMS-AI',
      confidence: 0.9,
      needsReview: false,
    );
  }
}
