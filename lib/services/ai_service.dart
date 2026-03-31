import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/transaction_model.dart';

/// Provider config — swap keys here only
class _Provider {
  final String name;
  final String url;
  final String apiKey;
  final String model;
  final Map<String, String> headers;

  const _Provider({
    required this.name,
    required this.url,
    required this.apiKey,
    required this.model,
    required this.headers,
  });
}

class AIService {
  // Configure provider keys locally before enabling network calls.
  static const _groqKey = "YOUR_GROQ_KEY";
  static const _geminiKey = "YOUR_GEMINI_KEY";
  static const _openrouterKey = "YOUR_OPENROUTER_KEY";

  static final List<_Provider> _providers = [
    // 1️⃣  Groq — fastest, try first
    _Provider(
      name: "Groq",
      url: "https://api.groq.com/openai/v1/chat/completions",
      apiKey: _groqKey,
      model: "llama-3.3-70b-versatile",
      headers: {
        "Authorization": "Bearer $_groqKey",
        "Content-Type": "application/json",
      },
    ),

    // 2️⃣  Gemini Flash — high quality, generous free tier
    _Provider(
      name: "Gemini",
      url:
          "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
      apiKey: _geminiKey,
      model: "gemini-2.5-flash",
      headers: {
        "Authorization": "Bearer $_geminiKey",
        "Content-Type": "application/json",
      },
    ),

    // 3️⃣  OpenRouter (free Llama model) — last resort fallback
    _Provider(
      name: "OpenRouter",
      url: "https://openrouter.ai/api/v1/chat/completions",
      apiKey: _openrouterKey,
      model: "meta-llama/llama-3.3-70b-instruct:free",
      headers: {
        "Authorization": "Bearer $_openrouterKey",
        "Content-Type": "application/json",
        "HTTP-Referer": "com.yourapp.spendsense", // your app package name
      },
    ),
  ];

  /// Tries each provider in order. Returns the first successful response.
  /// Falls back to the next provider on: timeout, HTTP error, or empty reply.
  Future<String> askAI(String query, List<TransactionModel> txs) async {
    final prompt = _buildPrompt(query, txs);

    for (final provider in _providers) {
      final result = await _tryProvider(provider, prompt);
      if (result != null) {
        print("✅ AI answered via ${provider.name}");
        return result;
      }
      print("⚠️ ${provider.name} failed — trying next provider...");
    }

    // All 3 providers exhausted
    return "I couldn't get an answer right now. "
        "Check your internet connection or try again shortly.";
  }

  /// Attempts one provider. Returns null on any failure so the chain continues.
  Future<String?> _tryProvider(_Provider provider, String prompt) async {
    try {
      final response = await http
          .post(
            Uri.parse(provider.url),
            headers: provider.headers,
            body: jsonEncode({
              "model": provider.model,
              "max_tokens": 150,
              "temperature": 0,
              "messages": [
                {"role": "user", "content": prompt}
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 429) {
        // Rate limited — skip to next provider immediately, no wait
        print("🔴 ${provider.name} rate limited (429)");
        return null;
      }

      if (response.statusCode != 200) {
        print("🔴 ${provider.name} HTTP ${response.statusCode}");
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>?;
      final choices = data?['choices'];

      if (choices == null || choices is! List || choices.isEmpty) return null;

      final content = choices[0]['message']?['content'] as String? ?? "";
      if (content.trim().isEmpty) return null;

      return content.trim();
    } catch (e) {
      print("🔴 ${provider.name} error: $e");
      return null; // triggers next provider in chain
    }
  }

  String _buildPrompt(String query, List<TransactionModel> txs) {
    final now = DateTime.now();

    // Only send current month transactions to keep token usage minimal
    final monthTx = txs
        .where((t) =>
            t.date.month == now.month &&
            t.date.year == now.year &&
            !t.isExcluded)
        .take(40)
        .toList();

    final summary = monthTx.isEmpty
        ? "No transactions this month."
        : monthTx.map((t) {
            return "• ${t.category}: ₹${t.amount.toStringAsFixed(0)}"
                " at ${t.merchant} on ${t.date.day}/${t.date.month}";
          }).join("\n");

    return """
You are a personal finance assistant for an Indian user.
Answer the question in 1-2 sentences using ONLY the data below.
Use ₹ for currency. Be direct and specific.

Question: $query

This month's transactions:
$summary
""";
  }
}
