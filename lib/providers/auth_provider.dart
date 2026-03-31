import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoggedIn = false;
  String _name = "";
  String _email = "";

  bool get isLoggedIn => _isLoggedIn;
  String get name => _name;
  String get email => _email;

  AuthProvider() {
    loadUser();
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('loggedIn') ?? false;
    _name = prefs.getString('name') ?? "";
    _email = prefs.getString('email') ?? "";
    notifyListeners();
  }

  Future<void> login(String name, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('loggedIn', true);
    await prefs.setString('name', name);
    await prefs.setString('email', email);

    _isLoggedIn = true;
    _name = name;
    _email = email;

    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    _isLoggedIn = false;
    _name = "";
    _email = "";

    notifyListeners();
  }
}
