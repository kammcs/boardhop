import 'dart:convert';
import 'dart:io';

import 'package:boardhop_relay/src/capture.dart';
import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/gateway/gateway.dart';
import 'package:boardhop_relay/src/gateway/pointer.dart';
import 'package:boardhop_relay/src/registration.dart';
import 'package:boardhop_relay/src/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Kelly's identity in the fixtures, and a second person to prove one caller
/// cannot touch another's device.
const kellyToken = 'ado-bearer-for-kelly';
const kellyId = '11111111-1111-1111-1111-111111111111';
const otherToken = 'ado-bearer-for-somebody-else';
const otherId = '22222222-2222-2222-2222-222222222222';

const fcmToken = 'fcm-token-abcdefghijklmnopqrstuvwxyz-012345';
const apnsToken = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

void main() {
  late RelayDb db;
  late FakeSender apns;
  late FakeSender fcm;
  late PushGateway gateway;
  late RelayServer server;

  setUp(() {
    db = RelayDb.openMemory()!;
    apns = FakeSender();
    fcm = FakeSender();
    gateway = PushGateway(apns: apns, fcm: fcm, db: db);
    server = RelayServer(
      version: 'test-sha',
      captureSecret: 'unused',
      captures: CaptureStore(Directory.systemTemp),
      dbStatus: 'ok',
      gateway: gateway,
      registrations: Registrations(
        db: db,
        validator: fakeValidator(const {kellyToken: kellyId, otherToken: otherId}, orgs: const {'puremedia'}),
        gateway: gateway,
        adminSecret: 'admin-secret',
      ),
    );
  });

  tearDown(() => db.close());

  Future<Response> call(String method, String path, {String? bearer, Object? body}) async => server.handler(
    Request(
      method,
      Uri.parse('http://localhost:8080$path'),
      headers: {if (bearer != null) 'authorization': 'Bearer $bearer', 'content-type': 'application/json'},
      body: body == null ? null : jsonEncode(body),
    ),
  );

  Future<Map<String, Object?>> json(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, Object?>;

  Map<String, Object?> androidBody({String token = fcmToken, String org = 'puremedia'}) => {
    'org': org,
    'platform': 'android',
    'token': token,
    'appVersion': '1.0.0+1',
    'locale': 'en-GB',
  };

  group('POST /v1/devices', () {
    test('registers and returns a device id and the user id', () async {
      final response = await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody());
      expect(response.statusCode, 200);
      final payload = await json(response);
      expect(payload['userId'], kellyId);
      expect((payload['deviceId']! as String).length, 36);
      expect(db.deviceCounts('puremedia'), {'android': 1});
      // The org row is created on first registration, enabled.
      expect(db.orgEnabled('puremedia'), isTrue);
    });

    test('is idempotent on (org, token)', () async {
      final first = await json(await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody()));
      final second = await json(await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody()));
      expect(second['deviceId'], first['deviceId']);
      expect(db.deviceCounts('puremedia'), {'android': 1});
    });

    test('401 without a bearer, and when the org does not know the token', () async {
      expect((await call('POST', '/v1/devices', body: androidBody())).statusCode, 401);
      expect((await call('POST', '/v1/devices', bearer: 'nonsense', body: androidBody())).statusCode, 401);
      expect(
        (await call(
          'POST',
          '/v1/devices',
          bearer: kellyToken,
          body: androidBody(org: 'someone-else'),
        )).statusCode,
        401,
      );
    });

    test('400 on a bad platform, org or token', () async {
      expect(
        (await call(
          'POST',
          '/v1/devices',
          bearer: kellyToken,
          body: {...androidBody(), 'platform': 'blackberry'},
        )).statusCode,
        400,
      );
      expect(
        (await call('POST', '/v1/devices', bearer: kellyToken, body: {...androidBody(), 'org': '../etc'})).statusCode,
        400,
      );
      expect(
        (await call('POST', '/v1/devices', bearer: kellyToken, body: {...androidBody(), 'token': 'short'})).statusCode,
        400,
      );
    });

    test('403 when the org kill switch is off', () async {
      await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody());
      db.setOrgEnabled('puremedia', false);
      final response = await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody());
      expect(response.statusCode, 403);
    });

    test('429 once the org has spent its bucket', () async {
      final limited = Registrations(
        db: db,
        validator: fakeValidator(const {kellyToken: kellyId}, orgs: const {'puremedia'}),
        gateway: gateway,
        limiter: OrgRateLimiter(capacity: 2, refillPerSecond: 0),
      );
      Future<int> post() async => (await limited.register(
        Request(
          'POST',
          Uri.parse('http://localhost/v1/devices'),
          headers: {'authorization': 'Bearer $kellyToken', 'content-type': 'application/json'},
          body: jsonEncode(androidBody()),
        ),
      )).statusCode;
      expect(await post(), 200);
      expect(await post(), 200);
      expect(await post(), 429);
    });
  });

  group('heartbeat and delete', () {
    Future<String> register() async =>
        (await json(await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody())))['deviceId']! as String;

    test('heartbeat moves lastSeenAt and rotates the token', () async {
      final id = await register();
      final before = db.deviceById(id)!.lastSeenAt;
      const rotated = 'fcm-token-rotated-zyxwvutsrqponmlkjihgfedcba-98765';
      final response = await call(
        'POST',
        '/v1/devices/$id/heartbeat',
        bearer: kellyToken,
        body: {'token': rotated, 'appVersion': '1.0.1+7'},
      );
      expect(response.statusCode, 200);
      final row = db.deviceById(id)!;
      expect(row.token, rotated);
      expect(row.appVersion, '1.0.1+7');
      expect(row.lastSeenAt.isBefore(before), isFalse);
    });

    test('DELETE removes it and answers 204', () async {
      final id = await register();
      expect((await call('DELETE', '/v1/devices/$id', bearer: kellyToken)).statusCode, 204);
      expect(db.deviceById(id), isNull);
    });

    test('another identity gets 404, not somebody else\'s device', () async {
      final id = await register();
      expect((await call('DELETE', '/v1/devices/$id', bearer: otherToken)).statusCode, 404);
      expect((await call('POST', '/v1/devices/$id/heartbeat', bearer: otherToken)).statusCode, 404);
      expect(db.deviceById(id), isNotNull);
    });

    test('401 without a bearer', () async {
      final id = await register();
      expect((await call('DELETE', '/v1/devices/$id')).statusCode, 401);
    });
  });

  group('POST /v1/test-push', () {
    test('pushes to every device of the caller in that org', () async {
      await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody());
      await call(
        'POST',
        '/v1/devices',
        bearer: kellyToken,
        body: {'org': 'puremedia', 'platform': 'ios', 'token': apnsToken},
      );
      // Somebody else's device must not be woken.
      await call(
        'POST',
        '/v1/devices',
        bearer: otherToken,
        body: androidBody(token: '${fcmToken}other'),
      );

      final response = await call('POST', '/v1/test-push', bearer: kellyToken, body: {'org': 'puremedia'});
      expect(response.statusCode, 200);
      final payload = await json(response);
      expect(payload['devices'], 2);
      expect(payload['sent'], 2);
      expect(fcm.sent.single.token, fcmToken);
      expect(apns.sent.single.token, apnsToken);
      expect(fcm.sent.single.pointer.eventType, 'boardhop.test');
    });

    test('404 when the caller has no devices', () async {
      expect((await call('POST', '/v1/test-push', bearer: kellyToken, body: {'org': 'puremedia'})).statusCode, 404);
    });

    test('401 without a valid bearer', () async {
      expect((await call('POST', '/v1/test-push', body: {'org': 'puremedia'})).statusCode, 401);
      expect((await call('POST', '/v1/test-push', bearer: 'nope', body: {'org': 'puremedia'})).statusCode, 401);
    });
  });

  group('GET /v1/admin/devices', () {
    test('counts and platforms only, never a token', () async {
      await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody());
      final response = await call('GET', '/v1/admin/devices?org=puremedia', bearer: 'admin-secret');
      expect(response.statusCode, 200);
      final body = await response.readAsString();
      expect(body, isNot(contains(fcmToken)));
      expect(body, isNot(contains(kellyId)));
      final payload = jsonDecode(body) as Map<String, Object?>;
      expect(payload['devices'], 1);
      expect(payload['users'], 1);
      expect(payload['platforms'], {'android': 1});
    });

    test('401 with the wrong secret', () async {
      expect((await call('GET', '/v1/admin/devices?org=puremedia', bearer: 'guess')).statusCode, 401);
      expect((await call('GET', '/v1/admin/devices?org=puremedia')).statusCode, 401);
    });
  });

  group('dead tokens', () {
    test('a dead result deletes the device row', () async {
      await call('POST', '/v1/devices', bearer: kellyToken, body: androidBody());
      fcm.result = const PushResult(PushOutcome.dead, status: 404, error: 'UNREGISTERED');
      final response = await call('POST', '/v1/test-push', bearer: kellyToken, body: {'org': 'puremedia'});
      expect(response.statusCode, 200);
      expect(db.deviceCounts('puremedia'), isEmpty);
    });
  });
}
