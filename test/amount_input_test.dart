
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/utils/money_parser.dart';

void main() {
  group('AmountInputFormatter', () {
    const formatter = AmountInputFormatter();

    TextEditingValue fmt(String oldT, String newT, {int oldBase = 0, int newBase = 0}) {
      return formatter.formatEditUpdate(
        TextEditingValue(text: oldT, selection: TextSelection.collapsed(offset: oldBase == 0 ? oldT.length : oldBase)),
        TextEditingValue(text: newT, selection: TextSelection.collapsed(offset: newBase == 0 ? newT.length : newBase)),
      );
    }

    test('allows single dot and two fractional digits', () {
      expect(fmt('', '12').text, '12');
      expect(fmt('12', '12.').text, '12.');
      expect(fmt('12.', '12.3').text, '12.3');
      expect(fmt('12.3', '12.34').text, '12.34');
    });

    test('rejects second dot', () {
      expect(fmt('12.3', '12.3.').text, '12.3');
      expect(fmt('12.3', '12..3').text, '12.3');
      expect(fmt('12.34', '12.34.').text, '12.34');
    });

    test('rejects third fractional digit', () {
      expect(fmt('12.34', '12.345').text, '12.34');
      expect(fmt('0.99', '0.999').text, '0.99');
    });

    test('allows normal editing: insertion, deletion, paste replacement', () {
      // deletion
      expect(fmt('12.34', '12.3').text, '12.3');
      expect(fmt('12.34', '').text, '');
      // insertion at start
      expect(fmt('2.34', '12.34').text, '12.34');
      // pasted valid
      expect(fmt('', '1234.56').text, '1234.56');
      // pasted invalid (second dot) rejected
      expect(fmt('12.34', '12.34.56').text, '12.34');
    });

    test('empty and lone dot are allowed transiently', () {
      expect(fmt('1', '').text, '');
      expect(fmt('', '.').text, '.');
      expect(fmt('.', '.5').text, '.5');
    });

    test('rejects letters and extra symbols', () {
      expect(fmt('12', '12a').text, '12');
      expect(fmt('12', '12,').text, '12');
      expect(fmt('', '12-').text, '');
    });

    test('parser semantics stay intact via parseRupeesToPaise', () {
      expect(parseRupeesToPaise('0'), 0);
      expect(parseRupeesToPaise('12'), 1200);
      expect(parseRupeesToPaise('12.3'), 1230);
      expect(parseRupeesToPaise('12.34'), 1234);
      expect(parseRupeesToPaise('12.00'), 1200);
      // Multiple dots must be rejected by the parser even if formatter slipped
      expect(() => parseRupeesToPaise('12..3'), throwsA(isA<MoneyParseException>()));
      expect(() => parseRupeesToPaise('12.345'), throwsA(isA<MoneyParseException>()));
      expect(() => parseRupeesToPaise(''), throwsA(isA<MoneyParseException>()));
    });
  });
}
