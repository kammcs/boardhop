import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'capture.dart';
import 'gateway/gateway.dart';
import 'log.dart';
import 'registration.dart';
import 'responses.dart';

/// Everything the handler needs; the relay's real routes grow from here.
class RelayServer {
  RelayServer({
    required this.version,
    required this.captureSecret,
    required this.captures,
    required this.registrations,
    required this.gateway,
    DateTime? startedAt,
    this.dbStatus = 'absent',
  }) : startedAt = startedAt ?? DateTime.now();

  final String version;
  final String captureSecret;
  final CaptureStore captures;
  final DateTime startedAt;

  /// Device registration and the test push (R1).
  final Registrations registrations;

  /// APNs and FCM; only its health is read here.
  final PushGateway gateway;

  /// "ok", "absent" or an error string; reported by /healthz.
  final String dbStatus;

  Handler get handler =>
      const Pipeline().addMiddleware(jsonRequestLog()).addMiddleware(_errorsAsJson).addHandler(_router.call);

  Router get _router => Router()
    ..get('/healthz', _healthz)
    ..post('/capture/<name>', _postCapture)
    ..get('/capture/<name>', _listCapture)
    ..post('/v1/devices', registrations.register)
    ..delete('/v1/devices/<deviceId>', registrations.unregister)
    ..post('/v1/devices/<deviceId>/heartbeat', registrations.heartbeat)
    ..post('/v1/test-push', registrations.testPush)
    ..get('/v1/admin/devices', registrations.adminDevices)
    ..get('/v1/admin/fcm-check', registrations.adminFcmCheck)
    ..all('/<ignored|.*>', (Request _) => jsonError(404, 'not found'));

  Response _healthz(Request request) {
    final health = gateway.health;
    return jsonResponse(200, {
      'ok': true,
      'version': version,
      'uptime': DateTime.now().difference(startedAt).inSeconds,
      'db': dbStatus,
      'apns': health['apns'],
      'fcm': health['fcm'],
    });
  }

  Future<Response> _postCapture(Request request, String name) async {
    if (!basicAuthOk(request, captureSecret)) return unauthorized();
    if (!CaptureStore.isValidName(name)) return jsonError(400, 'bad capture name');
    final body = await request.readAsString();
    final file = captures.write(name, body, request.headers);
    logEvent('capture', fields: {'name': name, 'file': file.uri.pathSegments.last, 'bytes': body.length});
    return jsonResponse(200, {'ok': true, 'file': file.uri.pathSegments.last});
  }

  Response _listCapture(Request request, String name) {
    if (!basicAuthOk(request, captureSecret)) return unauthorized();
    if (!CaptureStore.isValidName(name)) return jsonError(400, 'bad capture name');
    final files = captures.list(name);
    return jsonResponse(200, {'name': name, 'count': files.length, 'files': files});
  }
}

/// A thrown handler never leaks a stack trace to the caller.
Handler _errorsAsJson(Handler inner) => (Request request) async {
  try {
    return await inner(request);
  } catch (e, st) {
    logEvent(
      'handler failed',
      level: 'error',
      fields: {'path': '/${request.url.path}', 'error': '$e', 'stack': st.toString().split('\n').take(3).join(' | ')},
    );
    return jsonError(500, 'internal');
  }
};

/// Reads an environment variable, falling back to [fallback].
String env(String key, String fallback) {
  final v = Platform.environment[key];
  return (v == null || v.isEmpty) ? fallback : v;
}
