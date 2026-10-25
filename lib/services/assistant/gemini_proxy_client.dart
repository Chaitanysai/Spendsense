import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'assistant_auth.dart';
import 'finance_tool_engine.dart';

class AssistantRemoteException implements Exception {
  final String code;
  final String message;
  final bool retryable;

  const AssistantRemoteException(
    this.code,
    this.message, {
    this.retryable = false,
  });

  @override
  String toString() => 'AssistantRemoteException($code): $message';
}

class RemoteHistoryTurn {
  final String role; // 'user' or 'model'
  final String text;

  const RemoteHistoryTurn({required this.role, required this.text});
}

class RemoteToolCall {
  final String name;
  final Map<String, dynamic> arguments;

  const RemoteToolCall(this.name, this.arguments);
}

class RemoteToolExchange {
  final List<RemoteToolCall> calls;
  final List<Map<String, dynamic>> responses;

  const RemoteToolExchange({required this.calls, required this.responses});
}

class RemoteAssistantTurn {
  final String text;
  final List<RemoteToolCall> functionCalls;

  const RemoteAssistantTurn({
    required this.text,
    this.functionCalls = const [],
  });
}

abstract interface class AssistantRemoteClient {
  Future<RemoteAssistantTurn> send({
    required String message,
    required List<RemoteHistoryTurn> history,
    required List<RemoteToolExchange> toolExchanges,
  });
}

/// Client for SpendSense's trusted Gemini proxy.
///
/// It never holds or sends a Gemini key. The backend owns the key, the system
/// prompt and the tool declarations; this client only forwards the user's
/// question plus validated local tool results.
class GeminiProxyClient implements AssistantRemoteClient {
  static const int maxToolRounds = 4;
  static const int maxCallsPerTurn = 8;
  static const int maxHistoryTurns = 8;
  static const int maxRequestBytes = 48 * 1024;
  static const int requestsPerMinute = 8;

  final Uri endpoint;
  final AssistantAuthTokenProvider authTokenProvider;
  final AssistantIdentityTokenProvider identityTokenProvider;
  final http.Client _http;
  final Duration timeout;
  final DateTime Function() _clock;
  final List<DateTime> _requestTimes = [];

  GeminiProxyClient({
    required this.endpoint,
    required this.authTokenProvider,
    required this.identityTokenProvider,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 25),
    DateTime Function()? clock,
  })  : _http = httpClient ?? http.Client(),
        _clock = clock ?? DateTime.now;

  static GeminiProxyClient? fromBaseUrl(
    String baseUrl, {
    required AssistantAuthTokenProvider authTokenProvider,
    required AssistantIdentityTokenProvider identityTokenProvider,
    http.Client? httpClient,
  }) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return null;
    // The configured value IS the deployed function endpoint. Do not append a
    // synthetic path: Firebase Functions exposes the handler at this URL.
    return GeminiProxyClient(
      endpoint: uri,
      authTokenProvider: authTokenProvider,
      identityTokenProvider: identityTokenProvider,
      httpClient: httpClient,
    );
  }

  @override
  Future<RemoteAssistantTurn> send({
    required String message,
    required List<RemoteHistoryTurn> history,
    required List<RemoteToolExchange> toolExchanges,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed.length > 2000) {
      throw const AssistantRemoteException(
        'invalid_message',
        'Ask a shorter question (up to 2,000 characters).',
      );
    }
    if (toolExchanges.length > maxToolRounds) {
      throw const AssistantRemoteException(
        'too_many_tool_rounds',
        'The assistant needed too many steps. Try a narrower question.',
        retryable: true,
      );
    }

    final String appCheckToken;
    try {
      appCheckToken = await authTokenProvider.getToken();
    } on AssistantAuthException catch (e) {
      throw AssistantRemoteException(
        'auth_unavailable',
        e.message,
        retryable: true,
      );
    } catch (_) {
      throw const AssistantRemoteException(
        'auth_unavailable',
        'The assistant could not verify this app installation. Local '
            'assistant commands still work.',
        retryable: true,
      );
    }

    final String identityToken;
    try {
      identityToken = await identityTokenProvider.getIdToken();
    } on AssistantAuthException catch (e) {
      throw AssistantRemoteException(
        e.code == 'not_signed_in' ? 'auth_required' : 'auth_unavailable',
        e.message,
        retryable: e.code != 'not_signed_in',
      );
    } catch (_) {
      throw const AssistantRemoteException(
        'auth_unavailable',
        'Your sign-in session could not be verified. Local commands still work.',
        retryable: true,
      );
    }
    _enforceClientRateLimit();

    final body = jsonEncode({
      'message': trimmed,
      'history': [
        for (final turn in history.take(maxHistoryTurns))
          {
            'role': turn.role == 'model' ? 'model' : 'user',
            'text': turn.text.length > 1000
                ? turn.text.substring(0, 1000)
                : turn.text,
          },
      ],
      'toolExchanges': [
        for (final exchange in toolExchanges)
          {
            'calls': [
              for (final call in exchange.calls)
                {'name': call.name, 'args': call.arguments},
            ],
            'responses': exchange.responses,
          },
      ],
    });
    if (utf8.encode(body).length > maxRequestBytes) {
      throw const AssistantRemoteException(
        'context_too_large',
        'That result is too large to send. Ask for a smaller date range.',
      );
    }

    final http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-SpendSense-Client': 'assistant-v1',
              // Short-lived app-integrity assertion; never logged or returned.
              'X-Firebase-AppCheck': appCheckToken,
              // Short-lived user identity assertion, verified server-side.
              'Authorization': 'Bearer $identityToken',
            },
            body: body,
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AssistantRemoteException(
        'timeout',
        'Gemini took too long to respond. Your local data was not changed.',
        retryable: true,
      );
    } on SocketException {
      throw const AssistantRemoteException(
        'offline',
        'You appear to be offline. Local commands still work.',
        retryable: true,
      );
    } on http.ClientException {
      throw const AssistantRemoteException(
        'network_error',
        'Could not reach the assistant service. Local commands still work.',
        retryable: true,
      );
    }

    if (response.statusCode == 429) {
      throw const AssistantRemoteException(
        'rate_limited',
        'The assistant is receiving too many requests. Wait a minute and retry.',
        retryable: true,
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AssistantRemoteException(
        'unauthorised',
        'The assistant service rejected this build.',
      );
    }
    if (response.statusCode == 413) {
      throw const AssistantRemoteException(
        'context_too_large',
        'That request is too large. Ask for a smaller date range.',
      );
    }
    if (response.statusCode >= 500) {
      throw const AssistantRemoteException(
        'server_error',
        'The assistant service is unavailable right now. Local commands still work.',
        retryable: true,
      );
    }
    if (response.statusCode != 200) {
      throw AssistantRemoteException(
        'http_${response.statusCode}',
        'The assistant service could not answer that request.',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('not an object');
      }
      final text = (decoded['text'] as String? ?? '').trim();
      final rawCalls = decoded['functionCalls'];
      final calls = <RemoteToolCall>[];
      if (rawCalls != null) {
        if (rawCalls is! List || rawCalls.length > maxCallsPerTurn) {
          throw const FormatException('invalid calls');
        }
        for (final raw in rawCalls) {
          if (raw is! Map ||
              raw['name'] is! String ||
              !FinanceToolEngine.remoteToolNames.contains(raw['name']) ||
              raw['args'] is! Map) {
            throw const FormatException('invalid call');
          }
          calls.add(RemoteToolCall(
            raw['name'] as String,
            Map<String, dynamic>.from(raw['args'] as Map),
          ));
        }
      }
      if (text.isEmpty && calls.isEmpty) {
        throw const FormatException('empty turn');
      }
      return RemoteAssistantTurn(text: text, functionCalls: calls);
    } on FormatException {
      throw const AssistantRemoteException(
        'invalid_response',
        'The assistant returned an invalid response. Nothing was changed.',
      );
    }
  }

  void _enforceClientRateLimit() {
    final now = _clock();
    _requestTimes.removeWhere(
      (at) => now.difference(at) > const Duration(minutes: 1),
    );
    if (_requestTimes.length >= requestsPerMinute) {
      throw const AssistantRemoteException(
        'rate_limited',
        'You have reached the request limit. Wait a minute and try again.',
        retryable: true,
      );
    }
    _requestTimes.add(now);
  }
}
