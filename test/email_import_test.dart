import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/services/email/gmail_email_source.dart';

void main() {
  group('Gmail sender allowlist', () {
    const domains = ['hdfcbank.net', 'icicibank.com'];

    test('accepts an exact allowlisted domain', () {
      expect(
        GmailEmailSource.isAllowedSender(
          'HDFC Bank <alerts@hdfcbank.net>',
          domains,
        ),
        isTrue,
      );
    });

    test('rejects a look-alike domain', () {
      expect(
        GmailEmailSource.isAllowedSender(
          'HDFC <alerts@hdfcbank.net.evil.example>',
          domains,
        ),
        isFalse,
      );
      expect(
        GmailEmailSource.isAllowedSender('alerts@evil-hdfcbank.net', domains),
        isFalse,
      );
    });

    test('rejects a display-name spoof with a second angle-addr', () {
      expect(
        GmailEmailSource.isAllowedSender(
          '"HDFC <alerts@hdfcbank.net>" <x@attacker.example>',
          domains,
        ),
        isFalse,
      );
    });

    test('rejects a missing or malformed address', () {
      expect(GmailEmailSource.isAllowedSender('', domains), isFalse);
      expect(GmailEmailSource.isAllowedSender('alerts@', domains), isFalse);
    });
  });

  group('Gmail message date', () {
    test('uses Gmail internalDate over the RFC 2822 header', () {
      final message = gmail.Message(
        internalDate: '1760426400000',
        payload: gmail.MessagePart(headers: [
          gmail.MessagePartHeader(name: 'Date', value: 'Tue, 14 Oct 2026 10:00:00 +0530'),
        ]),
      );
      expect(
        GmailEmailSource.messageDateForTest(message),
        DateTime.fromMillisecondsSinceEpoch(1760426400000, isUtc: true),
      );
    });

    test('falls back to an RFC 2822 Date header', () {
      final message = gmail.Message(
        payload: gmail.MessagePart(headers: [
          gmail.MessagePartHeader(name: 'Date', value: 'Tue, 14 Oct 2026 10:00:00 +0530'),
        ]),
      );
      final date = GmailEmailSource.messageDateForTest(message);
      expect(date.year, 2026);
      expect(date.month, 10);
      expect(date.day, 14);
    });
  });

  group('Gmail subject filter', () {
    test('accepts debit/payment alert subjects', () {
      expect(
        GmailEmailSource.isDebitSubject('Your account has been debited'),
        isTrue,
      );
      expect(GmailEmailSource.isDebitSubject('Payment alert'), isTrue);
    });

    test('rejects unrelated subjects', () {
      expect(GmailEmailSource.isDebitSubject('Statement is ready'), isFalse);
      expect(GmailEmailSource.isDebitSubject('Festive offers'), isFalse);
    });
  });

  group('Gmail HTML extraction', () {
    test('strips tags and scripts', () {
      const html = '<html><body><script>alert(1)</script>'
          '<p>Rs 250 debited</p><p>at ABC STORE</p></body></html>';
      final text = GmailEmailSource.htmlToText(html);
      expect(text, contains('Rs 250 debited'));
      expect(text, contains('ABC STORE'));
      expect(text, isNot(contains('alert(1)')));
      expect(text, isNot(contains('<')));
    });

    test('decodes the rupee entity used in bank emails', () {
      expect(
        GmailEmailSource.htmlToText('<p>&#8377; 1,250 debited</p>'),
        contains('₹ 1,250 debited'),
      );
    });
  });

  group('Gmail consent', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('email import is off by default', () async {
      expect(await GmailEmailSource().hasConsent(), isFalse);
    });

    test('disconnect clears consent, cursor and connected address', () async {
      final source = GmailEmailSource();
      await source.setConsent(true);
      await source.markImported(DateTime.utc(2026, 10, 14));
      expect(await source.hasConsent(), isTrue);
      expect(await source.lastSyncAt(), isNotNull);

      await source.disconnect();

      expect(await source.hasConsent(), isFalse);
      expect(await source.lastSyncAt(), isNull);
    });

    test('no access token is persisted in preferences', () async {
      final source = GmailEmailSource();
      await source.setConsent(true);

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getKeys().where((k) {
        final value = prefs.get(k);
        return value is String && value.contains('ya29.');
      });
      expect(stored, isEmpty);
    });

    test('markImported never moves the cursor backwards', () async {
      final source = GmailEmailSource();
      final newer = DateTime.utc(2026, 10, 20);
      final older = DateTime.utc(2026, 10, 1);
      await source.markImported(newer);
      await source.markImported(older);
      expect(await source.lastSyncAt(), newer);
    });

    test('sender domains are validated before they are saved', () async {
      final source = GmailEmailSource();
      await source.setSenderDomains([
        'hdfcbank.net',
        'not a domain',
        'evil.example;rm -rf',
        'HDFCBANK.NET',
      ]);
      expect(await source.senderDomains(), ['hdfcbank.net']);
    });

    test('no Gmail request is attempted without consent', () async {
      final source = GmailEmailSource();
      await expectLater(
        source.fetchBankAlerts(seenIds: const {}),
        throwsA(isA<EmailConsentRequiredException>()),
      );
      await expectLater(
        source.connect(),
        throwsA(isA<EmailConsentRequiredException>()),
      );
    });
  });
}

