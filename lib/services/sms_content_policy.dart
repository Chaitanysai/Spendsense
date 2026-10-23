/// One place that decides whether a NEWLY created record keeps its raw SMS
/// body.
///
/// ## Why
///
/// The raw bank SMS is the most sensitive thing the app ever holds: account
/// suffixes, UTR/reference numbers, merchant, amount, and any OTP that arrived
/// in the same message. It was being persisted verbatim, next to the derived
/// transaction, in plain text. Nothing the user sees needs it except the
/// "Original SMS" panel, and the derived fields already describe the message.
///
/// ## Reduce-only
///
/// This phase stops NEW retention. It does not encrypt, delete or rewrite
/// anything that is already stored — existing bodies remain readable so no
/// migration or recovery work is implied, and no data is lost.
///
/// ## Reversible
///
/// [retainRawBodies] is the single switch. Flipping it back restores the old
/// behaviour without touching the parser, the AI adapter, the importer, the
/// model, the store or the UI. `test/sms_content_policy_test.dart` pins both
/// directions so neither can change silently.
///
/// ## What this is NOT
///
/// This is not encryption, and it does not make the ledger protected at rest.
/// Records already on disk are still plain text.
class SmsContentPolicy {
  SmsContentPolicy._();

  /// Whether a record created from now on stores the raw message body.
  ///
  /// Approved policy for this phase: no.
  static const bool retainRawBodies = false;

  /// The body to attach to a NEW record, or null when it must not be stored.
  static String? retainedBody(String smsBody, {bool? retainOverride}) =>
      bodyForNewRecord(smsBody, retainOverride: retainOverride);

  /// Explicit form used by tests to prove the switch works both ways.
  static String? bodyForNewRecord(String smsBody, {bool? retainOverride}) {
    final retain = retainOverride ?? retainRawBodies;
    return retain ? smsBody : null;
  }

  /// A body that is already stored is returned unchanged. Reading must never
  /// mutate a record — not in the details panel, not in an export.
  static String preserve(String storedBody) => storedBody;
}
