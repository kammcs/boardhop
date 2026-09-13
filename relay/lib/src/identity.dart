import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import 'log.dart';

/// Who the relay decided a bearer token belongs to. Ids only: no name is
/// needed to route a push, and none is stored.
class AdoIdentity {
  const AdoIdentity({required this.id, this.descriptor});

  /// The Azure DevOps identity GUID (`authenticatedUser.id`).
  final String id;

  /// `authenticatedUser.descriptor`, e.g. `aad.<base64>`; useful later for
  /// matching a hook payload's reviewer list.
  final String? descriptor;
}

/// Validates a bearer token against one organization. Injected so tests can
/// answer without a network, and so the product can swap `connectionData` for
/// something cheaper later.
typedef IdentityValidator = Future<AdoIdentity?> Function(String org, String bearer);

/// Azure DevOps organization names: what may appear in a URL path.
final _orgPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');

bool isValidOrg(String org) => _orgPattern.hasMatch(org);

/// The `Bearer <token>` the app sends. Returns null when the header is absent
/// or malformed. The token itself is never logged.
String? bearerOf(Request request) {
  final header = request.headers['authorization'];
  if (header == null) return null;
  final parts = header.split(' ');
  if (parts.length != 2 || parts[0].toLowerCase() != 'bearer') return null;
  final token = parts[1].trim();
  return token.isEmpty ? null : token;
}

/// The anonymous identity Azure DevOps hands back when a call is not
/// authenticated at all; `connectionData` answers 200 with it rather than 401.
const _anonymousId = '00000000-0000-0000-0000-000000000000';

/// The real validator: `GET /_apis/connectionData`, which every org answers for
/// any valid token and which needs no scope of its own.
///
/// The token is used for exactly one outbound call and then dropped: it is
/// never written to the database and never logged.
IdentityValidator connectionDataValidator({http.Client? client, Duration timeout = const Duration(seconds: 10)}) {
  final httpClient = client ?? http.Client();
  return (String org, String bearer) async {
    if (!isValidOrg(org)) return null;
    final uri = Uri.parse('https://dev.azure.com/$org/_apis/connectionData?api-version=7.1-preview');
    try {
      final response = await httpClient
          .get(uri, headers: {'authorization': 'Bearer $bearer', 'accept': 'application/json'})
          .timeout(timeout);
      if (response.statusCode != 200) {
        logEvent('identity rejected', fields: {'org': org, 'status': response.statusCode});
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final user = decoded['authenticatedUser'];
      if (user is! Map) return null;
      final id = user['id'];
      if (id is! String || id.isEmpty || id == _anonymousId) {
        logEvent('identity rejected', fields: {'org': org, 'reason': 'anonymous'});
        return null;
      }
      return AdoIdentity(id: id, descriptor: user['descriptor'] as String?);
    } catch (e) {
      logEvent('identity check failed', level: 'error', fields: {'org': org, 'error': '$e'});
      return null;
    }
  };
}
