import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/utils/app_text_styles.dart';
import 'package:spendsense/utils/app_typography.dart';

/// Regression cover for the variable-font weight trap.
///
/// Once Inter became the default preset, the rendered weight of a glyph comes
/// from the `wght` font variation baked in when the style was built. Dart's
/// `TextStyle.copyWith(fontWeight:)` changes only the reported weight, so text
/// that asked for bold kept rendering at the base weight — a silent, app-wide
/// loss of typographic hierarchy that no widget test would notice, because
/// `fontWeight` still reported the requested value.
void main() {
  test('copyWith alone leaves the variable axis behind (the trap)', () {
    final base = AppTypography.styleFor(
      'Inter',
      fontSize: 14,
      fontWeight: FontWeight.w400,
    );
    final naive = base.copyWith(fontWeight: FontWeight.w700);
    expect(naive.fontWeight, FontWeight.w700);
    expect(
      naive.fontVariations?.first.value,
      400,
      reason: 'documents why AppText.weight exists',
    );
  });

  test('AppText.weight moves the reported weight and the axis together', () {
    final bold = AppText.weight(
      AppTypography.styleFor('Inter',
          fontSize: 14, fontWeight: FontWeight.w400),
      FontWeight.w700,
    );
    expect(bold.fontWeight, FontWeight.w700);
    expect(bold.fontVariations?.first.axis, 'wght');
    expect(bold.fontVariations?.first.value, 700);
  });

  test('a static family gets no variation, so it is not affected', () {
    final bold = AppText.weight(
      AppTypography.styleFor(
        'Poppins',
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      FontWeight.w700,
    );
    expect(bold.fontWeight, FontWeight.w700);
    expect(
      bold.fontVariations,
      isNull,
      reason: 'Poppins ships static weight files; a wght axis would be wrong',
    );
  });

  test('every variable family reports itself as variable', () {
    for (final family in AppTypography.variableFamilies) {
      expect(AppTypography.isVariable(family), isTrue, reason: family);
    }
    expect(AppTypography.isVariable('Poppins'), isFalse);
    expect(AppTypography.isVariable(null), isFalse);
  });
}
