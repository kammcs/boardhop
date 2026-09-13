import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

/// Where log lines go when no sink is passed. Production leaves it null, which
/// means stdout; a test replaces it to capture (and assert on) what is written.
///
/// It takes the finished line, so nothing can slip past the JSON encoding that
/// [logEvent] and [jsonRequestLog] do.
void Function(String line)? logWriter;

void _write(IOSink? sink, String line) {
  if (sink != null) {
    sink.writeln(line);
    return;
  }
  final writer = logWriter;
  if (writer != null) {
    writer(line);
    return;
  }
  stdout.writeln(line);
}

/// One JSON line per request on stdout: method, path, status, ms.
///
/// Nothing from the request or response body is logged, and no header is
/// logged either — the Authorization header and the hook payload must never
/// reach the container log.
Middleware jsonRequestLog({IOSink? sink}) {
  return (Handler inner) {
    return (Request request) async {
      final watch = Stopwatch()..start();
      try {
        final response = await inner(request);
        _line(sink, request, response.statusCode, watch.elapsedMilliseconds);
        return response;
      } catch (_) {
        _line(sink, request, 500, watch.elapsedMilliseconds);
        rethrow;
      }
    };
  };
}

void _line(IOSink? out, Request request, int status, int ms) {
  _write(
    out,
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
  _write(sink, jsonEncode({'ts': DateTime.now().toUtc().toIso8601String(), 'level': level, 'msg': message, ...fields}));
}
