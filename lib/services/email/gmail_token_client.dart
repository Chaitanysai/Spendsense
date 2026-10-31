import 'dart:async';

import 'package:http/http.dart' as http;

/// An [http.Client] that attaches an OAuth bearer token to every request.
///
/// The Gmail API client only needs an HTTP client; this keeps the token out of
/// URL query strings and out of logs.
class GmailTokenClient extends http.BaseClient {
  final String accessToken;
  final http.Client _inner;

  GmailTokenClient(this.accessToken, {http.Client? inner})
      : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
