import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoggedIn = true; // Default to logged in for SpendSense 2.0 offline-first
  String _name = "SpendSense User";
  String _email = "user@spendsense.local";
  String? _profileImageBase64;

  bool get isLoggedIn => _isLoggedIn;
  String get name => _name;
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
    _name = prefs.getString('name') ?? "SpendSense User";
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
    _name = "Guest";
    _email = "";
    _profileImageBase64 = null;

    notifyListeners();
  }
}
