import 'package:boardhop_relay/src/gateway/apns.dart';
import 'package:boardhop_relay/src/gateway/fcm.dart';
import 'package:boardhop_relay/src/gateway/pointer.dart';
import 'package:test/test.dart';

PushPointer pr({String? title, String? deepLink}) => PushPointer(
  org: 'puremedia',
  eventType: 'git.pullrequest.updated',
  artifactType: PushArtifactType.pullRequest,
  artifactId: '8336',
  project: 'DevOps Mobile App',
  title: title,
  deepLink: deepLink,
);

void main() {
  group('the pointer contract', () {
    test('carries ids, and a title no longer than 80 characters', () {
      final long = 'x' * 200;
      final pointer = pr(title: long);
      expect(pointer.title!.length, PushPointer.maxTitle);
      expect(pointer.title, endsWith('…'));
    });

    test('an empty or blank title becomes null rather than an empty line', () {
      expect(pr(title: '   ').title, isNull);
      expect(pr().title, isNull);
    });

    test('the data payload is only the pointer fields', () {
      final data = pr(title: 'Wire up the relay', deepLink: '/orgs/puremedia/pull-requests/8336').toData();
      expect(data.keys.toSet(), {'org', 'eventType', 'artifactType', 'artifactId', 'project', 'title', 'deepLink'});
      expect(data['artifactType'], 'pullRequest');
      expect(data['artifactId'], '8336');
    });

    test('the collapse id is per artifact and fits APNs 64 bytes', () {
      expect(pr().collapseId, 'puremedia.pullRequest.8336');
      final huge = PushPointer(
        org: 'o' * 90,
        eventType: 'workitem.updated',
        artifactType: PushArtifactType.workItem,
        artifactId: '15503',
        project: 'p',
      );
      expect(huge.collapseId.length, 64);
    });

    test('the heading comes from the event type, the body from the title', () {
      expect(pr(title: 'Wire up the relay').notificationTitle, 'Pull request updated');
      expect(pr(title: 'Wire up the relay').notificationBody, 'Wire up the relay');
      // No title: still no content, just the artifact.
      expect(pr().notificationBody, 'Pull request 8336 in DevOps Mobile App');
    });

    test('an unknown event type still names the artifact kind', () {
      final pointer = PushPointer(
        org: 'puremedia',
        eventType: 'something.new',
        artifactType: PushArtifactType.approval,
        artifactId: '18',
        project: 'DevOps Mobile App',
      );
      expect(pointer.notificationTitle, 'Approval');
    });

    test('tryFromJson refuses an artifact type outside the four', () {
      Map<String, Object?> body(String type) => {
        'org': 'puremedia',
        'eventType': 'workitem.updated',
        'artifactType': type,
        'artifactId': '15503',
        'project': 'DevOps Mobile App',
      };
      expect(PushPointer.tryFromJson(body('workItem')), isNotNull);
      expect(PushPointer.tryFromJson(body('comment')), isNull);
      expect(PushPointer.tryFromJson(const {'org': 'puremedia'}), isNull);
    });
  });

  group('FCM message', () {
    test('carries the notification, the data and the app\'s own channel', () {
      final sender = FcmSender(projectId: 'boardhop-d4b8f', serviceAccountFile: 'nowhere.json');
      final message = sender.message('device-token', pr(title: 'Wire up the relay'));
      expect(message['token'], 'device-token');
      expect((message['notification']! as Map)['title'], 'Pull request updated');
      expect((message['data']! as Map)['artifactId'], '8336');
      final android = message['android']! as Map;
      expect(android['collapse_key'], 'puremedia.pullRequest.8336');
      expect((android['notification']! as Map)['channel_id'], 'activity');
    });

    test('is disabled and says why when the service account is missing', () {
      final sender = FcmSender(projectId: 'boardhop-d4b8f', serviceAccountFile: 'nowhere.json');
      expect(sender.ready, isFalse);
      expect(sender.status, 'disabled (no service account)');
    });
  });

  group('APNs', () {
    test('is disabled, with the reason, until the Key ID is known', () {
      final sender = ApnsSender(keyFile: 'nowhere.p8', keyId: '', teamId: '73W98CESN9', topic: 'com.kammcs.boardhop');
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
      final sender = ApnsSender(keyFile: 'nowhere.p8', keyId: '', teamId: '', topic: 't');
      final result = await sender.send('token', pr());
      expect(result.outcome, PushOutcome.skipped);
    });
  });
}
