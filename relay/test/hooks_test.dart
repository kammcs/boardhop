import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:boardhop_relay/src/auth.dart';
import 'package:boardhop_relay/src/capture.dart';
import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/gateway/gateway.dart';
import 'package:boardhop_relay/src/hooks/hook_event.dart';
import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/hooks/hook_queue.dart';
import 'package:boardhop_relay/src/hooks/ingest.dart';
import 'package:boardhop_relay/src/hooks/routing_view.dart';
import 'package:boardhop_relay/src/registration.dart';
import 'package:boardhop_relay/src/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';
import 'support.dart';

const adminSecret = 'admin-secret-for-tests';
const hookSecret = 'hook-secret-0123456789abcdef';
const otherOrg = 'fabrikam';

const subWiUpdated = '50000000-0000-4000-8000-000000000001';
const subWiCommented = '50000000-0000-4000-8000-000000000002';
const subWiCreated = '50000000-0000-4000-8000-000000000003';
const subPrCreated = '50000000-0000-4000-8000-000000000004';
const subPrVote = '50000000-0000-4000-8000-000000000005';
const subPrComment = '50000000-0000-4000-8000-000000000006';
const subPrMerged = '50000000-0000-4000-8000-000000000007';
const subBuild = '50000000-0000-4000-8000-000000000008';
const subRunState = '50000000-0000-4000-8000-000000000009';
const subApprovalPending = '50000000-0000-4000-8000-00000000000a';

/// The registry every test starts with: one subscription per kind under test.
List<HookSubscriptionRow> fixtureSubscriptions(String org, {String? projectName = 'Contoso Demo'}) => [
  for (final entry in <(String, HookKind)>[
    (subWiUpdated, HookKind.wiUpdated),
    (subWiCommented, HookKind.wiCommented),
    (subWiCreated, HookKind.wiCreated),
    (subPrCreated, HookKind.prCreated),
    (subPrVote, HookKind.prUpdatedVote),
    (subPrComment, HookKind.prComment),
    (subPrMerged, HookKind.prMerged),
    (subBuild, HookKind.buildComplete),
    (subRunState, HookKind.runState),
    (subApprovalPending, HookKind.approvalPending),
  ])
    HookSubscriptionRow(
      org: org,
      subId: entry.$1,
      eventType: entry.$2.eventType,
      kind: entry.$2.label,
      projectId: projectName == null ? null : projectGuid,
      projectName: projectName,
    ),
];

String basicHeader(String secret, {String user = 'hook'}) => 'Basic ${base64.encode(utf8.encode('$user:$secret'))}';

void main() {
  late RelayDb db;
  late RecordingHookProcessor processor;
  late HookQueue queue;
  late RelayServer server;

  RelayServer buildServer({HookIngest? ingest}) {
    final gateway = PushGateway(apns: FakeSender(ready: false), fcm: FakeSender(), db: db);
    return RelayServer(
      version: 'test-sha',
      captureSecret: 'unused',
      captures: CaptureStore(Directory.systemTemp),
      dbStatus: 'ok',
      gateway: gateway,
      registrations: Registrations(db: db, validator: fakeValidator(const {}), gateway: gateway),
      hooks: ingest ?? HookIngest(db: db, queue: queue, adminSecret: adminSecret),
    );
  }

  setUp(() {
    db = RelayDb.openMemory()!;
    processor = RecordingHookProcessor();
    queue = HookQueue(processor: processor);
    db.setHookSecretHash(fixtureOrg, sha256Hex(hookSecret));
    db.replaceHookSubscriptions(fixtureOrg, fixtureSubscriptions(fixtureOrg));
    server = buildServer();
  });

  tearDown(() => db.close());

  Future<Response> post(
    Object? body, {
    String org = fixtureOrg,
    String? secret = hookSecret,
    String? user = 'hook',
    String? activityId = 'activity-1',
    String? subIdHeader,
    String contentType = 'application/json; charset=utf-8',
    String? rawBody,
  }) async => server.handler(
    Request(
      'POST',
      Uri.parse('http://localhost:8080/hooks/$org'),
      headers: {
        if (secret != null) 'authorization': basicHeader(secret, user: user ?? 'hook'),
        'content-type': contentType,
        'user-agent': 'VSServices/1.0',
        if (activityId != null) 'X-VSS-ActivityId': activityId,
        if (subIdHeader != null) 'X-VSS-SubscriptionId': subIdHeader,
      },
      body: rawBody ?? jsonEncode(body),
    ),
  );

  Future<Response> admin(String method, String path, {String? bearer = adminSecret, Object? body}) async =>
      server.handler(
        Request(
          method,
          Uri.parse('http://localhost:8080$path'),
          headers: {if (bearer != null) 'authorization': 'Bearer $bearer', 'content-type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        ),
      );

  // ------------------------------------------------------------------- accept

  group('POST /hooks/{org}', () {
    test('accepts a registered delivery and queues exactly one event', () async {
      final response = await post(
        workItemUpdated(
          subId: subWiUpdated,
          changes: {
            'System.State': {'newValue': 'Done'},
          },
        ),
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString()), {'accepted': true});

      await queue.drain();
      expect(processor.events, hasLength(1));
      expect(processor.events.single.kind, HookKind.wiUpdated);
      expect(processor.events.single.view.artifactId, '15545');
      expect(processor.events.single.subId, subWiUpdated);
      expect(processor.events.single.activityId, 'activity-1');
    });

    test('takes the subscription id from the header when the body has none', () async {
      final body = workItemCommented(subId: subWiCommented)..remove('subscriptionId');
      expect((await post(body, subIdHeader: subWiCommented)).statusCode, 200);
      await queue.drain();
      expect(processor.events.single.kind, HookKind.wiCommented);
    });

    test('rejects a body whose event type is not the registered one', () async {
      // A build payload posted on the work item subscription.
      final response = await post(buildComplete(subId: subWiUpdated));
      expect(response.statusCode, 404);
      await queue.drain();
      expect(processor.events, isEmpty);
    });
  });

  // ------------------------------------------------------------- the 404 wall

  group('rejection is indistinguishable', () {
    Future<String> bodyOf(Future<Response> call) async {
      final response = await call;
      expect(response.statusCode, 404);
      return response.readAsString();
    }

    test('no secret, wrong secret, unknown org, disabled org and unknown sub all answer the same', () async {
      // An org that is registered but has no hook secret yet.
      db.ensureOrg(otherOrg);
      db.replaceHookSubscriptions(otherOrg, fixtureSubscriptions(otherOrg));

      final valid = workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{});
      final answers = <String, String>{
        'no secret': await bodyOf(post(valid, org: otherOrg)),
        'wrong secret': await bodyOf(post(valid, secret: 'not-the-secret-at-all')),
        'no credentials': await bodyOf(post(valid, secret: null)),
        'wrong user': await bodyOf(post(valid, user: 'admin')),
        'unknown org': await bodyOf(post(valid, org: 'nosuchorg')),
        'unknown subscription': await bodyOf(
          post(workItemUpdated(subId: '60000000-0000-4000-8000-000000000000', changes: const <String, Object?>{})),
        ),
      };
      expect(answers.values.toSet(), {'{}'});

      db.setOrgEnabled(fixtureOrg, false);
      expect(await bodyOf(post(valid)), '{}');

      await queue.drain();
      expect(processor.events, isEmpty);
    });

    test('each rejection logs a reason code and nothing else', () async {
      final lines = await captureLog(() async {
        await post(
          workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{}),
          secret: 'wrong-secret-xx',
        );
        await post(
          workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{}),
          org: 'nosuchorg',
        );
      });
      final rejections = lines
          .map(jsonDecode)
          .whereType<Map<String, Object?>>()
          .where((line) => line['msg'] == 'hook rejected');
      expect(rejections.map((line) => line['reason']), ['bad-secret', 'unknown-org']);
      for (final line in rejections) {
        expect(line.keys.toSet(), {'ts', 'level', 'msg', 'org', 'reason'});
      }
      // The secret never appears in any line, rejected or not.
      expect(lines.join('\n'), isNot(contains('wrong-secret-xx')));
      expect(lines.join('\n'), isNot(contains(hookSecret)));
    });
  });

  // --------------------------------------------------------------- body rules

  group('body', () {
    test('a payload over 1 MB answers 413', () async {
      final padding = 'x' * (HookIngest.maxBodyBytes + 1024);
      final raw = jsonEncode({
        'subscriptionId': subWiUpdated,
        'eventType': 'workitem.updated',
        'resource': {'workItemId': 1, 'padding': padding},
      });
      expect(raw.length, greaterThan(HookIngest.maxBodyBytes));
      final response = await post(null, rawBody: raw);
      expect(response.statusCode, 413);
      await queue.drain();
      expect(processor.events, isEmpty);
    });

    test('a non-JSON content type answers 415', () async {
      final response = await post(
        workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{}),
        contentType: 'text/plain',
      );
      expect(response.statusCode, 415);
    });

    test('a body that is not a JSON object answers 400', () async {
      expect((await post(null, rawBody: 'not json at all')).statusCode, 400);
      expect((await post(null, rawBody: '[1,2,3]')).statusCode, 400);
    });
  });

  // -------------------------------------------------------------------- dedup

  group('dedup', () {
    test('a retried delivery answers 200 and is processed once', () async {
      final body = workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{});
      final first = await post(body, activityId: 'retry-me');
      final lines = await captureLog(() async {
        final second = await post(body, activityId: 'retry-me');
        expect(second.statusCode, 200);
        expect(jsonDecode(await second.readAsString()), {'accepted': true, 'duplicate': true});
      });
      expect(first.statusCode, 200);
      expect(lines.where((l) => l.contains('"msg":"hook duplicate"')), hasLength(1));

      await queue.drain();
      expect(processor.events, hasLength(1));
      expect(db.hookDeliveryCount(), 1);
    });

    test('a different activity id is a different delivery', () async {
      final body = workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{});
      await post(body, activityId: 'one');
      await post(body, activityId: 'two');
      await queue.drain();
      expect(processor.events, hasLength(2));
      expect(db.hookDeliveryCount(), 2);
    });

    test('the body id is the fallback when the header is absent', () async {
      final body = workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{}, eventId: 'body-event-id');
      await post(body, activityId: null);
      await post(body, activityId: null);
      await queue.drain();
      expect(processor.events, hasLength(1));
      expect(processor.events.single.activityId, 'body-event-id');
    });

    test('rows older than the retention window are pruned', () async {
      await post(
        workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{}),
        activityId: 'old',
      );
      expect(db.hookDeliveryCount(), 1);
      expect(db.pruneHookDeliveries(DateTime.now().toUtc().add(const Duration(seconds: 1))), 1);
      expect(db.hookDeliveryCount(), 0);
      // Pruned means "may be delivered again", not "answered twice".
      expect(db.pruneHookDeliveries(DateTime.now().toUtc().subtract(RelayDb.deliveryRetention)), 0);
    });
  });

  // -------------------------------------------------------------------- queue

  group('HookQueue', () {
    RoutingView anyView() =>
        const RoutingView(org: fixtureOrg, kind: HookKind.wiUpdated, eventType: 'workitem.updated');

    test('holds up to its capacity and counts what it drops', () async {
      final blocked = RecordingHookProcessor()..gate = Completer<void>();
      final small = HookQueue(processor: blocked, capacity: 2);

      // The first is taken by the consumer at once and blocks there; the next
      // two fill the queue; everything after that is dropped and counted.
      for (var i = 0; i < 6; i++) {
        small.add(HookEvent(view: anyView()));
      }
      expect(small.depth, 2);
      expect(small.dropped, 3);

      blocked.gate!.complete();
      await small.drain();
      expect(blocked.events, hasLength(3));
      expect(small.processed, 3);
      expect(small.dropped, 3);
    });

    test('a drop is logged with a reason and no payload', () async {
      final blocked = RecordingHookProcessor()..gate = Completer<void>();
      final small = HookQueue(processor: blocked, capacity: 1);
      final lines = await captureLog(() async {
        for (var i = 0; i < 3; i++) {
          small.add(HookEvent(view: anyView()));
        }
      });
      final drops = lines.map(jsonDecode).whereType<Map<String, Object?>>().where((l) => l['msg'] == 'hook dropped');
      expect(drops, hasLength(1));
      expect(drops.single['reason'], 'queue-full');
      blocked.gate!.complete();
      await small.close();
    });

    test('a processor that throws is counted, not fatal', () async {
      final queue = HookQueue(processor: _ThrowingProcessor());
      await captureLog(() async {
        queue.add(HookEvent(view: anyView()));
        await queue.drain();
      });
      expect(queue.failed, 1);
      expect(queue.processed, 0);
    });

    test('the default capacity is 1000', () => expect(HookQueue(processor: processor).capacity, 1000));
  });

  // -------------------------------------------------------------------- admin

  group('admin', () {
    test('without RELAY_ADMIN_SECRET every admin route answers 404', () async {
      server = buildServer(
        ingest: HookIngest(db: db, queue: queue),
      );
      expect((await admin('GET', '/v1/admin/orgs/$fixtureOrg/subscriptions')).statusCode, 404);
      expect(
        (await admin('PUT', '/v1/admin/orgs/$fixtureOrg/hook-secret', body: {'secret': hookSecret})).statusCode,
        404,
      );
      expect((await admin('PUT', '/v1/admin/orgs/$fixtureOrg/subscriptions', body: const [])).statusCode, 404);
    });

    test('a wrong bearer answers 401', () async {
      expect((await admin('GET', '/v1/admin/orgs/$fixtureOrg/subscriptions', bearer: 'nope')).statusCode, 401);
      expect((await admin('GET', '/v1/admin/orgs/$fixtureOrg/subscriptions', bearer: null)).statusCode, 401);
    });

    test('PUT hook-secret stores the hash, never the secret', () async {
      const secret = 'a-brand-new-hook-secret-value';
      final lines = await captureLog(() async {
        final response = await admin('PUT', '/v1/admin/orgs/$otherOrg/hook-secret', body: {'secret': secret});
        expect(response.statusCode, 200);
        expect(await response.readAsString(), isNot(contains(secret)));
      });
      expect(lines.join('\n'), isNot(contains(secret)));

      final row = db.hookOrg(otherOrg)!;
      expect(row.enabled, isTrue, reason: 'a new org is created enabled');
      expect(row.hookSecretHash, sha256Hex(secret));
      expect(row.hookSecretHash, isNot(secret));
      expect(row.hookSecretHash, hasLength(64));
    });

    test('PUT hook-secret refuses a short secret', () async {
      expect((await admin('PUT', '/v1/admin/orgs/$otherOrg/hook-secret', body: {'secret': 'tiny'})).statusCode, 400);
      expect((await admin('PUT', '/v1/admin/orgs/$otherOrg/hook-secret', body: {'secret': 7})).statusCode, 400);
      expect(db.hookOrg(otherOrg), isNull);
    });

    test('PUT subscriptions replaces the whole set', () async {
      final response = await admin(
        'PUT',
        '/v1/admin/orgs/$fixtureOrg/subscriptions',
        body: [
          {
            'subId': 'only-one',
            'eventType': 'build.complete',
            'kind': 'build.complete',
            'projectId': projectGuid,
            'projectName': 'Contoso Demo',
          },
        ],
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString()), {'org': fixtureOrg, 'subscriptions': 1});

      final rows = db.hookSubscriptions(fixtureOrg);
      expect(rows, hasLength(1));
      expect(rows.single.subId, 'only-one');
      expect(rows.single.kind, 'build.complete');
      expect(db.hookSubscription(fixtureOrg, subWiUpdated), isNull);
    });

    test('an invalid kind is a 400 and leaves the old set in place', () async {
      final before = db.hookSubscriptions(fixtureOrg).length;
      final response = await admin(
        'PUT',
        '/v1/admin/orgs/$fixtureOrg/subscriptions',
        body: [
          {'subId': 'good', 'eventType': 'build.complete', 'kind': 'build.complete'},
          {'subId': 'bad', 'eventType': 'workitem.updated', 'kind': 'wi.retitled'},
        ],
      );
      expect(response.statusCode, 400);
      expect(await response.readAsString(), contains('unknown kind'));
      expect(db.hookSubscriptions(fixtureOrg), hasLength(before));
    });

    test('a kind that does not belong to its event is a 400', () async {
      final response = await admin(
        'PUT',
        '/v1/admin/orgs/$fixtureOrg/subscriptions',
        body: [
          {'subId': 'mismatched', 'eventType': 'workitem.updated', 'kind': 'pr.created'},
        ],
      );
      expect(response.statusCode, 400);
    });

    test('a duplicate subId and a non-array body are 400', () async {
      expect(
        (await admin(
          'PUT',
          '/v1/admin/orgs/$fixtureOrg/subscriptions',
          body: [
            {'subId': 'twice', 'eventType': 'build.complete', 'kind': 'build.complete'},
            {'subId': 'twice', 'eventType': 'build.complete', 'kind': 'build.complete'},
          ],
        )).statusCode,
        400,
      );
      expect(
        (await admin('PUT', '/v1/admin/orgs/$fixtureOrg/subscriptions', body: {'not': 'an array'})).statusCode,
        400,
      );
    });

    test('GET subscriptions lists what was registered', () async {
      final response = await admin('GET', '/v1/admin/orgs/$fixtureOrg/subscriptions');
      expect(response.statusCode, 200);
      final decoded = jsonDecode(await response.readAsString()) as Map<String, Object?>;
      expect(decoded['count'], fixtureSubscriptions(fixtureOrg).length);
      final listed = (decoded['subscriptions']! as List).cast<Map<String, Object?>>();
      expect(listed.map((row) => row['kind']), contains('approval.pending'));
      expect(listed.first.keys, containsAll(['subId', 'eventType', 'kind', 'projectId', 'projectName', 'createdAt']));
    });

    test('a registered subscription is what makes a post routable', () async {
      await admin(
        'PUT',
        '/v1/admin/orgs/$fixtureOrg/subscriptions',
        body: [
          {'subId': subBuild, 'eventType': 'build.complete', 'kind': 'build.complete'},
        ],
      );
      expect((await post(buildComplete(subId: subBuild))).statusCode, 200);
      expect(
        (await post(workItemUpdated(subId: subWiUpdated, changes: const <String, Object?>{}))).statusCode,
        404,
        reason: 'the work item subscription was replaced away',
      );
      await queue.drain();
      expect(processor.events.map((e) => e.kind), [HookKind.buildComplete]);
    });
  });

  // ---------------------------------------------------------------- redaction

  group('redaction', () {
    /// One of every kind, each carrying the canary in its title, description,
    /// comment content, History and message text.
    List<Map<String, Object?>> everyKind() => [
      workItemUpdated(
        subId: subWiUpdated,
        changes: {
          'System.Title': {'newValue': 'Renamed to $canary', 'oldValue': canary},
        },
      ),
      workItemCommentNoise(subId: subWiUpdated, history: 'Comment body $canary ${htmlMention(bobId, 'Bob Example')}'),
      workItemCommented(subId: subWiCommented, text: 'Another comment, $canary'),
      workItemCreated(subId: subWiCreated),
      pullRequestCreated(subId: subPrCreated),
      pullRequestUpdated(subId: subPrVote),
      pullRequestComment(subId: subPrComment, content: 'PR comment with $canary and @<$cleoId>'),
      pullRequestMerged(subId: subPrMerged),
      buildComplete(subId: subBuild),
      runStateChanged(subId: subRunState),
      approvalEvent(subId: subApprovalPending),
    ];

    test('no log line carries anything from the body', () async {
      final logging = HookQueue(processor: const LoggingHookProcessor());
      server = buildServer(
        ingest: HookIngest(db: db, queue: logging, adminSecret: adminSecret),
      );

      final lines = await captureLog(() async {
        var n = 0;
        for (final body in everyKind()) {
          final response = await post(body, activityId: 'canary-${n++}');
          expect(response.statusCode, 200, reason: '${body['eventType']} should be accepted');
        }
        await logging.drain();
      });

      final joined = lines.join('\n');
      expect(lines.where((l) => l.contains('"msg":"hook routed"')), hasLength(everyKind().length));
      for (final forbidden in [
        canary,
        'Ada Example',
        'Bob Example',
        'Cleo Example',
        'example.invalid',
        'Fix the thing',
        'Tidy the thing',
        'Renamed to',
        'refs/heads/spike',
      ]) {
        expect(joined, isNot(contains(forbidden)), reason: '"$forbidden" must not reach a log line');
      }
      // What a routed line *does* carry: the kind and ids.
      final routed = jsonDecode(lines.firstWhere((l) => l.contains('"msg":"hook routed"'))) as Map<String, Object?>;
      expect(routed['kind'], 'wi.updated');
      expect(routed['artifactId'], '15545');
      expect(routed.containsKey('title'), isFalse);
    });

    test('nothing from a body reaches the database file', () async {
      final dir = Directory.systemTemp.createTempSync('relay_hooks_db_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final fileDb = RelayDb.open('${dir.path}${Platform.pathSeparator}relay.sqlite')!;
      fileDb.setHookSecretHash(fixtureOrg, sha256Hex(hookSecret));
      // Registered without a project name, so the only strings in the file come
      // from the registry's own ids.
      fileDb.replaceHookSubscriptions(fixtureOrg, fixtureSubscriptions(fixtureOrg, projectName: null));

      final fileQueue = HookQueue(processor: const LoggingHookProcessor());
      final fileServer = RelayServer(
        version: 'test-sha',
        captureSecret: 'unused',
        captures: CaptureStore(Directory.systemTemp),
        dbStatus: 'ok',
        gateway: PushGateway(apns: FakeSender(ready: false), fcm: FakeSender(), db: fileDb),
        registrations: Registrations(
          db: fileDb,
          validator: fakeValidator(const {}),
          gateway: PushGateway(apns: FakeSender(ready: false), fcm: FakeSender(), db: fileDb),
        ),
        hooks: HookIngest(db: fileDb, queue: fileQueue, adminSecret: adminSecret),
      );

      await captureLog(() async {
        var n = 0;
        for (final body in everyKind()) {
          final response = await fileServer.handler(
            Request(
              'POST',
              Uri.parse('http://localhost:8080/hooks/$fixtureOrg'),
              headers: {
                'authorization': basicHeader(hookSecret),
                'content-type': 'application/json',
                'X-VSS-ActivityId': 'file-canary-${n++}',
              },
              body: jsonEncode(body),
            ),
          );
          expect(response.statusCode, 200);
        }
        await fileQueue.drain();
      });

      expect(fileDb.hookDeliveryCount(), everyKind().length);
      fileDb.close();

      final bytes = <int>[for (final entity in dir.listSync().whereType<File>()) ...entity.readAsBytesSync()];
      final blob = latin1.decode(bytes, allowInvalid: true);
      expect(blob, contains(subWiUpdated), reason: 'the delivery ids are there');
      for (final forbidden in [
        canary,
        'Ada Example',
        'Bob Example',
        'Cleo Example',
        'Contoso Demo',
        'example.invalid',
        'Fix the thing',
        adaId,
        hookSecret,
      ]) {
        expect(blob, isNot(contains(forbidden)), reason: '"$forbidden" must not reach the database');
      }
    });
  });
}

class _ThrowingProcessor implements HookProcessor {
  @override
  Future<void> process(HookEvent event) async => throw StateError('boom');
}
