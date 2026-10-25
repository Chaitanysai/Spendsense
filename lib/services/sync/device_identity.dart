import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// A random identifier for this installation, used only to break ties when two
/// devices change the same record at the same millisecond.
///
/// It is not an account identifier, is never shown to the user, and is stored
/// in plain preferences because it carries no personal information.
abstract final class DeviceIdentity {
  static const String _key = 'sync_device_id';

  static String? _cached;

  static Future<String> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored != null && stored.length >= 16) {
        _cached = stored;
        return stored;
      }
      final created = _randomHex();
      await prefs.setString(_key, created);
      _cached = created;
      return created;
    } catch (_) {
      // No backing store (tests, previews): a per-process id still gives the
      // tie-break a stable value for this session.
      final created = _randomHex();
      _cached = created;
      return created;
    }
  }

  static String _randomHex() {
    final random = Random.secure();
    return List<String>.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }
}
