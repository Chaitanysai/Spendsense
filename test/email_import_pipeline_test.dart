import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/providers/transaction_provider.dart';
import 'package:spendsense/screens/email_import_screen.dart';
import 'package:spendsense/services/email/gmail_email_source.dart';

/// A source that behaves like the real one at the boundary the provider cares
/// about: it never returns a message whose `gmail:<id>` is already known.
class _RecordingSource extends GmailEmailSource {
  _RecordingSource(this.alerts);

  final List<GmailAlert> alerts;
  Set<String>? seenIds;
  DateTime? cursor;

  @override
  Future<List<GmailAlert>> fetchBankAlerts({
    required Set<String> seenIds,
    DateTime? since,
  }) async {
    this.seenIds = seenIds;
    return [
      for (final alert in alerts)
        if (!seenIds.contains('gmail:${alert.id}')) alert,
    ];
  }

  @override
  Future<DateTime?> lastSyncAt() async => null;

  @override
  Future<void> markImported(DateTime newestMessageTime) async {
    cursor = newestMessageTime;
  }

  @override
  Future<void> markSyncedAt(DateTime when) async {}
}

class _AuthFailingSource extends GmailEmailSource {
  @override
  Future<List<GmailAlert>> fetchBankAlerts({
    required Set<String> seenIds,
    DateTime? since,
  }) async {
    throw const EmailAuthUnavailableException(
      'Gmail needs to be reconnected before syncing.',
    );
  }

  @override
  Future<DateTime?> lastSyncAt() async => null;
}

GmailAlert _alert(String id, String text, DateTime date) => GmailAlert(
      id: id,
      subject: 'Transaction alert',
      from: 'HDFC Bank <alerts@hdfcbank.net>',
      text: text,
      date: date,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('one unparsed debit does not hide or skip the rest', () async {
    final provider = TransactionProvider();
    await provider.ready;
    final source = _RecordingSource([
      _alert(
        'good',
        'Rs 450 debited from A/c XX1234 to Zomato on 12-10-26',
        DateTime.utc(2026, 10, 12, 10),
      ),
      _alert(
        'broken',
        'Your account was debited today for a recent purchase.',
        DateTime.utc(2026, 10, 13, 10),
      ),
      _alert(
        'statement',
        'Your monthly statement is ready to view.',
        DateTime.utc(2026, 10, 11, 10),
      ),
    ]);

    final report = await provider.importFromGmail(source: source);

    expect(report.found, 3, reason: 'all three allowlisted alerts were listed');
    expect(report.imported, 1);
    expect(report.skipped, 2);
    expect(provider.transactions, hasLength(1));
    expect(provider.transactions.single.source, 'Email-Gmail');
    expect(provider.transactions.single.amountMinor, 45000);

    // The cursor must stop before the oldest unparsed debit, so the next sync
    // still covers it. Advancing to the newest alert would step over it for
    // good — the bug this test exists to pin.
    expect(
      source.cursor,
      DateTime.utc(2026, 10, 13, 10).subtract(const Duration(seconds: 1)),
    );
  });

  test('a known record is not imported twice', () async {
    final provider = TransactionProvider();
    await provider.ready;
    final source = _RecordingSource([
      _alert(
        'good',
        'Rs 450 debited from A/c XX1234 to Zomato on 12-10-26',
        DateTime.utc(2026, 10, 12, 10),
      ),
    ]);

    final first = await provider.importFromGmail(source: source);
    final second = await provider.importFromGmail(source: source);

    expect(first.imported, 1);
    expect(second.imported, 0);
    expect(provider.transactions, hasLength(1));
    expect(source.seenIds, contains('gmail:good'));
  });

  test('a rejected message is not fetched again, but a recheck frees it',
      () async {
    final provider = TransactionProvider();
    await provider.ready;
    final broken = _alert(
      'broken',
      'Your account was debited today for a recent purchase.',
      DateTime.utc(2026, 10, 13, 10),
    );

    // First sync: nothing is known yet, so the message is listed and rejected.
    final first = _RecordingSource([broken]);
    await provider.importFromGmail(source: first);
    expect(first.seenIds, isNot(contains('gmail:broken')));
    expect(provider.skippedMessageCount, 1);

    // Second sync: the rejection is now part of the seen set, so the body is
    // not downloaded again.
    final second = _RecordingSource([broken]);
    await provider.importFromGmail(source: second);
    expect(second.seenIds, contains('gmail:broken'));

    // An explicit recheck clears the skip list, which puts the message back in
    // the fetch set for the next sync.
    await provider.recheckSkippedMessages();
    expect(provider.skippedMessageCount, 0);

    final third = _RecordingSource([broken]);
    await provider.importFromGmail(source: third);
    expect(third.seenIds, isNot(contains('gmail:broken')),
        reason: 'after a recheck the message must be eligible again');
  });

  test('an auth failure surfaces instead of reading as "no mail"', () async {
    final provider = TransactionProvider();
    await provider.ready;

    await expectLater(
      provider.importFromGmail(source: _AuthFailingSource()),
      throwsA(isA<EmailAuthUnavailableException>()),
    );
    expect(provider.syncFailure, isNotNull);
  });

  test('sync feedback separates empty, unrecognised and imported mail', () {
    expect(
      emailSyncSnackBarText(
        const GmailSyncReport(found: 0, imported: 0, skipped: 0),
      ),
      'No bank emails matched your sender domains',
    );
    expect(
      emailSyncSnackBarText(
        const GmailSyncReport(found: 2, imported: 0, skipped: 2),
      ),
      'Found 2 bank email(s), but none matched a transaction',
    );
    expect(
      emailSyncSnackBarText(
        const GmailSyncReport(found: 3, imported: 1, skipped: 2),
      ),
      'Imported 1 email transaction(s)',
    );
  });
}
