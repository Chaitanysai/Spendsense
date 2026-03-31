import '../models/transaction_model.dart';
import 'package:intl/intl.dart';

/// SmartParser — local regex-based fallback parser.
/// Used when AI providers are unavailable or rate-limited.
/// For best results the AI path (GeminiService) is preferred;
/// this parser handles the long tail of unrecognised SMS patterns.
class SmartParser {
  // ─── PUBLIC API ────────────────────────────────────────────────────────────

  /// Returns null if the SMS does not look like a debit/credit transaction.
  Future<TransactionModel?> parse(
    String smsText,
    String smsId,
    DateTime smsDate,
  ) async {
    final text = smsText.toLowerCase();

    // ── Determine transaction type ──────────────────────────────────────────
    final bool isExpense = _isExpense(text);
    final bool isIncome = _isIncome(text);

    // Skip entirely if it doesn't look financial
    if (!isExpense && !isIncome) return null;

    // ── Amount ──────────────────────────────────────────────────────────────
    final amount = _extractAmount(smsText);
    if (amount == null || amount <= 0) return null;

    // ── Merchant & Category ─────────────────────────────────────────────────
    final merchant = detectMerchant(smsText);
    final category = detectCategory(smsText, merchant);

    return TransactionModel(
      id: smsId,
      amount: amount,
      type: isIncome ? TransactionType.income : TransactionType.expense,
      merchant: merchant,
      category: category,
      paymentMethod: _detectPaymentMethod(text),
      date: smsDate,
      time: DateFormat('HH:mm').format(smsDate),
      originalSms: smsText,
      isExcluded: false,
    );
  }

  // ─── TRANSACTION TYPE ──────────────────────────────────────────────────────

  bool _isExpense(String lower) =>
      lower.contains('debited') ||
      lower.contains('deducted') ||
      lower.contains('spent') ||
      lower.contains('paid') ||
      lower.contains('payment') ||
      lower.contains('purchase') ||
      lower.contains('withdrawn') ||
      lower.contains('charged');

  bool _isIncome(String lower) =>
      lower.contains('credited') ||
      lower.contains('received') ||
      lower.contains('deposited') ||
      lower.contains('refund') ||
      lower.contains('cashback');

  // ─── AMOUNT ────────────────────────────────────────────────────────────────

  double? _extractAmount(String sms) {
    // Matches: ₹1,234.56 | Rs.1234 | INR 1234 | Rs 1,234
    final patterns = [
      RegExp(r'(?:₹|rs\.?|inr)\s*([\d,]+(?:\.\d{1,2})?)', caseSensitive: false),
      RegExp(r'([\d,]+(?:\.\d{1,2})?)\s*(?:₹|rs\.?|inr)', caseSensitive: false),
      // "amount of 1234"
      RegExp(r'amount\s+(?:of\s+)?(?:₹|rs\.?|inr)?\s*([\d,]+(?:\.\d{1,2})?)',
          caseSensitive: false),
    ];

    for (final re in patterns) {
      final m = re.firstMatch(sms);
      if (m != null) {
        final raw = m.group(1)?.replaceAll(',', '') ?? '';
        final val = double.tryParse(raw);
        if (val != null && val > 0) return val;
      }
    }
    return null;
  }

  // ─── PAYMENT METHOD ────────────────────────────────────────────────────────

  String _detectPaymentMethod(String lower) {
    if (lower.contains('upi')) return 'UPI';
    if (lower.contains('neft')) return 'NEFT';
    if (lower.contains('imps')) return 'IMPS';
    if (lower.contains('rtgs')) return 'RTGS';
    if (lower.contains('credit card') || lower.contains('cc '))
      return 'Credit Card';
    if (lower.contains('debit card')) return 'Debit Card';
    if (lower.contains('atm')) return 'ATM';
    if (lower.contains('net banking') || lower.contains('netbanking'))
      return 'Net Banking';
    return 'SMS';
  }

  // ─── MERCHANT DETECTION ────────────────────────────────────────────────────

  /// Priority order:
  /// 1. Known brand keyword match
  /// 2. UPI VPA extraction  (e.g. "zomato@icici" → "Zomato")
  /// 3. "at <Merchant>" pattern
  /// 4. "to <Merchant>" pattern
  /// 5. Generic label
  String detectMerchant(String sms) {
    final lower = sms.toLowerCase();

    // 1. Known brands — check these first so we always return a real name
    const brands = {
      // Food & Beverage
      'swiggy': 'Swiggy', 'zomato': 'Zomato', 'dunzo': 'Dunzo',
      'bigbasket': 'BigBasket', 'blinkit': 'Blinkit', 'zepto': 'Zepto',
      'dominos': "Domino's", 'mcdonald': "McDonald's", 'kfc': 'KFC',
      'subway': 'Subway', 'starbucks': 'Starbucks',
      // Shopping & E-commerce
      'amazon': 'Amazon', 'flipkart': 'Flipkart', 'myntra': 'Myntra',
      'ajio': 'Ajio', 'nykaa': 'Nykaa', 'meesho': 'Meesho',
      'snapdeal': 'Snapdeal', 'tatacliq': 'Tata CLiQ',
      // Travel
      'uber': 'Uber', 'ola': 'Ola', 'rapido': 'Rapido',
      'makemytrip': 'MakeMyTrip', 'irctc': 'IRCTC',
      'redbus': 'RedBus', 'yatra': 'Yatra',
      'oyo': 'OYO', 'airbnb': 'Airbnb',
      // Fuel
      'hpcl': 'HPCL', 'bpcl': 'BPCL', 'iocl': 'IOCL',
      'petrol': 'Fuel Station', 'fuel': 'Fuel Station',
      'reliance fuel': 'Reliance Fuel',
      // Bills & Utilities
      'airtel': 'Airtel', 'jio': 'Jio', 'bsnl': 'BSNL', 'vi ': 'Vi',
      'tata power': 'Tata Power', 'bescom': 'BESCOM', 'msedcl': 'MSEDCL',
      'mahanagar gas': 'Mahanagar Gas', 'indraprastha gas': 'IGL',
      'dth': 'DTH',
      // Health
      'apollo': 'Apollo', 'practo': 'Practo', 'netmeds': 'Netmeds',
      'pharmeasy': 'PharmEasy', '1mg': '1mg', 'medplus': 'MedPlus',
      // Entertainment
      'netflix': 'Netflix', 'hotstar': 'Hotstar', 'prime video': 'Prime Video',
      'spotify': 'Spotify', 'youtube premium': 'YouTube Premium',
      'bookmyshow': 'BookMyShow', 'pvr': 'PVR', 'inox': 'INOX',
      // Finance & Payments
      'phonepe': 'PhonePe', 'gpay': 'Google Pay', 'paytm': 'Paytm',
      'cred': 'CRED', 'slice': 'Slice',
    };

    for (final kv in brands.entries) {
      if (lower.contains(kv.key)) return kv.value;
    }

    // 2. UPI VPA: "to zomato@icici" → "Zomato"
    final vpaMatch = RegExp(
      r'(?:to|paid\s+to)\s+([a-z0-9._-]+)@([a-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(sms);
    if (vpaMatch != null) {
      final handle = vpaMatch.group(1) ?? '';
      if (handle.length > 2) return _capitalize(handle);
    }

    // 3. "at <Title Case Name>" — typical POS/card messages
    final atMatch = RegExp(
      r'\bat\s+([A-Z][A-Za-z0-9&\s]{2,25}?)(?:\s+on|\s+for|[,.]|$)',
    ).firstMatch(sms);
    if (atMatch != null) {
      final name = atMatch.group(1)?.trim() ?? '';
      if (name.length > 2) return name;
    }

    // 4. "to <Name>" — UPI P2P or NEFT
    final toMatch = RegExp(
      r'\bto\s+([A-Z][A-Za-z\s]{2,25}?)(?:\s+(?:via|on|for|using)|[,.]|$)',
    ).firstMatch(sms);
    if (toMatch != null) {
      final name = toMatch.group(1)?.trim() ?? '';
      if (name.length > 2) return name;
    }

    return 'SMS Transaction';
  }

  // ─── CATEGORY DETECTION ────────────────────────────────────────────────────

  /// Two-pass: first match on merchant (more specific), then raw SMS text.
  String detectCategory(String sms, [String? resolvedMerchant]) {
    final lower = sms.toLowerCase();
    final merch = (resolvedMerchant ?? '').toLowerCase();

    // Food
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
      'dhaba'
    ])) return 'Food';
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
      'biryani'
    ])) return 'Food';

    // Shopping
    if (_anyOf(merch, [
      'amazon',
      'flipkart',
      'myntra',
      'ajio',
      'nykaa',
      'meesho',
      'snapdeal',
      'tatacliq'
    ])) return 'Shopping';
    if (_anyOf(lower, [
      'shopping',
      'mart',
      'store',
      'mall',
      'retail',
      'purchase',
      'order',
      'apparel',
      'cloth'
    ])) return 'Shopping';

    // Travel
    if (_anyOf(merch, [
      'uber',
      'ola',
      'rapido',
      'makemytrip',
      'irctc',
      'redbus',
      'yatra',
      'oyo',
      'airbnb'
    ])) return 'Travel';
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
      'travel'
    ])) return 'Travel';

    // Fuel
    if (_anyOf(
        merch, ['hpcl', 'bpcl', 'iocl', 'fuel station', 'reliance fuel']))
      return 'Fuel';
    if (_anyOf(lower, ['petrol', 'diesel', 'fuel', 'gas station', 'pump']))
      return 'Fuel';

    // Bills & Utilities
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
      'dth'
    ])) return 'Bills';
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
      'premium'
    ])) return 'Bills';

    // Health
    if (_anyOf(
        merch, ['apollo', 'practo', 'netmeds', 'pharmeasy', '1mg', 'medplus']))
      return 'Health';
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
      'chemist',
      'drug'
    ])) return 'Health';

    // Entertainment
    if (_anyOf(merch, [
      'netflix',
      'hotstar',
      'prime video',
      'spotify',
      'youtube premium',
      'bookmyshow',
      'pvr',
      'inox'
    ])) return 'Entertainment';
    if (_anyOf(lower, [
      'subscription',
      'ott',
      'movie',
      'cinema',
      'ticket',
      'entertainment',
      'gaming',
      'game'
    ])) return 'Entertainment';

    // ATM / Cash
    if (_anyOf(lower, ['atm', 'cash withdrawal', 'withdrawn'])) return 'Cash';

    // Transfer (UPI P2P / NEFT / IMPS)
    if (_anyOf(lower, [
      'upi',
      'neft',
      'imps',
      'rtgs',
      'fund transfer',
      'transferred to',
      'sent to'
    ])) return 'Transfer';

    return 'Other';
  }

  // ─── HELPERS ───────────────────────────────────────────────────────────────

  bool _anyOf(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }
}
