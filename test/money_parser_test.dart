import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/utils/money_parser.dart';

void main() {
  test('converts exact decimal values to paise', () {
    expect(parseRupeesToPaise('239'), 23900);
    expect(parseRupeesToPaise('239.5'), 23950);
    expect(parseRupeesToPaise('239.50'), 23950);
    expect(parseRupeesToPaise('12,34,567.89'), 123456789);
  });

  test('formats paise without floating point', () {
    expect(formatPaise(23900), '239.00');
    expect(formatPaise(23950), '239.50');
    expect(formatPaise(23900, trimZeroPaise: true), '239');
  });

  test('rejects ambiguous or unsafe amounts', () {
    for (final value in ['1.234', '1.234,56', '-1', '']) {
      expect(
          () => parseRupeesToPaise(value), throwsA(isA<MoneyParseException>()));
    }
  });
}
