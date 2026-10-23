import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  /// Neutral placeholder shown when the user has not set a personal name. It is
  /// never used as a greeting name.
  static const String defaultName = 'SpendSense User';
  static const String guestName = 'Guest';

  bool _isLoggedIn =
      true; // Default to logged in for SpendSense 2.0 offline-first
  String _name = defaultName;
  String _email = "user@spendsense.local";
  String? _profileImageBase64;

  bool get isLoggedIn => _isLoggedIn;

  /// Profile name: the trimmed stored value, or [defaultName] when the user has
  /// not set (or has cleared) a name.
  String get name {
    final trimmed = _name.trim();
    return trimmed.isEmpty ? defaultName : trimmed;
  }

  /// Name suitable for a personalised greeting, or '' when no personal name is
  /// set — letting callers omit the suffix instead of printing "User".
  String get greetingName {
    final trimmed = _name.trim();
    if (trimmed.isEmpty || trimmed == defaultName || trimmed == guestName) {
      return '';
    }
    return trimmed;
  }

  String get email => _email;
  String? get profileImageBase64 => _profileImageBase64;
  bool get hasProfileImage =>
      _profileImageBase64 != null && _profileImageBase64!.isNotEmpty;
  Uint8List? get profileImageBytes =>
      hasProfileImage ? base64Decode(_profileImageBase64!) : null;

  AuthProvider() {
    loadUser();
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('loggedIn') ?? true;
    _name = prefs.getString('name') ?? defaultName;
    _email = prefs.getString('email') ?? "user@spendsense.local";
    _profileImageBase64 = prefs.getString('profileImageBase64');
    notifyListeners();
  }

  Future<void> login(
    String name,
    String email, {
    String? profileImageBase64,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', true);
    await prefs.setString('name', name);
    await prefs.setString('email', email);
    if (profileImageBase64 != null && profileImageBase64.isNotEmpty) {
      await prefs.setString('profileImageBase64', profileImageBase64);
    }

    _isLoggedIn = true;
    _name = name;
    _email = email;
    if (profileImageBase64 != null) {
      _profileImageBase64 = profileImageBase64;
    }

    notifyListeners();
  }

  /// Saves the user's preferred display name. An empty value clears it back to
  /// the neutral placeholder; the greeting then drops the name suffix.
  Future<void> updateName(String value) async {
    final trimmed = value.trim();
    _name = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', trimmed);
    notifyListeners();
  }

  Future<void> updateProfileImage(String? base64Image) async {
    final prefs = await SharedPreferences.getInstance();
    if (base64Image == null || base64Image.isEmpty) {
      await prefs.remove('profileImageBase64');
      _profileImageBase64 = null;
    } else {
      await prefs.setString('profileImageBase64', base64Image);
      _profileImageBase64 = base64Image;
    }
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', false);

    _isLoggedIn = false;
    _name = guestName;
    _email = "";
    _profileImageBase64 = null;

    notifyListeners();
  }
}
