import 'dart:convert';
import 'dart:io';

import 'package:boardhop_relay/src/auth.dart';
import 'package:boardhop_relay/src/capture.dart';
import 'package:boardhop_relay/src/cors.dart';
import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/gateway/gateway.dart';
import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/hooks/hook_queue.dart';
import 'package:boardhop_relay/src/hooks/ingest.dart';
import 'package:boardhop_relay/src/registration.dart';
import 'package:boardhop_relay/src/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The org-key provisioning routes (`/v1/orgs/{org}/…`): what the Marketplace
/// extension's hub calls from a browser page, authenticated with the org's own
/// hook secret and nothing relay-wide.
const org = 'puremedia';
const adminSecret = 'admin-secret-for-tests';
const hookSecret = 'hook-secret-0123456789abcdef';

const projectA = '11111111-1111-4111-8111-111111111111';
const projectB = '22222222-2222-4222-8222-222222222222';

const subA1 = 'a0000000-0000-4000-8000-000000000001';
const subA2 = 'a0000000-0000-4000-8000-000000000002';
const subB1 = 'b0000000-0000-4000-8000-000000000001';

const hubOrigin = 'https://kammcs.gallerycdn.vsassets.io';

String basicHeader(String secret, {String user = 'hook'}) => 'Basic ${base64.encode(utf8.encode('$user:$secret'))}';

Map<String, Object?> rowJson(String subId, HookKind kind, {String? projectId = projectA, String? name = 'Project A'}) =>
    {
      'subId': subId,
      'eventType': kind.eventType,
      'kind': kind.label,
      if (projectId != null) 'projectId': projectId,
      if (name != null) 'projectName': name,
    };

HookSubscriptionRow storedRow(String subId, HookKind kind, {String? projectId, String? name}) => HookSubscriptionRow(
  org: org,
  subId: subId,
  eventType: kind.eventType,
  kind: kind.label,
  projectId: projectId,
  projectName: name,
);

void main() {
  late RelayDb db;
  late HookQueue queue;
  late RelayServer server;

  setUp(() {
    db = RelayDb.openMemory()!;
    queue = HookQueue(processor: RecordingHookProcessor());
    db.setHookSecretHash(org, sha256Hex(hookSecret));
    // Two projects, so "replace one, keep the other" is testable.
    db.replaceHookSubscriptions(org, [
      storedRow(subA1, HookKind.wiUpdated, projectId: projectA, name: 'Project A'),
      storedRow(subA2, HookKind.prCreated, projectId: projectA, name: 'Project A'),
      storedRow(subB1, HookKind.buildComplete, projectId: projectB, name: 'Project B'),
    ]);
    final gateway = PushGateway(apns: FakeSender(ready: false), fcm: FakeSender(), db: db);
    server = RelayServer(
      version: 'test-sha',
      captureSecret: 'unused',
      captures: CaptureStore(Directory.systemTemp),
      dbStatus: 'ok',
      gateway: gateway,
      registrations: Registrations(db: db, validator: fakeValidator(const {}), gateway: gateway),
      hooks: HookIngest(db: db, queue: queue, adminSecret: adminSecret),
    );
  });

  tearDown(() => db.close());

  Future<Response> call(
    String method,
    String path, {
    String? secret = hookSecret,
    String? user = 'hook',
    String? origin,
    String contentType = 'application/json',
    Object? body,
    String? rawBody,
  }) async => server.handler(
    Request(
      method,
      Uri.parse('http://localhost:8080$path'),
      headers: {
        if (secret != null) 'authorization': basicHeader(secret, user: user ?? 'hook'),
        'content-type': contentType,
        if (origin != null) 'origin': origin,
      },
      body: rawBody ?? (body == null ? null : jsonEncode(body)),
    ),
  );

  Future<Map<String, Object?>> jsonOf(Future<Response> call) async =>
      jsonDecode(await (await call).readAsString()) as Map<String, Object?>;

  final subs = '/v1/orgs/$org/subscriptions';
  String project(String id) => '/v1/orgs/$org/projects/$id/subscriptions';

  // ---------------------------------------------------------- happy paths

  group('GET /v1/orgs/{org}/subscriptions', () {
    test('lists every registered row for the org', () async {
      final response = await call('GET', subs);
      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, Object?>;
      expect(body['org'], org);
      final rows = (body['subscriptions']! as List).cast<Map<String, Object?>>();
      expect(rows.map((r) => r['subId']), [subA1, subA2, subB1]);
      expect(rows.first['kind'], 'wi.updated');
      expect(rows.first['eventType'], 'workitem.updated');
      expect(rows.first['projectId'], projectA);
      expect(rows.first['projectName'], 'Project A');
      // The store stamps created_at NOT NULL, so the key is always there.
      expect(DateTime.parse(rows.first['createdAt']! as String).isUtc, isTrue);
    });
  });

  group('PUT /v1/orgs/{org}/projects/{projectId}/subscriptions', () {
    test('replaces only the named project and leaves the other alone', () async {
      final body = await jsonOf(
        call(
          'PUT',
          project(projectA),
          body: [
            rowJson(subA1, HookKind.wiCommented),
            rowJson('a0000000-0000-4000-8000-000000000009', HookKind.prMerged),
          ],
        ),
      );
      expect(body, {'org': org, 'projectId': projectA, 'subscriptions': 2, 'total': 3});

      final rows = db.hookSubscriptions(org);
      expect(rows.map((r) => r.subId).toSet(), {subA1, 'a0000000-0000-4000-8000-000000000009', subB1});
      // The row that stayed is untouched, kind and project intact.
      final kept = rows.firstWhere((r) => r.subId == subB1);
      expect(kept.kind, 'build.complete');
      expect(kept.projectId, projectB);
      // The replaced one took the new kind.
      expect(rows.firstWhere((r) => r.subId == subA1).kind, 'wi.commented');
      // And the one that was project A's and is not in the new set is gone.
      expect(rows.any((r) => r.subId == subA2), isFalse);
    });

    test('an empty array clears that project and keeps the rest', () async {
      final body = await jsonOf(call('PUT', project(projectA), body: const <Object?>[]));
      expect(body, {'org': org, 'projectId': projectA, 'subscriptions': 0, 'total': 1});
      expect(db.hookSubscriptions(org).single.subId, subB1);
    });

    test('a subId that moved project is taken from the incoming set', () async {
      // subB1 is project B's; PUTting it under project A moves it.
      final body = await jsonOf(
        call('PUT', project(projectA), body: [rowJson(subB1, HookKind.buildComplete)]),
      );
      expect(body, {'org': org, 'projectId': projectA, 'subscriptions': 1, 'total': 1});
      expect(db.hookSubscriptions(org).single.projectId, projectA);
    });

    test('a row with no project is kept', () async {
      db.replaceHookSubscriptions(org, [
        storedRow(subA1, HookKind.wiUpdated, projectId: projectA),
        storedRow(subB1, HookKind.buildComplete),
      ]);
      final body = await jsonOf(call('PUT', project(projectA), body: const <Object?>[]));
      expect(body['total'], 1);
      expect(db.hookSubscriptions(org).single.subId, subB1);
    });
  });

  group('DELETE /v1/orgs/{org}/projects/{projectId}/subscriptions', () {
    test('removes that project\'s rows and reports the count', () async {
      final body = await jsonOf(call('DELETE', project(projectA)));
      expect(body, {'org': org, 'projectId': projectA, 'removed': 2, 'total': 1});
      expect(db.hookSubscriptions(org).single.subId, subB1);
    });

    test('a project with no rows removes nothing', () async {
      final body = await jsonOf(call('DELETE', project('33333333-3333-4333-8333-333333333333')));
      expect(body['removed'], 0);
      expect(body['total'], 3);
    });
  });

  // ------------------------------------------------------------ the 404 wall

  group('rejection is indistinguishable', () {
    Future<({int status, String body, Map<String, String> headers})> answerOf(Future<Response> pending) async {
      final response = await pending;
      return (status: response.statusCode, body: await response.readAsString(), headers: response.headers);
    }

    test('wrong key, no key, wrong user, unknown org and a disabled org all answer 404 {}', () async {
      db.ensureOrg('fabrikam'); // registered, but with no hook secret

      final answers = <String, ({int status, String body, Map<String, String> headers})>{
        'wrong secret': await answerOf(call('GET', subs, secret: 'not-the-secret-at-all')),
        'no credentials': await answerOf(call('GET', subs, secret: null)),
        'wrong user': await answerOf(call('GET', subs, user: 'admin')),
        'unknown org': await answerOf(call('GET', '/v1/orgs/nosuchorg/subscriptions')),
        'no secret': await answerOf(call('GET', '/v1/orgs/fabrikam/subscriptions')),
        'put wrong secret': await answerOf(
          call('PUT', project(projectA), secret: 'nope', body: [rowJson(subA1, HookKind.wiUpdated)]),
        ),
        'delete wrong secret': await answerOf(call('DELETE', project(projectA), secret: 'nope')),
      };

      db.setOrgEnabled(org, false);
      answers['disabled org'] = await answerOf(call('GET', subs));

      for (final entry in answers.entries) {
        expect(entry.value.status, 404, reason: entry.key);
        expect(entry.value.body, '{}', reason: entry.key);
        expect(entry.value.headers['content-type'], 'application/json', reason: entry.key);
      }
      // Byte for byte the same answer, header set included.
      expect(answers.values.map((a) => '${a.status} ${a.body} ${a.headers}').toSet(), hasLength(1));
      // And nothing was written on the way past.
      db.setOrgEnabled(org, true);
      expect(db.hookSubscriptions(org), hasLength(3));
    });

    test('the same 404 as the ingest wall, byte for byte', () async {
      final wall = await call('GET', '/v1/orgs/nosuchorg/subscriptions');
      final ingest = await server.handler(
        Request(
          'POST',
          Uri.parse('http://localhost:8080/hooks/nosuchorg'),
          headers: {'content-type': 'application/json'},
          body: '{}',
        ),
      );
      expect(await wall.readAsString(), await ingest.readAsString());
      expect(wall.statusCode, ingest.statusCode);
      expect(wall.headers, ingest.headers);
    });

    test('each rejection logs a reason code and no secret', () async {
      final lines = await captureLog(() async {
        await call('GET', subs, secret: 'wrong-secret-xx');
        await call('DELETE', project(projectA), secret: null);
      });
      final rejections = lines
          .map(jsonDecode)
          .whereType<Map<String, Object?>>()
          .where((line) => line['msg'] == 'hook rejected');
      expect(rejections.map((line) => line['reason']), ['bad-secret', 'bad-secret']);
      for (final line in rejections) {
        expect(line.keys.toSet(), {'ts', 'level', 'msg', 'org', 'reason'});
      }
      expect(lines.join('\n'), isNot(contains('wrong-secret-xx')));
      expect(lines.join('\n'), isNot(contains(hookSecret)));
    });
  });

  // -------------------------------------------------------------- validation

  group('validation', () {
    Future<void> expectUnchanged() async {
      expect(db.hookSubscriptions(org).map((r) => r.subId), [subA1, subA2, subB1]);
      expect(db.hookSubscriptions(org).firstWhere((r) => r.subId == subA1).kind, 'wi.updated');
    }

    test('an unknown kind is a 400 and changes nothing', () async {
      final response = await call(
        'PUT',
        project(projectA),
        body: [
          {'subId': subA1, 'eventType': 'workitem.updated', 'kind': 'wi.invented', 'projectId': projectA},
        ],
      );
      expect(response.statusCode, 400);
      await expectUnchanged();
    });

    test('a kind that does not belong to its event type is a 400', () async {
      final response = await call(
        'PUT',
        project(projectA),
        body: [
          {'subId': subA1, 'eventType': 'build.complete', 'kind': 'wi.updated', 'projectId': projectA},
        ],
      );
      expect(response.statusCode, 400);
      expect(jsonDecode(await response.readAsString()), {
        'error': 'kind wi.updated does not belong to event build.complete',
      });
      await expectUnchanged();
    });

    test('a row whose projectId is not the path\'s is a 400', () async {
      final response = await call(
        'PUT',
        project(projectA),
        body: [rowJson(subA1, HookKind.wiUpdated), rowJson(subB1, HookKind.buildComplete, projectId: projectB)],
      );
      expect(response.statusCode, 400);
      expect(jsonDecode(await response.readAsString()), {'error': 'projectId does not match the path'});
      await expectUnchanged();
    });

    test('a row with no projectId at all is a 400', () async {
      final response = await call(
        'PUT',
        project(projectA),
        body: [rowJson(subA1, HookKind.wiUpdated, projectId: null)],
      );
      expect(response.statusCode, 400);
      await expectUnchanged();
    });

    test('a duplicate subId is a 400', () async {
      final response = await call(
        'PUT',
        project(projectA),
        body: [rowJson(subA1, HookKind.wiUpdated), rowJson(subA1, HookKind.wiCreated)],
      );
      expect(response.statusCode, 400);
      await expectUnchanged();
    });

    test('a non-JSON content type is a 415 and a non-array body a 400', () async {
      expect((await call('PUT', project(projectA), contentType: 'text/plain', body: const <Object?>[])).statusCode, 415);
      expect((await call('PUT', project(projectA), rawBody: '{"not":"an array"}')).statusCode, 400);
      expect((await call('PUT', project(projectA), rawBody: 'not json at all')).statusCode, 400);
      await expectUnchanged();
    });

    test('a body over 1 MB is a 413', () async {
      final padding = 'x' * (HookIngest.maxBodyBytes + 1024);
      final raw = jsonEncode([
        {...rowJson(subA1, HookKind.wiUpdated), 'projectName': padding},
      ]);
      expect(raw.length, greaterThan(HookIngest.maxBodyBytes));
      expect((await call('PUT', project(projectA), rawBody: raw)).statusCode, 413);
      await expectUnchanged();
    });
  });

  // -------------------------------------------------------------------- CORS

  group('CORS', () {
    test('a preflight from the gallery CDN answers 204 with the headers', () async {
      final response = await call('OPTIONS', project(projectA), secret: null, origin: hubOrigin);
      expect(response.statusCode, 204);
      expect(response.headers['access-control-allow-origin'], hubOrigin);
      expect(response.headers['access-control-allow-methods'], 'GET, PUT, DELETE, OPTIONS');
      expect(response.headers['access-control-allow-headers'], 'Authorization, Content-Type');
      expect(response.headers['access-control-max-age'], '600');
      expect(response.headers['vary'], 'Origin');
      // Never a credentials header and never a wildcard.
      expect(response.headers.containsKey('access-control-allow-credentials'), isFalse);
    });

    test('a preflight from a stranger gets the 404 wall and no headers', () async {
      final response = await call('OPTIONS', project(projectA), secret: null, origin: 'https://evil.example');
      expect(response.statusCode, 404);
      expect(await response.readAsString(), '{}');
      expect(response.headers.containsKey('access-control-allow-origin'), isFalse);
      expect(response.headers.containsKey('vary'), isFalse);
    });

    test('a successful GET echoes the allowed origin and varies on it', () async {
      final response = await call('GET', subs, origin: hubOrigin);
      expect(response.statusCode, 200);
      expect(response.headers['access-control-allow-origin'], hubOrigin);
      expect(response.headers['vary'], 'Origin');
    });

    test('a 404 rejection still carries the headers, so the hub can read it', () async {
      final response = await call('GET', subs, secret: 'wrong-one-entirely', origin: hubOrigin);
      expect(response.statusCode, 404);
      expect(await response.readAsString(), '{}');
      expect(response.headers['access-control-allow-origin'], hubOrigin);
      expect(response.headers['vary'], 'Origin');
    });

    test('a 400 carries the headers too', () async {
      final response = await call(
        'PUT',
        project(projectA),
        origin: 'https://dev.azure.com',
        body: [rowJson(subA1, HookKind.wiUpdated, projectId: projectB)],
      );
      expect(response.statusCode, 400);
      expect(response.headers['access-control-allow-origin'], 'https://dev.azure.com');
    });

    test('a disallowed origin gets no headers on a real response', () async {
      final response = await call('GET', subs, origin: 'https://evil.example');
      expect(response.statusCode, 200);
      expect(response.headers.containsKey('access-control-allow-origin'), isFalse);
      expect(response.headers.containsKey('vary'), isFalse);
    });

    test('a request with no origin gets no headers', () async {
      final response = await call('GET', subs);
      expect(response.headers.containsKey('access-control-allow-origin'), isFalse);
    });

    test('routes outside /v1/orgs/ are untouched', () async {
      final prefs = await server.handler(
        Request(
          'GET',
          Uri.parse('http://localhost:8080/v1/prefs'),
          headers: {'origin': hubOrigin, 'authorization': 'Bearer nope'},
        ),
      );
      expect(prefs.headers.containsKey('access-control-allow-origin'), isFalse);

      final health = await server.handler(
        Request('GET', Uri.parse('http://localhost:8080/healthz'), headers: {'origin': hubOrigin}),
      );
      expect(health.statusCode, 200);
      expect(health.headers.containsKey('access-control-allow-origin'), isFalse);

      // Including the admin twin of these routes.
      final admin = await server.handler(
        Request(
          'GET',
          Uri.parse('http://localhost:8080/v1/admin/orgs/$org/subscriptions'),
          headers: {'origin': hubOrigin, 'authorization': 'Bearer $adminSecret'},
        ),
      );
      expect(admin.statusCode, 200);
      expect(admin.headers.containsKey('access-control-allow-origin'), isFalse);

      // And an OPTIONS elsewhere is still the router's plain 404.
      final options = await server.handler(
        Request('OPTIONS', Uri.parse('http://localhost:8080/v1/prefs'), headers: {'origin': hubOrigin}),
      );
      expect(options.statusCode, 404);
      expect(options.headers.containsKey('access-control-allow-origin'), isFalse);
    });

    test('the origin allow-list', () {
      for (final allowed in [
        'https://kammcs.gallerycdn.vsassets.io',
        'https://cdn.vsassets.io',
        'https://a.b.c.vsassets.io',
        'https://dev.azure.com',
        'https://puremedia.visualstudio.com',
        'http://localhost:3000',
        'https://localhost:8080',
        'http://localhost',
      ]) {
        expect(isAllowedHubOrigin(allowed), isTrue, reason: allowed);
      }
      for (final denied in [
        null,
        '',
        'null',
        '*',
        'https://evil.example',
        'http://dev.azure.com', // http on a real host
        'https://dev.azure.com:8443', // non-default port
        'https://vsassets.io.evil.example',
        'https://notvsassets.io',
        'https://evil.example/https://dev.azure.com',
        'https://dev.azure.com/path',
        'https://user@dev.azure.com',
        'http://localhost.evil.example',
        'file://localhost',
      ]) {
        expect(isAllowedHubOrigin(denied), isFalse, reason: '$denied');
      }
    });
  });

  // ----------------------------------------------------------- body canary

  group('the org key never leaks', () {
    test('no response body and no log line contains the secret', () async {
      final bodies = <String>[];
      final lines = await captureLog(() async {
        for (final pending in <Future<Response>>[
          call('GET', subs, origin: hubOrigin),
          call('GET', subs, secret: '$hookSecret-wrong'),
          call('PUT', project(projectA), body: [rowJson(subA1, HookKind.wiUpdated)]),
          call('PUT', project(projectA), body: [rowJson(subA1, HookKind.wiUpdated, projectId: projectB)]),
          call('DELETE', project(projectA)),
          call('OPTIONS', project(projectA), secret: null, origin: hubOrigin),
          call('GET', '/v1/orgs/nosuchorg/subscriptions'),
        ]) {
          bodies.add(await (await pending).readAsString());
        }
      });

      final everything = '${bodies.join('\n')}\n${lines.join('\n')}';
      for (final forbidden in [hookSecret, sha256Hex(hookSecret), adminSecret, basicHeader(hookSecret)]) {
        expect(everything, isNot(contains(forbidden)));
      }
    });
  });
}
