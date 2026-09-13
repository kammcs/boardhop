import 'package:boardhop/data/models/push_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

/// The relay's own defaults, copied from `relay/README.md` ("Preferences"):
/// this is the contract the two halves have to agree on.
const relayDefaults = <String, Object?>{
  'enabled': true,
  'workItems': {
    'assigned': true,
    'stateChanged': true,
    'comments': 'on',
    'anyChangeOnMine': false,
  },
  'pullRequests': {
    'reviewRequested': true,
    'votes': 'on',
    'comments': 'on',
    'completedAbandoned': true,
    'pushes': false,
  },
  'builds': 'failuresAndFixed',
  'approvals': true,
  'quietHours': {
    'enabled': false,
    'start': '22:00',
    'end': '07:00',
    'exceptApprovals': true,
  },
  'mutedArtifacts': <Object?>[],
  'notActor': true,
};

void main() {
  group('defaults', () {
    test('are the relay document, key for key', () {
      expect(PushPrefs.fromDefaults().toJson(), relayDefaults);
    });

    test('a document the relay has not stored reads as the defaults', () {
      expect(PushPrefs.fromJson(const {}).toJson(), relayDefaults);
    });
  });

  group('JSON', () {
    test('round-trips every field', () {
      final prefs = PushPrefs(
        enabled: false,
        workItemsAssigned: false,
        workItemsStateChanged: false,
        workItemsComments: CommentPref.mentionsOnly,
        workItemsAnyChangeOnMine: true,
        pullRequestsReviewRequested: false,
        pullRequestsVotes: VotePref.rejectionsAndWaitsOnly,
        pullRequestsComments: PrCommentPref.myThreadsOnly,
        pullRequestsCompletedAbandoned: false,
        pullRequestsPushes: true,
        builds: BuildPref.all,
        approvals: false,
        quietHours: const QuietHours(
          enabled: true,
          start: '23:00',
          end: '06:30',
          exceptApprovals: false,
        ),
        mutedArtifacts: [
          const MutedArtifact(type: 'pr', id: '8336'),
          MutedArtifact(
            type: 'wi',
            id: '15545',
            until: DateTime.utc(2026, 9, 14, 8),
          ),
        ],
      );
      final back = PushPrefs.fromJson(prefs.toJson());
      expect(back.toJson(), prefs.toJson());
      expect(back.workItemsComments, CommentPref.mentionsOnly);
      expect(back.pullRequestsComments, PrCommentPref.myThreadsOnly);
      expect(back.builds, BuildPref.all);
      expect(back.quietHours.start, '23:00');
      expect(back.mutedArtifacts.map((m) => m.key), ['pr.8336', 'wi.15545']);
      expect(back.mutedArtifacts.last.until, DateTime.utc(2026, 9, 14, 8));
    });

    test('a value outside its list falls back rather than throwing', () {
      final prefs = PushPrefs.fromJson(const {
        'builds': 'sometimes',
        'workItems': {'comments': 'maybe'},
        'pullRequests': {'votes': 42},
      });
      expect(prefs.builds, BuildPref.failuresAndFixed);
      expect(prefs.workItemsComments, CommentPref.on);
      expect(prefs.pullRequestsVotes, VotePref.on);
    });

    test('the write form leaves notActor out, because the relay refuses it', () {
      final write = PushPrefs.fromDefaults().toJson(forWrite: true);
      expect(write.containsKey('notActor'), isFalse);
      expect(write['builds'], 'failuresAndFixed');
      // Everything else is still there: the relay fills a missing key from its
      // own defaults, and a key left out would silently change nothing.
      expect(write.keys, containsAll(relayDefaults.keys.where((k) => k != 'notActor')));
    });

    test('notActor is reported and not settable', () {
      expect(PushPrefs.notActor, isTrue);
      expect(
        PushPrefs.fromJson(const {'notActor': false}).toJson()['notActor'],
        isTrue,
      );
    });
  });

  group('quiet hours', () {
    test('validates and formats HH:mm', () {
      expect(QuietHours.isValidTime('00:00'), isTrue);
      expect(QuietHours.isValidTime('23:59'), isTrue);
      expect(QuietHours.isValidTime('24:00'), isFalse);
      expect(QuietHours.isValidTime('7:00'), isFalse);
      expect(QuietHours.parse('06:30'), (6, 30));
      expect(QuietHours.parse('nope'), isNull);
      expect(QuietHours.format(6, 5), '06:05');
    });
  });

  test('a muted artifact reads as the artifact does elsewhere', () {
    expect(const MutedArtifact(type: 'pr', id: '8336').label, '!8336');
    expect(const MutedArtifact(type: 'wi', id: '15545').label, '#15545');
    expect(const MutedArtifact(type: 'build', id: '20163').label, 'Build 20163');
  });
}
