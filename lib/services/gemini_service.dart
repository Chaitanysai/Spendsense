import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/transaction_model.dart';

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
  // ─── 🔑 YOUR KEYS ─────────────────────────────────────────────────────────
  static const _groqKey = 'YOUR_GROQ_KEY';
  static const _geminiKey = 'YOUR_GEMINI_KEY';
  static const _openrouterKey = 'YOUR_OPENROUTER_KEY';
  // ──────────────────────────────────────────────────────────────────────────

  static final List<_ParseProvider> _providers = [
    _ParseProvider(
      name: 'Groq',
      url: 'https://api.groq.com/openai/v1/chat/completions',
      apiKey: _groqKey,
      model: 'llama-3.3-70b-versatile',
    ),
    _ParseProvider(
      name: 'Gemini',
      url:
          'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions',
      apiKey: _geminiKey,
      model: 'gemini-2.5-flash',
    ),
    _ParseProvider(
      name: 'OpenRouter',
      url: 'https://openrouter.ai/api/v1/chat/completions',
      apiKey: _openrouterKey,
      model: 'meta-llama/llama-3.3-70b-instruct:free',
    ),
  ];

  // ─── PUBLIC ────────────────────────────────────────────────────────────────

  /// Step 1: Quickly decide if this SMS is a financial transaction at all.
  /// Returns false for OTPs, promotional, delivery alerts, etc.
  /// This avoids wasting AI tokens on non-financial SMS.
  bool looksFinancial(String sms) {
    final t = sms.toLowerCase();
    // Must contain a currency signal
    final hasCurrency = t.contains('₹') ||
        t.contains('rs.') ||
        t.contains('rs ') ||
        t.contains('inr') ||
        RegExp(r'\d+\.\d{2}').hasMatch(t); // e.g. 1234.00

    if (!hasCurrency) return false;

    // Must contain at least one transaction keyword
    const keywords = [
      // Debit signals
      'debited', 'deducted', 'spent', 'paid', 'payment', 'purchase',
      'withdrawn', 'charged', 'debit', 'sent', 'transferred',
      // Credit signals
      'credited', 'received', 'deposited', 'refund', 'cashback',
      'credit', 'added',
      // Generic financial
      'transaction', 'a/c', 'acct', 'account', 'balance', 'avl bal',
      'available balance', 'upi', 'neft', 'imps', 'rtgs', 'atm',
    ];

    return keywords.any((k) => t.contains(k));
  }

  /// Parses one SMS through the 3-provider fallback chain.
  /// Returns null if all providers fail OR if SMS is not financial.
  Future<TransactionModel?> parseSms(
    String sms,
    String id,
    DateTime smsDate,
  ) async {
    // Gate: skip non-financial SMS cheaply — no API call needed
    if (!looksFinancial(sms)) {
      print(
          '⏭️ Skipping non-financial SMS: ${sms.substring(0, sms.length.clamp(0, 60))}');
      return null;
    }

    for (final provider in _providers) {
      final result = await _tryProvider(provider, sms, id, smsDate);
      if (result != null) {
        print(
            '✅ Parsed via ${provider.name}: ${result.merchant} ₹${result.amount} [${result.category}]');
        return result;
      }
      print('⚠️ ${provider.name} failed — trying next…');
    }
    return null;
  }

  // ─── PRIVATE ───────────────────────────────────────────────────────────────

  Future<TransactionModel?> _tryProvider(
    _ParseProvider provider,
    String sms,
    String id,
    DateTime smsDate,
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
                  'content': _buildPrompt(sms),
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

      // Handle explicit "not_financial" signal from the model
      if (text.contains('"not_financial"') || text.contains('not_financial')) {
        return null;
      }

      // Extract the JSON object from the response
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return null;

      final jsonData =
          jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;

      // Skip if model signalled not financial via the json field
      if (jsonData['type'] == 'not_financial') return null;

      return _toModel(jsonData, sms, id, smsDate);
    } catch (e) {
      print('🔴 ${provider.name}: $e');
      return null;
    }
  }

  // ─── PROMPTS ───────────────────────────────────────────────────────────────

  /// System prompt is sent once per call but kept concise to save tokens.
  static const _systemPrompt =
      'You are a financial SMS parser for Indian bank and UPI messages. '
      'Return ONLY a single valid JSON object — no markdown, no explanation, no extra text. '
      'If the SMS is not a financial transaction, return exactly: {"type":"not_financial"}';

  String _buildPrompt(String sms) => '''
Parse this Indian bank/UPI SMS. Return ONLY this JSON:
{
  "amount": <number, no commas or symbols>,
  "type": "expense" | "income" | "not_financial",
  "merchant": "<see rules below>",
  "category": "<see list below>",
  "payment_method": "<see list below>"
}

TYPE RULES — read the ENTIRE message, not just the first word:
- "expense"  → debited / deducted / spent / paid / payment / purchase / withdrawn / charged / sent / dr
- "income"   → credited / received / deposited / refund / cashback / reversed / cr
- "not_financial" → OTP / promo / delivery update / no currency amount found

MERCHANT RULES (extract the real payee name, never return "Unknown"):
- UPI VPA:      "zomato@icici" → "Zomato", "q836271234@ybl" → use beneficiary name if present
- P2P transfer: use the recipient name from "to <Name>" or "beneficiary <Name>"
- POS/card:     use the merchant name after "at" (e.g. "at HDFC Bank ATM" → "HDFC ATM")
- NEFT/IMPS:    use the beneficiary account name
- If truly unknown: use the bank name + transaction type (e.g. "SBI ATM Withdrawal")

CATEGORY (pick exactly one):
Food | Shopping | Fuel | Travel | Bills | Transfer | Cash | Entertainment | Health | Investment | Other

CATEGORY HINTS:
- Food:          Swiggy, Zomato, Blinkit, BigBasket, restaurant, cafe, grocery
- Shopping:      Amazon, Flipkart, Myntra, Ajio, Nykaa, mall, retail
- Fuel:          HPCL, BPCL, IOCL, petrol, diesel, fuel pump
- Travel:        Uber, Ola, Rapido, IRCTC, MakeMyTrip, flight, train, bus, hotel
- Bills:         Airtel, Jio, electricity, water, gas, DTH, recharge, insurance, EMI
- Transfer:      UPI P2P, NEFT, IMPS, RTGS, wallet top-up, fund transfer
- Cash:          ATM withdrawal, cash advance
- Entertainment: Netflix, Hotstar, Spotify, BookMyShow, cinema, OTT
- Health:        Apollo, Practo, hospital, pharmacy, medical, lab
- Investment:    mutual fund, SIP, stock, share, demat, broker

PAYMENT_METHOD (pick one):
UPI | NEFT | IMPS | RTGS | Credit Card | Debit Card | ATM | Net Banking | Wallet | SMS

SMS: $sms
''';

  // ─── MODEL CONVERSION ──────────────────────────────────────────────────────

  TransactionModel? _toModel(
    Map<String, dynamic> json,
    String sms,
    String id,
    DateTime smsDate,
  ) {
    // ── Amount ────────────────────────────────────────────────────────────
    double amount = 0;
    final rawAmt = json['amount'];
    if (rawAmt is num) {
      amount = rawAmt.toDouble();
    } else if (rawAmt is String) {
      amount =
          double.tryParse(rawAmt.replaceAll(',', '').replaceAll('₹', '')) ?? 0;
    }
    // If AI returned 0, try extracting from SMS directly as last resort
    if (amount <= 0) amount = _extractAmountFallback(sms) ?? 0;
    if (amount <= 0) return null;

    // ── Merchant ──────────────────────────────────────────────────────────
    String merchant = (json['merchant'] as String?)?.trim() ?? '';
    if (merchant.isEmpty ||
        merchant.toLowerCase() == 'unknown' ||
        merchant.toLowerCase() == 'n/a') {
      merchant = _extractMerchantFallback(sms);
    }

    // ── Type ──────────────────────────────────────────────────────────────
    final typeStr = (json['type'] as String?)?.toLowerCase() ?? 'expense';
    final type =
        typeStr == 'income' ? TransactionType.income : TransactionType.expense;

    // ── Category ──────────────────────────────────────────────────────────
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

    // ── Payment method ────────────────────────────────────────────────────
    String paymentMethod = (json['payment_method'] as String?)?.trim() ?? 'SMS';

    return TransactionModel(
      id: id,
      amount: amount,
      type: type,
      merchant: merchant,
      category: category,
      paymentMethod: paymentMethod,
      date: smsDate,
      time: '${smsDate.hour.toString().padLeft(2, '0')}'
          ':${smsDate.minute.toString().padLeft(2, '0')}',
      originalSms: sms,
      isExcluded: false,
    );
  }

  // ─── FALLBACK HELPERS ──────────────────────────────────────────────────────

  double? _extractAmountFallback(String sms) {
    final patterns = [
      RegExp(r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false),
      RegExp(r'([\d,]+(?:\.\d{1,2})?)\s*(?:₹|rs\.?|inr)', caseSensitive: false),
      RegExp(r'amount\s+(?:of\s+)?(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(sms);
      if (m != null) {
        final val = double.tryParse(m.group(1)?.replaceAll(',', '') ?? '');
        if (val != null && val > 0) return val;
      }
    }
    return null;
  }

  String _extractMerchantFallback(String sms) {
    // UPI VPA
    final vpa = RegExp(
      r'(?:to|paid\s+to)\s+([a-z0-9._-]+)@([a-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(sms);
    if (vpa != null && (vpa.group(1)?.length ?? 0) > 2) {
      return _cap(vpa.group(1)!);
    }

    // "at <Merchant>" — card/POS
    final at = RegExp(
      r'\bat\s+([A-Z][A-Za-z0-9&\s]{2,25}?)(?:\s+on|\s+for|[,.]|$)',
    ).firstMatch(sms);
    if (at != null) {
      final n = at.group(1)?.trim() ?? '';
      if (n.length > 2) return n;
    }

    // "to <Name>" — P2P / NEFT
    final to = RegExp(
      r'\bto\s+([A-Z][A-Za-z\s]{2,25}?)(?:\s+(?:via|on|for|using)|[,.]|$)',
    ).firstMatch(sms);
    if (to != null) {
      final n = to.group(1)?.trim() ?? '';
      if (n.length > 2) return n;
    }

    return 'SMS Transaction';
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
}
