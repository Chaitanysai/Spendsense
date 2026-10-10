import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage service for API keys and sensitive configuration.
/// Uses platform-specific encryption (Keychain on iOS, EncryptedSharedPreferences on Android).
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // Key constants
  static const String _keyGroq = 'GROQ_API_KEY';
  static const String _keyCerebras = 'CEREBRAS_API_KEY';
  static const String _keyOpenRouter = 'OPENROUTER_API_KEY';
  static const String _keyGemini = 'GEMINI_API_KEY';

  /// Retrieves an API key by name. Returns null if not set.
  Future<String?> getApiKey(String keyName) async {
    try {
      return await _storage.read(key: keyName);
    } catch (e) {
      return null;
    }
  }

  /// Stores an API key securely. Returns true on success.
  Future<bool> setApiKey(String keyName, String value) async {
    try {
      if (value.trim().isEmpty) {
        await deleteApiKey(keyName);
        return true;
      }
      await _storage.write(key: keyName, value: value.trim());
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Deletes a specific API key.
  Future<void> deleteApiKey(String keyName) async {
    try {
      await _storage.delete(key: keyName);
    } catch (_) {}
  }

  /// Clears all stored API keys.
  Future<void> clearAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }

  // Convenience getters for specific providers
  Future<String?> getGroqKey() => getApiKey(_keyGroq);
  Future<String?> getCerebrasKey() => getApiKey(_keyCerebras);
  Future<String?> getOpenRouterKey() => getApiKey(_keyOpenRouter);
  Future<String?> getGeminiKey() => getApiKey(_keyGemini);

  // Convenience setters
  Future<bool> setGroqKey(String value) => setApiKey(_keyGroq, value);
  Future<bool> setCerebrasKey(String value) => setApiKey(_keyCerebras, value);
  Future<bool> setOpenRouterKey(String value) =>
      setApiKey(_keyOpenRouter, value);
  Future<bool> setGeminiKey(String value) => setApiKey(_keyGemini, value);

  // Key names for UI
  static const String groqKeyName = _keyGroq;
  static const String cerebrasKeyName = _keyCerebras;
  static const String openRouterKeyName = _keyOpenRouter;
  static const String geminiKeyName = _keyGemini;
}
