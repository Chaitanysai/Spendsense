import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spendsense/services/assistant/assistant_auth.dart';
import 'package:spendsense/services/assistant/assistant_settings.dart';
import 'package:spendsense/services/assistant/gemini_proxy_client.dart';

import 'fakes.dart';

void main() {
  final endpoint = Uri.parse('https://example.test/v1/assistant');
  final auth = StaticAuthTokenProvider(token: 'test-app-check-token');
  final identity = StaticIdentityTokenProvider(token: 'test-id-token');

  test('proxy URL validation requires https or loopback dev', () {
    expect(AssistantConfig.isValidProxy('https://example.test'), true);
    expect(AssistantConfig.isValidProxy('http://localhost:5001'), true);
    expect(AssistantConfig.isValidProxy('http://10.0.2.2:5001'), true);
    expect(AssistantConfig.isValidProxy('http://example.test'), false);
    expect(AssistantConfig.isValidProxy('not a url'), false);
  });

  test('configured function URL is used verbatim', () {
    const configured =
        'https://asia-south1-spendsense-ota-2026.cloudfunctions.net/assistantProxy';
    final client = GeminiProxyClient.fromBaseUrl(
      configured,
      authTokenProvider: auth,
      identityTokenProvider: identity,
    );
    expect(client, isNotNull);
    expect(client!.endpoint.toString(), configured);
  });

  test('request contains only the typed question and tool context', () async {
    String? capturedBody;
    Uri? capturedUrl;
    Map<String, String>? capturedHeaders;
    final client = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: identity,
      httpClient: MockClient((request) async {
        capturedBody = request.body;
        capturedUrl = request.url;
        capturedHeaders = request.headers;
        return http.Response(
          jsonEncode({'text': 'Answer', 'functionCalls': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final result = await client.send(
      message: 'How much did I spend?',
      history: const [
        RemoteHistoryTurn(role: 'user', text: 'Earlier'),
      ],
      toolExchanges: const [
        RemoteToolExchange(
          calls: [
            RemoteToolCall('search_transactions', {'limit': 5}),
          ],
          responses: [
            {
              'name': 'search_transactions',
              'response': {'matchedCount': 1}
            },
          ],
        ),
      ],
    );
    expect(result.text, 'Answer');
    expect(capturedUrl, endpoint);
    final body = jsonDecode(capturedBody!) as Map<String, dynamic>;
    expect(body.keys.toSet(), {'message', 'history', 'toolExchanges'});
    expect(body['message'], 'How much did I spend?');
    expect(body['history'], [
      {'role': 'user', 'text': 'Earlier'},
    ]);
    expect(capturedBody, isNot(contains('apiKey')));
    expect(capturedBody, isNot(contains('GEMINI')));
    expect(capturedBody, isNot(contains('originalSms')));
    expect(capturedHeaders?['X-Firebase-AppCheck'], 'test-app-check-token');
    expect(capturedHeaders?['Authorization'], 'Bearer test-id-token');
    expect(capturedBody, isNot(contains('test-app-check-token')));
    expect(capturedBody, isNot(contains('test-id-token')));
  });

  test('valid function calls are parsed and unknown calls rejected', () async {
    final valid = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: identity,
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'text': '',
              'functionCalls': [
                {
                  'name': 'search_transactions',
                  'args': {'brand': 'groww', 'limit': 10},
                },
              ],
            }),
            200,
          )),
    );
    final result = await valid.send(
      message: 'Groww?',
      history: const [],
      toolExchanges: const [],
    );
    expect(result.functionCalls.single.name, 'search_transactions');
    expect(result.functionCalls.single.arguments['limit'], 10);

    final invalid = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: identity,
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'text': '',
              'functionCalls': [
                {'name': 'apply_transaction_deletion', 'args': {}},
              ],
            }),
            200,
          )),
    );
    await expectLater(
      invalid.send(message: 'x', history: const [], toolExchanges: const []),
      throwsA(
        isA<AssistantRemoteException>().having(
          (e) => e.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('rate limits and upstream errors have actionable codes', () async {
    final limited = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: identity,
      httpClient: MockClient((_) async => http.Response('{}', 429)),
    );
    await expectLater(
      limited.send(message: 'x', history: const [], toolExchanges: const []),
      throwsA(
        isA<AssistantRemoteException>().having(
          (e) => e.code,
          'code',
          'rate_limited',
        ),
      ),
    );

    final serverError = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: identity,
      httpClient: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(
      serverError
          .send(message: 'x', history: const [], toolExchanges: const []),
      throwsA(
        isA<AssistantRemoteException>()
            .having((e) => e.code, 'code', 'server_error')
            .having((e) => e.retryable, 'retryable', true),
      ),
    );
  });

  test('client-side per-minute cap prevents runaway requests', () async {
    var now = DateTime(2026, 10, 25, 12);
    final client = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: identity,
      clock: () => now,
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({'text': 'ok'}),
            200,
          )),
    );
    for (var i = 0; i < GeminiProxyClient.requestsPerMinute; i++) {
      await client
          .send(message: 'q$i', history: const [], toolExchanges: const []);
    }
    now = now.add(const Duration(seconds: 10));
    await expectLater(
      client.send(
          message: 'one too many', history: const [], toolExchanges: const []),
      throwsA(
        isA<AssistantRemoteException>().having(
          (e) => e.code,
          'code',
          'rate_limited',
        ),
      ),
    );
    now = now.add(const Duration(minutes: 1));
    final result = await client.send(
      message: 'allowed again',
      history: const [],
      toolExchanges: const [],
    );
    expect(result.text, 'ok');
  });

  test('auth failure prevents any network request', () async {
    var requests = 0;
    final client = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: StaticAuthTokenProvider(
        error: const AssistantAuthException(
          'auth_unavailable',
          'The assistant could not verify this app installation.',
        ),
      ),
      identityTokenProvider: identity,
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(jsonEncode({'text': 'should not happen'}), 200);
      }),
    );
    await expectLater(
      client.send(message: 'x', history: const [], toolExchanges: const []),
      throwsA(
        isA<AssistantRemoteException>()
            .having((e) => e.code, 'code', 'auth_unavailable')
            .having((e) => e.message, 'message', contains('verify')),
      ),
    );
    expect(requests, 0);
  });

  test('signed-out identity failure prevents any network request', () async {
    var requests = 0;
    final client = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: StaticIdentityTokenProvider(
        error: const AssistantAuthException(
          'not_signed_in',
          'Sign in to use the cloud assistant.',
        ),
      ),
      httpClient: MockClient((_) async {
        requests++;
        return http.Response(jsonEncode({'text': 'should not happen'}), 200);
      }),
    );
    await expectLater(
      client.send(message: 'x', history: const [], toolExchanges: const []),
      throwsA(
        isA<AssistantRemoteException>()
            .having((e) => e.code, 'code', 'auth_required')
            .having((e) => e.message, 'message', contains('Sign in')),
      ),
    );
    expect(requests, 0);
  });

  test('unconfigured identity provider fails closed without plugin calls',
      () async {
    const provider = FirebaseAssistantIdentityTokenProvider();
    expect(provider.isConfigured, false);
    await expectLater(
      provider.getIdToken(),
      throwsA(
        isA<AssistantAuthException>().having(
          (e) => e.code,
          'code',
          'auth_not_configured',
        ),
      ),
    );
  });

  test('unconfigured App Check provider fails closed without plugin calls',
      () async {
    const provider = FirebaseAppCheckTokenProvider();
    expect(provider.isConfigured, false);
    await expectLater(
      provider.getToken(),
      throwsA(
        isA<AssistantAuthException>().having(
          (e) => e.code,
          'code',
          'auth_not_configured',
        ),
      ),
    );
  });

  test('timeouts and oversized context fail safely', () async {
    final slow = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: identity,
      timeout: const Duration(milliseconds: 10),
      httpClient: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return http.Response(jsonEncode({'text': 'late'}), 200);
      }),
    );
    await expectLater(
      slow.send(message: 'x', history: const [], toolExchanges: const []),
      throwsA(
        isA<AssistantRemoteException>().having(
          (e) => e.code,
          'code',
          'timeout',
        ),
      ),
    );

    final client = GeminiProxyClient(
      endpoint: endpoint,
      authTokenProvider: auth,
      identityTokenProvider: identity,
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    await expectLater(
      client.send(
        message: 'x' * 2001,
        history: const [],
        toolExchanges: const [],
      ),
      throwsA(
        isA<AssistantRemoteException>().having(
          (e) => e.code,
          'code',
          'invalid_message',
        ),
      ),
    );
  });
}
