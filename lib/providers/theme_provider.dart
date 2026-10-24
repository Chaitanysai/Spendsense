import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_colors.dart';
import '../utils/app_palette.dart';
import '../utils/app_typography.dart';
import '../utils/dashboard_sections.dart';

/// Owns the user's appearance choices: the active [AppPalette], the light/dark/
/// system preference, and their persistence.
///
/// Selecting a palette calls [AppColors.applyPalette] *before* notifying, so
/// every listener that rebuilds afterwards reads the new token values.
class ThemeProvider with ChangeNotifier {
  static const _darkModeKey = 'dark_mode_enabled';
  static const _themeModeKey = 'theme_mode';
  static const _paletteKey = 'palette_id';
  static const _fontPresetKey = 'font_preset_id';
  static const _fontScaleKey = 'font_scale';
  static const _hiddenSectionsKey = 'dashboard_hidden_sections';
  static const _sectionOrderKey = 'dashboard_section_order';

  bool _isDarkMode = false;
  bool _isLoaded = false;
  ThemeMode _themeMode = ThemeMode.light;
  AppPalette _palette = AppPalette.defaultPalette;
  FontPreset _fontPreset = FontPreset.standard;
  double _fontScale = FontScale.standard;
  Set<String> _hiddenSections = const {};
  List<String> _sectionOrder = DashboardSection.ids;

  bool get isDarkMode => _isDarkMode;
  bool get isLoaded => _isLoaded;
  AppPalette get palette => _palette;
  FontPreset get fontPreset => _fontPreset;

  /// User multiplier applied on top of the system text scale.
  double get fontScale => _fontScale;

  /// Dashboard section ids the user has hidden (see [DashboardSection]).
  Set<String> get hiddenSections => _hiddenSections;
  bool isSectionVisible(String id) => !_hiddenSections.contains(id);

  /// Complete saved order of every known section, hidden ones included.
  List<String> get sectionOrder => List.unmodifiable(_sectionOrder);

  /// Sections to draw, in the saved order, without the hidden ones.
  List<String> get visibleSectionOrder =>
      DashboardSection.visibleInOrder(_sectionOrder, _hiddenSections);

  /// Saves a new order. Unknown ids are dropped and missing ones appended, so a
  /// partial or stale list can never lose a section. Visibility is untouched.
  Future<void> setSectionOrder(List<String> order) async {
    final next = DashboardSection.normalizeOrder(order);
    if (_listEquals(next, _sectionOrder)) return;
    _sectionOrder = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_sectionOrderKey, next);
    notifyListeners();
  }

  Future<void> resetSectionOrder() async {
    _sectionOrder = DashboardSection.ids;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sectionOrderKey);
    notifyListeners();
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

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

    // Unknown / missing values fall back to the defaults rather than failing.
    _fontPreset = FontPreset.byId(prefs.getString(_fontPresetKey));
    AppTypography.active = _fontPreset;
    _fontScale = FontScale.sanitize(prefs.getDouble(_fontScaleKey));
    _hiddenSections = (prefs.getStringList(_hiddenSectionsKey) ?? const [])
        .where(DashboardSection.ids.contains)
        .toSet();
    // A malformed value (wrong type) throws from getStringList; treat it as
    // "nothing saved" rather than failing startup.
    Object? storedOrder;
    try {
      storedOrder = prefs.getStringList(_sectionOrderKey);
    } catch (_) {
      storedOrder = null;
    }
    _sectionOrder = DashboardSection.normalizeOrder(storedOrder);

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

  /// Selects a font preset. Typography is purely visual: it never touches the
  /// ledger, its encryption, or any money value.
  Future<void> setFontPreset(FontPreset next) async {
    if (next.id == _fontPreset.id) return;
    AppTypography.active = next;
    _fontPreset = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fontPresetKey, next.id);
    notifyListeners();
  }

  Future<void> setFontScale(double value) async {
    final next = FontScale.sanitize(value);
    if (next == _fontScale) return;
    _fontScale = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, next);
    notifyListeners();
  }

  /// One-tap return to the default face and the default scale.
  Future<void> resetTypography() async {
    AppTypography.active = FontPreset.standard;
    _fontPreset = FontPreset.standard;
    _fontScale = FontScale.standard;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_fontPresetKey);
    await prefs.remove(_fontScaleKey);
    notifyListeners();
  }

  Future<void> setSectionVisible(String id, bool visible) async {
    if (!DashboardSection.ids.contains(id)) return;
    final next = {..._hiddenSections};
    visible ? next.remove(id) : next.add(id);
    if (next.length == _hiddenSections.length &&
        next.containsAll(_hiddenSections)) {
      return;
    }
    _hiddenSections = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenSectionsKey, next.toList()..sort());
    notifyListeners();
  }

  /// Restores Emerald and the light appearance.
  Future<void> resetToDefaults() async {
    AppColors.applyPalette(AppPalette.defaultPalette);
    _palette = AppPalette.defaultPalette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_paletteKey);
    await prefs.setString(_themeModeKey, ThemeMode.light.name);
    await prefs.setBool(_darkModeKey, false);
    _themeMode = ThemeMode.light;
    _isDarkMode = false;
    notifyListeners();
  }
}
