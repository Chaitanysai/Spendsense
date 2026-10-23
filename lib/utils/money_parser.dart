/// Errors raised when an amount cannot be represented as INR paise.
class MoneyParseException implements Exception {
  final String message;

  const MoneyParseException(this.message);

  @override
  String toString() => 'MoneyParseException: $message';
}

/// Converts an INR decimal string to integer paise.
///
/// This parser accepts plain digits and valid Indian digit grouping. It allows
/// at most two decimal places and never uses a double for money.
int parseRupeesToPaise(String input) {
  final value = input.trim();
  if (value.isEmpty) throw const MoneyParseException('Amount is empty.');
  if (value.startsWith('-') || value.startsWith('+')) {
    throw const MoneyParseException('Amount must be non-negative.');
  }

  final match = RegExp(r'^(\d+|\d{1,3}(?:,\d{2})*,\d{3})(?:\.(\d{1,2}))?$')
      .firstMatch(value);
  if (match == null) {
    throw const MoneyParseException('Amount format is invalid.');
  }

  final whole = int.tryParse(match.group(1)!.replaceAll(',', ''));
  if (whole == null) throw const MoneyParseException('Amount is too large.');
  final fraction = match.group(2) ?? '';
  final paise = int.parse(fraction.padRight(2, '0'));
  final result = whole * 100 + paise;
  if (result < 0) throw const MoneyParseException('Amount is too large.');
  return result;
}

String formatPaise(int amountMinor, {bool trimZeroPaise = false}) {
  if (amountMinor < 0) {
    throw const MoneyParseException('Amount must be non-negative.');
  }
  final rupees = amountMinor ~/ 100;
  final paise = amountMinor % 100;
  if (trimZeroPaise && paise == 0) return rupees.toString();
  return '$rupees.${paise.toString().padLeft(2, '0')}';
}

/// Divides non-negative paise and rounds to the nearest paise.
///
/// This keeps average money values integral and makes the rounding rule clear.
int roundPaiseDivision(int amountMinor, int divisor) {
  if (amountMinor < 0 || divisor <= 0) {
    throw ArgumentError(
        'amountMinor must be non-negative and divisor positive.');
  }
  return (amountMinor + divisor ~/ 2) ~/ divisor;
}
