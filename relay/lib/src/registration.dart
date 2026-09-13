import 'package:shelf/shelf.dart';

import 'db.dart';
import 'gateway/gateway.dart';
import 'gateway/pointer.dart';
import 'identity.dart';
import 'log.dart';
import 'responses.dart';
import 'routing/prefs.dart';
import 'verb.dart';

/// A token bucket per organization. Generous on purpose: the app registers
/// once per install, heartbeats once a day and pushes a test on demand, so the
/// limit only exists to stop one org's runaway client from starving the rest.
class OrgRateLimiter {
  OrgRateLimiter({this.capacity = 120, this.refillPerSecond = 1, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int capacity;
  final double refillPerSecond;
  final DateTime Function() _clock;

  final Map<String, ({double tokens, DateTime at})> _buckets = {};

  /// Takes one token. False when the org has spent its budget.
  bool allow(String org) {
    final now = _clock();
    final bucket = _buckets[org];
    var tokens = capacity.toDouble();
    if (bucket != null) {
      final elapsed = now.difference(bucket.at).inMilliseconds / 1000.0;
      tokens = (bucket.tokens + elapsed * refillPerSecond).clamp(0, capacity.toDouble());
    }
    if (tokens < 1) {
      _buckets[org] = (tokens: tokens, at: now);
      return false;
    }
    _buckets[org] = (tokens: tokens - 1, at: now);
    return true;
  }
}

/// `/v1/devices*` and `/v1/test-push`: everything that needs the caller to
/// prove, with their own Azure DevOps token, who they are in one organization.
///
/// The bearer is validated against the org and dropped. It is never stored,
/// never logged, and never forwarded anywhere but Azure DevOps.
class Registrations {
  Registrations({
    required this.db,
    required this.validator,
    required this.gateway,
    OrgRateLimiter? limiter,
    this.adminSecret = '',
  }) : limiter = limiter ?? OrgRateLimiter();

  final RelayDb? db;
  final IdentityValidator validator;
  final PushGateway gateway;
  final OrgRateLimiter limiter;

  /// `RELAY_ADMIN_SECRET`. Empty means `/v1/admin/*` answers 404-shaped 401.
  final String adminSecret;

  static const _platforms = {'android', 'ios'};

  /// Device tokens: APNs is 64 hex characters; an FCM token is opaque and its
  /// length is not promised — under the Firebase-Installations registration it
  /// is as short as 22 characters (measured on the emulator, 2026-09-13), so
  /// this only keeps out the obviously wrong.
  static final _tokenPattern = RegExp(r'^[A-Za-z0-9_:.\-]{16,4096}$');

  /// UTC-14 to UTC+14, the whole range of real offsets (research/14 §6).
  static const maxTzOffsetMinutes = 840;

  // ------------------------------------------------------------ POST /v1/devices

  Future<Response> register(Request request) async {
    final store = db;
    if (store == null) return jsonError(503, 'database unavailable');

    final bearer = bearerOf(request);
    if (bearer == null) return bearerUnauthorized();

    final body = await readJsonObject(request);
    if (body == null) return jsonError(400, 'expected a JSON object');

    final org = body['org'];
    final platform = body['platform'];
    final token = body['token'];
    if (org is! String || !isValidOrg(org)) return jsonError(400, 'bad org');
    if (platform is! String || !_platforms.contains(platform)) return jsonError(400, 'bad platform');
    if (token is! String || !_tokenPattern.hasMatch(token)) return jsonError(400, 'bad token');
    if (!_validTzOffset(body['tzOffsetMinutes'])) return jsonError(400, 'bad tzOffsetMinutes');

    if (!limiter.allow(org)) return jsonError(429, 'too many registrations for this organization');
    if (!store.orgEnabled(org)) return jsonError(403, 'organization disabled');

    final identity = await validator(org, bearer);
    if (identity == null) return bearerUnauthorized();

    store.ensureOrg(org);
    final device = store.registerDevice(
      org: org,
      userId: identity.id,
      userDescriptor: identity.descriptor,
      platform: platform,
      token: token,
      appVersion: _short(body['appVersion']),
      locale: _short(body['locale']),
      tzOffsetMinutes: body['tzOffsetMinutes'] as int?,
    );
    logEvent(
      'device registered',
      fields: {
        'org': org,
        'deviceId': device.id,
        'platform': platform,
        'token': '…${device.tokenTail}',
        'appVersion': device.appVersion,
      },
    );
    return jsonResponse(200, {'deviceId': device.id, 'userId': device.userId, 'org': device.org});
  }

  // ---------------------------------------------------- DELETE /v1/devices/{id}

  Future<Response> unregister(Request request, String deviceId) async {
    final owned = await _ownedDevice(request, deviceId);
    if (owned is _Denied) return owned.response;
    final device = (owned as _Owned).device;
    db!.deleteDevice(device.id);
    logEvent('device removed', fields: {'org': device.org, 'deviceId': device.id, 'reason': 'unregistered'});
    return Response(204);
  }

  // ------------------------------------------- POST /v1/devices/{id}/heartbeat

  Future<Response> heartbeat(Request request, String deviceId) async {
    final owned = await _ownedDevice(request, deviceId);
    if (owned is _Denied) return owned.response;
    final device = (owned as _Owned).device;

    final body = await readJsonObject(request) ?? const <String, Object?>{};
    final rotated = body['token'];
    if (rotated != null && (rotated is! String || !_tokenPattern.hasMatch(rotated))) {
      return jsonError(400, 'bad token');
    }
    if (!_validTzOffset(body['tzOffsetMinutes'])) return jsonError(400, 'bad tzOffsetMinutes');
    final updated = db!.heartbeat(
      device.id,
      token: rotated as String?,
      appVersion: _short(body['appVersion']),
      locale: _short(body['locale']),
      tzOffsetMinutes: body['tzOffsetMinutes'] as int?,
    );
    if (updated == null) return jsonError(404, 'unknown device');
    return jsonResponse(200, {
      'deviceId': updated.id,
      'org': updated.org,
      'lastSeenAt': updated.lastSeenAt.toIso8601String(),
    });
  }

  // ----------------------------------------------------------- POST /v1/test-push

  /// The end-to-end test route, and later the one support asks a customer to
  /// press. It can only ever reach the caller's own devices in that org.
  Future<Response> testPush(Request request) async {
    final store = db;
    if (store == null) return jsonError(503, 'database unavailable');

    final bearer = bearerOf(request);
    if (bearer == null) return bearerUnauthorized();

    final body = await readJsonObject(request) ?? const <String, Object?>{};
    final org = body['org'];
    if (org is! String || !isValidOrg(org)) return jsonError(400, 'bad org');
    if (!limiter.allow(org)) return jsonError(429, 'too many pushes for this organization');
    if (!store.orgEnabled(org)) return jsonError(403, 'organization disabled');

    final identity = await validator(org, bearer);
    if (identity == null) return bearerUnauthorized();

    final devices = store.devicesFor(org, identity.id);
    if (devices.isEmpty) return jsonError(404, 'no devices registered for this identity');

    final results = await gateway.send(devices, testPointer(org, deepLink: _short(body['deepLink'])));
    return jsonResponse(200, {
      'devices': devices.length,
      'sent': results.where((r) => r.ok).length,
      'results': [
        for (var i = 0; i < devices.length; i++)
          {
            'deviceId': devices[i].id,
            'platform': devices[i].platform,
            'outcome': results[i].outcome.name,
            if (results[i].status != null) 'status': results[i].status,
            if (results[i].error != null) 'error': results[i].error,
          },
      ],
    });
  }

  /// The fixed pointer `/v1/test-push` sends. Points at the relay itself
  /// rather than an artifact, so a tap lands on the org's activity feed unless
  /// the caller passed a deep link.
  static PushPointer testPointer(String org, {String? deepLink, DateTime? sentAt}) => PushPointer(
    org: org,
    eventType: 'boardhop.test',
    artifactType: PushArtifactType.build,
    artifactId: '0',
    project: '',
    title: 'Push is working',
    deepLink: deepLink ?? '/activity',
    verb: Verb.test,
    sentAt: sentAt ?? DateTime.now().toUtc(),
  );

  // ------------------------------------------------ GET/PUT /v1/prefs?org=

  /// This person's push preferences for one org (research/14 §6, D5). Stored
  /// per `(org, userId)` rather than per device, so two phones agree and a
  /// reinstall keeps them; the defaults come back when nothing is stored.
  Future<Response> getPrefs(Request request) async {
    final resolved = await _callerInOrg(request);
    if (resolved is _Denied) return resolved.response;
    final caller = resolved as _Caller;
    return jsonResponse(200, PushPrefs.decode(db!.userPrefs(caller.org, caller.userId)).toJson());
  }

  /// Replaces the document. Every key and every value is checked against §6:
  /// an unknown key or a value outside its closed list is a **400**, so a typo
  /// in the app can never silently switch a notification off. `notActor` is
  /// reported but not editable (§5.2 rule 1).
  Future<Response> putPrefs(Request request) async {
    final resolved = await _callerInOrg(request);
    if (resolved is _Denied) return resolved.response;
    final caller = resolved as _Caller;

    final body = await readJsonObject(request);
    if (body == null) return jsonError(400, 'expected a JSON object');
    final parsed = PrefsParser.parse(body);
    final prefs = parsed.prefs;
    if (prefs == null) return jsonError(400, parsed.error ?? 'bad preferences');

    db!.saveUserPrefs(org: caller.org, userId: caller.userId, prefsJson: prefs.encode());
    // Counts and switches only: a preference document holds no content, and
    // the log does not need the document to say that it changed.
    logEvent(
      'prefs saved',
      fields: {'org': caller.org, 'quietHours': prefs.quietHours.enabled, 'muted': prefs.mutedArtifacts.length},
    );
    return jsonResponse(200, prefs.toJson());
  }

  // -------------------------------------------------- GET /v1/admin/devices?org=

  /// Counts and platforms only — never a token, never an identity id. Guarded
  /// by `RELAY_ADMIN_SECRET` in the `Authorization: Bearer` header.
  Response adminDevices(Request request) {
    if (adminSecret.isEmpty) return jsonError(404, 'not found');
    final bearer = bearerOf(request);
    if (bearer == null || !_constantTimeEquals(bearer, adminSecret)) return bearerUnauthorized();
    final store = db;
    if (store == null) return jsonError(503, 'database unavailable');
    final org = request.url.queryParameters['org'];
    if (org == null || !isValidOrg(org)) return jsonError(400, 'bad org');
    final counts = store.deviceCounts(org);
    return jsonResponse(200, {
      'org': org,
      'enabled': store.orgEnabled(org),
      'devices': counts.values.fold<int>(0, (a, b) => a + b),
      'platforms': counts,
      'users': store.userCount(org),
    });
  }

  /// `GET /v1/admin/fcm-check`: asks Google to validate a message without
  /// sending it, so a misconfigured Firebase project can be told apart from a
  /// phone that will not register.
  Future<Response> adminFcmCheck(Request request) async {
    if (adminSecret.isEmpty) return jsonError(404, 'not found');
    final bearer = bearerOf(request);
    if (bearer == null || !_constantTimeEquals(bearer, adminSecret)) return bearerUnauthorized();
    return jsonResponse(200, await gateway.fcmSelfTest());
  }

  // ------------------------------------------------------------------ helpers

  Future<_Ownership> _ownedDevice(Request request, String deviceId) async {
    final store = db;
    if (store == null) return _Denied(jsonError(503, 'database unavailable'));

    final bearer = bearerOf(request);
    if (bearer == null) return _Denied(bearerUnauthorized());

    final device = store.deviceById(deviceId);
    // A device id that does not exist and one that belongs to somebody else
    // answer the same way, so the route cannot be used to enumerate ids.
    if (device == null) return _Denied(jsonError(404, 'unknown device'));
    if (!limiter.allow(device.org)) return _Denied(jsonError(429, 'too many requests for this organization'));

    final identity = await validator(device.org, bearer);
    if (identity == null) return _Denied(bearerUnauthorized());
    if (identity.id != device.userId) return _Denied(jsonError(404, 'unknown device'));
    return _Owned(device);
  }

  /// The `?org=` routes' common front door: a valid org, inside its rate
  /// bucket and kill switch, and a bearer the org recognises. Exactly the
  /// checks `/v1/devices` makes, and the bearer is dropped the same way.
  Future<_Ownership> _callerInOrg(Request request) async {
    final store = db;
    if (store == null) return _Denied(jsonError(503, 'database unavailable'));

    final bearer = bearerOf(request);
    if (bearer == null) return _Denied(bearerUnauthorized());

    final org = request.url.queryParameters['org'];
    if (org == null || !isValidOrg(org)) return _Denied(jsonError(400, 'bad org'));
    if (!limiter.allow(org)) return _Denied(jsonError(429, 'too many requests for this organization'));
    if (!store.orgEnabled(org)) return _Denied(jsonError(403, 'organization disabled'));

    final identity = await validator(org, bearer);
    if (identity == null) return _Denied(bearerUnauthorized());
    return _Caller(org, identity.id);
  }

  /// Null (absent) is fine; anything else must be a whole number of minutes
  /// inside [maxTzOffsetMinutes].
  static bool _validTzOffset(Object? value) {
    if (value == null) return true;
    return value is int && value >= -maxTzOffsetMinutes && value <= maxTzOffsetMinutes;
  }

  /// Short free-text fields (app version, locale) are capped so a client
  /// cannot grow a row without limit.
  static String? _short(Object? value, {int max = 64}) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= max ? trimmed : trimmed.substring(0, max);
  }

  static bool _constantTimeEquals(String a, String b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i % (b.isEmpty ? 1 : b.length));
    }
    return diff == 0;
  }
}

sealed class _Ownership {
  const _Ownership();
}

class _Owned extends _Ownership {
  const _Owned(this.device);
  final DeviceRow device;
}

class _Denied extends _Ownership {
  const _Denied(this.response);
  final Response response;
}

/// A caller who proved who they are in one organization; no token is kept.
class _Caller extends _Ownership {
  const _Caller(this.org, this.userId);
  final String org;
  final String userId;
}
