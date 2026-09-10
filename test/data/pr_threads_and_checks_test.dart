import 'package:boardhop/data/models/pr_check.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrThread.fromJson', () {
    test('keeps comment ids, authors and dates; drops system and deleted', () {
      final thread = PrThread.fromJson({
        'id': 42375,
        'status': 'fixed',
        'threadContext': {
          'filePath': '/src/app.ts',
          'rightFileStart': {'line': 9, 'offset': 1},
        },
        'pullRequestThreadContext': {
          'trackingCriteria': {
            'origRightFileStart': {'line': 6, 'offset': 1},
          },
        },
        'comments': [
          {
            'id': 1,
            'parentCommentId': 0,
            'commentType': 'text',
            'content': 'root',
            'publishedDate': '2026-09-10T14:17:35.113Z',
            'author': {'displayName': 'Kelly Kamm', 'id': 'k'},
          },
          {
            'id': 2,
            'parentCommentId': 1,
            'commentType': 'text',
            'content': 'reply',
            'publishedDate': '2026-09-10T15:00:00Z',
            'author': {'displayName': 'Bot', 'id': 'b'},
          },
          {
            'id': 3,
            'commentType': 'text',
            'content': 'gone',
            'isDeleted': true,
          },
          {'id': 4, 'commentType': 'system', 'content': 'voted'},
        ],
      })!;
      expect(thread.filePath, '/src/app.ts');
      expect(thread.rightLine, 9);
      expect(thread.trackedFromLine, 6);
      expect(thread.isResolved, isTrue);
      expect(thread.isFileThread, isTrue);
      expect(thread.comments.map((c) => c.id), [1, 2]);
      expect(thread.comments[1].parentId, 1);
      expect(thread.comments[0].identity?.id, 'k');
      expect(thread.lastActivity, DateTime.utc(2026, 9, 10, 15));
    });

    test('returns null for deleted threads and system-only threads', () {
      expect(PrThread.fromJson({'id': 1, 'isDeleted': true}), isNull);
      expect(
        PrThread.fromJson({
          'id': 2,
          'comments': [
            {'commentType': 'system', 'content': 'joined'},
          ],
        }),
        isNull,
      );
    });

    test('status vocabulary', () {
      expect(PrThreadStatus.isResolved('fixed'), isTrue);
      expect(PrThreadStatus.isResolved('wontFix'), isTrue);
      expect(PrThreadStatus.isResolved('active'), isFalse);
      expect(PrThreadStatus.isResolved('pending'), isFalse);
      expect(PrThreadStatus.label('wontFix'), "Won't fix");
      expect(PrThreadStatus.label('fixed'), 'Resolved');
    });
  });

  group('PrCheck', () {
    test('folds policy evaluations into check states', () {
      PrCheck eval(String status, String name, [Map<String, dynamic>? extra]) =>
          PrCheck.fromEvaluation({
            'status': status,
            'configuration': {
              'isBlocking': true,
              'type': {'displayName': name},
              'settings': extra?['settings'] ?? {},
            },
            'context': extra?['context'] ?? {},
          });
      expect(
        eval('approved', 'Minimum number of reviewers', {
          'settings': {'minimumApproverCount': 2},
        }),
        const PrCheck(
          name: 'Minimum number of reviewers',
          state: PrCheckState.succeeded,
          detail: '2 approvals required',
          isBlocking: true,
        ),
      );
      expect(eval('rejected', 'Work item linking').state, PrCheckState.failed);
      expect(
        eval('rejected', 'Work item linking').detail,
        'No work item linked',
      );
      expect(
        eval('running', 'Build', {
          'settings': {'displayName': 'CI'},
          'context': {'buildDefinitionName': 'ci-main', 'isExpired': false},
        }).detail,
        'ci-main · running',
      );
      expect(eval('queued', 'Required reviewers').state, PrCheckState.pending);
      expect(eval('broken', 'Build').state, PrCheckState.error);
      expect(eval('notApplicable', 'Build').state, PrCheckState.notApplicable);
    });

    test('statuses: newest iteration only, newest row per context', () {
      Map<String, dynamic> status(int id, int iteration, String? state) => {
        'id': id,
        'iterationId': iteration,
        'state': ?state,
        'description': 'row $id',
        'context': {'name': 'codecoverage', 'genre': 'ci'},
      };
      final checks = PrCheck.latestStatuses([
        status(1, 1, null),
        status(2, 1, 'failed'),
        status(3, 2, null),
        status(4, 2, 'pending'),
        {
          'id': 5,
          'iterationId': 2,
          'state': 'succeeded',
          'context': {'name': 'lint', 'genre': 'ci'},
        },
      ]);
      expect(checks.length, 2);
      final coverage = checks.firstWhere((c) => c.name == 'ci / codecoverage');
      expect(coverage.state, PrCheckState.pending);
      expect(coverage.detail, 'row 4');
      expect(
        checks.firstWhere((c) => c.name == 'ci / lint').state,
        PrCheckState.succeeded,
      );
      // A queued status without a state counts as pending.
      expect(
        PrCheck.fromStatus(status(9, 1, null)).state,
        PrCheckState.pending,
      );
    });
  });

  test('list cache keys are scoped by org, project and filter', () {
    expect(
      PullRequestRepository.listKey('puremedia', null, PrListFilter.toReview),
      'pr-list:puremedia:*:toReview',
    );
    expect(
      PullRequestRepository.listKey(
        'puremedia',
        'CloudCover 2.0',
        PrListFilter.all,
      ),
      'pr-list:puremedia:CloudCover 2.0:all',
    );
  });
}
