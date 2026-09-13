import 'dart:convert';
import 'dart:io';

import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/hooks/hook_event.dart';
import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/hooks/routing_view.dart';
import 'package:boardhop_relay/src/routing/links.dart';
import 'package:boardhop_relay/src/routing/candidate.dart';
import 'package:boardhop_relay/src/routing/notification.dart';
import 'package:boardhop_relay/src/routing/prefs.dart';
import 'package:boardhop_relay/src/routing/routing_state.dart';
import 'package:boardhop_relay/src/routing/rule_engine.dart';
import 'package:boardhop_relay/src/routing/send_ledger.dart';
import 'package:boardhop_relay/src/routing/sink.dart';
import 'package:boardhop_relay/src/verb.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';
import 'support.dart';

/// research/14 §5.2 (the six rules), §3.1 (titles), §2 (deep links and collapse
/// keys) and §6 (the defaults), through the whole engine.
void main() {
  // ------------------------------------------------------ rule 1: the actor

  group('the actor is never a recipient (§5.2 rule 1)', () {
    /// Every kind whose payload names its actor, as a function of who that is.
    final cases = <String, RoutingView Function(String actor)>{
      'wi.updated assignment': (actor) => viewOf(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub',
          actorId: actor,
          creatorId: actor,
          currentAssignedTo: identity(actor, nameFor(actor)),
          changes: {
            'System.AssignedTo': {'newValue': identity(actor, nameFor(actor)), 'oldValue': identity(bobId, 'Bob')},
            'System.State': {'newValue': 'Done'},
          },
        ),
      ),
      'wi.updated comment': (actor) => viewOf(
        HookKind.wiUpdated,
        workItemCommentNoise(
          subId: 'sub',
          actorId: actor,
          creatorId: actor,
          currentAssignedTo: identity(actor, nameFor(actor)),
          history: 'self mention ${htmlMention(actor, nameFor(actor))}',
        ),
      ),
      'wi.created': (actor) =>
          viewOf(HookKind.wiCreated, workItemCreated(subId: 'sub', creatorId: actor, assignedTo: identity(actor, 'x'))),
      'pr.created': (actor) => viewOf(
        HookKind.prCreated,
        pullRequestCreated(subId: 'sub', authorId: actor, reviewers: [reviewer(actor), reviewer(bobId)]),
      ),
      'pr.comment': (actor) => viewOf(
        HookKind.prComment,
        pullRequestComment(
          subId: 'sub',
          authorId: actor,
          prAuthorId: actor,
          content: 'self mention @<$actor>',
          reviewers: [reviewer(actor, vote: 10)],
        ),
      ),
      'approval.completed': (actor) => viewOf(
        HookKind.approvalCompleted,
        approvalEvent(
          subId: 'sub',
          completed: true,
          status: 'approved',
          approverIds: [actor, cleoId],
          actualApproverId: actor,
        ),
      ),
    };

    for (final entry in cases.entries) {
      for (final actor in [adaId, bobId, cleoId]) {
        test('${entry.key}, actor ${nameFor(actor)}', () async {
          final harness = RoutingHarness(prefs: const AllOnPrefs());
          final notifications = await harness.run(entry.value(actor));
          expect(harness.recipientsOf(notifications), isNot(contains(actor)));
        });
      }
    }

    test('a build is the exception: its requester hears about their own failure', () async {
      final harness = RoutingHarness();
      final notifications = await harness.run(
        viewOf(HookKind.buildComplete, buildComplete(subId: 'sub', requestedForId: adaId, requestedById: adaId)),
      );
      expect(harness.recipientsOf(notifications), {adaId});
      expect(notifications.single.actorId, adaId);
      expect(notifications.single.verb, Verb.buildFailed);
    });

    test('the only approver of their own run still hears about it', () async {
      final harness = RoutingHarness();
      await harness.run(viewOf(HookKind.runState, runStateChanged(subId: 'sub', requestedForId: adaId)));
      final notifications = await harness.run(
        viewOf(HookKind.approvalPending, approvalEvent(subId: 'sub', approverIds: const [adaId])),
      );
      expect(harness.recipientsOf(notifications), {adaId});
    });
  });

  // ------------------------------------------ rule 2: one per person, loudest

  group('one notification per person per event (§5.2 rule 2)', () {
    test('a mention beats an assignment on the same update', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final notifications = await harness.run(
        viewOf(
          HookKind.wiUpdated,
          workItemUpdated(
            subId: 'sub',
            currentAssignedTo: identity(bobId, 'Bob Example'),
            currentHistory: 'ping ${htmlMention(bobId, 'Bob Example')}',
            changes: {
              'System.AssignedTo': {'newValue': identity(bobId, 'Bob Example')},
              'System.History': {'newValue': 'ping ${htmlMention(bobId, 'Bob Example')}'},
            },
          ),
        ),
      );
      final forBob = notifications.where((n) => n.recipients.contains(bobId));
      expect(forBob, hasLength(1));
      expect(forBob.single.verb, Verb.mentioned);
    });

    test('an assignment beats a state change on the same update', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final notifications = await harness.run(
        viewOf(
          HookKind.wiUpdated,
          workItemUpdated(
            subId: 'sub',
            state: 'Done',
            currentAssignedTo: identity(bobId, 'Bob Example'),
            changes: {
              'System.AssignedTo': {'newValue': identity(bobId, 'Bob Example')},
              'System.State': {'newValue': 'Done'},
            },
          ),
        ),
      );
      final forBob = notifications.where((n) => n.recipients.contains(bobId));
      expect(forBob, hasLength(1));
      expect(forBob.single.verb, Verb.assigned);
    });

    test('a mention and a comment on one PR comment are two notifications, one each', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final notifications = await harness.run(
        viewOf(HookKind.prComment, pullRequestComment(subId: 'sub', parentCommentId: 0)),
      );
      expect(notifications.map((n) => n.verb).toSet(), {Verb.mentioned, Verb.commented});
      // Cleo is mentioned; Ada is the PR author. Nobody is in two of them.
      final everyone = [for (final n in notifications) ...n.recipients];
      expect(everyone.toSet().length, everyone.length);
    });

    test('the same delivery processed twice notifies nobody the second time', () async {
      final harness = RoutingHarness();
      final view = viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub'), activityId: 'one-delivery');
      expect(await harness.run(view), hasLength(1));
      expect(await harness.run(view), isEmpty);
    });
  });

  // --------------------------------------------------- §6: the default prefs

  group('the §6 defaults', () {
    test('an edit on your own work item is silent', () async {
      final harness = RoutingHarness();
      final notifications = await harness.run(
        viewOf(
          HookKind.wiUpdated,
          workItemUpdated(
            subId: 'sub',
            currentAssignedTo: identity(bobId, 'Bob Example'),
            changes: {
              'System.Title': {'newValue': 'Renamed'},
            },
          ),
        ),
      );
      expect(notifications, isEmpty);
    });

    test('a push to a PR you voted on is silent', () async {
      final harness = RoutingHarness();
      harness.state.savePullRequest(
        const PrStateRow(org: fixtureOrg, prId: '8348', authorId: adaId, sourceCommit: 'old', reviewers: {bobId: 10}),
      );
      final notifications = await harness.run(
        viewOf(
          HookKind.prUpdatedPush,
          pullRequestUpdated(subId: 'sub', sourceCommit: 'new-commit', reviewers: [reviewer(bobId, vote: 10)]),
        ),
      );
      expect(notifications, isEmpty);
    });

    test('a plain build success is silent, a fix is not', () async {
      final harness = RoutingHarness();
      expect(
        await harness.run(viewOf(HookKind.buildComplete, buildComplete(subId: 'a', result: 'succeeded'))),
        isEmpty,
      );

      await harness.run(viewOf(HookKind.buildComplete, buildComplete(subId: 'b', result: 'failed')));
      final fixed = await harness.run(
        viewOf(
          HookKind.buildComplete,
          buildComplete(subId: 'c', result: 'succeeded'),
          activityId: 'fix',
        ),
      );
      expect(fixed.single.verb, Verb.buildFixed);
    });

    test('a mention is delivered even to somebody who has turned that verb off', () async {
      final harness = RoutingHarness(prefs: const _MentionsOnlyPrefs());
      final notifications = await harness.run(
        viewOf(HookKind.prComment, pullRequestComment(subId: 'sub', parentCommentId: 0)),
      );
      expect(notifications.map((n) => n.verb), [Verb.mentioned]);
      expect(notifications.single.recipients, {cleoId});
    });
  });

  group('quiet hours (§6, D5)', () {
    test('suppress an ordinary notification', () async {
      final harness = RoutingHarness(prefs: const AlwaysQuietPrefs());
      expect(await harness.run(viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub'))), isEmpty);
    });

    test('but never an approval', () async {
      final harness = RoutingHarness(prefs: const AlwaysQuietPrefs());
      final notifications = await harness.run(
        viewOf(HookKind.approvalPending, approvalEvent(subId: 'sub', approverIds: const [cleoId])),
      );
      expect(notifications.single.verb, Verb.approvalPending);
    });
  });

  // ----------------------------------------------------------- rule 6: caps

  group('the fan-out caps (§5.2 rule 6)', () {
    test('at most 50 recipients for one event', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final many = [for (var i = 0; i < 60; i++) reviewer(_syntheticId(i))];
      final notifications = await harness.run(
        viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub', reviewers: many)),
      );
      expect(harness.recipientsOf(notifications), hasLength(RuleEngine.maxFanOut));
    });

    test('at most 60 notifications per person per hour per org', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final now = DateTime.now().toUtc();
      for (var i = 0; i < RuleEngine.maxPerUserHourly; i++) {
        harness.sends.claim(org: fixtureOrg, eventKey: 'earlier-$i', userId: bobId, at: now);
      }
      final notifications = await harness.run(
        viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub', reviewers: [reviewer(bobId), reviewer(cleoId)])),
      );
      expect(harness.recipientsOf(notifications), {cleoId});
    });

    test('the cap is per organization', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final now = DateTime.now().toUtc();
      for (var i = 0; i < RuleEngine.maxPerUserHourly; i++) {
        harness.sends.claim(org: 'fabrikam', eventKey: 'earlier-$i', userId: bobId, at: now);
      }
      final notifications = await harness.run(
        viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub', reviewers: [reviewer(bobId)])),
      );
      expect(harness.recipientsOf(notifications), {bobId});
    });
  });

  // ------------------------------------------------ §2 and §3.1: what is sent

  group('deep links, collapse keys and titles (§2, §3.1)', () {
    test('a work item comment anchors on the comment', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final notifications = await harness.run(
        viewOf(
          HookKind.wiUpdated,
          workItemCommentNoise(subId: 'sub', currentAssignedTo: identity(bobId, 'Bob Example')),
        ),
      );
      final sent = notifications.firstWhere((n) => n.recipients.contains(bobId));
      expect(sent.deepLink, '/projects/Contoso%20Demo/work-items/15545?comment=4');
      expect(sent.collapseKey, '$fixtureOrg.wi.15545.comments');
      expect(sent.anchor, 'comment:4');
      expect(sent.title, startsWith('#15545 · '));
    });

    test('a work item state change has no anchor', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final notifications = await harness.run(
        viewOf(
          HookKind.wiUpdated,
          workItemUpdated(
            subId: 'sub',
            state: 'Done',
            currentAssignedTo: identity(bobId, 'Bob Example'),
            changes: {
              'System.State': {'newValue': 'Done'},
            },
          ),
        ),
      );
      final sent = notifications.first;
      expect(sent.deepLink, '/projects/Contoso%20Demo/work-items/15545');
      expect(sent.collapseKey, '$fixtureOrg.wi.15545');
      expect(sent.detail, 'Done');
    });

    test('a PR comment anchors on the thread', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final notifications = await harness.run(viewOf(HookKind.prComment, pullRequestComment(subId: 'sub')));
      final sent = notifications.first;
      expect(sent.deepLink, '/pull-requests/8348?thread=4821');
      expect(sent.collapseKey, '$fixtureOrg.pr.8348.t4821');
      expect(sent.title, startsWith('!8348 · '));
    });

    test('a PR push lands on the Files tab', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      harness.state.savePullRequest(
        const PrStateRow(org: fixtureOrg, prId: '8348', authorId: adaId, sourceCommit: 'old', reviewers: {bobId: 10}),
      );
      final notifications = await harness.run(
        viewOf(
          HookKind.prUpdatedPush,
          pullRequestUpdated(subId: 'sub', sourceCommit: 'new-commit', reviewers: [reviewer(bobId, vote: 10)]),
        ),
      );
      expect(notifications.single.deepLink, '/pull-requests/8348?tab=files');
      expect(notifications.single.collapseKey, '$fixtureOrg.pr.8348');
    });

    test('a new PR is the plain PR route', () async {
      final harness = RoutingHarness();
      final notifications = await harness.run(viewOf(HookKind.prCreated, pullRequestCreated(subId: 'sub')));
      expect(notifications.single.deepLink, '/pull-requests/8348');
      expect(notifications.single.collapseKey, '$fixtureOrg.pr.8348');
    });

    test('a build points at the run', () async {
      final harness = RoutingHarness();
      final notifications = await harness.run(viewOf(HookKind.buildComplete, buildComplete(subId: 'sub')));
      expect(notifications.single.deepLink, '/projects/Contoso%20Demo/pipelines/runs/20163');
      expect(notifications.single.collapseKey, '$fixtureOrg.build.20163');
      expect(notifications.single.title, 'contoso-scratch · 20260913.1');
    });

    test('a pending approval opens the Approvals tab on that approval', () async {
      final harness = RoutingHarness();
      // The pipelines publisher sends no project name, so the relay uses the
      // one it learned from another event in the same project.
      await harness.run(viewOf(HookKind.buildComplete, buildComplete(subId: 'b')));
      final notifications = await harness.run(
        viewOf(HookKind.approvalPending, approvalEvent(subId: 'sub', approverIds: const [cleoId])),
      );
      const approvalId = '44444444-eeee-4eee-8eee-444444444444';
      expect(notifications.single.deepLink, '/projects/Contoso%20Demo/pipelines?tab=approvals&approval=$approvalId');
      expect(notifications.single.collapseKey, '$fixtureOrg.approval.$approvalId');
      expect(notifications.single.title, 'contoso-scratch → Deploy');
      expect(notifications.single.runId, '20163');
    });

    test('without a learned project name the id stands in', () async {
      final harness = RoutingHarness();
      final notifications = await harness.run(
        viewOf(HookKind.approvalPending, approvalEvent(subId: 'sub', approverIds: const [cleoId])),
      );
      expect(notifications.single.deepLink, startsWith('/projects/$projectGuid/pipelines?tab=approvals'));
    });

    test('a completed approval replaces the pending one and opens the run', () async {
      final harness = RoutingHarness();
      await harness.run(viewOf(HookKind.buildComplete, buildComplete(subId: 'b')));
      final notifications = await harness.run(
        viewOf(
          HookKind.approvalCompleted,
          approvalEvent(subId: 'sub', completed: true, status: 'approved', approverIds: const [adaId, cleoId]),
        ),
      );
      expect(notifications.single.deepLink, '/projects/Contoso%20Demo/pipelines/runs/20163');
      expect(notifications.single.collapseKey, '$fixtureOrg.approval.44444444-eeee-4eee-8eee-444444444444');
      expect(notifications.single.detail, 'approved');
    });

    test('a title longer than the cap is truncated, never dropped', () {
      final notification = Notification(
        org: fixtureOrg,
        kind: HookKind.wiUpdated,
        eventKey: 'k',
        artifactType: artifactTypeOf(HookKind.wiUpdated),
        artifactId: '1',
        verb: Verb.assigned,
        deepLink: '/activity',
        collapseKey: 'wi.1',
        recipients: const {bobId},
        title: 'x' * 200,
        actorName: 'y' * 200,
      );
      expect(notification.title, hasLength(Notification.maxTitle));
      expect(notification.actorName, hasLength(Notification.maxActorName));
    });

    test('a detail outside a verb closed list is refused', () {
      Notification build(Verb verb, String detail) => Notification(
        org: fixtureOrg,
        kind: HookKind.buildComplete,
        eventKey: 'k',
        artifactType: artifactTypeOf(HookKind.buildComplete),
        artifactId: '1',
        verb: verb,
        deepLink: '/activity',
        collapseKey: 'build.1',
        recipients: const {bobId},
        detail: detail,
      );
      expect(build(Verb.buildFailed, 'failed').detail, 'failed');
      expect(build(Verb.buildFailed, 'a comment body').detail, isNull);
      expect(build(Verb.voted, 'approved').detail, 'approved');
      expect(build(Verb.voted, 'lgtm!').detail, isNull);
      // A free-form detail (a state name) is capped, not refused.
      expect(build(Verb.stateChanged, 'z' * 100).detail, hasLength(Verb.maxDetail));
    });
  });

  // ------------------------------------------------------ the events that do
  // not notify at all

  group('events that produce nothing', () {
    test('workitem.commented', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      expect(await harness.run(viewOf(HookKind.wiCommented, workItemCommented(subId: 'sub'))), isEmpty);
    });

    test('run-state-changed and stage-state-changed', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      expect(await harness.run(viewOf(HookKind.runState, runStateChanged(subId: 'sub'))), isEmpty);
      expect(await harness.run(viewOf(HookKind.stageState, stageStateChanged(subId: 'sub'))), isEmpty);
      expect(harness.state.run(fixtureOrg, '20163'), isNotNull);
    });

    test('a system comment on a PR', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      expect(
        await harness.run(viewOf(HookKind.prComment, pullRequestComment(subId: 'sub', commentType: 'system'))),
        isEmpty,
      );
    });

    test('a successful merge', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      expect(
        await harness.run(viewOf(HookKind.prMerged, pullRequestMerged(subId: 'sub', mergeStatus: 'succeeded'))),
        isEmpty,
      );
    });
  });

  // --------------------------------------------------------------- redaction

  group('nothing from a body escapes', () {
    /// One of every kind the engine routes, each carrying the canary.
    List<(HookKind, Map<String, Object?>)> everyKind() => [
      (
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub',
          currentAssignedTo: identity(bobId, 'Bob Example'),
          changes: {
            'System.AssignedTo': {'newValue': identity(bobId, 'Bob Example')},
            'System.State': {'newValue': 'Done'},
          },
        ),
      ),
      (
        HookKind.wiUpdated,
        workItemCommentNoise(
          subId: 'sub',
          currentAssignedTo: identity(bobId, 'Bob Example'),
          history: 'Comment $canary ${htmlMention(cleoId, 'Cleo Example')}',
        ),
      ),
      (HookKind.wiCommented, workItemCommented(subId: 'sub')),
      (HookKind.wiCreated, workItemCreated(subId: 'sub')),
      (HookKind.prCreated, pullRequestCreated(subId: 'sub', reviewers: [reviewer(bobId), reviewer(cleoId)])),
      (HookKind.prUpdatedReviewers, pullRequestUpdated(subId: 'sub', reviewers: [reviewer(cleoId)])),
      (HookKind.prUpdatedVote, pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId, vote: 10)])),
      (HookKind.prUpdatedStatus, pullRequestUpdated(subId: 'sub', status: 'completed')),
      (HookKind.prUpdatedPush, pullRequestUpdated(subId: 'sub', sourceCommit: 'another-commit')),
      (HookKind.prComment, pullRequestComment(subId: 'sub')),
      (HookKind.prMerged, pullRequestMerged(subId: 'sub')),
      (HookKind.buildComplete, buildComplete(subId: 'sub')),
      (HookKind.runState, runStateChanged(subId: 'sub')),
      (HookKind.stageState, stageStateChanged(subId: 'sub')),
      (HookKind.approvalPending, approvalEvent(subId: 'sub')),
      (HookKind.approvalCompleted, approvalEvent(subId: 'sub', completed: true, status: 'approved')),
    ];

    test('no log line carries a title, a name or a body', () async {
      final harness = RoutingHarness(prefs: const AllOnPrefs());
      final logging = RuleEngine(
        state: harness.state,
        prefs: FixedPrefsSource(const AllOnPrefs()),
        sink: const LoggingNotificationSink(),
        sends: harness.sends,
      );
      final lines = await captureLog(() async {
        var n = 0;
        for (final (kind, body) in everyKind()) {
          await logging.process(HookEvent(view: viewOf(kind, body, activityId: 'canary-${n++}')));
        }
      });

      final joined = lines.join('\n');
      expect(lines.where((l) => l.contains('"msg":"notification"')), isNotEmpty);
      for (final forbidden in [
        canary,
        'Ada Example',
        'Bob Example',
        'Cleo Example',
        'Fix the thing',
        'Tidy the thing',
        'contoso-scratch',
        'Contoso Demo',
        'refs/heads',
        'example.invalid',
      ]) {
        expect(joined, isNot(contains(forbidden)), reason: '"$forbidden" must not reach a log line');
      }
      final notification =
          jsonDecode(lines.firstWhere((l) => l.contains('"msg":"notification"'))) as Map<String, Object?>;
      expect(notification.containsKey('title'), isFalse);
      expect(notification.containsKey('actorName'), isFalse);
      expect(notification.containsKey('detail'), isFalse);
      expect(notification['recipients'], isA<int>());
    });

    test('nothing but ids and the project map reaches the database file', () async {
      final dir = Directory.systemTemp.createTempSync('relay_routing_db_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = RelayDb.open('${dir.path}${Platform.pathSeparator}relay.sqlite')!;

      final engine = RuleEngine(
        state: DbRoutingState(db),
        prefs: const DefaultPrefsSource(),
        sink: const LoggingNotificationSink(),
        sends: DbSendLedger(db),
      );
      await captureLog(() async {
        var n = 0;
        for (final (kind, body) in everyKind()) {
          await engine.process(HookEvent(view: viewOf(kind, body, activityId: 'db-canary-${n++}')));
        }
      });
      db.close();

      final bytes = <int>[for (final file in dir.listSync().whereType<File>()) ...file.readAsBytesSync()];
      final blob = latin1.decode(bytes, allowInvalid: true);
      expect(blob, contains(adaId), reason: 'identity ids are the point of these tables');
      expect(
        blob,
        contains('Contoso Demo'),
        reason: 'the projects table is the one place a name is kept, and only so a route can be built',
      );
      for (final forbidden in [
        canary,
        'Ada Example',
        'Bob Example',
        'Cleo Example',
        'Fix the thing',
        'Tidy the thing',
        'contoso-scratch',
        '20260913.1',
        'Comment ',
      ]) {
        expect(blob, isNot(contains(forbidden)), reason: '"$forbidden" must not reach the database');
      }
    });

    test('no state table has a column that could hold text', () {
      final db = RelayDb.openMemory()!;
      addTearDown(db.close);
      final columns = db.schemaColumns();
      expect(columns.keys, containsAll(['pr_state', 'pr_thread_state', 'run_state', 'build_state', 'projects']));
      const forbidden = ['title', 'name', 'text', 'content', 'description', 'comment', 'body', 'message'];
      for (final table in ['pr_state', 'pr_thread_state', 'run_state', 'build_state', 'notification_sends']) {
        for (final column in columns[table]!) {
          for (final word in forbidden) {
            expect(
              column.toLowerCase(),
              isNot(contains(word)),
              reason: '$table.$column looks like it could hold content',
            );
          }
        }
      }
      // `projects` is the documented exception (research/14 §5.1): the app's
      // routes take a project name and some payloads carry only the id.
      expect(columns['projects'], ['org', 'project_id', 'project_name', 'updated_at']);
    });

    test('routing state expires after 90 days', () {
      final db = RelayDb.openMemory()!;
      addTearDown(db.close);
      final old = DateTime.now().toUtc().subtract(const Duration(days: 100)).toIso8601String();
      db.savePrState(PrStateRow(org: fixtureOrg, prId: '1', updatedAt: old));
      db.savePrThreadState(PrThreadStateRow(org: fixtureOrg, prId: '1', threadId: '2', updatedAt: old));
      db.saveRunState(RunStateRow(org: fixtureOrg, runId: '3', createdAt: old));
      db.saveBuildState(BuildStateRow(org: fixtureOrg, projectId: 'p', definitionId: 'd', branch: 'b', updatedAt: old));
      expect(db.pruneRoutingState(DateTime.now().toUtc().subtract(RelayDb.routingStateRetention)), 4);
      expect(db.prState(fixtureOrg, '1'), isNull);
    });
  });
}

/// A throwaway identity id for the fan-out cap test.
String _syntheticId(int i) => 'aaaaaaaa-1111-4111-8111-${i.toString().padLeft(12, '0')}';

/// Preferences that hear mentions and nothing else — the "mentions only"
/// narrowing of research/14 §6.
class _MentionsOnlyPrefs implements UserPrefs {
  const _MentionsOnlyPrefs();

  @override
  bool allows(Verb verb, {required CandidateReason reason, String? detail, String? artifactKey}) =>
      reason == CandidateReason.mention;

  @override
  bool quietHoursSuppress(Verb verb, DateTime nowUtc, int? tzOffsetMinutes) => false;
}
