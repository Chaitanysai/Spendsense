import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/secure_storage_service.dart';

/// Central API-key accessor for SpendSense.
/// Priority: Secure Storage > .env > --dart-define
abstract final class AppConfig {
  static final _secureStorage = SecureStorageService();

  // Legacy sync accessors (for backward compatibility, loads from .env/dart-define only)
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

  // New async accessors (checks secure storage first, then falls back to .env/dart-define)
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

    // 2. Fallback to .env/dart-define
    final value = _readOptional(key);
    if (value.isNotEmpty) return value;

    return '';
  }

  static String _readOptional(String key) {
    final compiletime = _dartDefine(key);
    if (compiletime.isNotEmpty) return compiletime;
    try {
      return dotenv.maybeGet(key) ?? '';
    } catch (_) {
      return '';
    }
  }

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
