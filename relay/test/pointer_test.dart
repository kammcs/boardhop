import 'dart:convert';

import 'package:boardhop_relay/src/gateway/apns.dart';
import 'package:boardhop_relay/src/gateway/fcm.dart';
import 'package:boardhop_relay/src/gateway/pointer.dart';
import 'package:boardhop_relay/src/verb.dart';
import 'package:test/test.dart';

/// A pull request pointer, the R2.3 shape (research/14 §3.2).
PushPointer pr({
  String? title,
  String? deepLink,
  String? actor,
  Verb? verb,
  String? detail,
  String? anchor,
  String? collapseKey,
  DateTime? sentAt,
}) => PushPointer(
  org: 'contoso',
  eventType: 'ms.vss-code.git-pullrequest-comment-event',
  artifactType: PushArtifactType.pullRequest,
  artifactId: '8348',
  project: 'Contoso Demo',
  title: title,
  deepLink: deepLink,
  actor: actor,
  actorId: 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
  verb: verb,
  detail: detail,
  anchor: anchor,
  collapseKey: collapseKey,
  sentAt: sentAt,
);

void main() {
  group('the pointer contract', () {
    test('carries ids, and a title no longer than 80 characters', () {
      final pointer = pr(title: 'x' * 200);
      expect(pointer.title!.length, PushPointer.maxTitle);
      expect(pointer.title, endsWith('…'));
    });

    test('an actor is a display name capped at 60 characters', () {
      expect(pr(actor: 'y' * 200).actor!.length, PushPointer.maxActor);
      expect(pr(actor: '   ').actor, isNull);
    });

    test('an empty or blank title becomes null rather than an empty line', () {
      expect(pr(title: '   ').title, isNull);
      expect(pr().title, isNull);
    });

    test('the data payload carries every v2 field, all as strings', () {
      final pointer = PushPointer(
        org: 'contoso',
        eventType: 'ms.vss-pipelinechecks-events.approval-pending',
        artifactType: PushArtifactType.approval,
        artifactId: '18',
        project: 'Contoso Demo',
        title: 'contoso-scratch → Deploy',
        deepLink: '/projects/Contoso%20Demo/pipelines?tab=approvals&approval=18',
        actor: 'Ada Example',
        actorId: 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
        verb: Verb.approvalPending,
        detail: 'Deploy',
        anchor: 'approval:18',
        runId: '20163',
        subId: '33333333-3333-4333-8333-333333333333',
        sentAt: DateTime.utc(2026, 9, 13, 15, 51),
      );
      final data = pointer.toData();
      expect(data.keys.toSet(), {
        'org',
        'eventType',
        'artifactType',
        'artifactId',
        'project',
        'title',
        'deepLink',
        'actor',
        'actorId',
        'verb',
        'detail',
        'anchor',
        'runId',
        'subId',
        'sentAt',
      });
      expect(data['verb'], 'approvalPending');
      expect(data['anchor'], 'approval:18');
      expect(data['sentAt'], '2026-09-13T15:51:00.000Z');
      for (final value in data.values) {
        expect(value, isA<String>());
      }
    });

    test('round-trips through tryFromJson', () {
      final pointer = pr(
        title: '!8348 · Tidy the thing',
        deepLink: '/pull-requests/8348?thread=4821',
        actor: 'Ada Example',
        verb: Verb.replied,
        anchor: 'thread:4821',
        collapseKey: 'contoso.pr.8348.t4821',
        sentAt: DateTime.utc(2026, 9, 13, 16),
      );
      final back = PushPointer.tryFromJson({...pointer.toData(), 'collapseKey': pointer.collapseId})!;
      expect(back.toData(), pointer.toData());
      expect(back.verb, Verb.replied);
      expect(back.collapseId, 'contoso.pr.8348.t4821');
      expect(back.sentAt, pointer.sentAt);
    });

    test('a verb outside the closed list is dropped, not carried', () {
      final body = {...pr(verb: Verb.replied).toData(), 'verb': 'exfiltrated'};
      final back = PushPointer.tryFromJson(body)!;
      expect(back.verb, isNull);
      expect(back.toData().containsKey('verb'), isFalse);
    });

    test('a detail outside its verb\'s vocabulary is dropped', () {
      // `voted` has a closed list: the four vote labels and nothing else.
      expect(pr(verb: Verb.voted, detail: 'rejected').detail, 'rejected');
      expect(pr(verb: Verb.voted, detail: 'Fix the tests first').detail, isNull);
      // A free-form detail (a state name) is only length-capped.
      expect(pr(verb: Verb.stateChanged, detail: 'In Progress').detail, 'In Progress');
      expect(pr(verb: Verb.stateChanged, detail: 'z' * 80).detail!.length, Verb.maxDetail);
      // No verb, no detail: there is nothing to validate it against.
      expect(pr(detail: 'anything').detail, isNull);
    });

    test('an anchor that is not one of the four shapes is dropped', () {
      for (final good in ['comment:12', 'thread:4821', 'approval:18', 'tab:files']) {
        expect(pr(anchor: good).anchor, good, reason: good);
      }
      for (final bad in [
        'tab:secrets',
        'comment:',
        'https://example.invalid',
        'comment:12;drop',
        'thread:${'9' * 80}',
      ]) {
        expect(pr(anchor: bad).anchor, isNull, reason: bad);
      }
    });

    test('an id that does not fit is dropped rather than truncated', () {
      final pointer = PushPointer(
        org: 'contoso',
        eventType: 'workitem.updated',
        artifactType: PushArtifactType.workItem,
        artifactId: '15545',
        project: 'Contoso Demo',
        actorId: 'a' * 100,
        runId: '  ',
      );
      expect(pointer.actorId, isNull);
      expect(pointer.runId, isNull);
    });

    test('the longest legal pointer still fits the 1 KB budget (§3.2)', () {
      final longest = PushPointer(
        org: 'o' * 64,
        eventType: 'ms.vss-pipelinechecks-events.approval-pending',
        artifactType: PushArtifactType.workItem,
        artifactId: '9' * 12,
        project: 'p' * 64,
        title: 't' * 120,
        deepLink: '/projects/${'p' * 64}/work-items/999999999999?comment=${'9' * 20}',
        actor: 'a' * 120,
        actorId: 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
        verb: Verb.stateChanged,
        detail: 'd' * 60,
        anchor: 'comment:${'9' * 20}',
        runId: '99999999',
        subId: '33333333-3333-4333-8333-333333333333',
        sentAt: DateTime.utc(2026, 9, 13, 15, 51),
      );
      expect(longest.dataBytes, lessThan(PushPointer.dataBudget));
    });

    test('the collapse id is the routed key when there is one, else per artifact', () {
      expect(pr().collapseId, 'contoso.pullRequest.8348');
      expect(pr(collapseKey: 'contoso.pr.8348.t4821').collapseId, 'contoso.pr.8348.t4821');
      expect(pr().collapseFamily, 'pr');
      final huge = PushPointer(
        org: 'o' * 90,
        eventType: 'workitem.updated',
        artifactType: PushArtifactType.workItem,
        artifactId: '15503',
        project: 'p',
      );
      expect(huge.collapseId.length, PushPointer.maxCollapseKey);
      expect(huge.collapseFamily, 'wi');
    });

    test('tryFromJson refuses an artifact type outside the four', () {
      Map<String, Object?> body(String type) => {
        'org': 'contoso',
        'eventType': 'workitem.updated',
        'artifactType': type,
        'artifactId': '15503',
        'project': 'Contoso Demo',
      };
      expect(PushPointer.tryFromJson(body('workItem')), isNotNull);
      expect(PushPointer.tryFromJson(body('comment')), isNull);
      expect(PushPointer.tryFromJson(const {'org': 'contoso'}), isNull);
    });
  });

  // --------------------------------------------------------- the alert lines

  group('the fallback line (§3.1)', () {
    test('the title is the artifact line the relay already built', () {
      expect(pr(title: '!8348 · Tidy the thing').notificationTitle, '!8348 · Tidy the thing');
      // Nothing to show: the artifact, never a guess at content.
      expect(pr().notificationTitle, 'Pull request 8348');
    });

    test('the test push keeps its own heading', () {
      final pointer = PushPointer(
        org: 'contoso',
        eventType: 'boardhop.test',
        artifactType: PushArtifactType.build,
        artifactId: '0',
        project: '',
        title: 'Push is working',
        verb: Verb.test,
      );
      expect(pointer.notificationTitle, 'Boardhop');
      expect(pointer.notificationBody, 'Push is working');
      expect(pointer.notificationSubtitle, isNull);
    });

    test('the subtitle is the project and nothing else', () {
      expect(pr().notificationSubtitle, 'Contoso Demo');
    });

    test('the four lines research/14 §3.1 names', () {
      PushPointer wi(Verb verb, {String? actor, String? detail}) => PushPointer(
        org: 'contoso',
        eventType: 'workitem.updated',
        artifactType: PushArtifactType.workItem,
        artifactId: '15545',
        project: 'Contoso Demo',
        actor: actor,
        verb: verb,
        detail: detail,
      );

      expect(wi(Verb.assigned, actor: 'Ada Example').notificationBody, 'Ada Example assigned you');
      expect(pr(verb: Verb.replied, actor: 'Ada Example').notificationBody, 'Ada Example replied on !8348');
      expect(
        PushPointer(
          org: 'contoso',
          eventType: 'build.complete',
          artifactType: PushArtifactType.build,
          artifactId: '20163',
          project: 'Contoso Demo',
          verb: Verb.buildFailed,
          detail: 'failed',
        ).notificationBody,
        'Build failed',
      );
      expect(
        PushPointer(
          org: 'contoso',
          eventType: 'ms.vss-pipelinechecks-events.approval-pending',
          artifactType: PushArtifactType.approval,
          artifactId: '18',
          project: 'Contoso Demo',
          verb: Verb.approvalPending,
        ).notificationBody,
        'Needs your approval',
      );
    });

    test('every verb has a phrase, with an actor and without', () {
      for (final verb in Verb.values) {
        final named = pr(verb: verb, actor: 'Ada Example', detail: _detailFor(verb)).notificationBody;
        final anonymous = pr(verb: verb, detail: _detailFor(verb)).notificationBody;
        expect(named, startsWith('Ada Example '), reason: verb.name);
        expect(named.length, greaterThan('Ada Example '.length), reason: verb.name);
        expect(anonymous, isNotEmpty, reason: verb.name);
        // A service identity's line starts with a capital and never leaves a
        // dangling template.
        expect(anonymous[0], anonymous[0].toUpperCase(), reason: verb.name);
        for (final line in [named, anonymous]) {
          expect(line, isNot(contains('{')), reason: verb.name);
          expect(line, isNot(contains('null')), reason: verb.name);
          expect(line, isNot(contains('  ')), reason: verb.name);
        }
      }
    });

    test('a vote reads as its label, and an unlabelled one still reads', () {
      expect(
        pr(verb: Verb.voted, actor: 'Ada Example', detail: 'rejected').notificationBody,
        'Ada Example rejected !8348',
      );
      expect(
        pr(verb: Verb.voted, actor: 'Ada Example', detail: 'waitingForAuthor').notificationBody,
        'Ada Example is waiting for the author !8348',
      );
      expect(pr(verb: Verb.voted).notificationBody, 'New vote !8348');
    });

    test('no line carries anything but metadata', () {
      // The only strings that can reach an alert are the title, the actor and
      // a closed-vocabulary detail; the body is built from the verb table.
      final pointer = pr(title: '!8348 · Tidy the thing', actor: 'Ada Example', verb: Verb.commented);
      expect(pointer.notificationBody, 'Ada Example commented on !8348');
    });
  });

  // ------------------------------------------------------------------- APNs

  group('the APNs payload (§3.3, D6)', () {
    final sender = ApnsSender(keyFile: 'nowhere.p8', keyId: '', teamId: '', topic: 'com.kammcs.boardhop');

    test('is an enrichable alert with the pointer beside aps', () {
      final pointer = pr(
        title: '!8348 · Tidy the thing',
        actor: 'Ada Example',
        verb: Verb.replied,
        anchor: 'thread:4821',
        collapseKey: 'contoso.pr.8348.t4821',
        deepLink: '/pull-requests/8348?thread=4821',
        sentAt: DateTime.utc(2026, 9, 13, 16),
      );
      final payload = sender.payload(pointer);
      final aps = payload['aps']! as Map<String, Object?>;
      final alert = aps['alert']! as Map<String, Object?>;

      expect(aps['mutable-content'], 1);
      expect(aps['thread-id'], 'contoso.pr.8348.t4821');
      expect(aps['interruption-level'], 'active');
      expect(aps['category'], 'boardhop.pointer');
      expect(alert['title'], '!8348 · Tidy the thing');
      expect(alert['subtitle'], 'Contoso Demo');
      expect(alert['body'], 'Ada Example replied on !8348');

      // The pointer sits at the top level, not under `aps`, and there is
      // nothing in the payload beyond it.
      expect(payload.keys.toSet(), {'aps', ...pointer.toData().keys});
      expect(payload['verb'], 'replied');
      expect(aps.keys.toSet(), {'alert', 'sound', 'thread-id', 'mutable-content', 'interruption-level', 'category'});
    });

    test('an approval is standard priority too (D6: no time-sensitive)', () {
      final payload = sender.payload(
        PushPointer(
          org: 'contoso',
          eventType: 'ms.vss-pipelinechecks-events.approval-pending',
          artifactType: PushArtifactType.approval,
          artifactId: '18',
          project: 'Contoso Demo',
          verb: Verb.approvalPending,
        ),
      );
      expect((payload['aps']! as Map)['interruption-level'], 'active');
    });

    test('is disabled, with the reason, until the Key ID is known', () {
      expect(sender.ready, isFalse);
      expect(sender.status, 'disabled (no key id)');
    });

    test('picks the sandbox host by default and production when asked', () {
      ApnsSender make(String env) =>
          ApnsSender(keyFile: 'k.p8', keyId: 'ABC123', teamId: 'T', topic: 'com.kammcs.boardhop', environment: env);
      expect(make('sandbox').host, 'api.sandbox.push.apple.com');
      expect(make('production').host, 'api.push.apple.com');
    });

    test('a send without a key is skipped rather than attempted', () async {
      final result = await sender.send('token', pr());
      expect(result.outcome, PushOutcome.skipped);
    });
  });

  // -------------------------------------------------------------------- FCM

  group('the FCM message (§3.3)', () {
    final sender = FcmSender(projectId: 'boardhop-d4b8f', serviceAccountFile: 'nowhere.json');

    test('is data-only, HIGH, one hour, collapsed by family', () {
      final pointer = pr(
        title: '!8348 · Tidy the thing',
        actor: 'Ada Example',
        verb: Verb.replied,
        anchor: 'thread:4821',
        collapseKey: 'contoso.pr.8348.t4821',
        sentAt: DateTime.utc(2026, 9, 13, 16),
      );
      final message = sender.message('device-token', pointer);

      expect(message['token'], 'device-token');
      // No `notification` block: the app posts the notification itself after
      // enrichment (research/06 decision point 4, D7).
      expect(message.containsKey('notification'), isFalse);
      expect(message.keys.toSet(), {'token', 'data', 'android'});

      final android = message['android']! as Map<String, Object?>;
      expect(android['priority'], 'HIGH');
      expect(android['ttl'], '3600s');
      // FCM allows four collapse keys per device, so Android collapses by
      // family and keeps the exact key as the tag.
      expect(android['collapse_key'], 'pr');
      expect(android.containsKey('notification'), isFalse);

      final data = message['data']! as Map<String, Object?>;
      expect(data.keys.toSet(), {
        ...pointer.toData().keys,
        'fallbackTitle',
        'fallbackBody',
        'fallbackSubtitle',
        'collapseKey',
      });
      expect(data['fallbackTitle'], '!8348 · Tidy the thing');
      expect(data['fallbackBody'], 'Ada Example replied on !8348');
      expect(data['fallbackSubtitle'], 'Contoso Demo');
      expect(data['collapseKey'], 'contoso.pr.8348.t4821');
      for (final value in data.values) {
        expect(value, isA<String>());
      }
    });

    test('the test push travels in the same data-only shape', () {
      final message = sender.message(
        'device-token',
        PushPointer(
          org: 'contoso',
          eventType: 'boardhop.test',
          artifactType: PushArtifactType.build,
          artifactId: '0',
          project: '',
          title: 'Push is working',
          verb: Verb.test,
        ),
      );
      expect(message.containsKey('notification'), isFalse);
      final data = message['data']! as Map<String, Object?>;
      expect(data['fallbackTitle'], 'Boardhop');
      expect(data['fallbackBody'], 'Push is working');
      expect(data.containsKey('fallbackSubtitle'), isFalse);
      expect((message['android']! as Map)['collapse_key'], 'build');
    });

    test('the whole message is well under the 4 KB transport cap', () {
      final message = sender.message('d' * 200, pr(title: 't' * 80, actor: 'a' * 60, verb: Verb.commented));
      expect(utf8.encode(jsonEncode(message)).length, lessThan(4096));
    });

    test('is disabled and says why when the service account is missing', () {
      expect(sender.ready, isFalse);
      expect(sender.status, 'disabled (no service account)');
    });
  });
}

/// A detail each verb will actually accept, so the phrase table is exercised
/// with one rather than without.
String? _detailFor(Verb verb) => switch (verb) {
  Verb.voted => 'approved',
  Verb.buildFailed || Verb.buildPartial || Verb.buildCanceled || Verb.buildFixed || Verb.buildSucceeded => 'failed',
  Verb.approvalCompleted => 'approved',
  Verb.mergeFailed => 'conflicts',
  Verb.stateChanged => 'Active',
  _ => null,
};
