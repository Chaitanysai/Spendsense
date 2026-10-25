import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Build-time backend endpoint. This is a URL, never an API key.
abstract final class AssistantConfig {
  static const String proxyUrl =
      String.fromEnvironment('SPENDSENSE_AI_PROXY_URL');

  /// HTTPS is required. The only HTTP exception is a loopback development
  /// endpoint used by unit tests; nothing here ever reads a Gemini key.
  static bool isValidProxy(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    final loopback = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '10.0.2.2';
    return uri.scheme == 'http' && loopback;
  }

  static bool get isCloudConfigured =>
      proxyUrl.trim().isNotEmpty && isValidProxy(proxyUrl);
}

abstract interface class AssistantConsentStore {
  Future<bool> hasCloudConsent();

  Future<void> setCloudConsent(bool allowed);
}

/// Consent is local-only and defaults to OFF. Local deterministic commands work
/// without it.
class PreferencesAssistantConsentStore implements AssistantConsentStore {
  static const prefsKey = 'assistant_cloud_consent_v1';

  @override
  Future<bool> hasCloudConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  @override
  Future<void> setCloudConsent(bool allowed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, allowed);
  }
}

/// The exact context categories the app may send when cloud assistance is
/// enabled. Kept in one place so the UI and docs cannot drift.
abstract final class AssistantPrivacy {
  static const String summary =
      'When cloud assistance is on, SpendSense sends your typed question, a '
      'short recent chat transcript, and only the tool results needed for that '
      'question (merchant, date, category, amount, type and count).';

  static const List<String> sent = [
    'Your current question and up to 8 recent chat text turns',
    'Only the matching rows requested by the assistant (merchant, date, category, amount, type, excluded flag)',
    'Totals and date ranges computed locally from those rows',
    'Tool names and validated arguments, so Gemini can ask for a follow-up query',
    'A short-lived Firebase App Check token proving this is a genuine SpendSense installation',
    'A short-lived Firebase sign-in ID token used only by the SpendSense backend to authenticate your account',
  ];

  static const List<String> neverSent = [
    'Raw SMS bodies or OTPs',
    'Account numbers, card numbers, UPI IDs or references',
    'Encryption keys, API keys or credentials',
    'Your complete transaction history',
    'Bill payment history unrelated to the question',
  ];

  static String jsonSummary() =>
      jsonEncode({'sent': sent, 'neverSent': neverSent});
}
