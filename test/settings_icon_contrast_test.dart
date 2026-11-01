import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:spendsense/screens/settings_screen.dart';
import 'package:spendsense/utils/app_colors.dart';
import 'package:spendsense/utils/app_palette.dart';

/// Guards the Settings row glyphs.
///
/// Two failure modes are covered:
///  1. A role added to the screen but never audited. The registry on
///     [SettingsScreen] must list exactly the roles the file paints with.
///  2. A role that passes only because `inkOn` was skipped. Every tile role is
///     measured against the real tint in both themes for all 13 palettes.
double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

Color _role(String name, bool dark) {
  switch (name) {
    case 'brand':
      return AppColors.brand;
    case 'azure':
      return AppColors.azure;
    case 'brandBright':
      return AppColors.brandBright;
    case 'danger':
      return AppColors.danger;
    case 'warning':
      return AppColors.warning;
    case 'incomeGreen':
      return AppColors.incomeGreen;
    case 'textTertiary':
      // The one role that resolves per theme rather than per palette.
      return AppColors.textTertiaryFor(dark);
    default:
      throw ArgumentError('unaudited Settings tile role: $name');
  }
}

void main() {
  test('the registry matches the roles the screen actually uses', () {
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();
    // Strip comments first: this file's own doc comment shows the
    // `iconColor: AppColors.x` pattern as an example, and a naive scan would
    // read that as a real role.
    final code = source
        .replaceAll(RegExp(r'//[^\n]*'), '')
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final used = RegExp(r'iconColor:\s*AppColors\.(\w+)')
        .allMatches(code)
        .map((m) => m.group(1)!)
        .toSet();
    expect(
      used.difference(SettingsScreen.tileRoles.toSet()),
      isEmpty,
      reason: 'a Settings tile painted a role that is not in tileRoles — '
          'audit its contrast and add it',
    );
  });

  test('every tile role clears AA on its own tint in every palette/theme', () {
    final failures = <String>[];
    var min = 99.0;
    for (final dark in [false, true]) {
      for (final palette in AppPalette.all) {
        AppColors.applyPalette(palette);
        final base = dark ? AppColors.darkSurfaceAlt : AppColors.surface;
        for (final name in SettingsScreen.tileRoles) {
          final tint = _role(name, dark);
          final well = tint.withValues(alpha: dark ? 0.22 : 0.12);
          final blended = Color.alphaBlend(well, base);
          final ink = AppColors.inkOn(tint, well, base);
          final ratio = _contrast(ink, blended);
          if (ratio < min) min = ratio;
          if (ratio < 4.5) {
            failures.add('${dark ? "dark" : "light"}/${palette.id}/$name '
                '${ratio.toStringAsFixed(2)}');
          }
        }
      }
    }
    // ignore: avoid_print
    print('Settings tile glyph minimum contrast: ${min.toStringAsFixed(2)}:1');
    expect(failures, isEmpty);
  });
}
