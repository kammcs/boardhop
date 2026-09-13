import 'dart:convert';

import 'package:shelf/shelf.dart';

/// The only capture user. The secret is `RELAY_CAPTURE_SECRET` on the box.
const captureUsername = 'hook';

/// Constant-time comparison, so a wrong secret cannot be found byte by byte.
bool secureEquals(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  var diff = x.length ^ y.length;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ y[i % (y.isEmpty ? 1 : y.length)];
  }
  return diff == 0;
}

/// True when the request carries `Basic hook:<secret>`.
bool basicAuthOk(Request request, String secret) {
  if (secret.isEmpty) return false;
  final header = request.headers['authorization'];
  if (header == null) return false;
  final parts = header.split(' ');
  if (parts.length != 2 || parts[0].toLowerCase() != 'basic') return false;
  String decoded;
  try {
    decoded = utf8.decode(base64.decode(parts[1].trim()));
  } catch (_) {
    return false;
  }
  final colon = decoded.indexOf(':');
  if (colon < 0) return false;
  final user = decoded.substring(0, colon);
  final pass = decoded.substring(colon + 1);
  // Both halves in constant time; `&` rather than `&&` so neither short-circuits.
  final userOk = secureEquals(user, captureUsername);
  final passOk = secureEquals(pass, secret);
  return userOk & passOk;
}

Response unauthorized() => Response(
  401,
  body: '{"error":"unauthorized"}',
  headers: {'content-type': 'application/json', 'www-authenticate': 'Basic realm="boardhop-relay", charset="UTF-8"'},
);
