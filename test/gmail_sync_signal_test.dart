import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/services/email/gmail_email_source.dart';

/// A source that finds no matching bank mail, which is the normal state until
/// the right sender domain is on the allowlist — and, before this fix, the
/// exact situation that left the screen saying "Last sync: never" after every
/// sync the person ran.
class _EmptyMailSource extends GmailEmailSource {
  DateTime? recordedSync;
  DateTime? recordedCursor;

  @override
  Future<List<GmailAlert>> fetchBankAlerts({
    required Set<String> seenIds,
    DateTime? since,
  }) async =>
      const [];

  @override
  Future<DateTime?> lastSyncAt() async => null;

  @override
  Future<void> markImported(DateTime newestMessageTime) async {
    recordedCursor = newestMessageTime;
  }

  @override
  Future<void> markSyncedAt(DateTime when) async {
    recordedSync = when;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a sync that matches nothing still records that it ran', () async {
    final provider = TransactionProvider();
    await provider.ready;
    final source = _EmptyMailSource();

    final imported = await provider.importFromGmail(source: source);

    expect(imported, 0);
    expect(
      source.recordedSync,
      isNotNull,
      reason: 'the screen reads this, so "never" must stop being shown',
    );
    expect(
      source.recordedCursor,
      isNull,
      reason: 'a sync with no mail must not move the Gmail query boundary',
    );
    expect(provider.syncFailure, isNull);
  });
}
