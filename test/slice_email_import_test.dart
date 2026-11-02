import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spendsense/models/transaction_model.dart';
import 'package:spendsense/services/email/gmail_email_source.dart';
import 'package:spendsense/services/smart_parser.dart';

/// Regression cover for a real bank email that never imported.
///
/// The mobile capture (from Slice, `noreply@slice.bank.in`):
///
///   Hi KANDULA,
///   ₹100 was debited from your slice bank account ending in 3317 via UPI.
///   Transaction date 01-Nov-26
///   To  K Venkata Ravi Prasad
///
/// Three separate defects stopped this reaching the ledger, and each one alone
/// was enough to drop it silently.
void main() {
  const from = 'slice <noreply@slice.bank.in>';
  const body = 'Hi KANDULA, \u20B9100 was debited from your slice bank account '
      'ending in 3317 via UPI. Transaction date 01-Nov-26 '
      'To K Venkata Ravi Prasad';
  final when = DateTime(2026, 11, 1, 10, 24);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Slice sender allowlist', () {
    test('the real sender domain is a default, so it works untouched', () async {
      final domains = await GmailEmailSource().senderDomains();
      expect(domains, contains('slice.bank.in'));
      expect(GmailEmailSource.isAllowedSender(from, domains), isTrue);
    });

    test('a look-alike Slice domain is still refused', () async {
      final domains = await GmailEmailSource().senderDomains();
      expect(
        GmailEmailSource.isAllowedSender('slice <x@evil.slice.bank.in>', domains),
        isFalse,
      );
    });

    test('the subject of the real alert passes the filter', () {
      expect(
        GmailEmailSource.isDebitSubject('slice Bank Transaction Notification'),
        isTrue,
      );
    });
  });

  group('passive-voice debits', () {
    // The amount matcher accepted "has been debited" but not "was debited",
    // which is the wording Slice actually uses — so the debit was recognised
    // while the amount came back null.
    for (final phrase in [
      'Rs 100 was debited from your account',
      '\u20B9100 was debited from your account',
      'Rs 100 is debited',
      'Rs 100 got debited',
      'Rs 100 have been debited',
      'Rs 100 has been debited',
    ]) {
      test('amount is read from "$phrase"', () {
        expect(SmartParser().extractDebitAmountMinor(phrase), 10000);
      });
    }
  });

  group('the whole Slice message', () {
    test('imports as a 100 rupee UPI expense', () async {
      final tx = await SmartParser().parse(body, 'slice', when);
      expect(tx, isNotNull);
      expect(tx!.amountMinor, 10000);
      expect(tx.type, TransactionType.expense);
      expect(tx.paymentMethod, 'UPI');
    });

    test('the payee is recorded, not the bank', () async {
      final tx = await SmartParser().parse(body, 'slice', when);
      expect(tx!.merchant, 'K Venkata Ravi Prasad');
      expect(
        tx.category,
        'Transfer',
        reason: 'a person-to-person transfer, not a phone bill',
      );
    });
  });

  group('short category keywords match whole words only', () {
    // "vi" (the telecom) is a keyword. As a substring it matched inside "via"
    // and inside the payee "K Venkata Ravi Prasad", so UPI transfers were
    // categorised as Bills.
    test('"via UPI" is not the Vi telecom brand', () {
      expect(
        SmartParser().detectMerchant('Rs 100 debited via UPI to Swiggy'),
        'Swiggy',
      );
    });

    test('a name containing "vi" is not a phone bill', () {
      expect(
        SmartParser().detectCategory('Rs 100 debited to K Venkata Ravi Prasad'),
        isNot('Bills'),
      );
    });

    test('a real Vi recharge still resolves to Vi', () {
      expect(SmartParser().detectMerchant('Rs 399 paid to vi recharge'), 'Vi');
      expect(
        SmartParser().detectCategory('Rs 399 paid to vi recharge', 'Vi'),
        'Bills',
      );
    });
  });
}
