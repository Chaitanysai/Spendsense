import 'package:shared_preferences/shared_preferences.dart';

/// Explicit consent for sending ambiguous bank SMS text to a third-party AI
/// provider.
///
/// Off by default. The keys in AI Provider Settings only authenticate a
/// provider; they do not imply consent to share message text. Without this
/// switch the local parser remains the only SMS parser.
class AiSmsConsentStore {
  static const prefsKey = 'ai_sms_cloud_consent_v1';

  const AiSmsConsentStore();

  Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsKey) ?? false;
  }

  Future<void> setConsent(bool allowed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefsKey, allowed);
  }
}
