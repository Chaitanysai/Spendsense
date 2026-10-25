import '../models/transaction_model.dart';

/// The kind of obligation a transaction or message describes.
enum BillKind {
  utility,
  broadband,
  mobile,
  loan,
  insurance,
  rent,
  subscription,
  other,
  none,
}

extension BillKindX on BillKind {
  String get label => switch (this) {
        BillKind.utility => 'Utility',
        BillKind.broadband => 'Broadband',
        BillKind.mobile => 'Mobile',
        BillKind.loan => 'Loan / EMI',
        BillKind.insurance => 'Insurance',
        BillKind.rent => 'Rent / maintenance',
        BillKind.subscription => 'Subscription',
        BillKind.other => 'Bill',
        BillKind.none => 'Ordinary',
      };
}

/// Internal evidence label. Only [paidBill], [recurringBill] and (when a
/// reliable pattern backs it) [ambiguous] may reach the Bills screen.
enum BillEvidence {
  /// A successful payment with strong, bill-specific evidence.
  paidBill,

  /// A reliable repeating obligation inferred from consistent payments.
  recurringBill,

  /// Bill-shaped but not proven. Stays an ordinary transaction.
  ambiguous,

  /// Groceries, food, fuel, shopping, transfers, cash and one-offs.
  ordinary,
}

/// One deterministic classification result. Contains no SMS text beyond
/// normalized keywords, so it is safe to hold in memory and show in the UI.
class BillClassification {
  final BillEvidence evidence;
  final BillKind kind;
  final double confidence;
  final String billerKey;
  final String billerLabel;
  final bool reminderOnly;
  final bool paymentConfirmation;
  final List<String> reasons;

  const BillClassification({
    required this.evidence,
    required this.kind,
    required this.confidence,
    required this.billerKey,
    required this.billerLabel,
    required this.reminderOnly,
    required this.paymentConfirmation,
    required this.reasons,
  });

  bool get isOrdinary => evidence == BillEvidence.ordinary;
  bool get isStrong => evidence == BillEvidence.paidBill;
  bool get isBillLike => evidence != BillEvidence.ordinary;
}

/// Local-first, deterministic classification.
///
/// Rules are intentionally narrow:
/// * a hard deny-list keeps groceries, restaurants, fuel, shopping, travel,
///   generic UPI/transfers and cash withdrawals ordinary even when the message
///   happens to contain the word "bill";
/// * a bill needs a specific obligation signal (utility/telecom/EMI/insurance/
///   rent/subscription keyword or a known biller), not merely the `Bills`
///   category;
/// * recurrence can strengthen evidence, but a single weak match cannot create
///   a recurring bill.
///
/// No network call is made here. The optional advisor interface in
/// `bill_classification_advisor.dart` is deliberately not wired into this
/// classifier.
class BillClassifier {
  const BillClassifier();

  /// Categories that can never be a bill, regardless of wording.
  static const Set<String> hardOrdinaryCategories = {
    'food',
    'fuel',
    'shopping',
    'travel',
  };

  /// Payment rails that are ordinary *unless* a specific bill keyword or
  /// biller is present. A utility bill paid by UPI/NEFT is still a bill; a
  /// generic transfer to a person is not.
  static const Set<String> softOrdinaryCategories = {
    'transfer',
    'cash',
    'upi',
  };

  static const List<String> _foodAndGrocery = [
    'swiggy',
    'zomato',
    'bigbasket',
    'blinkit',
    'zepto',
    'instamart',
    'dmart',
    'reliance fresh',
    'more supermarket',
    'grofers',
    'jiomart',
    'dominos',
    'pizza hut',
    'mcdonald',
    'kfc',
    'starbucks',
    'restaurant',
    'cafe',
    'food court',
    'bakery',
    'grocery',
    'supermarket',
    'kirana',
  ];

  static const List<String> _shoppingAndTravel = [
    'amazon',
    'flipkart',
    'myntra',
    'ajio',
    'meesho',
    'nykaa',
    'tata cliq',
    'croma',
    'reliance digital',
    'uber',
    'ola',
    'rapido',
    'irctc',
    'makemytrip',
    'redbus',
    'oyo',
    'airbnb',
    'fuel station',
    'petrol pump',
    'hpcl',
    'bpcl',
    'iocl',
  ];

  static const List<String> _prepaidMarkers = [
    'prepaid',
    'recharge',
    'top up',
    'topup',
  ];

  static const List<String> _cashAndTransfers = [
    'cash withdrawal',
    'atm withdrawal',
    'atm cash',
    'withdrawal',
    'upi transfer',
    'p2p',
    'person to person',
    'send money',
    'neft',
    'imps',
    'rtgs',
    'self transfer',
  ];

  static const List<String> _reminderMarkers = [
    'is due',
    'due on',
    'due date',
    'amount due',
    'minimum due',
    'payment due',
    'will be debited',
    'will get debited',
    'please pay',
    'pay before',
    'bill generated',
    'bill is ready',
    'bill has been generated',
    'reminder',
    'outstanding',
    'scheduled for',
    'autopay on',
  ];

  static const List<String> _confirmationMarkers = [
    'debited',
    'auto debit',
    'autopay',
    'payment successful',
    'payment of',
    'successfully paid',
    'has been paid',
    'payment received',
    'thank you for your payment',
    'mandate executed',
    'emi debited',
  ];

  static const Map<BillKind, List<String>> _merchantRules = {
    BillKind.utility: [
      'tata power',
      'adani electricity',
      'adani power',
      'bescom',
      'msedcl',
      'mseb',
      'bses',
      'torrent power',
      'cesc',
      'mahanagar gas',
      'indraprastha gas',
      'gujarat gas',
      'water board',
      'municipal corporation',
      'electricity board',
    ],
    BillKind.broadband: [
      'act fibernet',
      'hathway',
      'excitel',
      'jiofiber',
      'jio fiber',
      'airtel xstream',
      'spectra',
      'you broadband',
    ],
    BillKind.mobile: [
      'airtel',
      'jio',
      'vodafone',
      'bsnl',
      'vi postpaid',
      'postpaid',
    ],
    BillKind.loan: [
      'bajaj finance',
      'emi',
      'loan repayment',
      'home loan',
      'personal loan',
      'car loan',
    ],
    BillKind.insurance: [
      'lic',
      'hdfc life',
      'icici prudential',
      'sbi life',
      'max life',
      'policybazaar',
      'insurance',
    ],
    BillKind.rent: [
      'rent',
      'maintenance',
      'society',
      'property tax',
      'lease',
    ],
    BillKind.subscription: [
      'netflix',
      'spotify',
      'hotstar',
      'prime video',
      'youtube premium',
      'google one',
      'icloud',
      'adobe',
      'microsoft 365',
      'canva',
      'chatgpt',
      'openai',
      'audible',
    ],
  };

  static const Map<BillKind, List<String>> _keywordRules = {
    BillKind.utility: [
      'electricity',
      'power bill',
      'water bill',
      'gas bill',
      'utility',
      'energy bill',
      'dth',
      'cable bill',
    ],
    BillKind.broadband: [
      'broadband',
      'fibernet',
      'fibre',
      'internet bill',
      'wifi bill',
    ],
    BillKind.mobile: [
      'postpaid',
      'mobile bill',
      'phone bill',
      'telephone bill',
      'landline bill',
    ],
    BillKind.loan: [
      'emi',
      'loan',
      'instalment',
      'installment',
      'loan repayment',
      'credit card bill',
    ],
    BillKind.insurance: [
      'insurance',
      'premium',
      'policy number',
      'policy no',
      'lic premium',
    ],
    BillKind.rent: [
      'rent',
      'maintenance',
      'society charges',
      'property tax',
    ],
    BillKind.subscription: [
      'subscription',
      'ott',
      'annual plan',
      'monthly plan',
      'renewal',
    ],
    BillKind.other: ['bill', 'invoice'],
  };

  /// Classifies a stored expense. Reminder-only evidence never becomes a bill
  /// payment even if the category says Bills.
  BillClassification classify(TransactionModel transaction) {
    if (transaction.type != TransactionType.expense ||
        transaction.isExcluded ||
        transaction.amountMinor <= 0) {
      return _ordinary(transaction.merchant, 'Not an eligible expense');
    }
    final hint = kindFromHint(transaction.billKindHint);
    if (hint != null) {
      if (hint == BillKind.none) {
        return _ordinary(
            transaction.merchant, 'Parser classified this as ordinary');
      }
      if (transaction.billReminderHint) {
        return BillClassification(
          evidence: BillEvidence.ambiguous,
          kind: hint,
          confidence: 0.55,
          billerKey: billerKey(transaction.merchant, hint),
          billerLabel: _label(transaction.merchant, hint),
          reminderOnly: true,
          paymentConfirmation: false,
          reasons: const ['Reminder-only message, not a payment'],
        );
      }
      if (hint == BillKind.other) {
        return BillClassification(
          evidence: BillEvidence.ambiguous,
          kind: hint,
          confidence: 0.70,
          billerKey: billerKey(transaction.merchant, hint),
          billerLabel: _label(transaction.merchant, hint),
          reminderOnly: false,
          paymentConfirmation: true,
          reasons: const ['Generic bill wording; needs recurrence'],
        );
      }
      return BillClassification(
        evidence: BillEvidence.paidBill,
        kind: hint,
        confidence: 0.86,
        billerKey: billerKey(transaction.merchant, hint),
        billerLabel: _label(transaction.merchant, hint),
        reminderOnly: false,
        paymentConfirmation: true,
        reasons: ['Parser bill hint: ${hint.label.toLowerCase()}'],
      );
    }
    return classifyText(
      transaction.originalSms,
      merchant: transaction.merchant,
      category: transaction.category,
      amountMinor: transaction.amountMinor,
      reference: transaction.reference,
    );
  }

  /// Maps a stored hint name back to an enum. Unknown names are ignored rather
  /// than trusted, so corrupted import data cannot invent a bill kind.
  static BillKind? kindFromHint(String? hint) {
    if (hint == null) return null;
    for (final kind in BillKind.values) {
      if (kind.name == hint) return kind;
    }
    return null;
  }

  /// Text-level classifier used by tests and by the optional future advisor.
  /// The caller must pass already-authorized, locally available text.
  BillClassification classifyText(
    String text, {
    required String merchant,
    required String category,
    int amountMinor = 0,
    String? reference,
  }) {
    final merchantNorm = normalize(merchant);
    final categoryNorm = category.toLowerCase().trim();
    final textNorm = normalize(text);

    if (amountMinor < 0) {
      return _ordinary(merchant, 'Invalid amount');
    }

    if (hardOrdinaryCategories.contains(categoryNorm) ||
        _containsAny(merchantNorm, _foodAndGrocery) ||
        _containsAny(merchantNorm, _shoppingAndTravel) ||
        _containsAny(merchantNorm, _cashAndTransfers)) {
      return _ordinary(merchant, 'Ordinary spending category');
    }

    // Prepaid top-ups and recharges are purchases, not recurring postpaid
    // obligations. A message that also says "postpaid" is not affected.
    if ((_containsAny(textNorm, _prepaidMarkers) ||
            _containsAny(merchantNorm, _prepaidMarkers)) &&
        !textNorm.contains('postpaid')) {
      return _ordinary(merchant, 'Prepaid recharge, not a bill');
    }

    final reminderOnly = _containsAny(textNorm, _reminderMarkers) &&
        !_containsAny(textNorm, _confirmationMarkers);
    final confirmation = _containsAny(textNorm, _confirmationMarkers);

    final merchantKind = _kindForMerchant(merchantNorm);
    final keywordKind = _kindForText(textNorm);
    final kind = merchantKind ?? keywordKind ?? BillKind.none;

    if (kind == BillKind.none) {
      if (softOrdinaryCategories.contains(categoryNorm) ||
          _containsAny(textNorm, _cashAndTransfers)) {
        return _ordinary(merchant, 'Cash or transfer, not a bill');
      }
      // The category alone is not proof. Keep it ambiguous so a single row can
      // never enter Bills.
      if (categoryNorm == 'bills') {
        return BillClassification(
          evidence: BillEvidence.ambiguous,
          kind: BillKind.other,
          confidence: 0.55,
          billerKey: billerKey(merchant, BillKind.other),
          billerLabel: _label(merchant, BillKind.other),
          reminderOnly: reminderOnly,
          paymentConfirmation: confirmation,
          reasons: const ['Bills category without bill-specific evidence'],
        );
      }
      return _ordinary(merchant, 'No bill-specific evidence');
    }

    var confidence = merchantKind != null ? 0.84 : 0.78;
    if (merchantKind != null && keywordKind != null) confidence += 0.04;
    if (reference != null && reference.trim().isNotEmpty) confidence += 0.03;
    if (confirmation) confidence += 0.05;
    if (reminderOnly) confidence = 0.55;
    confidence = confidence.clamp(0.0, 0.98).toDouble();

    return BillClassification(
      // A generic "bill"/"invoice" word alone is ambiguous. A reliable
      // recurrence can still elevate it later; a single row cannot.
      evidence: reminderOnly || kind == BillKind.other
          ? BillEvidence.ambiguous
          : BillEvidence.paidBill,
      kind: kind,
      confidence: confidence,
      billerKey: billerKey(merchant, kind),
      billerLabel: _label(merchant, kind),
      reminderOnly: reminderOnly,
      paymentConfirmation: confirmation,
      reasons: [
        if (merchantKind != null) 'Known ${kind.label.toLowerCase()} biller',
        if (keywordKind != null) '${kind.label} keyword in message',
        if (reminderOnly) 'Reminder text, not a payment confirmation',
      ],
    );
  }

  /// True when a message reads as a reminder and carries no confirmation.
  static bool isReminderOnly(String text) {
    final norm = normalize(text);
    if (norm.isEmpty) return false;
    return _containsAny(norm, _reminderMarkers) &&
        !_containsAny(norm, _confirmationMarkers);
  }

  static bool isPaymentConfirmation(String text) {
    final norm = normalize(text);
    return norm.isEmpty || _containsAny(norm, _confirmationMarkers);
  }

  /// Convenience for the recurring screen: only bill-like patterns get a
  /// "Plan this bill" affordance.
  static bool isBillLike(TransactionModel transaction) =>
      const BillClassifier().classify(transaction).isBillLike;

  static String billerKey(String merchant, BillKind kind) {
    final norm = normalize(merchant);
    return '${kind.name}:${norm.isEmpty ? kind.name : norm}';
  }

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static BillClassification _ordinary(String merchant, String reason) =>
      BillClassification(
        evidence: BillEvidence.ordinary,
        kind: BillKind.none,
        confidence: 0,
        billerKey: billerKey(merchant, BillKind.none),
        billerLabel: merchant.trim(),
        reminderOnly: false,
        paymentConfirmation: false,
        reasons: [reason],
      );

  static BillKind? _kindForMerchant(String merchantNorm) {
    if (merchantNorm.isEmpty) return null;
    for (final entry in _merchantRules.entries) {
      if (_containsKeyword(merchantNorm, entry.value)) return entry.key;
    }
    return null;
  }

  static BillKind? _kindForText(String textNorm) {
    if (textNorm.isEmpty) return null;
    for (final entry in _keywordRules.entries) {
      if (_containsKeyword(textNorm, entry.value)) return entry.key;
    }
    return null;
  }

  static bool _containsAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }

  /// Whole-word matching for bill keywords.
  ///
  /// Substring matching made `emi` match inside `premium` (turning insurance
  /// into a loan) and `rent` match inside `current`. Multi-word phrases and
  /// full merchant names still use the same boundary-aware check.
  static bool _containsKeyword(String haystack, List<String> needles) {
    for (final needle in needles) {
      final pattern = RegExp(
        '(?:^|[^a-z0-9])${RegExp.escape(needle)}(?:[^a-z0-9]|\$)',
      );
      if (pattern.hasMatch(haystack)) return true;
    }
    return false;
  }

  static String _label(String merchant, BillKind kind) {
    final trimmed = merchant.trim();
    if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'bank debit') {
      return trimmed;
    }
    return kind.label;
  }
}
