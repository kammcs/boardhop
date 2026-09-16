import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// One request as the demo handlers see it.
class DemoRequest {
  DemoRequest(this.method, this.uri, this.body, this.match);

  final String method;
  final Uri uri;

  /// The decoded request body (JSON map or list), or the raw string.
  final Object? body;

  /// The route pattern's match against `host/path`; groups are the path
  /// parameters.
  final RegExpMatch match;

  String group(int i) => Uri.decodeComponent(match.group(i) ?? '');
  Map<String, String> get query => uri.queryParameters;
}

/// A handler's answer when a plain JSON value is not enough.
class DemoResponse {
  const DemoResponse(this.status, [this.body, this.contentType]);

  final int status;
  final Object? body;
  final String? contentType;
}

/// Answers the request: a JSON-encodable value (Map, List), a [String]
/// (sent as text), [Uint8List] (bytes), a [DemoResponse], or null for 404.
typedef DemoHandler = Object? Function(DemoRequest request);

/// The demo mode's whole "Azure DevOps": a routing table from
/// `METHOD host/path` patterns to handlers, served through Dio so every
/// repository and parser runs exactly as it does against the service.
///
/// Patterns are regular expressions matched against `host/path` with the
/// leading `https://` removed, anchored at both ends; the first match in
/// registration order wins. Unmatched requests answer 404 and are logged
/// with `DEMO MISS`, which is how a screen's missing fixtures are found.
class DemoBackend implements HttpClientAdapter {
  DemoBackend({this.latency = const Duration(milliseconds: 60)});

  /// A small delay so loading states behave as they do on a network.
  final Duration latency;

  final List<(String, RegExp, DemoHandler)> _routes = [];

  /// Every request no fixture answered (`METHOD url`), for tests.
  final List<String> misses = [];

  /// Every request that reached the backend (`METHOD url`), for tests.
  final List<String> requests = [];

  void on(String method, String pattern, DemoHandler handler) =>
      _routes.add((method.toUpperCase(), RegExp('^$pattern\$'), handler));

  void get(String pattern, DemoHandler handler) => on('GET', pattern, handler);
  void post(String pattern, DemoHandler handler) =>
      on('POST', pattern, handler);
  void patch(String pattern, DemoHandler handler) =>
      on('PATCH', pattern, handler);
  void put(String pattern, DemoHandler handler) => on('PUT', pattern, handler);
  void delete(String pattern, DemoHandler handler) =>
      on('DELETE', pattern, handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = options.uri;
    final method = options.method.toUpperCase();
    final target = '${uri.host}${uri.path}';
    requests.add('$method $uri');
    Object? body = options.data;
    if (requestStream != null && body == null) {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (all, chunk) => all..addAll(chunk),
      );
      body = utf8.decode(bytes, allowMalformed: true);
    }
    if (body is String && body.isNotEmpty) {
      try {
        body = jsonDecode(body);
      } on FormatException {
        // Plain text body: leave it as is.
      }
    }
    if (latency > Duration.zero) await Future<void>.delayed(latency);

    for (final (m, pattern, handler) in _routes) {
      if (m != method) continue;
      final match = pattern.firstMatch(target);
      if (match == null) continue;
      final Object? result;
      try {
        result = handler(DemoRequest(method, uri, body, match));
      } catch (e, stack) {
        debugPrint('DEMO ERROR $method $uri: $e\n$stack');
        return _json(500, {'message': 'Demo handler failed: $e'});
      }
      if (result == null) break;
      return _encode(result);
    }
    misses.add('$method $uri');
    debugPrint('DEMO MISS $method $uri');
    return _json(404, {'message': 'Not in the demo data: $method $target'});
  }

  static ResponseBody _encode(Object result) {
    if (result is DemoResponse) {
      final body = result.body;
      if (body == null) {
        return ResponseBody.fromString('', result.status);
      }
      if (body is Uint8List) {
        return ResponseBody.fromBytes(
          body,
          result.status,
          headers: _type(result.contentType ?? 'application/octet-stream'),
        );
      }
      if (body is String) {
        return ResponseBody.fromString(
          body,
          result.status,
          headers: _type(result.contentType ?? 'text/plain; charset=utf-8'),
        );
      }
      return _json(result.status, body);
    }
    if (result is Uint8List) {
      return ResponseBody.fromBytes(
        result,
        200,
        headers: _type('application/octet-stream'),
      );
    }
    if (result is String) {
      return ResponseBody.fromString(
        result,
        200,
        headers: _type('text/plain; charset=utf-8'),
      );
    }
    return _json(200, result);
  }

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: _type('application/json; charset=utf-8'),
  );

  static Map<String, List<String>> _type(String type) => {
    Headers.contentTypeHeader: [type],
  };

  @override
  void close({bool force = false}) {}
}
