import 'package:flutter_test/flutter_test.dart';
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

    test('rejects a missing or malformed address', () {
      expect(GmailEmailSource.isAllowedSender('', domains), isFalse);
      expect(GmailEmailSource.isAllowedSender('alerts@', domains), isFalse);
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

    test('consent flag persists but no token is written', () async {
      final source = GmailEmailSource();
      await source.setConsent(true);
      expect(await source.hasConsent(), isTrue);
      await source.setConsent(false);
      expect(await source.hasConsent(), isFalse);
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

