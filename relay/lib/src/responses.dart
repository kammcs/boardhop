import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Every answer the relay gives is JSON, and no answer ever echoes a token, a
/// header or a hook body back at the caller.
Response jsonResponse(int status, Object body) =>
    Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json'});

Response jsonError(int status, String message) => jsonResponse(status, {'error': message});

/// The bearer was missing, malformed, or the org did not recognise it.
Response bearerUnauthorized() => Response(
  401,
  body: '{"error":"unauthorized"}',
  headers: {'content-type': 'application/json', 'www-authenticate': 'Bearer realm="boardhop-relay"'},
);

/// Reads a JSON object body. Returns null for anything that is not an object
/// or is larger than [maxBytes].
Future<Map<String, Object?>?> readJsonObject(Request request, {int maxBytes = 16 * 1024}) async {
  final body = await request.readAsString();
  if (body.isEmpty || body.length > maxBytes) return null;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map<String, Object?> ? decoded : null;
  } catch (_) {
    return null;
  }
}
