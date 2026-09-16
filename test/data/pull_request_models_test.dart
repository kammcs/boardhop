import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shapes copied from the scratch readbacks of spikes w39, w40 and s65
/// (scratch project "DevOps Mobile App", pull request 8401).
const org = 'puremedia';
const projectGuid = '98720989-0195-48cb-ae2e-0e58ec1bb9a9';
const repoGuid = '4c06881a-4e20-49c8-88c4-a21323fe04b5';
const meGuid = '5ed61bee-579a-69a3-8d5b-295951b461b4';

Map<String, dynamic> prJson({
  Map<String, dynamic>? autoCompleteSetBy,
  Map<String, dynamic>? completionOptions,
  Object? labels,
  String status = 'active',
}) => {
  'pullRequestId': 8401,
  'title': 'spike w39 PR A retitled',
  'status': status,
  'isDraft': false,
  'repository': {
    'id': repoGuid,
    'name': 'DevOps Mobile App',
    'project': {'id': projectGuid, 'name': 'DevOps Mobile App'},
  },
  'sourceRefName': 'refs/heads/spike/w39-a',
  'targetRefName': 'refs/heads/scratch/policy-target',
  'createdBy': {'displayName': 'Kelly Kamm', 'id': meGuid},
  'mergeStatus': 'succeeded',
  'labels': ?labels,
  'autoCompleteSetBy': ?autoCompleteSetBy,
  'completionOptions': ?completionOptions,
};

/// The options as the service echoes them: `squashMerge` rides along beside
/// `mergeStrategy`.
Map<String, dynamic> squashOptions() => {
  'mergeCommitMessage': 'spike w39: squash merge message for PR 8401',
  'deleteSourceBranch': true,
  'squashMerge': true,
  'mergeStrategy': 'squash',
  'transitionWorkItems': true,
};

Map<String, dynamic> policyJson({
  required int id,
  required String type,
  required String displayName,
  bool isBlocking = true,
  bool isEnabled = true,
  Map<String, dynamic> settings = const {},
  String refName = 'refs/heads/scratch/policy-target',
  String matchKind = 'exact',
}) => {
  'id': id,
  'isBlocking': isBlocking,
  'isEnabled': isEnabled,
  'isDeleted': false,
  'type': {'id': type, 'displayName': displayName},
  'settings': {
    ...settings,
    'scope': [
      {'refName': refName, 'matchKind': matchKind, 'repositoryId': repoGuid},
    ],
  },
};

/// Policy 193 on the scratch target: squash and no-fast-forward only.
Map<String, dynamic> mergeStrategyPolicy({
  bool isBlocking = true,
  Map<String, dynamic> settings = const {
    'allowNoFastForward': true,
    'allowSquash': true,
  },
}) => policyJson(
  id: 193,
  type: PrPolicy.mergeStrategyType,
  displayName: 'Require a merge strategy',
  isBlocking: isBlocking,
  settings: settings,
);

/// Policy 192 on the scratch target.
Map<String, dynamic> minimumReviewersPolicy() => policyJson(
  id: 192,
  type: PrPolicy.minimumReviewersType,
  displayName: 'Minimum number of reviewers',
  settings: const {'minimumApproverCount': 1, 'creatorVoteCounts': false},
);

Map<String, dynamic> systemThread({
  required int id,
  required String kind,
  required String content,
  Map<String, dynamic>? identities,
}) => {
  'id': id,
  'status': null,
  'publishedDate': '2026-09-16T04:40:00Z',
  'properties': {
    'CodeReviewThreadType': {r'$type': 'System.String', r'$value': kind},
    if (kind == 'AutoCompleteUpdate')
      'CodeReviewAutoCompleteNowSet': {
        r'$type': 'System.String',
        r'$value': '1',
      },
  },
  'identities': ?identities,
  'comments': [
    {
      'id': 1,
      'parentCommentId': 0,
      'content': content,
      'commentType': 'system',
      'publishedDate': '2026-09-16T04:40:00Z',
      'author': {'displayName': 'Kelly Kamm', 'id': meGuid},
    },
  ],
};

Map<String, dynamic> fileThread({
  required int id,
  required Map<String, dynamic> threadContext,
  List<Map<String, dynamic>>? comments,
  String status = 'active',
}) => {
  'id': id,
  'status': status,
  'publishedDate': '2026-09-16T04:35:00Z',
  'threadContext': threadContext,
  'pullRequestThreadContext': {
    'iterationContext': {
      'firstComparingIteration': 1,
      'secondComparingIteration': 1,
    },
    'changeTrackingId': 4,
  },
  'comments':
      comments ??
      [
        {
          'id': 1,
          'parentCommentId': 0,
          'content': 'spike w39: a comment.',
          'commentType': 'text',
          'publishedDate': '2026-09-16T04:35:00Z',
          'author': {'displayName': 'Kelly Kamm', 'id': meGuid},
          'usersLiked': const <Object>[],
        },
      ],
};

void main() {
  group('PullRequest auto-complete', () {
    test('reads autoCompleteSetBy and the options it was set with', () {
      final pr = PullRequest.fromJson(
        prJson(
          autoCompleteSetBy: {'displayName': 'Kelly Kamm', 'id': meGuid},
          completionOptions: squashOptions(),
        ),
      );

      expect(pr.isAutoCompleteSet, isTrue);
      expect(pr.autoCompleteSetBy!.displayName, 'Kelly Kamm');
      expect(pr.completionOptions!.mergeStrategy, MergeStrategy.squash);
      expect(pr.completionOptions!.deleteSourceBranch, isTrue);
      expect(pr.completionOptions!.transitionWorkItems, isTrue);
      expect(pr.completionOptions!.mergeCommitMessage, contains('squash'));
    });

    test('a cancel drops the identity and keeps the remembered options', () {
      // What `PATCH autoCompleteSetBy: {id: null-guid}` reads back as.
      final pr = PullRequest.fromJson(
        prJson(
          completionOptions: const {
            'deleteSourceBranch': true,
            'mergeStrategy': 'rebase',
          },
        ),
      );

      expect(pr.isAutoCompleteSet, isFalse);
      expect(pr.completionOptions!.mergeStrategy, MergeStrategy.rebase);
      expect(pr.completionOptions!.deleteSourceBranch, isTrue);
    });

    test('a pull request with neither reads as not set', () {
      final pr = PullRequest.fromJson(prJson());
      expect(pr.isAutoCompleteSet, isFalse);
      expect(pr.completionOptions, isNull);
    });

    test('survives a cache round trip', () {
      final pr = PullRequest.fromJson(
        prJson(
          autoCompleteSetBy: {'displayName': 'Kelly Kamm', 'id': meGuid},
          completionOptions: squashOptions(),
          labels: [
            {'id': 'c2e3426f', 'name': 'boardhop-spike', 'active': true},
          ],
        ),
      );

      final back = PullRequest.fromJson(pr.toJson());

      expect(back.autoCompleteSetBy?.id, meGuid);
      expect(back.completionOptions, pr.completionOptions);
      expect(back.labels.single.name, 'boardhop-spike');
      expect(back, pr);
    });
  });

  group('PrCompletionOptions', () {
    test('sends mergeStrategy, never the legacy squashMerge flag', () {
      const options = PrCompletionOptions(
        mergeStrategy: MergeStrategy.squash,
        deleteSourceBranch: true,
        transitionWorkItems: true,
        mergeCommitMessage: 'Squashed',
      );

      expect(options.toJson(), {
        'mergeStrategy': 'squash',
        'deleteSourceBranch': true,
        'transitionWorkItems': true,
        'mergeCommitMessage': 'Squashed',
      });
    });

    test('reads the legacy squashMerge flag when no strategy is named', () {
      final options = PrCompletionOptions.fromJson(const {
        'squashMerge': true,
        'deleteSourceBranch': false,
      });
      expect(options.mergeStrategy, MergeStrategy.squash);
    });

    test('a bypass reason only rides along with the bypass', () {
      const withoutBypass = PrCompletionOptions(bypassReason: 'hotfix');
      expect(withoutBypass.toJson().containsKey('bypassReason'), isFalse);

      const withBypass = PrCompletionOptions(
        bypassPolicy: true,
        bypassReason: 'hotfix',
      );
      expect(withBypass.toJson()['bypassPolicy'], isTrue);
      expect(withBypass.toJson()['bypassReason'], 'hotfix');
    });

    test('ignored config ids ride along only when there are some', () {
      const none = PrCompletionOptions();
      expect(none.toJson().containsKey('autoCompleteIgnoreConfigIds'), isFalse);
      const some = PrCompletionOptions(autoCompleteIgnoreConfigIds: [191]);
      expect(some.toJson()['autoCompleteIgnoreConfigIds'], [191]);
    });
  });

  group('PrLabel', () {
    test('a list route carries objects, a get carries null', () {
      final listed = PullRequest.fromJson(
        prJson(
          labels: [
            {'id': 'c2e3426f', 'name': 'boardhop-spike', 'active': true},
            {'id': '65176f7a', 'name': 'boardhop-spike-2', 'active': true},
          ],
        ),
      );
      expect(listed.labels.map((l) => l.name), [
        'boardhop-spike',
        'boardhop-spike-2',
      ]);

      // `GET pullRequests/{id}` never carries labels, whatever the query
      // (spikes s65 §A and w40): the detail has to read the sub-resource.
      final fetched = PullRequest.fromJson(prJson());
      expect(fetched.labels, isEmpty);
      expect(PullRequest.fromJson(prJson(labels: null)).labels, isEmpty);
    });

    test('bare strings and nameless entries are tolerated', () {
      expect(PrLabel.listFrom(['a', 'b']).map((l) => l.name), ['a', 'b']);
      expect(PrLabel.listFrom([const <String, Object>{}]), isEmpty);
      expect(PrLabel.listFrom('nonsense'), isEmpty);
    });
  });

  group('PrReviewer', () {
    test('reads required, flagged, declined and the teams voted for', () {
      final reviewer = PrReviewer.fromJson({
        'id': meGuid,
        'displayName': 'Kelly Kamm',
        'vote': 10,
        'isRequired': true,
        'isFlagged': true,
        'hasDeclined': false,
        'votedFor': [
          {'id': '8c08e1e1', 'displayName': 'DevOps Mobile App Team'},
        ],
      });

      expect(reviewer.isRequired, isTrue);
      expect(reviewer.isFlagged, isTrue);
      expect(reviewer.hasDeclined, isFalse);
      expect(reviewer.votedFor.single.displayName, 'DevOps Mobile App Team');
      // `isRequired: false` comes back as an absent field, not `false`.
      expect(
        PrReviewer.fromJson({
          'id': meGuid,
          'displayName': 'Kelly Kamm',
          'vote': 0,
        }).isRequired,
        isFalse,
      );
    });

    test('a team reviewer is a container with no votes of its own', () {
      final team = PrReviewer.fromJson({
        'id': '8c08e1e1',
        'displayName': 'DevOps Mobile App Team',
        'vote': 10,
        'isContainer': true,
        'votedFor': const <Object>[],
      });
      expect(team.isContainer, isTrue);
      expect(team.votedFor, isEmpty);
    });
  });

  group('PrThread system threads', () {
    test('they are dropped by default and kept behind includeSystem', () {
      final raw = systemThread(
        id: 42900,
        kind: 'AutoCompleteUpdate',
        content: 'Kelly Kamm set auto-complete',
      );

      expect(PrThread.fromJson(raw), isNull);

      final kept = PrThread.fromJson(raw, includeSystem: true)!;
      expect(kept.isSystem, isTrue);
      expect(kept.systemKind, 'AutoCompleteUpdate');
      expect(kept.systemText, 'Kelly Kamm set auto-complete');
    });

    test('{n} placeholders resolve against the identities map', () {
      final kept = PrThread.fromJson(
        systemThread(
          id: 42901,
          kind: 'VoteUpdate',
          content: '{1} voted 10',
          identities: {
            '1': {'displayName': 'Kelly Kamm', 'id': meGuid},
          },
        ),
        includeSystem: true,
      )!;

      expect(kept.systemText, 'Kelly Kamm voted 10');
    });

    test('a placeholder with no identity is left alone', () {
      final kept = PrThread.fromJson(
        systemThread(id: 42902, kind: 'RefUpdate', content: '{2} pushed'),
        includeSystem: true,
      )!;
      expect(kept.systemText, '{2} pushed');
    });

    test('a human thread is never a system one', () {
      final thread = PrThread.fromJson(
        fileThread(
          id: 42977,
          threadContext: const {
            'filePath': '/spike/w39/one.txt',
            'rightFileStart': {'line': 1, 'offset': 1},
            'rightFileEnd': {'line': 1, 'offset': 1},
          },
        ),
      )!;
      expect(thread.isSystem, isFalse);
      expect(thread.systemKind, isNull);
    });
  });

  group('PrThread anchors', () {
    test('a path with no line on either side is file-level', () {
      final thread = PrThread.fromJson(
        fileThread(id: 42973, threadContext: const {'filePath': '/src/app.ts'}),
      )!;

      expect(thread.isFileLevel, isTrue);
      expect(thread.isLeftSide, isFalse);
      expect(thread.anchorLine, isNull);
      expect(thread.isFileThread, isTrue);
    });

    test('leftFileStart puts the thread on the original side', () {
      final thread = PrThread.fromJson(
        fileThread(
          id: 42974,
          threadContext: const {
            'filePath': '/src/app.ts',
            'leftFileStart': {'line': 5, 'offset': 1},
            'leftFileEnd': {'line': 5, 'offset': 2147483647},
          },
        ),
      )!;

      expect(thread.isLeftSide, isTrue);
      expect(thread.isFileLevel, isFalse);
      expect(thread.leftLine, 5);
      expect(thread.leftLineEnd, 5);
      expect(thread.anchorLine, 5);
      expect(thread.isRange, isFalse);
    });

    test('a right-side range keeps both ends', () {
      final thread = PrThread.fromJson(
        fileThread(
          id: 42975,
          threadContext: const {
            'filePath': '/src/app.ts',
            'rightFileStart': {'line': 5, 'offset': 1},
            'rightFileEnd': {'line': 6, 'offset': 10},
          },
        ),
      )!;

      expect(thread.rightLine, 5);
      expect(thread.rightLineEnd, 6);
      expect(thread.anchorLineEnd, 6);
      expect(thread.isRange, isTrue);
      expect(thread.isLeftSide, isFalse);
    });

    test('a conversation thread has no file and no anchor', () {
      final thread = PrThread.fromJson({
        'id': 1,
        'status': 'active',
        'comments': [
          {
            'id': 1,
            'content': 'plain',
            'commentType': 'text',
            'publishedDate': '2026-09-16T04:00:00Z',
            'author': {'displayName': 'Kelly Kamm'},
          },
        ],
      })!;

      expect(thread.isFileThread, isFalse);
      expect(thread.isFileLevel, isFalse);
      expect(thread.anchorLine, isNull);
    });
  });

  group('PrComment', () {
    test('a deleted comment is dropped by default, kept for the stub', () {
      final raw = fileThread(
        id: 42975,
        threadContext: const {
          'filePath': '/src/app.ts',
          'rightFileStart': {'line': 5, 'offset': 1},
          'rightFileEnd': {'line': 6, 'offset': 10},
        },
        comments: [
          {
            'id': 1,
            'parentCommentId': 0,
            'content': 'spike w39: multi-line right range 5-6.',
            'commentType': 'text',
            'publishedDate': '2026-09-16T04:35:00Z',
            'author': {'displayName': 'Kelly Kamm', 'id': meGuid},
          },
          {
            'id': 2,
            'parentCommentId': 1,
            'content': null,
            'isDeleted': true,
            'commentType': 'text',
            'publishedDate': '2026-09-16T04:36:00Z',
            'author': {'displayName': 'Kelly Kamm', 'id': meGuid},
          },
        ],
      );

      expect(PrThread.fromJson(raw)!.comments.length, 1);

      final withStub = PrThread.fromJson(raw, includeDeleted: true)!;
      expect(withStub.comments.length, 2);
      expect(withStub.comments.last.isDeleted, isTrue);
      expect(withStub.comments.last.content, isEmpty);
    });

    test('likes come back on every read', () {
      final thread = PrThread.fromJson(
        fileThread(
          id: 42975,
          threadContext: const {'filePath': '/src/app.ts'},
          comments: [
            {
              'id': 1,
              'content': 'liked',
              'commentType': 'text',
              'publishedDate': '2026-09-16T04:35:00Z',
              'author': {'displayName': 'Kelly Kamm', 'id': meGuid},
              'usersLiked': [
                {'id': meGuid, 'displayName': 'Kelly Kamm'},
              ],
            },
          ],
        ),
      )!;

      expect(thread.comments.single.usersLiked.length, 1);
      expect(thread.comments.single.likedBy(meGuid), isTrue);
      expect(thread.comments.single.likedBy('someone-else'), isFalse);
      expect(thread.comments.single.likedBy(null), isFalse);
    });

    test('an edit moves lastContentUpdatedDate, which marks it edited', () {
      Map<String, dynamic> comment(String updated) => {
        'id': 2,
        'content': 'spike w39: reply, **edited**.',
        'commentType': 'text',
        'publishedDate': '2026-09-16T04:36:00Z',
        'lastContentUpdatedDate': updated,
        'author': {'displayName': 'Kelly Kamm', 'id': meGuid},
      };

      expect(
        PrComment.fromJson(comment('2026-09-16T04:36:00Z')).isEdited,
        isFalse,
      );
      expect(
        PrComment.fromJson(comment('2026-09-16T04:41:00Z')).isEdited,
        isTrue,
      );
      // Nothing to compare against is not "edited".
      expect(
        PrComment.fromJson(const {'id': 3, 'content': 'x'}).isEdited,
        isFalse,
      );
    });
  });

  group('PrPolicySet', () {
    test('the scratch target: blocking, squash and no-fast-forward only', () {
      final set = PrPolicySet.fromJson({
        'value': [minimumReviewersPolicy(), mergeStrategyPolicy()],
      }, 'refs/heads/scratch/policy-target');

      expect(set.hasBlocking, isTrue);
      expect(set.allowedStrategies, {
        MergeStrategy.noFastForward,
        MergeStrategy.squash,
      });
      expect(set.minimumApproverCount, 1);
      expect(set.creatorVoteCounts, isFalse);
    });

    test('no merge-strategy policy allows all four', () {
      final set = PrPolicySet.fromJson({
        'value': [minimumReviewersPolicy()],
      }, 'refs/heads/scratch/policy-target');

      expect(set.allowedStrategies, MergeStrategy.values.toSet());
    });

    test('two blocking policies intersect', () {
      final set = PrPolicySet.fromJson({
        'value': [
          mergeStrategyPolicy(),
          policyJson(
            id: 194,
            type: PrPolicy.mergeStrategyType,
            displayName: 'Require a merge strategy',
            settings: const {'allowSquash': true, 'allowRebase': true},
          ),
        ],
      }, 'refs/heads/scratch/policy-target');

      expect(set.allowedStrategies, {MergeStrategy.squash});
    });

    test('a non-blocking merge-strategy policy does not narrow anything', () {
      final set = PrPolicySet.fromJson({
        'value': [mergeStrategyPolicy(isBlocking: false)],
      }, 'refs/heads/scratch/policy-target');

      expect(set.hasBlocking, isFalse);
      expect(set.allowedStrategies, MergeStrategy.values.toSet());
    });

    test('main, which carries no policy at all, blocks nothing', () {
      final set = PrPolicySet.fromJson(const {'value': []}, 'refs/heads/main');
      expect(set.policies, isEmpty);
      expect(set.hasBlocking, isFalse);
      expect(set.minimumApproverCount, 0);
      expect(set.requiredReviewerIds, isEmpty);
    });

    test('forTarget keeps only the policies that cover the branch', () {
      final all = [
        PrPolicy.fromJson(mergeStrategyPolicy()),
        PrPolicy.fromJson(
          policyJson(
            id: 300,
            type: PrPolicy.minimumReviewersType,
            displayName: 'Minimum number of reviewers',
            refName: 'refs/heads/releases/',
            matchKind: 'prefix',
            settings: const {'minimumApproverCount': 2},
          ),
        ),
        PrPolicy.fromJson(
          policyJson(
            id: 301,
            type: PrPolicy.minimumReviewersType,
            displayName: 'Minimum number of reviewers',
            isEnabled: false,
            settings: const {'minimumApproverCount': 9},
          ),
        ),
      ];

      final target = PrPolicySet.forTarget(
        all,
        'refs/heads/scratch/policy-target',
      );
      expect(target.policies.map((p) => p.id), [193]);

      final release = PrPolicySet.forTarget(all, 'refs/heads/releases/1.0');
      expect(release.policies.map((p) => p.id), [300]);
      expect(release.minimumApproverCount, 2);
    });

    test('required reviewer ids come from the required-reviewers policy', () {
      final set = PrPolicySet.fromJson({
        'value': [
          policyJson(
            id: 302,
            type: PrPolicy.requiredReviewersType,
            displayName: 'Required reviewers',
            settings: {
              'requiredReviewerIds': [meGuid, meGuid, '8c08e1e1'],
              'minimumApproverCount': 1,
            },
          ),
        ],
      }, 'refs/heads/scratch/policy-target');

      expect(set.requiredReviewerIds, [meGuid, '8c08e1e1']);
    });

    test('survives the cache round trip the repository writes', () {
      final set = PrPolicySet.fromJson({
        'value': [minimumReviewersPolicy(), mergeStrategyPolicy()],
      }, 'refs/heads/scratch/policy-target');

      final back = PrPolicySet.fromJson(
        set.toJson(),
        'refs/heads/scratch/policy-target',
      );

      expect(back, set);
      expect(back.allowedStrategies, set.allowedStrategies);
      expect(back.minimumApproverCount, 1);
    });
  });

  group('PrConflict', () {
    test('reads the two conflicts spike w39 provoked', () {
      final conflicts = [
        for (final m in [
          {
            'conflictId': 1,
            'conflictType': 'editEdit',
            'conflictPath': '/src/app.ts',
            'resolution': <String, dynamic>{},
          },
          {
            'conflictId': 2,
            'conflictType': 'addAdd',
            'conflictPath': '/spike/w39/both.txt',
            'resolutionStatus': 'resolved',
            'resolvedBy': {'displayName': 'Kelly Kamm', 'id': meGuid},
          },
        ])
          PrConflict.fromJson(m),
      ];

      expect(conflicts.first.path, '/src/app.ts');
      expect(conflicts.first.isResolved, isFalse);
      expect(conflicts.first.typeLabel, 'Edited on both sides');
      expect(conflicts.last.isResolved, isTrue);
      expect(conflicts.last.resolvedBy!.displayName, 'Kelly Kamm');
      expect(PrConflict.fromJson(const {}).typeLabel, 'Conflict');
    });
  });

  group('MergeStrategy', () {
    test('wire names round trip and unknown ones are null', () {
      for (final s in MergeStrategy.values) {
        expect(MergeStrategy.fromWire(s.wire), s);
      }
      expect(MergeStrategy.fromWire('Squash'), MergeStrategy.squash);
      expect(MergeStrategy.fromWire('octopus'), isNull);
      expect(MergeStrategy.fromWire(null), isNull);
    });
  });

  group('webUrl', () {
    test('is the link the web opens and Share sends', () {
      final pr = PullRequest.fromJson(prJson());
      expect(
        pr.webUrl(org),
        'https://dev.azure.com/puremedia/DevOps%20Mobile%20App/_git/'
        'DevOps%20Mobile%20App/pullrequest/8401',
      );
    });
  });
}
