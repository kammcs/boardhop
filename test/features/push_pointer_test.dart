import 'package:boardhop/features/notifications/push_pointer.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';

Map<String, Object?> data({
  String artifactType = 'pullRequest',
  String artifactId = '8336',
  String project = 'DevOps Mobile App',
  String eventType = 'git.pullrequest.updated',
  String? title,
  String? deepLink,
}) => {
  'org': 'puremedia',
  'eventType': eventType,
  'artifactType': artifactType,
  'artifactId': artifactId,
  'project': project,
  'title': ?title,
  'deepLink': ?deepLink,
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
  });

  group('pointer to route', () {
    String routeOf(Map<String, Object?> json) =>
        PushPointer.tryFrom(json)!.route(account);

    test('a pull request lands on the org-level PR route', () {
      expect(
        routeOf(data()),
        '/a/kelly%40kammcs.com-home/orgs/puremedia/pull-requests/8336',
      );
    });

    test('a work item lands inside its project', () {
      expect(
        routeOf(data(artifactType: 'workItem', artifactId: '15503')),
        '/a/kelly%40kammcs.com-home/orgs/puremedia/projects/'
        'DevOps%20Mobile%20App/work-items/15503',
      );
    });

    test('a build lands on its run', () {
      expect(
        routeOf(data(artifactType: 'build', artifactId: '4242')),
        '/a/kelly%40kammcs.com-home/orgs/puremedia/projects/'
        'DevOps%20Mobile%20App/pipelines/runs/4242',
      );
    });

    test('an approval lands on the project pipelines page', () {
      expect(
        routeOf(data(artifactType: 'approval', artifactId: '18')),
        '/a/kelly%40kammcs.com-home/orgs/puremedia/projects/'
        'DevOps%20Mobile%20App/pipelines',
      );
    });

    test('an unroutable pointer falls back to the activity feed', () {
      expect(
        routeOf(data(artifactType: 'build', artifactId: '0', project: '')),
        '/a/kelly%40kammcs.com-home/orgs/puremedia/activity',
      );
    });

    test('a deep link is used only when it names an account', () {
      expect(
        routeOf(data(deepLink: '/a/someone-else/orgs/puremedia/activity')),
        '/a/someone-else/orgs/puremedia/activity',
      );
      // Anything else is ignored: the relay cannot steer the app at a route
      // of its own choosing.
      expect(
        routeOf(data(deepLink: '/activity')),
        '/a/kelly%40kammcs.com-home/orgs/puremedia/pull-requests/8336',
      );
    });
  });

  group('the notification it produces', () {
    test(
      'the heading comes from the event type and the body from the title',
      () {
        final (title, body) = PushPointer.tryFrom(
          data(title: 'Wire up the relay'),
        )!.message;
        expect(title, 'Pull request updated');
        expect(body, 'Wire up the relay');
      },
    );

    test('without a title the body names the artifact, never content', () {
      final (_, body) = PushPointer.tryFrom(data())!.message;
      expect(body, 'Pull request 8336 in DevOps Mobile App');
    });

    test('the notification id is stable per artifact', () {
      final a = PushPointer.tryFrom(data(title: 'one'))!.notificationId;
      final b = PushPointer.tryFrom(data(title: 'two'))!.notificationId;
      final c = PushPointer.tryFrom(data(artifactId: '8334'))!.notificationId;
      expect(a, b);
      expect(a, isNot(c));
      expect(a, greaterThanOrEqualTo(0));
    });
  });
}
