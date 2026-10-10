import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Central API-key accessor for SpendSense.
abstract final class AppConfig {
  static String get groqKey => _resolve('GROQ_API_KEY');
  static String get geminiKey => _resolve('GEMINI_API_KEY');
  static String get openRouterKey => _resolve('OPENROUTER_API_KEY');

  static bool get hasAnyAiProviderConfigured =>
      groqKeyOrEmpty.isNotEmpty ||
      geminiKeyOrEmpty.isNotEmpty ||
      openRouterKeyOrEmpty.isNotEmpty;

  static String get groqKeyOrEmpty => _readOptional('GROQ_API_KEY');
  static String get geminiKeyOrEmpty => _readOptional('GEMINI_API_KEY');
  static String get openRouterKeyOrEmpty => _readOptional('OPENROUTER_API_KEY');

  static String _resolve(String key) {
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
      case 'GEMINI_API_KEY':
        return const String.fromEnvironment('GEMINI_API_KEY');
      case 'OPENROUTER_API_KEY':
        return const String.fromEnvironment('OPENROUTER_API_KEY');
      default:
        return '';
    }
  }
}
