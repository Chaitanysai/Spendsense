import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendsense/services/ai_sms_consent.dart';
import 'package:spendsense/services/gemini_service.dart';

/// Regression tests for the SMS cloud-parsing privacy boundary: identifiers
/// must be redacted, and no SMS text may be sent without explicit consent.
void main() {
  group('GeminiService.sanitizeSms', () {
    final service = GeminiService();

    test('masks 4-8 digit OTP tokens', () {
      expect(service.sanitizeSms('OTP is 456789'), 'OTP is ***');
      expect(service.sanitizeSms('OTP is 12345678'), 'OTP is ***');
      expect(service.sanitizeSms('use 1234 to verify'), 'use *** to verify');
    });

    test('masks full card/account numbers but keeps the last four digits', () {
      expect(
        service.sanitizeSms('card 4111111111111234 used'),
        'card ****1234 used',
      );
      expect(
        service.sanitizeSms('card 4111 1111 1111 1234 used'),
        'card ****1234 used',
      );
    });

    test('masks nine- and seventeen-digit account numbers', () {
      expect(service.sanitizeSms('acct 123456789'), 'acct ***');
      expect(
        service.sanitizeSms('acct 12345678901234567'),
        'acct ****4567',
      );
    });

    test('masks UPI, IFSC and explicit references', () {
      expect(
        service.sanitizeSms('paid to alice@okhdfcbank'),
        'paid to ***@***',
      );
      expect(
        service.sanitizeSms('IFSC HDFC0001234 used'),
        'IFSC IFSC *** used',
      );
      expect(
        service.sanitizeSms('UTR: ABC123XYZ'),
        'UTR ***',
      );
    });

    test('masks CVV/PIN values', () {
      expect(service.sanitizeSms('cvv 123'), 'cvv: ***');
      expect(service.sanitizeSms('PIN 123'), 'cvv: ***');
    });

    test('leaves ordinary debit amounts and merchants untouched', () {
      const sms = 'Rs 250 debited via UPI to ABC STORE';
      expect(service.sanitizeSms(sms), sms);
    });

    test('preserves currency-prefixed amounts of any length', () {
      expect(
        service.sanitizeSms('Rs 2500 debited at ABC STORE'),
        'Rs 2500 debited at ABC STORE',
      );
      expect(
        service.sanitizeSms('Rs 1234567 debited at ABC STORE'),
        'Rs 1234567 debited at ABC STORE',
      );
      expect(
        service.sanitizeSms('INR 12,500.50 debited at ABC STORE'),
        'INR 12,500.50 debited at ABC STORE',
      );
      // The amount survives, but a bare account number in the same message
      // is still redacted.
      expect(
        service.sanitizeSms('Rs 2500 debited from A/C 1234567890123456'),
        'Rs 2500 debited from A/C ****3456',
      );
    });
  });

  group('AI SMS consent', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('cloud SMS parsing is off by default', () async {
      expect(await const AiSmsConsentStore().hasConsent(), isFalse);
    });

    test('consent is explicit and persisted', () async {
      const store = AiSmsConsentStore();
      await store.setConsent(true);
      expect(await store.hasConsent(), isTrue);
    });
  });
}
