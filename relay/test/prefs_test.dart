import 'dart:convert';
import 'dart:io';

import 'package:boardhop_relay/src/capture.dart';
import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/gateway/gateway.dart';
import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/registration.dart';
import 'package:boardhop_relay/src/routing/candidate.dart';
import 'package:boardhop_relay/src/routing/prefs.dart';
import 'package:boardhop_relay/src/server.dart';
import 'package:boardhop_relay/src/verb.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';
import 'support.dart';

/// Two synthetic callers, whose identity ids come from the shared fixtures.
const adaToken = 'ado-bearer-for-ada';
const bobToken = 'ado-bearer-for-bob';
const fcmToken = 'fcm-token-abcdefghijklmnopqrstuvwxyz-012345';

/// research/14 §6 (the preference document, its defaults and what each setting
/// means), D5 (where they live and quiet hours) and the `/v1/prefs` routes.
void main() {
  // ------------------------------------------------------------ the document

  group('the document and its defaults (§6)', () {
    test('a person with no row is on the §6 defaults', () {
      final json = PushPrefs.defaults.toJson();
      expect(json, {
        'enabled': true,
        'workItems': {'assigned': true, 'stateChanged': true, 'comments': 'on', 'anyChangeOnMine': false},
        'pullRequests': {
          'reviewRequested': true,
          'votes': 'on',
          'comments': 'on',
          'completedAbandoned': true,
          'pushes': false,
        },
        'builds': 'failuresAndFixed',
        'approvals': true,
        'quietHours': {'enabled': false, 'start': '22:00', 'end': '07:00', 'exceptApprovals': true},
        'mutedArtifacts': <Object?>[],
        'notActor': true,
      });
    });

    test('round-trips through the stored JSON', () {
      const prefs = PushPrefs(
        workItemsComments: CommentPref.mentionsOnly,
        pullRequestsVotes: VotePref.rejectionsAndWaitsOnly,
        builds: BuildPref.off,
        quietHours: QuietHours(enabled: true, start: '23:30', end: '06:15', exceptApprovals: false),
        mutedArtifacts: [MutedArtifact(type: 'pr', id: '8348')],
      );
      expect(PushPrefs.decode(prefs.encode()).toJson(), prefs.toJson());
    });

    test('an unreadable row falls back to the defaults rather than to silence', () {
      expect(PushPrefs.decode('not json').toJson(), PushPrefs.defaults.toJson());
      expect(PushPrefs.decode(null).toJson(), PushPrefs.defaults.toJson());
    });
  });

  group('validation (a typo must not switch something off)', () {
    String? errorOf(Map<String, Object?> body) => PrefsParser.parse(body).error;

    test('an unknown key is refused, at every level', () {
      expect(errorOf({'enabled': true, 'workitems': <String, Object?>{}}), contains('unknown preference'));
      expect(
        errorOf({
          'workItems': {'assigned': true, 'assinged': true},
        }),
        contains('unknown preference "assinged"'),
      );
      expect(
        errorOf({
          'quietHours': {'from': '22:00'},
        }),
        contains('unknown preference "from"'),
      );
    });

    test('notActor is reported but cannot be set (§5.2 rule 1)', () {
      expect(errorOf({'notActor': false}), 'notActor is not editable');
      expect(errorOf({'notActor': true}), 'notActor is not editable');
    });

    test('a value outside its closed list is refused', () {
      expect(
        errorOf({
          'workItems': {'comments': 'myThreadsOnly'},
        }),
        contains('workItems.comments must be one of on, mentionsOnly, off'),
      );
      expect(errorOf({'builds': 'sometimes'}), contains('builds must be one of'));
      expect(errorOf({'enabled': 'yes'}), 'enabled must be true or false');
      expect(
        errorOf({
          'quietHours': {'start': '9pm'},
        }),
        'quietHours.start must be "HH:mm"',
      );
      expect(
        errorOf({
          'quietHours': {'start': '24:00'},
        }),
        isNotNull,
      );
    });

    test('mutes take either vocabulary and are stored as the family', () {
      final parsed = PrefsParser.parse({
        'mutedArtifacts': [
          {'type': 'pullRequest', 'id': '8348', 'until': '2026-09-14T09:00:00Z'},
          {'type': 'wi', 'id': '15545'},
        ],
      });
      expect(parsed.error, isNull);
      expect(parsed.prefs!.mutedArtifacts.map((m) => m.key), ['pr.8348', 'wi.15545']);
      expect(parsed.prefs!.mutedArtifacts.first.until, DateTime.utc(2026, 9, 14, 9));
    });

    test('a malformed mute is refused', () {
      expect(errorOf({'mutedArtifacts': <Object?>{}}), 'mutedArtifacts must be a list');
      expect(
        errorOf({
          'mutedArtifacts': [
            {'type': 'epic', 'id': '1'},
          ],
        }),
        contains('type must be one of'),
      );
      expect(
        errorOf({
          'mutedArtifacts': [
            {'type': 'pr', 'id': 8348},
          ],
        }),
        contains('id must be'),
      );
      expect(
        errorOf({
          'mutedArtifacts': [
            {'type': 'pr', 'id': '1', 'until': 'tomorrow'},
          ],
        }),
        contains('until must be'),
      );
      expect(
        errorOf({
          'mutedArtifacts': [
            for (var i = 0; i < PushPrefs.maxMutedArtifacts + 1; i++) {'type': 'pr', 'id': '$i'},
          ],
        }),
        contains('at most'),
      );
    });

    test('every key left out keeps its default', () {
      final parsed = PrefsParser.parse({
        'pullRequests': {'pushes': true},
      });
      expect(parsed.prefs!.pullRequestsPushes, isTrue);
      expect(parsed.prefs!.workItemsComments, CommentPref.on);
      expect(parsed.prefs!.builds, BuildPref.failuresAndFixed);
    });
  });

  // ------------------------------------------------- what a setting means

  group('what each setting means', () {
    StoredPrefs prefsOf(PushPrefs prefs, {DateTime? now}) =>
        StoredPrefs(prefs, clock: () => now ?? DateTime.utc(2026, 9, 13, 12));

    bool allows(
      StoredPrefs prefs,
      Verb verb, {
      CandidateReason reason = CandidateReason.assignee,
      String? detail,
      String? artifactKey,
    }) => prefs.allows(verb, reason: reason, detail: detail, artifactKey: artifactKey);

    test('the master switch stops everything, approvals included', () {
      final prefs = prefsOf(const PushPrefs(enabled: false));
      for (final verb in Verb.values) {
        expect(allows(prefs, verb), isFalse, reason: verb.name);
      }
    });

    test('the defaults are D2 and D3', () {
      const prefs = DefaultPrefs();
      expect(allows(prefs, Verb.assigned), isTrue);
      expect(allows(prefs, Verb.stateChanged), isTrue);
      expect(allows(prefs, Verb.edited), isFalse, reason: 'workItems.anyChangeOnMine is off (D2)');
      expect(allows(prefs, Verb.pushed), isFalse, reason: 'pullRequests.pushes is off');
      expect(allows(prefs, Verb.buildFailed), isTrue);
      expect(allows(prefs, Verb.buildFixed), isTrue, reason: 'failures and fixed (D3)');
      expect(allows(prefs, Verb.buildSucceeded), isFalse);
      expect(allows(prefs, Verb.approvalPending), isTrue);
    });

    test('workItems.comments: on, mentions only, off', () {
      for (final (setting, comment, mention) in [
        (CommentPref.on, true, true),
        (CommentPref.mentionsOnly, false, true),
        (CommentPref.off, false, false),
      ]) {
        final prefs = prefsOf(PushPrefs(workItemsComments: setting));
        expect(allows(prefs, Verb.commented, artifactKey: 'wi.15545'), comment, reason: '${setting.name} / commented');
        expect(
          allows(prefs, Verb.mentioned, reason: CandidateReason.mention, artifactKey: 'wi.15545'),
          mention,
          reason: '${setting.name} / mentioned',
        );
      }
    });

    test('pullRequests.comments: my threads only keeps the thread and the mention', () {
      final prefs = prefsOf(const PushPrefs(pullRequestsComments: PrCommentPref.myThreadsOnly));
      bool forReason(CandidateReason reason) => allows(prefs, Verb.replied, reason: reason, artifactKey: 'pr.8348');
      expect(forReason(CandidateReason.threadParticipant), isTrue);
      expect(forReason(CandidateReason.author), isFalse, reason: 'a thread you have not spoken in');
      expect(forReason(CandidateReason.votedReviewer), isFalse);
      expect(allows(prefs, Verb.mentioned, reason: CandidateReason.mention, artifactKey: 'pr.8348'), isTrue);
    });

    test('pullRequests.votes: rejections and waits only', () {
      final prefs = prefsOf(const PushPrefs(pullRequestsVotes: VotePref.rejectionsAndWaitsOnly));
      for (final (label, heard) in [
        ('rejected', true),
        ('waitingForAuthor', true),
        ('approved', false),
        ('approvedWithSuggestions', false),
        (null, false),
      ]) {
        expect(
          allows(prefs, Verb.voted, reason: CandidateReason.author, detail: label, artifactKey: 'pr.8348'),
          heard,
          reason: '$label',
        );
      }
      final all = prefsOf(const PushPrefs());
      expect(allows(all, Verb.voted, reason: CandidateReason.author, detail: 'approved'), isTrue);
    });

    test('builds: failures, failures and fixed, all, off', () {
      final expected = {
        BuildPref.failures: (true, false, false),
        BuildPref.failuresAndFixed: (true, true, false),
        BuildPref.all: (true, true, true),
        BuildPref.off: (false, false, false),
      };
      expected.forEach((setting, outcome) {
        final prefs = prefsOf(PushPrefs(builds: setting));
        final (failed, fixed, succeeded) = outcome;
        expect(allows(prefs, Verb.buildFailed), failed, reason: '${setting.name} / failed');
        expect(allows(prefs, Verb.buildFixed), fixed, reason: '${setting.name} / fixed');
        expect(allows(prefs, Verb.buildSucceeded), succeeded, reason: '${setting.name} / succeeded');
      });
    });

    test('a mute drops everything about one artifact until it lapses', () {
      final now = DateTime.utc(2026, 9, 13, 12);
      final prefs = prefsOf(
        PushPrefs(
          mutedArtifacts: [
            MutedArtifact(type: 'pr', id: '8348', until: now.add(const Duration(hours: 24))),
            const MutedArtifact(type: 'wi', id: '15545'),
          ],
        ),
        now: now,
      );
      expect(allows(prefs, Verb.reviewRequested, artifactKey: 'pr.8348'), isFalse);
      expect(allows(prefs, Verb.mentioned, reason: CandidateReason.mention, artifactKey: 'pr.8348'), isFalse);
      expect(allows(prefs, Verb.reviewRequested, artifactKey: 'pr.8349'), isTrue, reason: 'another PR');
      expect(allows(prefs, Verb.assigned, artifactKey: 'wi.15545'), isFalse, reason: 'muted for good');

      final later = prefsOf(
        PushPrefs(
          mutedArtifacts: [MutedArtifact(type: 'pr', id: '8348', until: now.add(const Duration(hours: 24)))],
        ),
        now: now.add(const Duration(hours: 25)),
      );
      expect(later.allows(Verb.reviewRequested, reason: CandidateReason.reviewer, artifactKey: 'pr.8348'), isTrue);
    });

    test('quiet hours are the device\'s local time, and wrap midnight', () {
      const prefs = PushPrefs(quietHours: QuietHours(enabled: true));
      final stored = StoredPrefs(prefs);
      // 02:00 UTC: the middle of the night in UTC, late morning in Tokyo.
      final night = DateTime.utc(2026, 9, 13, 2);
      expect(stored.quietHoursSuppress(Verb.assigned, night, null), isTrue);
      expect(stored.quietHoursSuppress(Verb.assigned, night, 540), isFalse, reason: 'UTC+9: 11:00');
      expect(stored.quietHoursSuppress(Verb.assigned, night, -480), isFalse, reason: 'UTC-8: 18:00 yesterday');
      expect(
        stored.quietHoursSuppress(Verb.assigned, DateTime.utc(2026, 9, 13, 8), -480),
        isTrue,
        reason: 'UTC-8: midnight, inside a window that wraps',
      );
      // Midday everywhere in the window's terms.
      expect(stored.quietHoursSuppress(Verb.assigned, DateTime.utc(2026, 9, 13, 12), 0), isFalse);
      // Quiet hours off: never suppressed.
      expect(const StoredPrefs(PushPrefs()).quietHoursSuppress(Verb.assigned, night, null), isFalse);
    });

    test('approvals are exempt by default, and not when that is turned off', () {
      final night = DateTime.utc(2026, 9, 13, 2);
      const exempt = StoredPrefs(PushPrefs(quietHours: QuietHours(enabled: true)));
      expect(exempt.quietHoursSuppress(Verb.approvalPending, night, null), isFalse);
      expect(exempt.quietHoursSuppress(Verb.approvalCompleted, night, null), isFalse);

      const strict = StoredPrefs(PushPrefs(quietHours: QuietHours(enabled: true, exceptApprovals: false)));
      expect(strict.quietHoursSuppress(Verb.approvalPending, night, null), isTrue);
    });
  });

  // --------------------------------------------------------- in the engine

  group('the engine honours them (§6 through the whole pipeline)', () {
    test('a muted pull request produces nothing at all', () async {
      final harness = RoutingHarness(
        prefs: const StoredPrefs(
          PushPrefs(
            mutedArtifacts: [MutedArtifact(type: 'pr', id: '8348')],
          ),
        ),
      );
      expect(await harness.run(viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub'))), isEmpty);
      // A different PR is untouched.
      final other = await harness.run(
        viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub', pullRequestId: 8349)),
      );
      expect(other.single.verb, Verb.reviewRequested);
    });

    test('quiet hours use the offset the device reported', () async {
      const prefs = StoredPrefs(PushPrefs(quietHours: QuietHours(enabled: true)));
      final night = DateTime.utc(2026, 9, 13, 2);

      final asleep = RoutingHarness(prefs: prefs, now: night);
      expect(await asleep.run(viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub'))), isEmpty);

      final awake = RoutingHarness(prefs: prefs, now: night, tzOffsetMinutes: 540);
      expect(
        (await awake.run(viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub')))).single.verb,
        Verb.reviewRequested,
      );
    });

    test('"mentions only" on work items keeps the mention and drops the comment', () async {
      final harness = RoutingHarness(prefs: const StoredPrefs(PushPrefs(workItemsComments: CommentPref.mentionsOnly)));
      final notifications = await harness.run(
        viewOf(
          HookKind.wiUpdated,
          workItemCommentNoise(
            subId: 'sub',
            actorId: bobId,
            creatorId: cleoId,
            currentAssignedTo: identity(adaId, 'Ada Example'),
            history: 'have a look ${htmlMention(cleoId, 'Cleo Example')}',
          ),
        ),
      );
      expect(notifications.map((n) => n.verb), [Verb.mentioned]);
      expect(notifications.single.recipients, {cleoId});
    });

    test('"my threads only" keeps the participant and drops the author', () async {
      final harness = RoutingHarness(
        prefs: const StoredPrefs(PushPrefs(pullRequestsComments: PrCommentPref.myThreadsOnly)),
      );
      // Cleo speaks first, which is what puts her in `pr_thread_state`.
      await harness.run(
        viewOf(HookKind.prComment, pullRequestComment(subId: 'sub', authorId: cleoId, content: 'first', eventId: 'e1')),
      );
      final notifications = await harness.run(
        viewOf(HookKind.prComment, pullRequestComment(subId: 'sub', authorId: bobId, content: 'second', eventId: 'e2')),
      );
      final recipients = harness.recipientsOf(notifications);
      expect(recipients, contains(cleoId), reason: 'already in the thread');
      expect(recipients, isNot(contains(adaId)), reason: 'the PR author, who has not spoken in it');
    });

    test('"rejections and waits only" drops an approval vote', () async {
      const prefs = StoredPrefs(PushPrefs(pullRequestsVotes: VotePref.rejectionsAndWaitsOnly));
      final quiet = RoutingHarness(prefs: prefs);
      expect(
        await quiet.run(
          viewOf(HookKind.prUpdatedVote, pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId, vote: 10)])),
        ),
        isEmpty,
      );

      final loud = RoutingHarness(prefs: prefs);
      final notifications = await loud.run(
        viewOf(HookKind.prUpdatedVote, pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId, vote: -10)])),
      );
      expect(notifications.single.verb, Verb.voted);
      expect(notifications.single.detail, 'rejected');
    });
  });

  // ------------------------------------------------------------- the routes

  group('GET/PUT /v1/prefs', () {
    late RelayDb db;
    late RelayServer server;

    setUp(() {
      db = RelayDb.openMemory()!;
      final gateway = PushGateway(apns: FakeSender(), fcm: FakeSender(), db: db);
      server = RelayServer(
        version: 'test-sha',
        captureSecret: 'unused',
        captures: CaptureStore(Directory.systemTemp),
        dbStatus: 'ok',
        gateway: gateway,
        registrations: Registrations(
          db: db,
          validator: fakeValidator(const {adaToken: adaId, bobToken: bobId}, orgs: const {fixtureOrg}),
          gateway: gateway,
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

    test('answers the defaults when nothing is stored', () async {
      final response = await call('GET', '/v1/prefs?org=$fixtureOrg', bearer: adaToken);
      expect(response.statusCode, 200);
      expect(await json(response), PushPrefs.defaults.toJson());
    });

    test('stores per (org, userId) and answers what it stored', () async {
      final put = await call(
        'PUT',
        '/v1/prefs?org=$fixtureOrg',
        bearer: adaToken,
        body: {
          'workItems': {'anyChangeOnMine': true},
          'builds': 'all',
          'quietHours': {'enabled': true, 'start': '23:00', 'end': '06:30'},
          'mutedArtifacts': [
            {'type': 'pullRequest', 'id': '8348'},
          ],
        },
      );
      expect(put.statusCode, 200);
      final stored = await json(put);
      expect((stored['workItems']! as Map)['anyChangeOnMine'], true);
      expect(stored['builds'], 'all');
      expect((stored['quietHours']! as Map)['start'], '23:00');
      expect(stored['mutedArtifacts'], [
        {'type': 'pr', 'id': '8348'},
      ]);

      expect(await json(await call('GET', '/v1/prefs?org=$fixtureOrg', bearer: adaToken)), stored);
      // Somebody else in the same org still has the defaults: the row is keyed
      // by identity, not by org.
      expect(await json(await call('GET', '/v1/prefs?org=$fixtureOrg', bearer: bobToken)), PushPrefs.defaults.toJson());
      // And the engine reads exactly that row.
      final prefs = DbPrefsSource(db).prefsFor(fixtureOrg, adaId);
      expect(prefs.allows(Verb.edited, reason: CandidateReason.assignee), isTrue);
      expect(prefs.allows(Verb.reviewRequested, reason: CandidateReason.reviewer, artifactKey: 'pr.8348'), isFalse);
    });

    test('a bad key or value is a 400 and changes nothing', () async {
      await call('PUT', '/v1/prefs?org=$fixtureOrg', bearer: adaToken, body: {'builds': 'off'});
      for (final body in [
        {'buidls': 'off'},
        {'builds': 'sometimes'},
        {'notActor': false},
        {
          'quietHours': {'start': '9pm'},
        },
      ]) {
        final response = await call('PUT', '/v1/prefs?org=$fixtureOrg', bearer: adaToken, body: body);
        expect(response.statusCode, 400, reason: '$body');
        expect((await json(response))['error'], isA<String>());
      }
      expect((await json(await call('GET', '/v1/prefs?org=$fixtureOrg', bearer: adaToken)))['builds'], 'off');
    });

    test('needs the same bearer as /v1/devices, for the same org', () async {
      expect((await call('GET', '/v1/prefs?org=$fixtureOrg')).statusCode, 401);
      expect((await call('GET', '/v1/prefs?org=$fixtureOrg', bearer: 'nonsense')).statusCode, 401);
      expect((await call('GET', '/v1/prefs?org=other-org', bearer: adaToken)).statusCode, 401);
      expect((await call('GET', '/v1/prefs', bearer: adaToken)).statusCode, 400);
      expect((await call('PUT', '/v1/prefs?org=$fixtureOrg', bearer: adaToken)).statusCode, 400);
    });

    test('the kill switch stops them too', () async {
      db.setOrgEnabled(fixtureOrg, false);
      expect((await call('GET', '/v1/prefs?org=$fixtureOrg', bearer: adaToken)).statusCode, 403);
      expect(
        (await call('PUT', '/v1/prefs?org=$fixtureOrg', bearer: adaToken, body: {'builds': 'off'})).statusCode,
        403,
      );
    });

    test('a prefs write never stores anything but the document', () async {
      final lines = await captureLog(() async {
        await call('PUT', '/v1/prefs?org=$fixtureOrg', bearer: adaToken, body: {'builds': 'off'});
      });
      final joined = lines.join('\n');
      expect(joined, contains('"msg":"prefs saved"'));
      expect(joined, isNot(contains(adaToken)));
    });
  });

  // ------------------------------------------------- tzOffsetMinutes (§6, D5)

  group('the device time zone', () {
    late RelayDb db;
    late RelayServer server;

    setUp(() {
      db = RelayDb.openMemory()!;
      final gateway = PushGateway(apns: FakeSender(), fcm: FakeSender(), db: db);
      server = RelayServer(
        version: 'test-sha',
        captureSecret: 'unused',
        captures: CaptureStore(Directory.systemTemp),
        dbStatus: 'ok',
        gateway: gateway,
        registrations: Registrations(
          db: db,
          validator: fakeValidator(const {adaToken: adaId}, orgs: const {fixtureOrg}),
          gateway: gateway,
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

    Future<String> register({int? tzOffsetMinutes}) async {
      final response = await call(
        'POST',
        '/v1/devices',
        bearer: adaToken,
        body: {
          'org': fixtureOrg,
          'platform': 'android',
          'token': fcmToken,
          if (tzOffsetMinutes != null) 'tzOffsetMinutes': tzOffsetMinutes,
        },
      );
      expect(response.statusCode, 200);
      return (jsonDecode(await response.readAsString()) as Map<String, Object?>)['deviceId']! as String;
    }

    test('registration takes it and the heartbeat moves it', () async {
      final deviceId = await register(tzOffsetMinutes: 60);
      expect(db.deviceById(deviceId)!.tzOffsetMinutes, 60);
      expect(db.timeZoneOffsetMinutes(fixtureOrg, adaId), 60);

      // Kelly lands in Tokyo.
      final beat = await call(
        'POST',
        '/v1/devices/$deviceId/heartbeat',
        bearer: adaToken,
        body: {'tzOffsetMinutes': 540},
      );
      expect(beat.statusCode, 200);
      expect(db.deviceById(deviceId)!.tzOffsetMinutes, 540);

      // A heartbeat that does not mention it leaves it alone.
      await call('POST', '/v1/devices/$deviceId/heartbeat', bearer: adaToken, body: {'appVersion': '1.0.1'});
      expect(db.deviceById(deviceId)!.tzOffsetMinutes, 540);
    });

    test('an offset outside UTC-14..UTC+14 is a 400', () async {
      final deviceId = await register(tzOffsetMinutes: 0);
      for (final bad in [841, -841, 'PST']) {
        final response = await call(
          'POST',
          '/v1/devices/$deviceId/heartbeat',
          bearer: adaToken,
          body: {'tzOffsetMinutes': bad},
        );
        expect(response.statusCode, 400, reason: '$bad');
      }
      final registration = await call(
        'POST',
        '/v1/devices',
        bearer: adaToken,
        body: {'org': fixtureOrg, 'platform': 'ios', 'token': 'a' * 64, 'tzOffsetMinutes': -1000},
      );
      expect(registration.statusCode, 400);
    });

    test('the column is added to a database that predates it', () async {
      // A relay upgraded in place: schema 4 has `devices` without the column,
      // and the migration must add it rather than re-create the table.
      final dir = Directory.systemTemp.createTempSync('relay_schema5_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}relay.sqlite';

      final old = RelayDb.open(path)!;
      old.registerDevice(org: fixtureOrg, userId: adaId, platform: 'android', token: fcmToken);
      old.close();
      // Drop the column the way an older schema had it, then re-open.
      final raw = sqlite3.open(path);
      raw.execute('ALTER TABLE devices DROP COLUMN tz_offset_minutes;');
      raw.dispose();

      final upgraded = RelayDb.open(path)!;
      addTearDown(upgraded.close);
      expect(upgraded.schemaColumns()['devices'], contains('tz_offset_minutes'));
      expect(upgraded.devicesFor(fixtureOrg, adaId), hasLength(1), reason: 'the rows survive');
      expect(upgraded.timeZoneOffsetMinutes(fixtureOrg, adaId), isNull);
    });

    test('no device has reported one: the window is evaluated in UTC', () async {
      await register();
      expect(db.timeZoneOffsetMinutes(fixtureOrg, adaId), isNull);
      expect(DbPrefsSource(db).timeZoneOffsetMinutes(fixtureOrg, adaId), isNull);
    });
  });
}
