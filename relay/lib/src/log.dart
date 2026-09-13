import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// One JSON line per request on stdout: method, path, status, ms.
///
/// Nothing from the request or response body is logged, and no header is
/// logged either — the Authorization header and the hook payload must never
/// reach the container log.
Middleware jsonRequestLog({IOSink? sink}) {
  final out = sink ?? stdout;
  return (Handler inner) {
    return (Request request) async {
      final watch = Stopwatch()..start();
      try {
        final response = await inner(request);
        _line(out, request, response.statusCode, watch.elapsedMilliseconds);
        return response;
      } catch (_) {
        _line(out, request, 500, watch.elapsedMilliseconds);
        rethrow;
      }
    };
  };
}

void _line(IOSink out, Request request, int status, int ms) {
  out.writeln(
    jsonEncode({
      'ts': DateTime.now().toUtc().toIso8601String(),
      'level': status >= 500 ? 'error' : 'info',
      'msg': 'request',
      'method': request.method,
      // The path only; a query string could carry a token one day.
      'path': '/${request.url.path}',
      'status': status,
      'ms': ms,
    }),
  );
}

/// A JSON line for anything that is not a request (startup, shutdown, errors).
void logEvent(String message, {Map<String, Object?> fields = const {}, String level = 'info', IOSink? sink}) {
  (sink ?? stdout).writeln(
    jsonEncode({'ts': DateTime.now().toUtc().toIso8601String(), 'level': level, 'msg': message, ...fields}),
  );
}
