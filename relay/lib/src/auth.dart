import 'dart:convert';

import 'package:crypto/crypto.dart';
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

/// The username and password out of an HTTP Basic header, or null when there
/// is none or it is malformed. Neither half is ever logged.
({String username, String password})? basicCredentials(Request request) {
  final header = request.headers['authorization'];
  if (header == null) return null;
  final parts = header.split(' ');
  if (parts.length != 2 || parts[0].toLowerCase() != 'basic') return null;
  String decoded;
  try {
    decoded = utf8.decode(base64.decode(parts[1].trim()));
  } catch (_) {
    return null;
  }
  final colon = decoded.indexOf(':');
  if (colon < 0) return null;
  return (username: decoded.substring(0, colon), password: decoded.substring(colon + 1));
}

/// The hash stored in `orgs.hook_secret_hash`. The secret itself is never
/// written to the database, a log line or a response.
String sha256Hex(String secret) => sha256.convert(utf8.encode(secret)).toString();

/// True when the request carries `Basic hook:<secret>`.
bool basicAuthOk(Request request, String secret) {
  if (secret.isEmpty) return false;
  final credentials = basicCredentials(request);
  if (credentials == null) return false;
  // Both halves in constant time; `&` rather than `&&` so neither short-circuits.
  final userOk = secureEquals(credentials.username, captureUsername);
  final passOk = secureEquals(credentials.password, secret);
  return userOk & passOk;
}

Response unauthorized() => Response(
  401,
  body: '{"error":"unauthorized"}',
  headers: {'content-type': 'application/json', 'www-authenticate': 'Basic realm="boardhop-relay", charset="UTF-8"'},
);
