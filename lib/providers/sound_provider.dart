import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/sound_service.dart';

/// Owns the user's sound-effect preferences and their persistence, and is the
/// single object the UI talks to.
///
/// Deliberately built on the same [ChangeNotifier] + [SharedPreferences] pattern
/// as `ThemeProvider` and `TransactionProvider`, so no new state-management
/// concept enters the codebase.
class SoundProvider extends ChangeNotifier with WidgetsBindingObserver {
  SoundProvider({SoundService? service, bool observeLifecycle = true})
      : _service = service ?? SoundService(),
        _observeLifecycle = observeLifecycle {
    initialized = _restore();
  }

  /// Completes once stored preferences have been read and the cues preloaded.
  ///
  /// Exposed so tests (and anything that truly needs to wait) can synchronise
  /// instead of guessing at delays.
  late final Future<void> initialized;

  static const String masterKey = 'sound_master_enabled';
  static const String uiKey = 'sound_ui_enabled';
  static const String transactionsKey = 'sound_transactions_enabled';

  final SoundService _service;
  final bool _observeLifecycle;

  SoundPreferences _prefs = SoundPreferences.defaults;
  bool _restored = false;

  SoundPreferences get prefs => _prefs;
  bool get masterEnabled => _prefs.masterEnabled;
  bool get uiEnabled => _prefs.uiEnabled;
  bool get transactionsEnabled => _prefs.transactionsEnabled;

  /// Whether stored values have been read (or reading has failed).
  bool get isRestored => _restored;

  /// The service underneath — exposed so tests can inspect what was loaded.
  SoundService get service => _service;

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = SoundPreferences(
        masterEnabled:
            prefs.getBool(masterKey) ?? SoundPreferences.defaults.masterEnabled,
        uiEnabled: prefs.getBool(uiKey) ?? SoundPreferences.defaults.uiEnabled,
        transactionsEnabled: prefs.getBool(transactionsKey) ??
            SoundPreferences.defaults.transactionsEnabled,
      );
    } catch (error) {
      // Storage unavailable: the in-memory defaults stand. Sound must never be
      // able to break startup.
      debugPrint('SoundProvider: could not restore preferences — $error');
    }
    _restored = true;
    if (_observeLifecycle) {
      try {
        WidgetsBinding.instance.addObserver(this);
      } catch (_) {
        // No binding (plain unit test) — lifecycle handling is simply skipped.
      }
    }
    notifyListeners();

    // Preload after restoring so the first interaction is not silent.
    await _service.init();
  }

  /// Plays [event] under the current preferences.
  ///
  /// Returns a future for tests and for call sites that care; the UI uses
  /// `SoundScope.play`, which deliberately ignores it.
  Future<void> play(SoundEventType event) => _service.play(event, _prefs);

  Future<void> setMasterEnabled(bool value) =>
      _update(_prefs.copyWith(masterEnabled: value), masterKey, value);

  Future<void> setUiEnabled(bool value) =>
      _update(_prefs.copyWith(uiEnabled: value), uiKey, value);

  Future<void> setTransactionsEnabled(bool value) => _update(
        _prefs.copyWith(transactionsEnabled: value),
        transactionsKey,
        value,
      );

  Future<void> _update(SoundPreferences next, String key, bool value) async {
    if (next == _prefs) return;
    // Apply in memory and notify *before* touching storage, so a mute takes
    // effect on the very next interaction.
    _prefs = next;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error) {
      debugPrint('SoundProvider: could not persist $key — $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_service.handleLifecycle(state));
  }

  @override
  void dispose() {
    if (_observeLifecycle) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {
        // Ignore: nothing was registered.
      }
    }
    unawaited(_service.dispose());
    super.dispose();
  }
}
