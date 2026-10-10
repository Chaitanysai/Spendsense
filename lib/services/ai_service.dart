import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/ai_chat_message.dart';
import '../models/transaction_model.dart';

/// Provider config — keys are resolved at runtime from AppConfig.
class _Provider {
  final String name;
  final String url;
  final String apiKey;
  final String model;
  final Map<String, String> Function(String key) _headerBuilder;

  _Provider({
    required this.name,
    required this.url,
    required this.apiKey,
    required this.model,
    required Map<String, String> Function(String key) headerBuilder,
  }) : _headerBuilder = headerBuilder;

  Map<String, String> get headers => _headerBuilder(apiKey);
}

class AIService {
  // 🔑 Keys are loaded from secure storage (priority) or .env/--dart-define (fallback).
  // Never hardcode keys here. See lib/config/app_config.dart.
  static Future<List<_Provider>> _getProviders() async {
    final groqKey = await AppConfig.getGroqKey();
    final cerebrasKey = await AppConfig.getCerebrasKey();
    final geminiKey = await AppConfig.getGeminiKey();
    final openRouterKey = await AppConfig.getOpenRouterKey();

    return [
      // 1️⃣  Groq — fastest, try first
      _Provider(
        name: 'Groq',
        url: 'https://api.groq.com/openai/v1/chat/completions',
        apiKey: groqKey,
        model: 'llama-3.3-70b-versatile',
        headerBuilder: (key) => {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
      ),

      // 2️⃣  Cerebras — fast and cost-effective
      _Provider(
        name: 'Cerebras',
        url: 'https://api.cerebras.ai/v1/chat/completions',
        apiKey: cerebrasKey,
        model: 'llama3.1-8b',
        headerBuilder: (key) => {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
      ),

      // 3️⃣  Gemini Flash — high quality, generous free tier
      _Provider(
        name: 'Gemini',
        url:
            'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
        apiKey: geminiKey,
        model: 'gemini-2.5-flash',
        headerBuilder: (key) => {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
      ),

      // 4️⃣  OpenRouter (free Llama model) — last resort fallback
      _Provider(
        name: 'OpenRouter',
        url: 'https://openrouter.ai/api/v1/chat/completions',
        apiKey: openRouterKey,
        model: 'meta-llama/llama-3.3-70b-instruct:free',
        headerBuilder: (key) => {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
          'HTTP-Referer': 'com.yourapp.spendsense',
        },
      ),
    ];
  }

  /// Tries each provider in order. Returns the first successful response.
  /// Falls back to the next provider on: timeout, HTTP error, or empty reply.
  Future<String> askAI(
    List<AIChatMessage> history,
    List<TransactionModel> txs,
  ) async {
    final result = await tryAskAI(history, txs);
    return result ??
        "I couldn't get an answer right now. "
            "Check your internet connection or try again shortly.";
  }

  Future<String?> tryAskAI(
    List<AIChatMessage> history,
    List<TransactionModel> txs,
  ) async {
    final promptMessages = _buildMessages(history, txs);
    final providers = await _getProviders();

    for (final provider in providers) {
      if (provider.apiKey.isEmpty) continue;
      final result = await _tryProvider(provider, promptMessages);
      if (result != null) {
        debugPrint('✅ AI answered via ${provider.name}');
        return result;
      }
      debugPrint('⚠️ ${provider.name} failed — trying next provider...');
    }

    return null;
  }

  /// Attempts one provider. Returns null on any failure so the chain continues.
  Future<String?> _tryProvider(
    _Provider provider,
    List<Map<String, String>> messages,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(provider.url),
            headers: provider.headers,
            body: jsonEncode({
              'model': provider.model,
              'max_tokens': 150,
              'temperature': 0,
              'messages': messages,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 429) {
        // Rate limited — skip to next provider immediately, no wait
        debugPrint('🔴 ${provider.name} rate limited (429)');
        return null;
      }

      if (response.statusCode != 200) {
        debugPrint('🔴 ${provider.name} HTTP ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>?;
      final choices = data?['choices'];

      if (choices == null || choices is! List || choices.isEmpty) return null;

      final content = choices[0]['message']?['content'] as String? ?? '';
      if (content.trim().isEmpty) return null;

      return content.trim();
    } catch (e) {
      debugPrint('🔴 ${provider.name} error: $e');
      return null; // triggers next provider in chain
    }
  }

  List<Map<String, String>> _buildMessages(
    List<AIChatMessage> history,
    List<TransactionModel> txs,
  ) {
    final now = DateTime.now();

    // Only send current month transactions to keep token usage minimal
    final monthTx = txs
        .where((t) =>
            t.date.month == now.month &&
            t.date.year == now.year &&
            !t.isExcluded)
        .take(40)
        .toList();

    final expenseTx =
        monthTx.where((t) => t.type == TransactionType.expense).toList();
    final incomeTx =
        monthTx.where((t) => t.type == TransactionType.income).toList();

    final summary = [
      if (expenseTx.isEmpty)
        'Expenses: none this month.'
      else
        'Expenses:\n${expenseTx.map((t) {
          return '- ${t.category}: ₹${t.amount.toStringAsFixed(0)}'
              ' at ${t.merchant} on ${t.date.day}/${t.date.month}';
        }).join('\n')}',
      if (incomeTx.isNotEmpty)
        'Income:\n${incomeTx.map((t) {
          return '- ₹${t.amount.toStringAsFixed(0)}'
              ' from ${t.merchant} on ${t.date.day}/${t.date.month}';
        }).join('\n')}',
    ].join('\n');

    return [
      {
        'role': 'system',
        'content':
            'You are SpendSense AI, a concise personal finance assistant '
                'for an Indian user. Answer using only the spending snapshot '
                'provided in this chat. Use ₹ for currency. If the user asks '
                'about something not present in the data, say that clearly.',
      },
      {
        'role': 'system',
        'content': 'Current month transaction snapshot:\n$summary',
      },
      ...history.map((message) => {
            'role': message.role,
            'content': message.content,
          }),
    ];
  }
}
