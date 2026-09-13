import 'dart:convert';

import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/gateway/gateway.dart';
import 'package:boardhop_relay/src/gateway/pointer.dart';
import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/routing/candidate.dart';
import 'package:boardhop_relay/src/routing/gateway_sink.dart';
import 'package:boardhop_relay/src/routing/notification.dart';
import 'package:boardhop_relay/src/routing/push_pointer_adapter.dart';
import 'package:boardhop_relay/src/verb.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';
import 'support.dart';

/// R2.3's last mile: a routed [Notification] becomes one pointer and reaches
/// every device of every recipient (research/14 §3.2, §5.2 rule 7).
void main() {
  late RelayDb db;
  late FakeSender apns;
  late FakeSender fcm;
  late GatewayNotificationSink sink;

  final sentAt = DateTime.utc(2026, 9, 13, 16, 30);

  setUp(() {
    db = RelayDb.openMemory()!;
    apns = FakeSender();
    fcm = FakeSender();
    sink = GatewayNotificationSink(
      db: db,
      gateway: PushGateway(apns: apns, fcm: fcm, db: db),
      clock: () => sentAt,
    );
  });

  tearDown(() => db.close());

  void registerDevice(String userId, String platform, String token) =>
      db.registerDevice(org: fixtureOrg, userId: userId, platform: platform, token: token);

  Notification prComment({Set<String>? recipients}) => Notification(
    org: fixtureOrg,
    kind: HookKind.prComment,
    eventKey: 'activity-1',
    artifactType: PushArtifactType.pullRequest,
    artifactId: '8348',
    projectId: projectGuid,
    projectName: 'Contoso Demo',
    title: '!8348 · Tidy the thing',
    actorId: bobId,
    actorName: 'Bob Example',
    verb: Verb.replied,
    anchor: 'thread:4821',
    subId: 'sub-pr.comment',
    deepLink: '/pull-requests/8348?thread=4821',
    collapseKey: '$fixtureOrg.pr.8348.t4821',
    recipients: recipients ?? {adaId, cleoId},
  );

  test('one notification reaches two devices of each of two people', () async {
    registerDevice(adaId, 'android', 'fcm-token-ada-0123456789abcdef');
    registerDevice(adaId, 'ios', 'a' * 64);
    registerDevice(cleoId, 'android', 'fcm-token-cleo-0123456789abcdef');
    registerDevice(bobId, 'android', 'fcm-token-bob-0123456789abcdef');

    await sink.deliver(prComment());

    expect(fcm.sent.map((s) => s.token), ['fcm-token-ada-0123456789abcdef', 'fcm-token-cleo-0123456789abcdef']);
    expect(apns.sent.map((s) => s.token), ['a' * 64]);
    // Bob wrote the comment; the engine took him out of the audience long
    // before this, and the sink only visits the recipients it is given.
    expect(fcm.sent.every((s) => s.token.contains('bob')), isFalse);
  });

  test('the pointer is the notification, carried across once', () async {
    registerDevice(adaId, 'android', 'fcm-token-ada-0123456789abcdef');
    await sink.deliver(prComment(recipients: {adaId}));

    final pointer = fcm.sent.single.pointer;
    expect(pointer.org, fixtureOrg);
    expect(pointer.eventType, 'ms.vss-code.git-pullrequest-comment-event');
    expect(pointer.artifactType, PushArtifactType.pullRequest);
    expect(pointer.artifactId, '8348');
    expect(pointer.project, 'Contoso Demo');
    expect(pointer.title, '!8348 · Tidy the thing');
    expect(pointer.actor, 'Bob Example');
    expect(pointer.actorId, bobId);
    expect(pointer.verb, Verb.replied);
    expect(pointer.anchor, 'thread:4821');
    expect(pointer.deepLink, '/pull-requests/8348?thread=4821');
    expect(pointer.collapseId, '$fixtureOrg.pr.8348.t4821');
    expect(pointer.subId, 'sub-pr.comment');
    expect(pointer.sentAt, sentAt);
    expect(pointer.notificationBody, 'Bob Example replied on !8348');
  });

  test('a recipient with no device is simply not reached (§5.2 rule 7)', () async {
    await sink.deliver(prComment());
    expect(fcm.sent, isEmpty);
    expect(apns.sent, isEmpty);
  });

  test('a dead token deletes the row, and the log line says so', () async {
    registerDevice(adaId, 'android', 'fcm-token-ada-0123456789abcdef');
    fcm.result = const PushResult(PushOutcome.dead, status: 404, error: 'UNREGISTERED');

    final lines = await captureLog(() => sink.deliver(prComment(recipients: {adaId})));
    expect(db.devicesFor(fixtureOrg, adaId), isEmpty);

    final push = jsonDecode(lines.firstWhere((l) => l.contains('"msg":"push"'))) as Map<String, Object?>;
    expect(push['platform'], 'android');
    expect(push['outcome'], 'dead');
    // Only the tail of the token, never the token.
    expect(push['token'], '…abcdef');
  });

  test('the notification line counts outcomes and carries no content', () async {
    registerDevice(adaId, 'android', 'fcm-token-ada-0123456789abcdef');
    registerDevice(cleoId, 'ios', 'c' * 64);

    final lines = await captureLog(() => sink.deliver(prComment()));
    final line = lines.firstWhere((l) => l.contains('"msg":"notification"'));
    final logged = jsonDecode(line) as Map<String, Object?>;

    expect(logged['artifact'], 'pullRequest/8348');
    expect(logged['verb'], 'replied');
    expect(logged['reached'], 2);
    expect(logged['devices'], 2);
    expect(logged['sent'], 2);
    expect(logged['recipients'], 2);
    for (final forbidden in ['Tidy the thing', 'Bob Example', canary]) {
      expect(line, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('a transport that is switched off is skipped, not an error', () async {
    registerDevice(adaId, 'android', 'fcm-token-ada-0123456789abcdef');
    final off = GatewayNotificationSink(
      db: db,
      gateway: PushGateway(
        apns: FakeSender(ready: false),
        fcm: FakeSender(ready: false, result: const PushResult(PushOutcome.skipped, error: 'disabled (fake)')),
        db: db,
      ),
      clock: () => sentAt,
    );
    final lines = await captureLog(() => off.deliver(prComment(recipients: {adaId})));
    final logged = jsonDecode(lines.firstWhere((l) => l.contains('"msg":"notification"'))) as Map<String, Object?>;
    expect(logged['skipped'], 1);
    expect(db.devicesFor(fixtureOrg, adaId), hasLength(1), reason: 'a skipped send is not a dead device');
  });

  test('the adapter keeps a project id when no name was ever seen', () {
    final pointer = pointerFromNotification(
      Notification(
        org: fixtureOrg,
        kind: HookKind.approvalPending,
        eventKey: 'activity-2',
        artifactType: PushArtifactType.approval,
        artifactId: '18',
        projectId: projectGuid,
        verb: Verb.approvalPending,
        detail: 'Deploy',
        anchor: 'approval:18',
        runId: '20163',
        deepLink: '/projects/$projectGuid/pipelines?tab=approvals&approval=18',
        collapseKey: '$fixtureOrg.approval.18',
        recipients: const {adaId},
      ),
      sentAt: sentAt,
    );
    expect(pointer.project, projectGuid);
    expect(pointer.runId, '20163');
    expect(pointer.notificationBody, 'Needs your approval');
    expect(pointer.collapseFamily, 'approval');
  });

  test('a candidate reason never reaches the wire', () {
    // The reason is routing's business: it decides whether a notification
    // happens, and is not part of the pointer contract.
    final data = pointerFromNotification(prComment(), sentAt: sentAt).toData();
    for (final reason in CandidateReason.values) {
      expect(data.values, isNot(contains(reason.name)), reason: reason.name);
    }
  });
}
