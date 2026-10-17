/// Single source of truth for bank identification from transaction messages.
///
/// Bank names are derived only from the message text. Identifying a bank here
/// never implies a live connection to that bank — it is a label on a parsed
/// debit/credit, nothing more.
///
/// The table is intentionally a plain, local mapping: no network request is
/// made to identify a bank, and the same rules are reused by the deterministic
/// parser and the AI-assisted path so the two cannot diverge.
class BankRecognizer {
  BankRecognizer._();

  /// Values that mean "we could not identify a bank". Never treated as a real
  /// bank name, and never used to overwrite a known bank.
  static const List<String> _unknownValues = [
    'others',
    'other',
    'unknown',
    'none',
    'na',
    'n/a',
    '-',
  ];

  /// Words that carry no bank identity on their own. A candidate made up only of
  /// these is a bare descriptor, not a bank ("Bank", "Bank Account", "Your
  /// Bank"), and must not be accepted as an identified bank.
  static const Set<String> _degenerateWords = {
    'bank',
    'account',
    'acc',
    'ac',
    'a',
    'c',
    'your',
    'my',
    'the',
    'of',
    'and',
  };

  /// Ordered alias table. More specific phrases must appear before the shorter
  /// tokens they contain (e.g. 'south indian bank' before 'indian bank'), because
  /// the first match wins.
  static const List<_BankAlias> _aliases = [
    _BankAlias('airtel payments bank', 'Airtel Payments Bank'),
    _BankAlias('paytm payments bank', 'Paytm Payments Bank'),
    _BankAlias('bank of baroda', 'Bank of Baroda'),
    _BankAlias('punjab national bank', 'Punjab National Bank'),
    _BankAlias('state bank of india', 'SBI'),
    _BankAlias('south indian bank', 'South Indian Bank'),
    _BankAlias('karur vysya', 'Karur Vysya Bank'),
    _BankAlias('city union bank', 'City Union Bank'),
    _BankAlias('bank of maharashtra', 'Bank of Maharashtra'),
    _BankAlias('punjab and sind', 'Punjab & Sind Bank'),
    _BankAlias('punjab & sind', 'Punjab & Sind Bank'),
    _BankAlias('central bank of india', 'Central Bank of India'),
    _BankAlias('union bank of india', 'Union Bank of India'),
    _BankAlias('canara bank', 'Canara Bank'),
    _BankAlias('idbi bank', 'IDBI Bank'),
    _BankAlias('indusind', 'IndusInd Bank'),
    _BankAlias('yes bank', 'YES Bank'),
    _BankAlias('idfc', 'IDFC FIRST Bank'),
    _BankAlias('bandhan', 'Bandhan Bank'),
    _BankAlias('rbl', 'RBL Bank'),
    _BankAlias('kotak', 'Kotak Mahindra Bank'),
    _BankAlias('federal bank', 'Federal Bank'),
    _BankAlias('icici', 'ICICI Bank'),
    _BankAlias('hdfc', 'HDFC Bank'),
    _BankAlias('axis', 'Axis Bank'),
    _BankAlias('indian bank', 'Indian Bank'),
    _BankAlias('state bank', 'SBI'),
    _BankAlias('canara', 'Canara Bank'),
    _BankAlias('union bank', 'Union Bank of India'),
    _BankAlias('idbi', 'IDBI Bank'),
    _BankAlias('sbi', 'SBI'),
    _BankAlias('pnb', 'Punjab National Bank'),
    _BankAlias('ppbl', 'Paytm Payments Bank'),
  ];

  /// Extracts a bank from a raw SMS body, returning the canonical display name
  /// or null when no bank is named. Deterministic and local.
  static String? detectFromSms(String sms) => _matchAlias(sms);

  /// Normalizes an externally supplied bank value (e.g. an AI response) into a
  /// canonical display name, or null when it is not a usable bank.
  ///
  /// A value that is a bare rail/instrument/wallet/payment-app name is rejected;
  /// a value that names a bank is kept. This is the only place that decides.
  static String? normalize(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (_unknownValues.contains(lower)) return null;

    final alias = _matchAlias(value);
    if (alias != null) return alias;

    // Anything else is trusted only when it names a bank beyond the generic
    // words themselves, so degenerate values like "Bank", "Bank Account" or
    // "Your Bank" are rejected rather than stored as a bank name.
    final hasName = lower
        .replaceAll(RegExp(r'[^a-z]'), ' ')
        .split(' ')
        .any((word) => word.isNotEmpty && !_degenerateWords.contains(word));
    if (hasName && RegExp(r'\bbank\b', caseSensitive: false).hasMatch(value)) {
      return _titleCase(value);
    }
    return null;
  }

  /// True when [bank] is a real, identified bank — i.e. not null, blank, or the
  /// display fallback 'Others'.
  static bool isKnown(String? bank) {
    final value = bank?.trim();
    if (value == null || value.isEmpty) return false;
    return !_unknownValues.contains(value.toLowerCase());
  }

  static String? _matchAlias(String text) {
    for (final alias in _aliases) {
      final pattern = RegExp(
        '\\b${RegExp.escape(alias.token)}\\b',
        caseSensitive: false,
      );
      if (pattern.hasMatch(text)) return alias.canonical;
    }
    return null;
  }

  static String _titleCase(String value) {
    final cleaned = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    final isUniformCase =
        cleaned == cleaned.toLowerCase() || cleaned == cleaned.toUpperCase();
    if (!isUniformCase) return cleaned;
    return cleaned
        .split(' ')
        .map((word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _BankAlias {
  final String token;
  final String canonical;
  const _BankAlias(this.token, this.canonical);
}
