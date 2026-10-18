import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/services/gemini_service.dart';

/// Regression tests for the SpendSense 2.0 privacy mandate: sensitive banking
/// data (OTP, PIN, CVV, card/account numbers) must be redacted before any SMS
/// text is handed to a cloud LLM provider.
void main() {
  group('GeminiService.sanitizeSms', () {
    final service = GeminiService();

    test('masks 4-6 digit OTP tokens', () {
      expect(service.sanitizeSms('OTP is 456789'), 'OTP is ***');
      expect(service.sanitizeSms('use 1234 to verify'), 'use *** to verify');
    });

    test('masks full card/account numbers but keeps the last four digits', () {
      expect(
        service.sanitizeSms('card 4111111111111234 used'),
        'card ****1234 used',
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
  });
}
