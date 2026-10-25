import 'package:flutter/foundation.dart';
import '../models/transaction_model.dart';
import 'bill_classifier.dart';
import 'sms_content_policy.dart';
import '../utils/bank_recognizer.dart';
import '../utils/money_parser.dart';
import 'package:intl/intl.dart';

/// SpendSense 2.0 Enhanced SmartParser
/// Performs local regex extraction of amount, type, merchant, category,
/// payment method, bank, account, reference, and computes a real confidence score.
class SmartParser {
  static const _negativePatterns = <String>[
    'credited',
    'credit',
    'received',
    'deposited',
    'salary',
    'cashback',
    'refund',
    'refunded',
    'reversal',
    'reversed',
    'interest credited',
    'amount received',
    'money received',
  ];
  static const _securityPatterns = <String>[
    'otp',
    'one time password',
    'verification code',
    'verification',
    'pin',
    'cvv',
    'login code',
    'authentication code',
    'do not share',
    'valid for',
  ];
  static const _nonTransactionPatterns = <String>[
    'not debited',
    'not deducted',
    'declined',
    'failed',
    'unsuccessful',
    'could not be processed',
    'unable to process',
    'pending',
    'scheduled',
  ];
  static const _boundaries = <String>[
    'txn id',
    'transaction id',
    'ref no',
    'reference',
    'ref',
    'utr',
    'upi ref',
    'imps ref',
    'available balance',
    'available bal',
    'closing balance',
    'current balance',
    'balance',
    'bal:',
    'bal ',
    'call ',
    'not you?',
    'for help',
    'customer care',
  ];

  /// The SMS must describe money leaving the account. This check deliberately
  /// runs before amount extraction and is also used to gate AI parsing.
  static bool isDebitExpenseSms(String sms) {
    final lower = sms.toLowerCase();
    if (_negativePatterns.any(lower.contains) ||
        _securityPatterns.any(lower.contains) ||
        _nonTransactionPatterns.any(lower.contains)) {
      return false;
    }
    if (RegExp(r'\b(?:offer|promo(?:tional)?|limited time|cashback)\b',
            caseSensitive: false)
        .hasMatch(lower)) {
      return false;
    }
    return _hasDebitSignal(sms);
  }

  static String debitSmsRejectionReason(String sms) {
    final lower = sms.toLowerCase();
    if (_negativePatterns.any(lower.contains)) return 'CREDIT';
    if (_securityPatterns.any(lower.contains)) return 'OTP_SECURITY';
    if (_nonTransactionPatterns.any(lower.contains)) return 'NOT_COMPLETED';
    if (RegExp(r'\b(?:offer|promo(?:tional)?|limited time|cashback)\b')
        .hasMatch(lower)) {
      return 'PROMO';
    }
    if (RegExp(r'\b(?:balance|bal|available bal)\b').hasMatch(lower) &&
        !_hasDebitSignal(sms)) {
      return 'BALANCE_ONLY';
    }
    return 'UNKNOWN';
  }

  static bool _hasDebitSignal(String text) {
    final lower = text.toLowerCase();
    return RegExp(
          r'\b(?:debited|debit|deducted|deduction|spent|paid|purchase|withdrawn|withdrawal|charged)\b|'
          r'\b(?:a/c|account)\s+(?:has\s+been\s+)?debited\b|'
          r'\b(?:sent\s+(?:to|via\s+upi)|transferred\s+to|transferred)\b',
          caseSensitive: false,
        ).hasMatch(lower) ||
        RegExp(r'\bDR\b').hasMatch(text);
  }

  /// Returns null if the SMS does not look like a financial transaction.
  /// Otherwise returns a TransactionModel with confidence scoring.
  Future<TransactionModel?> parse(
    String smsText,
    String smsId,
    DateTime smsDate,
  ) async {
    if (!isDebitExpenseSms(smsText)) {
      debugPrint(
        'SMS FILTER: REJECT reason=${debitSmsRejectionReason(smsText)}',
      );
      return null;
    }

    final amountMinor = _extractAmountMinor(smsText);
    if (amountMinor == null || amountMinor <= 0) {
      debugPrint('SMS FILTER: REJECT reason=NO_CONTEXTUAL_DEBIT_AMOUNT');
      return null;
    }

    final merchant = detectMerchant(smsText);
    final category = detectCategory(smsText, merchant);
    final paymentMethod = _detectPaymentMethod(smsText.toLowerCase());
    final bank = _detectBank(smsText);
    final account = _extractAccount(smsText);
    final reference = _extractReference(smsText);
    // Persist only the non-sensitive classification hint before the raw body
    // is discarded. The classifier needs the message wording to distinguish,
    // for example, a broadband bill from a generic bank debit and a prepaid
    // recharge from a postpaid bill.
    final billSignal = const BillClassifier().classifyText(
      smsText,
      merchant: merchant,
      category: category,
      amountMinor: amountMinor,
      reference: reference,
    );

    // Compute confidence score (0.0 to 1.0)
    double confidence = 0.7; // explicit debit + contextual amount
    if (merchant != 'Bank Debit') confidence += 0.1;
    if (paymentMethod != 'Other') confidence += 0.05;
    if (bank != null) confidence += 0.1;
    if (reference != null) confidence += 0.05;
    if (confidence > 1.0) confidence = 1.0;

    final bool needsReview = confidence < 0.8;

    final result = TransactionModel(
      id: smsId,
      amountMinor: amountMinor,
      type: TransactionType.expense,
      merchant: merchant,
      category: category,
      paymentMethod: paymentMethod,
      date: smsDate,
      time: DateFormat('HH:mm').format(smsDate),
      // Reduce-only policy: a new record no longer stores the raw bank SMS.
      // See SmsContentPolicy — the single, reversible switch.
      originalSms: SmsContentPolicy.retainedBody(smsText) ?? '',
      isExcluded: false,
      bank: bank,
      account: account,
      reference: reference,
      source: 'SMS-Parser',
      confidence: confidence,
      needsReview: needsReview,
      billKindHint: billSignal.kind.name,
      billReminderHint: billSignal.reminderOnly,
    );
    // Acceptance is logged WITHOUT the parsed values: the amount, merchant,
    // bank and reference are financial data and must not reach the device log
    // (only the confidence band is safe to emit).
    debugPrint(
        'SMS FILTER: ACCEPT reason=DEBIT confidence=${confidence.toStringAsFixed(2)}');
    return result;
  }

  /// Exposes the same contextual amount check for validating AI responses.
  int? extractDebitAmountMinor(String sms) => _extractAmountMinor(sms);

  // ─── TRANSACTION TYPE ──────────────────────────────────────────────────────

  int? _extractAmountMinor(String sms) {
    final lower = sms.toLowerCase();
    var transactionEnd = sms.length;
    for (final boundary in _boundaries) {
      final index = lower.indexOf(boundary);
      if (index >= 0 && index < transactionEnd) transactionEnd = index;
    }
    final prefix = lower.substring(0, transactionEnd);
    final rupee = String.fromCharCode(0x20B9);
    final currencyAmount = RegExp(
      '(?:$rupee|\\b(?:rs\\.?|inr\\.?)\\s*)([\\d,]+(?:\\.\\d{1,2})?)',
      caseSensitive: false,
    );
    for (final match in currencyAmount.allMatches(prefix)) {
      final start = match.start;
      final end = match.end;
      final leftContext = lower.substring((start - 100).clamp(0, start), start);
      final rightContext =
          lower.substring(end, (end + 45).clamp(end, transactionEnd));
      final eventBefore = RegExp(
            r'\b(?:debited|debit|deducted|deduction|spent|paid|purchase|withdrawn|withdrawal|charged)\b|'
            r'\b(?:sent\s+(?:to|via\s+upi)|transferred(?:\s+to)?)\b',
          ).hasMatch(leftContext) ||
          RegExp(r'\bDR\b').hasMatch(sms.substring(
            (start - 100).clamp(0, start),
            start,
          ));
      final eventAfter = RegExp(
            r'^\s*(?:has\s+been\s+)?(?:debited|debit|deducted|spent|paid|charged|withdrawn)\b|'
            r'^\s*(?:sent\s+(?:to|via\s+upi)|transferred(?:\s+to)?)\b',
          ).hasMatch(rightContext) ||
          RegExp(r'^\s*DR\b').hasMatch(
              sms.substring(end, (end + 45).clamp(end, transactionEnd)));
      if (!eventBefore && !eventAfter) continue;
      final rawAmount = match.group(1)!;
      if (rawAmount.replaceAll(',', '').length > 12) continue;
      try {
        final amountMinor = parseRupeesToPaise(rawAmount);
        if (amountMinor > 0) return amountMinor;
      } on MoneyParseException {
        continue;
      }
    }
    return null;
  }

  String _detectPaymentMethod(String lower) {
    if (lower.contains('upi')) {
      return 'UPI';
    }
    if (lower.contains('neft')) {
      return 'NEFT';
    }
    if (lower.contains('imps')) {
      return 'IMPS';
    }
    if (lower.contains('rtgs')) {
      return 'RTGS';
    }
    if (lower.contains('credit card') || lower.contains('cc ')) {
      return 'Credit Card';
    }
    if (lower.contains('debit card')) {
      return 'Debit Card';
    }
    if (lower.contains('atm')) {
      return 'ATM';
    }
    if (lower.contains('net banking') || lower.contains('netbanking')) {
      return 'Net Banking';
    }
    if (lower.contains('wallet') || lower.contains('paytm wallet')) {
      return 'Wallet';
    }
    return 'Other';
  }

  // ─── BANK DETECTION ────────────────────────────────────────────────────────

  /// Delegates to [BankRecognizer] so the deterministic parser and the AI path
  /// share one alias table and one "is this really a bank" rule. Returns null
  /// when no bank is explicitly named, or when the only token present is a
  /// rail, wallet or payment-app name.
  String? _detectBank(String sms) => BankRecognizer.detectFromSms(sms);

  // ─── ACCOUNT EXTRACTION ────────────────────────────────────────────────────

  String? _extractAccount(String sms) {
    final match = RegExp(
      r'(?:a\/c|acct|account|card)\s*(?:no\.?|ending)?\s*([x\*\d]{4,16})',
      caseSensitive: false,
    ).firstMatch(sms);
    if (match != null) {
      final digits = match.group(1)!.replaceAll(RegExp(r'\D'), '');
      if (digits.length >= 4) return digits.substring(digits.length - 4);
    }
    return null;
  }

  // ─── REFERENCE / UTR EXTRACTION ───────────────────────────────────────────

  String? _extractReference(String sms) {
    final match = RegExp(
      r'(?:upi\s*ref|imps\s*ref|ref(?:erence)?|utr|txn(?:\s*id)?|transaction\s*id)\s*(?:no\.?|[:#])?\s*([a-z0-9]{6,20})',
      caseSensitive: false,
    ).firstMatch(sms);
    if (match != null) {
      return match.group(1);
    }
    return null;
  }

  // ─── MERCHANT DETECTION ────────────────────────────────────────────────────

  String detectMerchant(String sms) {
    final lower = sms.toLowerCase();

    final towardsMatch = RegExp(
      '\\btowards\\s+(.+?)\\s+for\\s+(?:${String.fromCharCode(0x20B9)}|rs\\.?|inr\\.?|the amount)',
      caseSensitive: false,
    ).firstMatch(sms);
    if (towardsMatch != null) {
      final value =
          towardsMatch.group(1)!.trim().replaceAll(RegExp(r'[.,;]+$'), '');
      if (value.isNotEmpty && !value.contains('@')) {
        return _normalizeMerchantName(value);
      }
    }
    if (lower.contains('airtel payments bank')) return 'Bank Debit';

    const brands = {
      'swiggy': 'Swiggy',
      'zomato': 'Zomato',
      'dunzo': 'Dunzo',
      'bigbasket': 'BigBasket',
      'blinkit': 'Blinkit',
      'zepto': 'Zepto',
      'dominos': "Domino's",
      'mcdonald': "McDonald's",
      'kfc': 'KFC',
      'subway': 'Subway',
      'starbucks': 'Starbucks',
      'amazon': 'Amazon',
      'flipkart': 'Flipkart',
      'myntra': 'Myntra',
      'ajio': 'Ajio',
      'nykaa': 'Nykaa',
      'meesho': 'Meesho',
      'snapdeal': 'Snapdeal',
      'tatacliq': 'Tata CLiQ',
      'uber': 'Uber',
      'ola': 'Ola',
      'rapido': 'Rapido',
      'makemytrip': 'MakeMyTrip',
      'irctc': 'IRCTC',
      'redbus': 'RedBus',
      'yatra': 'Yatra',
      'oyo': 'OYO',
      'airbnb': 'Airbnb',
      'hpcl': 'HPCL',
      'bpcl': 'BPCL',
      'iocl': 'IOCL',
      'petrol': 'Fuel Station',
      'fuel': 'Fuel Station',
      'reliance fuel': 'Reliance Fuel',
      'airtel': 'Airtel',
      'jio': 'Jio',
      'bsnl': 'BSNL',
      'vi ': 'Vi',
      'tata power': 'Tata Power',
      'bescom': 'BESCOM',
      'msedcl': 'MSEDCL',
      'mahanagar gas': 'Mahanagar Gas',
      'indraprastha gas': 'IGL',
      'dth': 'DTH',
      'apollo': 'Apollo',
      'practo': 'Practo',
      'netmeds': 'Netmeds',
      'pharmeasy': 'PharmEasy',
      '1mg': '1mg',
      'medplus': 'MedPlus',
      'netflix': 'Netflix',
      'hotstar': 'Hotstar',
      'prime video': 'Prime Video',
      'spotify': 'Spotify',
      'youtube premium': 'YouTube Premium',
      'bookmyshow': 'BookMyShow',
      'pvr': 'PVR',
      'inox': 'INOX',
      'phonepe': 'PhonePe',
      'gpay': 'Google Pay',
      'paytm': 'Paytm',
      'cred': 'CRED',
      'slice': 'Slice',
    };

    for (final kv in brands.entries) {
      if (lower.contains(kv.key)) {
        return kv.value;
      }
    }

    final vpaMatch = RegExp(
      r'(?:to|paid\s+to)\s+([a-z0-9._-]+)@([a-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(sms);
    if (vpaMatch != null) {
      final handle = vpaMatch.group(1) ?? '';
      if (handle.length > 2) {
        return _capitalize(handle);
      }
    }

    final upiRecipientMatch = RegExp(
      r'(?:sent|paid|transferred)\s+via\s+upi\s+to\s+([a-z0-9&._\-\s]{2,40}?)(?:\s+(?:ref|utr|on|from|a/c|acct|avl|bal)|[,.]|$)',
      caseSensitive: false,
    ).firstMatch(sms);
    if (upiRecipientMatch != null) {
      final name = upiRecipientMatch.group(1)?.trim() ?? '';
      if (name.length > 2) {
        return _normalizeMerchantName(name);
      }
    }

    final atMatch = RegExp(
      r'\bat\s+([A-Z][A-Za-z0-9&\s]{2,25}?)(?:\s+on|\s+for|[,.]|$)',
    ).firstMatch(sms);
    if (atMatch != null) {
      final name = atMatch.group(1)?.trim() ?? '';
      if (name.length > 2) {
        return name;
      }
    }

    final toMatch = RegExp(
      r'\bto\s+([a-z][a-z0-9&.\-\s]{2,40}?)(?:\s+(?:via|on|for|using|ref|utr|from|a/c|acct|avl|bal)|[,.]|$)',
      caseSensitive: false,
    ).firstMatch(sms);
    if (toMatch != null) {
      final name = toMatch.group(1)?.trim() ?? '';
      if (name.length > 2) {
        return _normalizeMerchantName(name);
      }
    }

    return 'Bank Debit';
  }

  // ─── CATEGORY DETECTION ────────────────────────────────────────────────────

  String detectCategory(String sms, [String? resolvedMerchant]) {
    final lower = sms.toLowerCase();
    final merch = (resolvedMerchant ?? '').toLowerCase();

    if (_anyOf(merch, [
      'swiggy',
      'zomato',
      'bigbasket',
      'blinkit',
      'zepto',
      'dunzo',
      'domino',
      'mcdonald',
      'kfc',
      'subway',
      'starbucks',
      'restaurant',
      'cafe',
      'dhaba',
    ])) {
      return 'Food';
    }
    if (_anyOf(lower, [
      'restaurant',
      'cafe',
      'dhaba',
      'food',
      'meal',
      'dinner',
      'lunch',
      'breakfast',
      'grocery',
      'groceries',
      'kitchen',
      'pizza',
      'burger',
      'biryani',
    ])) {
      return 'Food';
    }

    if (_anyOf(merch, [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'nykaa',
      'meesho',
      'snapdeal',
      'tatacliq',
    ])) {
      return 'Shopping';
    }
    if (_anyOf(lower, [
      'shopping',
      'mart',
      'store',
      'mall',
      'retail',
      'purchase',
      'order',
      'apparel',
      'cloth',
    ])) {
      return 'Shopping';
    }

    if (_anyOf(merch, [
      'uber',
      'ola',
      'rapido',
      'makemytrip',
      'irctc',
      'redbus',
      'yatra',
      'oyo',
      'airbnb',
    ])) {
      return 'Travel';
    }
    if (_anyOf(lower, [
      'cab',
      'taxi',
      'auto',
      'ride',
      'flight',
      'train',
      'bus',
      'hotel',
      'booking',
      'travel',
    ])) {
      return 'Travel';
    }

    if (_anyOf(
        merch, ['hpcl', 'bpcl', 'iocl', 'fuel station', 'reliance fuel'])) {
      return 'Fuel';
    }
    if (_anyOf(lower, ['petrol', 'diesel', 'fuel', 'gas station', 'pump'])) {
      return 'Fuel';
    }

    if (_anyOf(merch, [
      'airtel',
      'jio',
      'bsnl',
      'vi',
      'tata power',
      'bescom',
      'msedcl',
      'mahanagar gas',
      'igl',
      'dth',
    ])) {
      return 'Bills';
    }
    if (_anyOf(lower, [
      'recharge',
      'bill',
      'utility',
      'electricity',
      'water',
      'gas',
      'broadband',
      'internet',
      'postpaid',
      'prepaid',
      'emi',
      'insurance',
      'premium',
    ])) {
      return 'Bills';
    }

    if (_anyOf(merch,
        ['apollo', 'practo', 'netmeds', 'pharmeasy', '1mg', 'medplus'])) {
      return 'Health';
    }
    if (_anyOf(lower, [
      'hospital',
      'clinic',
      'pharmacy',
      'medicine',
      'medical',
      'doctor',
      'health',
      'lab',
      'diagnostic',
    ])) {
      return 'Health';
    }

    if (_anyOf(merch, [
      'netflix',
      'hotstar',
      'prime video',
      'spotify',
      'youtube premium',
      'bookmyshow',
      'pvr',
      'inox',
    ])) {
      return 'Entertainment';
    }
    if (_anyOf(lower, [
      'subscription',
      'ott',
      'movie',
      'cinema',
      'ticket',
      'entertainment',
      'gaming'
    ])) {
      return 'Entertainment';
    }

    if (_anyOf(lower, ['atm', 'cash withdrawal', 'withdrawn'])) {
      return 'Cash';
    }

    if (_anyOf(lower, [
      'upi',
      'neft',
      'imps',
      'rtgs',
      'fund transfer',
      'transferred to',
      'sent to'
    ])) {
      return 'Transfer';
    }

    return 'Other';
  }

  bool _anyOf(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  String _normalizeMerchantName(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return cleaned;
    if (cleaned == cleaned.toUpperCase() &&
        RegExp(r'[A-Z]').hasMatch(cleaned)) {
      return cleaned;
    }
    return cleaned.split(' ').where((part) => part.isNotEmpty).map((part) {
      final lower = part.toLowerCase();
      return lower[0].toUpperCase() + lower.substring(1);
    }).join(' ');
  }
}
