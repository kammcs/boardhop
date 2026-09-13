@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/hooks/ingest.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

// `tool/` is outside `lib/`, so the test reaches it by relative path. That is
// what `dart test` can import; a `package:` URI would need the code in `lib/`,
// which would ship a CLI's argument parsing inside the server image.
import '../tool/src/hooks_commands.dart';
import '../tool/src/hooks_lib.dart';

const org = 'puremedia';
const scratch = 'DevOps Mobile App';
const projectId = '11111111-2222-4333-8444-555555555555';
const otherProjectId = '99999999-2222-4333-8444-555555555555';
const relayUrl = 'https://relay.test';
const pat = 'pat-0123456789abcdef0123456789abcdef';
const adminSecret = 'admin-0123456789abcdef0123456789';
const hookSecret = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

String get hookUrl => '$relayUrl/hooks/$org';

HooksConfig configWith({String allowProject = scratch, String relay = relayUrl}) => HooksConfig.fromEnvironment({
  'ADO_ORG_URL': 'https://dev.azure.com/$org',
  'ADO_PAT': pat,
  'RELAY_URL': relay,
  'RELAY_ADMIN_SECRET': adminSecret,
  'HOOKS_ALLOW_PROJECT': allowProject,
});

/// One recorded call, so a test can assert the order and the bodies.
typedef Call = ({String method, Uri url, String body});

/// A client that records every call and answers from [handler]; any request the
/// handler does not recognise fails the test loudly.
class Recorder {
  Recorder(this.handler);

  final http.Response Function(Call call) handler;
  final calls = <Call>[];

  MockClient get client => MockClient((request) async {
    final call = (method: request.method, url: request.url, body: request.body);
    calls.add(call);
    return handler(call);
  });

  List<Call> where(String method, String contains) => [
    for (final call in calls)
      if (call.method == method && call.url.toString().contains(contains)) call,
  ];
}

http.Response json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A subscription as Azure DevOps returns it.
Map<String, Object?> adoSub({
  required String id,
  required String eventType,
  Map<String, String> publisherInputs = const {},
  String? url,
  String project = projectId,
  String status = 'enabled',
}) => {
  'id': id,
  'eventType': eventType,
  'status': status,
  'publisherInputs': {'projectId': project, ...publisherInputs},
  'consumerInputs': {'url': url ?? hookUrl, 'basicAuthUsername': 'hook'},
};

void main() {
  group('plan', () {
    test('is 14 subscriptions over 11 distinct event ids', () {
      expect(plannedSubscriptions, hasLength(14));
      expect(plannedEventIdCount, 11);
      expect(planTable(), contains('14 subscriptions over 11 distinct event ids'));
    });

    test('has exactly the event ids and versions of research/14 §1', () {
      final rows = [
        for (final plan in plannedSubscriptions)
          '${plan.publisherId} ${plan.eventType} ${plan.resourceVersion} ${plan.filterSummary}',
      ];
      expect(rows, [
        'tfs git.pullrequest.created 1.0 —',
        'tfs git.pullrequest.updated 1.0 notificationType=PushNotification',
        'tfs git.pullrequest.updated 1.0 notificationType=ReviewersUpdateNotification',
        'tfs git.pullrequest.updated 1.0 notificationType=StatusUpdateNotification',
        'tfs git.pullrequest.updated 1.0 notificationType=ReviewerVoteNotification',
        'tfs ms.vss-code.git-pullrequest-comment-event 2.0 —',
        'tfs git.pullrequest.merged 1.0 mergeResult=Unsuccessful',
        'tfs workitem.created 5.1-preview.3 —',
        'tfs workitem.updated 5.1-preview.3 —',
        'tfs workitem.commented 5.1-preview.3 —',
        'tfs build.complete 2.0 —',
        'pipelines ms.vss-pipelines.run-state-changed-event 5.1-preview.1 —',
        'pipelines ms.vss-pipelinechecks-events.approval-pending 5.1-preview.1 —',
        'pipelines ms.vss-pipelinechecks-events.approval-completed 5.1-preview.1 —',
      ]);
    });

    test('leaves stage-state-changed out of the beta set', () {
      expect(
        plannedSubscriptions.map((p) => p.eventType),
        isNot(contains('ms.vss-pipelines.stage-state-changed-event')),
      );
    });

    test('derives every kind from HookKind, the labels the relay stores', () {
      expect(plannedSubscriptions.map((p) => p.kind.label).toList(), [
        'pr.created',
        'pr.updated.push',
        'pr.updated.reviewers',
        'pr.updated.status',
        'pr.updated.vote',
        'pr.comment',
        'pr.merged',
        'wi.created',
        'wi.updated',
        'wi.commented',
        'build.complete',
        'run.state',
        'approval.pending',
        'approval.completed',
      ]);
      // Every label is one the ingest route will accept.
      for (final plan in plannedSubscriptions) {
        expect(HookKind.tryParse(plan.kind.label), isNotNull);
        expect(HookKind.tryParse(plan.kind.label)!.eventType, plan.eventType);
      }
    });

    test('sends the empty-string publisher inputs w22/w24 send', () {
      final byEvent = {for (final plan in plannedSubscriptions) '${plan.eventType}|${plan.notificationType}': plan};
      expect(byEvent['git.pullrequest.created|null']!.filters.keys, [
        'repository',
        'branch',
        'pullrequestCreatedBy',
        'pullrequestReviewersContains',
      ]);
      expect(byEvent['workitem.updated|null']!.filters, {'areaPath': '', 'workItemType': '', 'changedFields': ''});
      expect(byEvent['build.complete|null']!.filters, {'definitionName': '', 'buildStatus': ''});
      expect(byEvent['ms.vss-pipelines.run-state-changed-event|null']!.filters, {
        'pipelineId': '',
        'runStateId': '',
        'runResultId': '',
      });
      expect(byEvent['ms.vss-pipelinechecks-events.approval-pending|null']!.filters, {
        'pipelineId': '',
        'stageName': '',
        'environmentName': '',
      });
    });

    test('prints without calling anything', () {
      final recorder = Recorder((call) => fail('plan must not call ${call.url}'));
      final lines = <String>[];
      final config = configWith();
      HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: lines.add,
      ).plan(org: org, project: scratch);
      expect(recorder.calls, isEmpty);
      expect(lines.join('\n'), contains('$relayUrl/hooks/$org'));
      expect(lines.join('\n'), contains('approval.completed'));
    });
  });

  group('subscription body', () {
    test('is the shape w24 proved works', () {
      final plan = plannedSubscriptions.firstWhere((p) => p.kind == HookKind.prUpdatedVote);
      final body = subscriptionBody(plan: plan, projectId: projectId, url: hookUrl, secret: hookSecret);
      expect(body, {
        'publisherId': 'tfs',
        'eventType': 'git.pullrequest.updated',
        'resourceVersion': '1.0',
        'consumerId': 'webHooks',
        'consumerActionId': 'httpRequest',
        'publisherInputs': {
          'projectId': projectId,
          'repository': '',
          'branch': '',
          'pullrequestCreatedBy': '',
          'pullrequestReviewersContains': '',
          'notificationType': 'ReviewerVoteNotification',
        },
        'consumerInputs': {
          'url': hookUrl,
          'basicAuthUsername': 'hook',
          'basicAuthPassword': hookSecret,
          'resourceDetailsToSend': 'all',
          'messagesToSend': 'text',
          'detailedMessagesToSend': 'text',
        },
      });
    });

    test('uses the username the ingest route checks', () {
      expect(hookUsername, HookIngest.hookUsername);
    });

    test('builds the ingest url without a double slash', () {
      expect(hookUrlFor('https://relay.test/', org), '$relayUrl/hooks/$org');
      expect(hookUrlPrefix('https://relay.test//'), '$relayUrl/hooks/');
    });
  });

  group('matchesPlan', () {
    final vote = plannedSubscriptions.firstWhere((p) => p.kind == HookKind.prUpdatedVote);
    final created = plannedSubscriptions.firstWhere((p) => p.kind == HookKind.prCreated);

    test('matches the same event, filter, project and url', () {
      final sub = adoSub(
        id: 's1',
        eventType: 'git.pullrequest.updated',
        publisherInputs: {'notificationType': 'ReviewerVoteNotification'},
      );
      expect(matchesPlan(sub, vote, projectId: projectId, url: hookUrl), isTrue);
    });

    test('does not match another notificationType, project or url', () {
      final push = adoSub(
        id: 's2',
        eventType: 'git.pullrequest.updated',
        publisherInputs: {'notificationType': 'PushNotification'},
      );
      expect(matchesPlan(push, vote, projectId: projectId, url: hookUrl), isFalse);
      final elsewhere = adoSub(
        id: 's3',
        eventType: 'git.pullrequest.updated',
        publisherInputs: {'notificationType': 'ReviewerVoteNotification'},
        project: otherProjectId,
      );
      expect(matchesPlan(elsewhere, vote, projectId: projectId, url: hookUrl), isFalse);
      final capture = adoSub(
        id: 's4',
        eventType: 'git.pullrequest.updated',
        publisherInputs: {'notificationType': 'ReviewerVoteNotification'},
        url: 'https://relay.test/capture/scratch-r2',
      );
      expect(matchesPlan(capture, vote, projectId: projectId, url: hookUrl), isFalse);
    });

    test('an unfiltered subscription is not the filtered one', () {
      final unfiltered = adoSub(id: 's5', eventType: 'git.pullrequest.updated');
      expect(matchesPlan(unfiltered, vote, projectId: projectId, url: hookUrl), isFalse);
      // …and a filtered merged is not the unfiltered created.
      final merged = adoSub(
        id: 's6',
        eventType: 'git.pullrequest.created',
        publisherInputs: {'mergeResult': 'Unsuccessful'},
      );
      expect(matchesPlan(merged, created, projectId: projectId, url: hookUrl), isFalse);
    });
  });

  group('registry merge', () {
    RegistryRow row(String subId, String project) =>
        RegistryRow(subId: subId, eventType: 'workitem.updated', kind: 'wi.updated', projectId: project);

    test('keeps rows registered for other projects', () {
      final merged = mergeRegistry(
        existing: [row('a', otherProjectId), row('b', projectId), RegistryRow.fromJson(const {})],
        projectId: projectId,
        rows: [row('c', projectId), row('d', projectId)],
      );
      expect(merged.map((r) => r.subId), ['a', '', 'c', 'd']);
    });

    test('an incoming subId always wins, whatever project the old row claimed', () {
      final merged = mergeRegistry(
        existing: [row('a', otherProjectId)],
        projectId: projectId,
        rows: [row('a', projectId)],
      );
      expect(merged, hasLength(1));
      expect(merged.single.projectId, projectId);
    });

    test('removeFromRegistry drops only the named subIds', () {
      final kept = removeFromRegistry(existing: [row('a', projectId), row('b', otherProjectId)], subIds: {'a'});
      expect(kept.map((r) => r.subId), ['b']);
    });

    test('a row serialises to what the admin PUT validates', () {
      final json = RegistryRow(
        subId: 'sub-1',
        eventType: 'git.pullrequest.updated',
        kind: 'pr.updated.vote',
        projectId: projectId,
        projectName: scratch,
      ).toJson();
      expect(json, {
        'subId': 'sub-1',
        'eventType': 'git.pullrequest.updated',
        'kind': 'pr.updated.vote',
        'projectId': projectId,
        'projectName': scratch,
      });
      final kind = HookKind.tryParse(json['kind']! as String)!;
      expect(kind.eventType, json['eventType']);
    });
  });

  group('redaction', () {
    test('an error body echoing the PAT prints <redacted>', () async {
      final recorder = Recorder((call) => http.Response('{"message":"bad token $pat"}', 401));
      final config = configWith();
      final api = HooksHttp(config: config, client: recorder.client);
      final response = await api.ado('GET', '/_apis/projects/x');
      final failure = api.failureFor('could not read', 'https://dev.azure.com/$org/_apis/projects/x', response);
      expect(failure.message, contains('HTTP 401'));
      expect(failure.message, contains('<redacted>'));
      expect(failure.message, isNot(contains(pat)));
    });

    test('redacts the base64 basic-auth form of the PAT too', () {
      final encoded = base64Encode(utf8.encode(':$pat'));
      final text = redactSecrets('Authorization: Basic $encoded', [pat]);
      expect(text, 'Authorization: Basic <redacted>');
    });

    test('redacts the admin secret and cuts the excerpt to 200 characters', () {
      final body = 'x' * 400;
      expect(bodyExcerpt('$body $adminSecret', [adminSecret]).length, 201);
      expect(bodyExcerpt('leak $adminSecret', [adminSecret]), 'leak <redacted>');
    });

    test('a transport error carries no secret', () async {
      final client = MockClient((request) => throw const SocketException('no route'));
      final config = configWith();
      final api = HooksHttp(config: config, client: client);
      await expectLater(
        api.ado('GET', '/_apis/projects/x'),
        throwsA(
          isA<HooksFailure>()
              .having((f) => f.message, 'message', contains('no route'))
              .having((f) => f.message, 'message', isNot(contains(pat))),
        ),
      );
    });
  });

  group('rate limiting', () {
    test('retries once on 429, honouring Retry-After, then gives up', () async {
      var calls = 0;
      final waits = <Duration>[];
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response('slow down', 429, headers: {'retry-after': '2'});
        return json({'id': projectId, 'name': scratch});
      });
      final config = configWith();
      final api = HooksHttp(config: config, client: client, sleep: (d) async => waits.add(d));
      final response = await api.ado('GET', '/_apis/projects/x');
      expect(calls, 2);
      expect(waits, [const Duration(seconds: 2)]);
      expect(response.ok, isTrue);

      // A second 429 is not retried again.
      calls = 0;
      final always = MockClient((request) async => http.Response('slow down', 429, headers: {'retry-after': '1'}));
      final api2 = HooksHttp(config: config, client: always, sleep: (d) async {});
      expect((await api2.ado('GET', '/_apis/projects/x')).status, 429);
    });
  });

  group('the write guard', () {
    test('refuses a project other than HOOKS_ALLOW_PROJECT before any network call', () async {
      final recorder = Recorder((call) => fail('the guard must refuse before calling ${call.url}'));
      final config = configWith();
      final runner = HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: (_) {},
      );
      await expectLater(
        runner.create(org: org, project: 'CloudCover 2.0', secretFile: 'unused'),
        throwsA(isA<HooksFailure>().having((f) => f.message, 'message', contains('refusing to write'))),
      );
      await expectLater(
        runner.delete(org: org, project: 'Product'),
        throwsA(isA<HooksFailure>().having((f) => f.message, 'message', contains('DevOps Mobile App'))),
      );
      expect(recorder.calls, isEmpty);
    });

    test('refuses when HOOKS_ALLOW_PROJECT is unset', () async {
      final recorder = Recorder((call) => fail('no call expected'));
      final config = configWith(allowProject: '');
      final runner = HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: (_) {},
      );
      await expectLater(
        runner.create(org: org, project: scratch, secretFile: 'unused'),
        throwsA(isA<HooksFailure>().having((f) => f.message, 'message', contains('HOOKS_ALLOW_PROJECT is not set'))),
      );
      expect(recorder.calls, isEmpty);
    });

    test('refuses a project whose id resolves to a different name', () async {
      final dir = Directory.systemTemp.createTempSync('hooks-guard');
      addTearDown(() => dir.deleteSync(recursive: true));
      final secretFile = File('${dir.path}/secret')..writeAsStringSync(hookSecret);
      final recorder = Recorder((call) => json({'id': otherProjectId, 'name': 'Something Else'}));
      final config = configWith();
      final runner = HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: (_) {},
      );
      await expectLater(
        runner.create(org: org, project: scratch, secretFile: secretFile.path),
        throwsA(isA<HooksFailure>().having((f) => f.message, 'message', contains('not "DevOps Mobile App"'))),
      );
      expect(recorder.where('POST', 'hooks/subscriptions'), isEmpty);
    });
  });

  group('create end to end', () {
    late Directory dir;
    late File secretFile;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('hooks-create');
      secretFile = File('${dir.path}/.hooks-secret-$org')..writeAsStringSync('$hookSecret\n');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    Recorder recorderFor({List<Map<String, Object?>> existing = const [], List<Object?> registry = const []}) {
      var next = 0;
      return Recorder((call) {
        final path = call.url.path;
        if (call.method == 'GET' && path.contains('/_apis/projects/')) {
          return json({'id': projectId, 'name': scratch});
        }
        if (call.method == 'GET' && path.endsWith('/_apis/hooks/subscriptions')) {
          return json({'count': existing.length, 'value': existing});
        }
        if (call.method == 'POST' && path.endsWith('/_apis/hooks/subscriptions')) {
          next++;
          return json({'id': 'new-$next', 'status': 'enabled'}, 201);
        }
        if (call.method == 'GET' && path.endsWith('/subscriptions')) {
          return json({'org': org, 'count': registry.length, 'subscriptions': registry});
        }
        if (call.method == 'PUT' && path.endsWith('/subscriptions')) {
          return json({'org': org, 'subscriptions': (jsonDecode(call.body) as List).length});
        }
        return fail('unexpected ${call.method} ${call.url}');
      });
    }

    test('creates all fourteen, registers them, and keeps another project rows', () async {
      final recorder = recorderFor(
        registry: [
          {
            'subId': 'other-1',
            'eventType': 'workitem.updated',
            'kind': 'wi.updated',
            'projectId': otherProjectId,
            'projectName': 'Other',
          },
        ],
      );
      final lines = <String>[];
      final config = configWith();
      await HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: lines.add,
      ).create(org: org, project: scratch, secretFile: secretFile.path);

      expect(recorder.where('POST', '/_apis/hooks/subscriptions'), hasLength(14));
      // Every create carries the url, the basic auth and All + text.
      for (final call in recorder.where('POST', '/_apis/hooks/subscriptions')) {
        final body = jsonDecode(call.body) as Map<String, Object?>;
        final consumer = (body['consumerInputs']! as Map).cast<String, Object?>();
        expect(consumer['url'], hookUrl);
        expect(consumer['basicAuthUsername'], 'hook');
        expect(consumer['basicAuthPassword'], hookSecret);
        expect(consumer['resourceDetailsToSend'], 'all');
        expect(consumer['messagesToSend'], 'text');
        expect(consumer['detailedMessagesToSend'], 'text');
        expect((body['publisherInputs']! as Map)['projectId'], projectId);
      }

      final put = recorder.where('PUT', '/v1/admin/orgs/$org/subscriptions').single;
      final rows = (jsonDecode(put.body) as List).cast<Map<String, Object?>>();
      expect(rows, hasLength(15));
      expect(rows.first['subId'], 'other-1', reason: 'the other project stays registered');
      expect(rows.skip(1).map((r) => r['kind']), plannedSubscriptions.map((p) => p.kind.label));
      expect(rows.skip(1).map((r) => r['projectName']).toSet(), {scratch});
      expect(lines.join('\n'), contains('14 created, 0 already there'));
    });

    test('skips a subscription that already exists and still registers it', () async {
      final recorder = recorderFor(
        existing: [
          adoSub(id: 'already-there', eventType: 'workitem.created', publisherInputs: {'areaPath': ''}),
          // Same event, different project: not ours.
          adoSub(id: 'elsewhere', eventType: 'workitem.updated', project: otherProjectId),
          // Same event, the old capture endpoint: not ours either.
          adoSub(id: 'capture', eventType: 'build.complete', url: '$relayUrl/capture/scratch-r2'),
        ],
      );
      final lines = <String>[];
      final config = configWith();
      await HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: lines.add,
      ).create(org: org, project: scratch, secretFile: secretFile.path);

      expect(recorder.where('POST', '/_apis/hooks/subscriptions'), hasLength(13));
      expect(lines.join('\n'), contains('13 created, 1 already there'));
      final rows = (jsonDecode(recorder.where('PUT', '/subscriptions').single.body) as List)
          .cast<Map<String, Object?>>();
      expect(rows, hasLength(14));
      expect(rows.map((r) => r['subId']), contains('already-there'));
    });

    test('a missing secret file stops it before any Azure DevOps call', () async {
      final recorder = recorderFor();
      final config = configWith();
      final runner = HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: (_) {},
      );
      await expectLater(
        runner.create(org: org, project: scratch, secretFile: '${dir.path}/missing'),
        throwsA(isA<HooksFailure>().having((f) => f.message, 'message', contains('no secret file'))),
      );
      expect(recorder.calls, isEmpty);
    });

    test('a failed create reports the status and a redacted excerpt', () async {
      final recorder = Recorder((call) {
        if (call.method == 'GET' && call.url.path.contains('/_apis/projects/')) {
          return json({'id': projectId, 'name': scratch});
        }
        if (call.method == 'GET') return json({'value': const []});
        return http.Response('{"message":"TF400813 with $pat"}', 403);
      });
      final config = configWith();
      final runner = HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: (_) {},
      );
      await expectLater(
        runner.create(org: org, project: scratch, secretFile: secretFile.path),
        throwsA(
          isA<HooksFailure>()
              .having((f) => f.message, 'm', contains('HTTP 403'))
              .having((f) => f.message, 'm', contains('git.pullrequest.created'))
              .having((f) => f.message, 'm', contains('<redacted>'))
              .having((f) => f.message, 'm', isNot(contains(pat))),
        ),
      );
    });
  });

  group('delete end to end', () {
    test('deletes only this org ingest subscriptions for this project', () async {
      final subs = [
        adoSub(id: 'mine-1', eventType: 'workitem.updated'),
        adoSub(id: 'mine-2', eventType: 'build.complete'),
        adoSub(id: 'other-project', eventType: 'workitem.updated', project: otherProjectId),
        adoSub(id: 'other-org', eventType: 'workitem.updated', url: '$relayUrl/hooks/fabrikam'),
        adoSub(id: 'capture', eventType: 'workitem.updated', url: '$relayUrl/capture/scratch-r2'),
      ];
      final registry = [
        {'subId': 'mine-1', 'eventType': 'workitem.updated', 'kind': 'wi.updated', 'projectId': projectId},
        {'subId': 'mine-2', 'eventType': 'build.complete', 'kind': 'build.complete', 'projectId': projectId},
        {'subId': 'keep-me', 'eventType': 'workitem.updated', 'kind': 'wi.updated', 'projectId': otherProjectId},
      ];
      final recorder = Recorder((call) {
        final path = call.url.path;
        if (call.method == 'GET' && path.contains('/_apis/projects/')) {
          return json({'id': projectId, 'name': scratch});
        }
        if (call.method == 'GET' && path.endsWith('/_apis/hooks/subscriptions')) return json({'value': subs});
        if (call.method == 'DELETE') return http.Response('', 204);
        if (call.method == 'GET' && path.endsWith('/subscriptions')) return json({'subscriptions': registry});
        if (call.method == 'PUT') return json({'org': org, 'subscriptions': 1});
        return fail('unexpected ${call.method} ${call.url}');
      });
      final lines = <String>[];
      final config = configWith();
      await HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: lines.add,
      ).delete(org: org, project: scratch);

      final deleted = recorder.where('DELETE', '/_apis/hooks/subscriptions/');
      expect(deleted.map((c) => c.url.pathSegments.last), ['mine-1', 'mine-2']);
      final rows = (jsonDecode(recorder.where('PUT', '/subscriptions').single.body) as List)
          .cast<Map<String, Object?>>();
      expect(rows.map((r) => r['subId']), ['keep-me']);
      expect(lines.join('\n'), contains('2 deleted'));
    });
  });

  group('list', () {
    Recorder recorderFor(List<Map<String, Object?>> subs, List<Object?> registry) => Recorder((call) {
      final path = call.url.path;
      if (call.method == 'GET' && path.contains('/_apis/projects/')) return json({'id': projectId, 'name': scratch});
      if (call.method == 'GET' && path.endsWith('/_apis/hooks/subscriptions')) return json({'value': subs});
      if (call.method == 'GET' && path.endsWith('/subscriptions')) return json({'subscriptions': registry});
      return fail('unexpected ${call.method} ${call.url}');
    });

    test('reports in step when Azure DevOps and the relay agree', () async {
      final recorder = recorderFor(
        [
          adoSub(
            id: 's1',
            eventType: 'git.pullrequest.updated',
            publisherInputs: {'notificationType': 'PushNotification'},
          ),
        ],
        [
          {'subId': 's1', 'eventType': 'git.pullrequest.updated', 'kind': 'pr.updated.push', 'projectId': projectId},
        ],
      );
      final lines = <String>[];
      final config = configWith();
      await HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: lines.add,
      ).list(org: org);
      expect(lines.join('\n'), contains('In step.'));
      expect(lines.join('\n'), contains('pr.updated.push'));
    });

    test('flags an unregistered subscription and a registry orphan', () async {
      final recorder = recorderFor(
        [adoSub(id: 's1', eventType: 'workitem.updated')],
        [
          {'subId': 'ghost', 'eventType': 'build.complete', 'kind': 'build.complete', 'projectId': projectId},
        ],
      );
      final lines = <String>[];
      final config = configWith();
      final runner = HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: lines.add,
      );
      await expectLater(runner.list(org: org), throwsA(isA<HooksFailure>()));
      expect(lines.join('\n'), contains('NOT REGISTERED'));
      expect(lines.join('\n'), contains('REGISTERED but no matching Azure DevOps subscription'));
      expect(lines.join('\n'), contains('2 mismatch(es)'));
    });

    test('ignores subscriptions that do not point at the relay', () async {
      final recorder = recorderFor([
        adoSub(id: 'capture', eventType: 'workitem.updated', url: '$relayUrl/capture/scratch-r2'),
      ], const []);
      final lines = <String>[];
      final config = configWith();
      await HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: lines.add,
      ).list(org: org);
      expect(lines.join('\n'), contains('posting to $relayUrl/hooks/'));
      expect(lines.join('\n'), contains('In step.'));
    });
  });

  group('secret', () {
    test('stores the hash on the relay and writes the plaintext, printing neither', () async {
      final dir = Directory.systemTemp.createTempSync('hooks-secret');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/.hooks-secret-$org';
      String? sent;
      final recorder = Recorder((call) {
        expect(call.method, 'PUT');
        expect(call.url.path, '/v1/admin/orgs/$org/hook-secret');
        sent = (jsonDecode(call.body) as Map)['secret'] as String?;
        return json({'org': org, 'updated': true});
      });
      final lines = <String>[];
      final config = configWith();
      await HooksRunner(
        config: config,
        http: HooksHttp(config: config, client: recorder.client),
        out: lines.add,
      ).secret(org: org, outPath: path);

      final written = File(path).readAsStringSync().trim();
      expect(written, hasLength(64));
      expect(written, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(sent, written);
      expect(lines.join('\n'), isNot(contains(written)));
      expect(lines.join('\n'), contains(path));
    });

    test('generates a different 32-byte secret every time', () {
      final secrets = {for (var i = 0; i < 20; i++) generateHookSecret()};
      expect(secrets, hasLength(20));
      expect(secrets.every((s) => s.length == 64), isTrue);
    });
  });

  group('config', () {
    test('defaults RELAY_URL and strips trailing slashes', () {
      final config = HooksConfig.fromEnvironment(const {'ADO_ORG_URL': 'https://dev.azure.com/puremedia/'});
      expect(config.relayUrl, defaultRelayUrl);
      expect(config.orgUrl, 'https://dev.azure.com/puremedia');
      expect(config.secrets, isEmpty);
    });

    test('names every missing variable at once', () {
      final config = HooksConfig.fromEnvironment(const {});
      expect(
        () => config.require(['ADO_ORG_URL', 'ADO_PAT', 'RELAY_ADMIN_SECRET']),
        throwsA(
          isA<HooksFailure>().having(
            (f) => f.message,
            'm',
            'set ADO_ORG_URL, ADO_PAT, RELAY_ADMIN_SECRET in the environment',
          ),
        ),
      );
    });
  });
}
