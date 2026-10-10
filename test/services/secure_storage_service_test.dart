import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spendsense/services/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureStorageService', () {
    late SecureStorageService service;

    setUp(() {
      service = SecureStorageService();
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('getApiKey returns null when key does not exist', () async {
      final result = await service.getApiKey('NON_EXISTENT_KEY');
      expect(result, isNull);
    });

    test('setApiKey stores and retrieves a key successfully', () async {
      const testKey = 'TEST_KEY';
      const testValue = 'test_api_key_value';

      final setResult = await service.setApiKey(testKey, testValue);
      expect(setResult, isTrue);

      final getValue = await service.getApiKey(testKey);
      expect(getValue, equals(testValue));
    });

    test('setApiKey trims whitespace before storing', () async {
      const testKey = 'TEST_KEY';
      const testValue = '  test_api_key_value  ';

      await service.setApiKey(testKey, testValue);

      final getValue = await service.getApiKey(testKey);
      expect(getValue, equals('test_api_key_value'));
    });

    test('setApiKey deletes key when empty value provided', () async {
      const testKey = 'TEST_KEY';

      await service.setApiKey(testKey, 'initial_value');
      expect(await service.getApiKey(testKey), equals('initial_value'));

      await service.setApiKey(testKey, '');
      expect(await service.getApiKey(testKey), isNull);
    });

    test('deleteApiKey removes stored key', () async {
      const testKey = 'TEST_KEY';
      const testValue = 'test_value';

      await service.setApiKey(testKey, testValue);
      expect(await service.getApiKey(testKey), equals(testValue));

      await service.deleteApiKey(testKey);
      expect(await service.getApiKey(testKey), isNull);
    });

    test('clearAll removes all stored keys', () async {
      await service.setApiKey('KEY1', 'value1');
      await service.setApiKey('KEY2', 'value2');
      await service.setApiKey('KEY3', 'value3');

      expect(await service.getApiKey('KEY1'), equals('value1'));
      expect(await service.getApiKey('KEY2'), equals('value2'));

      await service.clearAll();

      expect(await service.getApiKey('KEY1'), isNull);
      expect(await service.getApiKey('KEY2'), isNull);
      expect(await service.getApiKey('KEY3'), isNull);
    });

    test('convenience getters retrieve correct keys', () async {
      await service.setGroqKey('groq_key');
      await service.setCerebrasKey('cerebras_key');
      await service.setGeminiKey('gemini_key');
      await service.setOpenRouterKey('openrouter_key');

      expect(await service.getGroqKey(), equals('groq_key'));
      expect(await service.getCerebrasKey(), equals('cerebras_key'));
      expect(await service.getGeminiKey(), equals('gemini_key'));
      expect(await service.getOpenRouterKey(), equals('openrouter_key'));
    });

    test('multiple operations maintain data integrity', () async {
      await service.setApiKey('KEY1', 'value1');
      await service.setApiKey('KEY2', 'value2');
      await service.deleteApiKey('KEY1');
      await service.setApiKey('KEY3', 'value3');

      expect(await service.getApiKey('KEY1'), isNull);
      expect(await service.getApiKey('KEY2'), equals('value2'));
      expect(await service.getApiKey('KEY3'), equals('value3'));
    });
  });
}
