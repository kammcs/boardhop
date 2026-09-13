import 'package:boardhop/features/notifications/push_pointer.dart';
import 'package:boardhop/features/notifications/push_verbs.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';

Map<String, Object?> data({
  String artifactType = 'pullRequest',
  String artifactId = '8336',
  String project = 'DevOps Mobile App',
  String eventType = 'git.pullrequest.updated',
  String? title,
  String? deepLink,
  String? actor,
  String? actorId,
  String? verb,
  String? detail,
  String? anchor,
  String? runId,
  String? subId,
  String? sentAt,
  String? collapseKey,
  String? fallbackTitle,
  String? fallbackBody,
  String? fallbackSubtitle,
}) => {
  'org': 'contoso',
  'eventType': eventType,
  'artifactType': artifactType,
  'artifactId': artifactId,
  'project': project,
  'title': ?title,
  'deepLink': ?deepLink,
  'actor': ?actor,
  'actorId': ?actorId,
  'verb': ?verb,
  'detail': ?detail,
  'anchor': ?anchor,
  'runId': ?runId,
  'subId': ?subId,
  'sentAt': ?sentAt,
  'collapseKey': ?collapseKey,
  'fallbackTitle': ?fallbackTitle,
  'fallbackBody': ?fallbackBody,
  'fallbackSubtitle': ?fallbackSubtitle,
};

void main() {
  group('reading a push', () {
    test('needs the org, the artifact type and the id', () {
      expect(PushPointer.tryFrom(data()), isNotNull);
      expect(PushPointer.tryFrom({...data()}..remove('org')), isNull);
      expect(PushPointer.tryFrom({...data()}..remove('artifactId')), isNull);
      expect(PushPointer.tryFrom(const {}), isNull);
    });

    test('a missing project and title are tolerated', () {
      final pointer = PushPointer.tryFrom(data(project: ''))!;
      expect(pointer.project, '');
      expect(pointer.title, isNull);
    });

    test('an R1 pointer parses with every v2 field absent', () {
      final pointer = PushPointer.tryFrom(data(title: 'Old shape'))!;
      expect(pointer.actor, isNull);
      expect(pointer.verb, isNull);
      expect(pointer.anchor, isNull);
      expect(pointer.sentAt, isNull);
      expect(pointer.collapseKey, isNull);
      expect(pointer.isStale, isFalse);
    });

    test('the v2 fields come off the data map', () {
      final pointer = PushPointer.tryFrom(
        data(
          actor: 'Ada Example',
          actorId: '2f0b2f6c-0000-4000-8000-000000000001',
          verb: 'replied',
          detail: 'rejected',
          anchor: 'thread:4821',
          runId: '20163',
          subId: '6a1e0f10-0000-4000-8000-000000000002',
          sentAt: '2026-09-13T10:00:00Z',
          collapseKey: 'contoso.pr.8336.t4821',
          fallbackTitle: '!8336 · Wire up the relay',
          fallbackBody: 'Ada Example replied on !8336',
          fallbackSubtitle: 'DevOps Mobile App',
        ),
      )!;
      expect(pointer.actor, 'Ada Example');
      expect(pointer.actorId, '2f0b2f6c-0000-4000-8000-000000000001');
      expect(pointer.verb, PushVerb.replied);
      expect(pointer.detail, 'rejected');
      expect(pointer.anchor, 'thread:4821');
      expect(pointer.runId, '20163');
      expect(pointer.subId, '6a1e0f10-0000-4000-8000-000000000002');
      expect(pointer.sentAt, DateTime.utc(2026, 9, 13, 10));
      expect(pointer.collapseKey, 'contoso.pr.8336.t4821');
      expect(pointer.fallbackSubtitle, 'DevOps Mobile App');
      // The wire map is kept whole, so a background notification can carry it.
      expect(pointer.data['verb'], 'replied');
      expect(pointer.data['org'], 'contoso');
    });

    test('a verb this app does not know is dropped, not shown', () {
      final pointer = PushPointer.tryFrom(data(verb: 'defenestrated'))!;
      expect(pointer.verb, isNull);
    });
  });

  group('staleness', () {
    final sent = DateTime.utc(2026, 9, 13, 10);

    test('a pointer with no sentAt is never stale', () {
      expect(
        PushPointer.tryFrom(data())!.isStaleAt(DateTime.utc(2030)),
        isFalse,
      );
    });

    test('ten minutes is still fresh, eleven is not', () {
      final pointer = PushPointer.tryFrom(
        data(sentAt: sent.toIso8601String()),
      )!;
      expect(pointer.isStaleAt(sent.add(const Duration(minutes: 9))), isFalse);
      expect(pointer.isStaleAt(sent.add(const Duration(minutes: 10))), isFalse);
      expect(pointer.isStaleAt(sent.add(const Duration(minutes: 11))), isTrue);
    });

    test('a local clock is compared in UTC', () {
      final pointer = PushPointer.tryFrom(
        data(sentAt: sent.toIso8601String()),
      )!;
      expect(
        pointer.isStaleAt(sent.add(const Duration(minutes: 1)).toLocal()),
        isFalse,
      );
    });
  });

  group('pointer to route', () {
    String routeOf(Map<String, Object?> json) =>
        PushPointer.tryFrom(json)!.route(account);

    test('a pull request lands on the org-level PR route', () {
      expect(
        routeOf(data()),
        '/a/kelly%40kammcs.com-home/orgs/contoso/pull-requests/8336',
      );
    });

    test('a work item lands inside its project', () {
      expect(
        routeOf(data(artifactType: 'workItem', artifactId: '15503')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/projects/'
        'DevOps%20Mobile%20App/work-items/15503',
      );
    });

    test('a build lands on its run', () {
      expect(
        routeOf(data(artifactType: 'build', artifactId: '4242')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/projects/'
        'DevOps%20Mobile%20App/pipelines/runs/4242',
      );
    });

    test('an approval lands on the project pipelines page', () {
      expect(
        routeOf(data(artifactType: 'approval', artifactId: '18')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/projects/'
        'DevOps%20Mobile%20App/pipelines',
      );
    });

    test('an unroutable pointer falls back to the activity feed', () {
      expect(
        routeOf(data(artifactType: 'build', artifactId: '0', project: '')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/activity',
      );
    });

    test('a deep link is used only when it names an account', () {
      expect(
        routeOf(data(deepLink: '/a/someone-else/orgs/contoso/activity')),
        '/a/someone-else/orgs/contoso/activity',
      );
      // Anything else is ignored: the relay cannot steer the app at a route
      // of its own choosing, anchors included.
      expect(
        routeOf(data(deepLink: '/pull-requests/1?tab=files')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/pull-requests/8336',
      );
    });
  });

  group('anchors become a query string (research/14 §4.2)', () {
    String routeOf(Map<String, Object?> json) =>
        PushPointer.tryFrom(json)!.route(account);

    test('comment on a work item', () {
      expect(
        routeOf(
          data(
            artifactType: 'workItem',
            artifactId: '15545',
            anchor: 'comment:1998234',
          ),
        ),
        '/a/kelly%40kammcs.com-home/orgs/contoso/projects/'
        'DevOps%20Mobile%20App/work-items/15545?comment=1998234',
      );
    });

    test('thread on a pull request', () {
      expect(
        routeOf(data(anchor: 'thread:4821')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/pull-requests/8336'
        '?thread=4821',
      );
    });

    test('the files tab of a pull request', () {
      expect(
        routeOf(data(anchor: 'tab:files')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/pull-requests/8336?tab=files',
      );
    });

    test('an approval opens the approvals tab at its id', () {
      expect(
        routeOf(
          data(
            artifactType: 'approval',
            artifactId: '18',
            anchor: 'approval:18',
          ),
        ),
        '/a/kelly%40kammcs.com-home/orgs/contoso/projects/'
        'DevOps%20Mobile%20App/pipelines?tab=approvals&approval=18',
      );
    });

    test('an approval carries its run, so the page can offer it', () {
      // research/14 §2.4: the approval's owner is the run, and R2.5's
      // "Already decided" snackbar opens it.
      expect(
        routeOf(
          data(
            artifactType: 'approval',
            artifactId: '18',
            anchor: 'approval:18',
            runId: '20163',
          ),
        ),
        '/a/kelly%40kammcs.com-home/orgs/contoso/projects/'
        'DevOps%20Mobile%20App/pipelines?tab=approvals&approval=18&run=20163',
      );
    });

    test('a run on any other anchor changes nothing', () {
      expect(
        routeOf(data(anchor: 'thread:4821', runId: '20163')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/pull-requests/8336'
        '?thread=4821',
      );
    });

    test('an anchor this app does not know adds nothing', () {
      expect(
        routeOf(data(anchor: 'wat:1')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/pull-requests/8336',
      );
      expect(
        routeOf(data(anchor: 'comment:')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/pull-requests/8336',
      );
    });

    test('an anchor never reaches the activity fallback', () {
      expect(
        routeOf(data(artifactType: 'nope', anchor: 'tab:files')),
        '/a/kelly%40kammcs.com-home/orgs/contoso/activity',
      );
    });
  });

  group('the notification it produces', () {
    test('the relay fallback line wins when it is there', () {
      final (title, body) = PushPointer.tryFrom(
        data(
          title: 'Wire up the relay',
          fallbackTitle: '!8336 · Wire up the relay',
          fallbackBody: 'Ada Example replied on !8336',
          fallbackSubtitle: 'DevOps Mobile App',
        ),
      )!.message;
      expect(title, '!8336 · Wire up the relay');
      expect(body, 'Ada Example replied on !8336');
    });

    test('without a fallback body the app builds the phrase from the verb', () {
      final pointer = PushPointer.tryFrom(
        data(actor: 'Ada Example', verb: 'voted', detail: 'rejected'),
      )!;
      expect(pointer.body, 'Ada Example rejected !8336');
    });

    test('a verb with no actor reads as a standalone phrase', () {
      final pointer = PushPointer.tryFrom(
        data(
          artifactType: 'approval',
          artifactId: '18',
          verb: 'approvalPending',
        ),
      )!;
      expect(pointer.body, 'Needs your approval');
    });

    test('an R1 pointer keeps the old heading and body', () {
      final (title, body) = PushPointer.tryFrom(data())!.message;
      expect(title, 'Pull request updated');
      expect(body, 'Pull request 8336 in DevOps Mobile App');
    });

    test('the subtitle is the project unless the relay said otherwise', () {
      expect(PushPointer.tryFrom(data())!.subtitle, 'DevOps Mobile App');
      expect(PushPointer.tryFrom(data(project: ''))!.subtitle, isNull);
      expect(
        PushPointer.tryFrom(data(fallbackSubtitle: 'Other'))!.subtitle,
        'Other',
      );
    });

    test('the tag is the collapse key, and the id follows it', () {
      final thread = PushPointer.tryFrom(
        data(collapseKey: 'contoso.pr.8336.t4821'),
      )!;
      final artifact = PushPointer.tryFrom(
        data(collapseKey: 'contoso.pr.8336'),
      )!;
      expect(thread.tag, 'contoso.pr.8336.t4821');
      expect(thread.notificationId, isNot(artifact.notificationId));
      expect(thread.notificationId, greaterThanOrEqualTo(0));
      // Two events on the same thread land on the same notification.
      expect(
        PushPointer.tryFrom(
          data(collapseKey: 'contoso.pr.8336.t4821', title: 'other'),
        )!.notificationId,
        thread.notificationId,
      );
    });

    test('without a collapse key the id is stable per artifact', () {
      final a = PushPointer.tryFrom(data(title: 'one'))!;
      final b = PushPointer.tryFrom(data(title: 'two'))!;
      final c = PushPointer.tryFrom(data(artifactId: '8334'))!;
      expect(a.notificationId, b.notificationId);
      expect(a.notificationId, isNot(c.notificationId));
      expect(a.tag, 'contoso.pullRequest.8336');
    });

    test('the group is the artifact family in that organization', () {
      expect(PushPointer.tryFrom(data())!.groupKey, 'contoso.pr');
      expect(
        PushPointer.tryFrom(data(artifactType: 'workItem'))!.groupKey,
        'contoso.wi',
      );
    });
  });

  group('the feed key', () {
    test('matches what the poll writes', () {
      expect(PushPointer.tryFrom(data())!.activityKey, 'pr:8336');
      expect(
        PushPointer.tryFrom(
          data(artifactType: 'workItem', artifactId: '15503'),
        )!.activityKey,
        'wi:15503',
      );
      expect(
        PushPointer.tryFrom(data(artifactType: 'build', artifactId: '20163'))!
            .activityKey,
        'build:20163',
      );
    });

    test('an approval takes its run, and none without one', () {
      expect(
        PushPointer.tryFrom(
          data(artifactType: 'approval', artifactId: '18', runId: '20163'),
        )!.activityKey,
        'build:20163',
      );
      expect(
        PushPointer.tryFrom(data(artifactType: 'approval', artifactId: '18'))!
            .activityKey,
        isNull,
      );
    });
  });
}
