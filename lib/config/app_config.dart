import '../services/secure_storage_service.dart';

/// Central API-key accessor for SpendSense.
/// Priority: Secure Storage > --dart-define
///
/// API keys are never read from files bundled with the app: no secret material
/// ships inside the APK. Keys enter the app exclusively through --dart-define
/// at build/run time or through the in-app AI settings (secure storage).
abstract final class AppConfig {
  static final _secureStorage = SecureStorageService();

  // Legacy sync accessors (dart-define only; secure storage is async and cannot
  // be read from a sync getter)
  static String get groqKey => _readOptional('GROQ_API_KEY');
  static String get geminiKey => _readOptional('GEMINI_API_KEY');
  static String get openRouterKey => _readOptional('OPENROUTER_API_KEY');

  static bool get hasAnyAiProviderConfigured =>
      groqKeyOrEmpty.isNotEmpty ||
      geminiKeyOrEmpty.isNotEmpty ||
      openRouterKeyOrEmpty.isNotEmpty;

  static String get groqKeyOrEmpty => _readOptional('GROQ_API_KEY');
  static String get geminiKeyOrEmpty => _readOptional('GEMINI_API_KEY');
  static String get openRouterKeyOrEmpty => _readOptional('OPENROUTER_API_KEY');

  // Async accessors: secure storage first, then --dart-define
  static Future<String> getGroqKey() async =>
      await _resolveAsync('GROQ_API_KEY');
  static Future<String> getCerebrasKey() async =>
      await _resolveAsync('CEREBRAS_API_KEY');
  static Future<String> getGeminiKey() async =>
      await _resolveAsync('GEMINI_API_KEY');
  static Future<String> getOpenRouterKey() async =>
      await _resolveAsync('OPENROUTER_API_KEY');

  static Future<String> _resolveAsync(String key) async {
    // 1. Check secure storage first
    final fromSecure = await _secureStorage.getApiKey(key);
    if (fromSecure != null && fromSecure.isNotEmpty) return fromSecure;

    // 2. Fallback to --dart-define
    final value = _readOptional(key);
    if (value.isNotEmpty) return value;

    return '';
  }

  static String _readOptional(String key) => _dartDefine(key);

  static String _dartDefine(String key) {
    switch (key) {
      case 'GROQ_API_KEY':
        return const String.fromEnvironment('GROQ_API_KEY');
      case 'CEREBRAS_API_KEY':
        return const String.fromEnvironment('CEREBRAS_API_KEY');
      case 'GEMINI_API_KEY':
        return const String.fromEnvironment('GEMINI_API_KEY');
      case 'OPENROUTER_API_KEY':
        return const String.fromEnvironment('OPENROUTER_API_KEY');
      default:
        return '';
    }
  }
}
