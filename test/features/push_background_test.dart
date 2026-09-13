import 'dart:convert';

import 'package:boardhop/features/notifications/push_background.dart';
import 'package:boardhop/features/notifications/push_pointer.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 9, 13, 10, 30);

Map<String, Object?> data({
  String artifactType = 'pullRequest',
  String artifactId = '8336',
  String? collapseKey = 'contoso.pr.8336.t4821',
  String? sentAt,
  String? fallbackTitle = '!8336 · Wire up the relay',
  String? fallbackBody = 'Ada Example replied on !8336',
  String? fallbackSubtitle = 'DevOps Mobile App',
  String eventType = 'ms.vss-code.git-pullrequest-comment-event',
}) => {
  'org': 'contoso',
  'eventType': eventType,
  'artifactType': artifactType,
  'artifactId': artifactId,
  'project': 'DevOps Mobile App',
  'verb': 'replied',
  'actor': 'Ada Example',
  'anchor': 'thread:4821',
  'collapseKey': ?collapseKey,
  'sentAt': sentAt ?? now.toIso8601String(),
  'fallbackTitle': ?fallbackTitle,
  'fallbackBody': ?fallbackBody,
  'fallbackSubtitle': ?fallbackSubtitle,
};

void main() {
  group('what the background isolate posts', () {
    test('the fallback line, tagged and grouped', () {
      final request = backgroundNotificationFor(
        data(),
        enabled: true,
        now: now,
      )!;
      expect(request.title, '!8336 · Wire up the relay');
      expect(request.body, 'Ada Example replied on !8336');
      expect(request.subtitle, 'DevOps Mobile App');
      expect(request.tag, 'contoso.pr.8336.t4821');
      expect(request.groupKey, 'contoso.pr');
      expect(request.id, greaterThanOrEqualTo(0));
    });

    test('the lock-screen version is the same line, for now', () {
      final request = backgroundNotificationFor(
        data(),
        enabled: true,
        now: now,
      )!;
      expect(request.publicTitle, request.title);
      expect(request.publicBody, request.body);
      expect(request.publicMatchesPrivate, isTrue);
    });

    test('the payload is the pointer, so a tap routes like any other', () {
      final request = backgroundNotificationFor(
        data(),
        enabled: true,
        now: now,
      )!;
      expect(request.payload, startsWith(pushPayloadPrefix));
      final decoded =
          jsonDecode(request.payload.substring(pushPayloadPrefix.length))
              as Map<String, Object?>;
      expect(decoded['artifactId'], '8336');
      expect(decoded['anchor'], 'thread:4821');

      final pointer = pointerFromPayload(request.payload)!;
      expect(
        pointer.route('acct'),
        '/a/acct/orgs/contoso/pull-requests/8336?thread=4821',
      );
    });

    test('without a collapse key the tag is the artifact', () {
      final request = backgroundNotificationFor(
        data(collapseKey: null),
        enabled: true,
        now: now,
      )!;
      expect(request.tag, 'contoso.pullRequest.8336');
    });

    test('the test push shows too: it is the support route', () {
      final request = backgroundNotificationFor(
        {
          'org': 'contoso',
          'eventType': 'boardhop.test',
          'artifactType': 'build',
          'artifactId': '0',
          'project': '',
          'verb': 'test',
          'fallbackTitle': 'Boardhop',
          'fallbackBody': 'Push is working',
        },
        enabled: true,
        now: now,
      );
      expect(request, isNotNull);
      expect(request!.body, 'Push is working');
      expect(request.subtitle, isNull);
    });
  });

  group('what it drops', () {
    test('a pointer that does not parse', () {
      expect(
        backgroundNotificationFor(const {'hello': 'world'},
            enabled: true, now: now),
        isNull,
      );
    });

    test('everything while the user has notifications off', () {
      expect(
        backgroundNotificationFor(data(), enabled: false, now: now),
        isNull,
      );
    });

    test('a pointer older than ten minutes', () {
      final stale = data(
        sentAt: now.subtract(const Duration(minutes: 11)).toIso8601String(),
      );
      expect(backgroundNotificationFor(stale, enabled: true, now: now), isNull);
      final fresh = data(
        sentAt: now.subtract(const Duration(minutes: 9)).toIso8601String(),
      );
      expect(
        backgroundNotificationFor(fresh, enabled: true, now: now),
        isNotNull,
      );
    });
  });

  group('the tap payload', () {
    test('an ordinary route is left alone', () {
      expect(pointerFromPayload('/a/acct/orgs/contoso/activity'), isNull);
    });

    test('a malformed pointer payload is not a crash', () {
      expect(pointerFromPayload('push:{not json'), isNull);
      expect(pointerFromPayload('push:{"org":"contoso"}'), isNull);
      expect(pointerFromPayload('push:[]'), isNull);
    });

    test('round-trips through the pointer', () {
      final pointer = PushPointer.tryFrom(data())!;
      final back = pointerFromPayload(pushPayloadFor(pointer))!;
      expect(back.org, pointer.org);
      expect(back.collapseKey, pointer.collapseKey);
      expect(back.verb, pointer.verb);
      expect(back.sentAt, pointer.sentAt);
    });
  });

  group('who posts a background pointer (R2.6)', () {
    test('off Android nothing is handed to the platform', () {
      // BoardhopMessagingService owns background pointers on Android and
      // enriches them; everywhere else this isolate is still the poster.
      expect(handledByPlatform(data()), isFalse);
      expect(handledByPlatform(const {'org': 'contoso'}), isFalse);
    });
  });
}
