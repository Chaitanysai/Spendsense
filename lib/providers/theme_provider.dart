import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_colors.dart';
import '../utils/app_palette.dart';

/// Owns the user's appearance choices: the active [AppPalette], the light/dark/
/// system preference, and their persistence.
///
/// Selecting a palette calls [AppColors.applyPalette] *before* notifying, so
/// every listener that rebuilds afterwards reads the new token values.
class ThemeProvider with ChangeNotifier {
  static const _darkModeKey = 'dark_mode_enabled';
  static const _themeModeKey = 'theme_mode';
  static const _paletteKey = 'palette_id';

  bool _isDarkMode = false;
  bool _isLoaded = false;
  ThemeMode _themeMode = ThemeMode.light;
  AppPalette _palette = AppPalette.oceanBlue;

  bool get isDarkMode => _isDarkMode;
  bool get isLoaded => _isLoaded;
  AppPalette get palette => _palette;

  /// Resolved mode for [MaterialApp.themeMode]. `system` follows the platform,
  /// which is why [isDarkMode] is derived from [_themeMode] rather than stored
  /// independently.
  ThemeMode get themeMode => _themeMode;

  /// Effective brightness given [_themeMode]; `null` when deferring to the
  /// platform, in which case MaterialApp resolves it.
  bool? get isDark => _themeMode == ThemeMode.system ? null : _isDarkMode;

  ThemeProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // Legacy key: a bare bool written before appearance modes existed.
    _isDarkMode = prefs.getBool(_darkModeKey) ?? false;

    final storedMode = prefs.getString(_themeModeKey);
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == storedMode,
      orElse: () => _isDarkMode ? ThemeMode.dark : ThemeMode.light,
    );

    AppColors.applyPalette(AppPalette.byId(prefs.getString(_paletteKey)));
    _palette = AppColors.palette;

    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    // `system` defers to the platform, so it leaves the flag alone.
    if (mode == ThemeMode.dark) {
      _isDarkMode = true;
    } else if (mode == ThemeMode.light) {
      _isDarkMode = false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode.name);
    // Keep the legacy flag in sync so older code paths agree with the mode.
    await prefs.setBool(_darkModeKey, _isDarkMode);
    notifyListeners();
  }

  /// Legacy entry point kept for the existing Dark-mode switch. Writing an
  /// explicit light/dark mode clears any `system` setting.
  Future<void> setDarkMode(bool value) =>
      setThemeMode(value ? ThemeMode.dark : ThemeMode.light);

  Future<void> toggle() =>
      setThemeMode(_isDarkMode ? ThemeMode.light : ThemeMode.dark);

  Future<void> setPalette(AppPalette next) async {
    if (next.id == _palette.id) return;
    // Tokens first, then notify, so listeners rebuild against the new ramp.
    AppColors.applyPalette(next);
    _palette = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paletteKey, next.id);
    notifyListeners();
  }

  /// Restores Ocean Blue and the light appearance.
  Future<void> resetToDefaults() async {
    AppColors.applyPalette(AppPalette.oceanBlue);
    _palette = AppPalette.oceanBlue;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_paletteKey);
    await prefs.setString(_themeModeKey, ThemeMode.light.name);
    await prefs.setBool(_darkModeKey, false);
    _themeMode = ThemeMode.light;
    _isDarkMode = false;
    notifyListeners();
  }
}
