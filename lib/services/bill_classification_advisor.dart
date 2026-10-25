import 'bill_classifier.dart';

/// Optional, future classification advisor.
///
/// SpendSense currently ships **no** implementation of this interface: bill
/// detection is entirely local and deterministic. The interface exists so a
/// secure backend can add a second opinion later without putting an API key in
/// the APK and without changing [BillClassifier].
///
/// Contract for any future implementation:
/// * never receive the SMS inbox or unrelated transaction history;
/// * receive only [BillAdvisoryRequest.redactedText], which has account numbers,
///   OTPs, phone numbers, card numbers and balances removed;
/// * enforce authentication, rate limits, quotas and response-size limits on
///   the server, not the client;
/// * return a strict, validated suggestion — never proof of payment;
/// * fail closed: a timeout, missing key or bad response must leave local
///   classification unchanged.
abstract interface class BillClassificationAdvisor {
  Future<BillAdvisory?> advise(BillAdvisoryRequest request);
}

/// The default advisor. It performs no I/O and always declines, so an offline
/// device behaves identically to one with no advisor configured.
class LocalOnlyBillAdvisor implements BillClassificationAdvisor {
  const LocalOnlyBillAdvisor();

  @override
  Future<BillAdvisory?> advise(BillAdvisoryRequest request) async => null;
}

/// Minimal, redacted payload a future backend would receive.
class BillAdvisoryRequest {
  final String redactedText;
  final BillKind localKind;
  final double localConfidence;

  const BillAdvisoryRequest({
    required this.redactedText,
    required this.localKind,
    required this.localConfidence,
  });
}

/// A model suggestion. It can only change presentation, never mark a payment.
class BillAdvisory {
  final BillKind? kind;
  final double confidence;
  final String? reason;

  const BillAdvisory({this.kind, required this.confidence, this.reason});
}

/// Removes high-risk identifiers before any future outbound request.
///
/// This is not used today (no advisor performs I/O), but keeping the redaction
/// beside the interface makes the privacy boundary explicit and testable.
class BillTextRedactor {
  BillTextRedactor._();

  static String redact(String text) {
    var out = text;
    // OTPs and long card/account numbers.
    out = out.replaceAll(RegExp(r'\b\d{4,}\b'), '[number]');
    // Phone numbers, with or without separators.
    out = out.replaceAll(RegExp(r'(?:\+91[\s-]?)?[6-9]\d{9}\b'), '[phone]');
    // Email addresses (not needed for bill classification).
    out = out.replaceAll(
        RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'), '[email]');
    // Balance / available-limit clauses, which are irrelevant to a bill type.
    out = out.replaceAll(
      RegExp(r'(?:avl|available|closing)\s*(?:bal|balance)[^.]*',
          caseSensitive: false),
      '[balance]',
    );
    return out;
  }
}
