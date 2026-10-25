import '../../models/transaction_model.dart';

/// A known investment brand and the narration aliases that identify it.
class MerchantBrand {
  final String key;
  final String label;
  final List<String> aliases;

  const MerchantBrand({
    required this.key,
    required this.label,
    required this.aliases,
  });
}

/// Conservative merchant-alias resolution for the assistant.
///
/// Matching is token based, never a raw substring: "Growwth Capital" is not
/// Groww, and a bare "Kite" is not Zerodha. All alias hits must occupy a whole
/// token sequence in normalized text.
class MerchantMatcher {
  MerchantMatcher._();

  static const MerchantBrand groww = MerchantBrand(
    key: 'groww',
    label: 'Groww',
    aliases: [
      'groww',
      'groww broking',
      'groww securities',
      'groww wealth',
      'groww amc',
      'groww mutual fund',
      'groww instant',
    ],
  );

  static const MerchantBrand zerodha = MerchantBrand(
    key: 'zerodha',
    label: 'Zerodha',
    aliases: [
      'zerodha',
      'zerodha broking',
      'zerodha securities',
      'kite zerodha',
      'zerodha kite',
      'coin by zerodha',
      'zerodha coin',
    ],
  );

  static const List<MerchantBrand> brands = [groww, zerodha];

  static String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  /// True when [alias] appears as one or more complete words in [text].
  static bool hasAlias(String text, String alias) {
    final normalizedText = normalize(text);
    final normalizedAlias = normalize(alias);
    if (normalizedText.isEmpty || normalizedAlias.isEmpty) return false;
    return ' $normalizedText '.contains(' $normalizedAlias ');
  }

  static MerchantBrand? brandByKey(String key) {
    for (final brand in brands) {
      if (brand.key == key) return brand;
    }
    return null;
  }

  /// Brands explicitly named by the user's text. "Growth" never matches Groww.
  static List<MerchantBrand> detectInQuery(String query) {
    final found = <MerchantBrand>[];
    for (final brand in brands) {
      if (brand.aliases.any((alias) => hasAlias(query, alias))) {
        found.add(brand);
      }
    }
    return found;
  }

  /// Merchant values that carry no identity of their own. Only for these rows
  /// may the retained narration be used to recover a brand, which avoids
  /// matching a Groww mention in the SMS body of an unrelated merchant.
  static const Set<String> _genericMerchants = {
    '',
    'upi',
    'unknown',
    'sms transaction',
    'others',
    'other',
    'payment',
    'bank transfer',
    'neft',
    'imps',
    'rtgs',
    'wallet',
  };

  static bool _isGenericMerchant(String merchant) =>
      _genericMerchants.contains(normalize(merchant));

  /// The first known brand represented by a stored transaction.
  ///
  /// Merchant text is authoritative. Narration is consulted only when the
  /// parsed merchant is generic such as "UPI". The retained SMS body is matched
  /// locally and is never sent to a model.
  static MerchantBrand? matchTransaction(TransactionModel tx) {
    for (final brand in brands) {
      if (matchesBrand(tx, brand)) return brand;
    }
    return null;
  }

  static bool matchesBrand(TransactionModel tx, MerchantBrand brand) {
    if (brand.aliases.any((alias) => hasAlias(tx.merchant, alias))) {
      return true;
    }
    if (!_isGenericMerchant(tx.merchant)) return false;
    final fallback = '${tx.reference ?? ''} ${tx.originalSms}';
    return brand.aliases.any((alias) => hasAlias(fallback, alias));
  }

  /// Matches a caller-supplied alias with the same conservative rule.
  static bool matchesAlias(TransactionModel tx, String alias) {
    if (hasAlias(tx.merchant, alias)) return true;
    if (!_isGenericMerchant(tx.merchant)) return false;
    return hasAlias('${tx.reference ?? ''} ${tx.originalSms}', alias);
  }

  /// Generic free-text merchant matching used by tool filters. Requires every
  /// whitespace-separated token to occur as a whole word, so a filter for "SBI"
  /// does not also match "SBICARD" unless the user typed that.
  static bool matchesFilter(TransactionModel tx, String filter) {
    final normalizedFilter = normalize(filter);
    if (normalizedFilter.isEmpty) return true;
    final haystacks = [
      tx.merchant,
      tx.category,
      tx.paymentMethod,
      tx.bankName,
      tx.reference ?? '',
    ].map(normalize).toList();
    final tokens = normalizedFilter.split(' ');
    return haystacks.any((text) {
      final padded = ' $text ';
      return tokens.every((token) => padded.contains(' $token '));
    });
  }
}
