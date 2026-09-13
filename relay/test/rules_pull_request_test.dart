import 'package:boardhop_relay/src/db.dart';
import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/routing/candidate.dart';
import 'package:boardhop_relay/src/routing/pull_request_rules.dart';
import 'package:boardhop_relay/src/routing/routing_state.dart';
import 'package:boardhop_relay/src/verb.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';

/// research/14 §2.2, one test per row. Ada is the PR author in every fixture.
void main() {
  late MemoryRoutingState state;

  setUp(() => state = MemoryRoutingState());

  List<Candidate> evaluate(HookKind kind, Map<String, Object?> body) => evaluatePullRequest(viewOf(kind, body), state);

  const otherCommit = 'aaaaaaaabbbbbbbbccccccccddddddddeeeeeeee';

  group('git.pullrequest.created', () {
    test('a published PR asks every reviewer who is a person', () {
      final candidates = evaluate(
        HookKind.prCreated,
        pullRequestCreated(
          subId: 'sub',
          reviewers: [reviewer(bobId), reviewer(cleoId), reviewer(groupId, isContainer: true)],
        ),
      );
      expect(candidates.map((c) => (c.userId, c.verb)), [
        (bobId, Verb.reviewRequested),
        (cleoId, Verb.reviewRequested),
      ]);
    });

    test('a draft asks nobody', () {
      expect(evaluate(HookKind.prCreated, pullRequestCreated(subId: 'sub', isDraft: true)), isEmpty);
    });

    test('it records the PR so the next event has something to diff against', () {
      evaluate(HookKind.prCreated, pullRequestCreated(subId: 'sub', reviewers: [reviewer(bobId, vote: 10)]));
      final row = state.pullRequest(fixtureOrg, '8348')!;
      expect(row.authorId, adaId);
      expect(row.reviewers, {bobId: 10});
      expect(row.isDraft, isFalse);
      expect(row.status, 'active');
    });
  });

  group('updated / ReviewersUpdate', () {
    test('only the reviewers added since the last state are asked', () {
      state.savePullRequest(const PrStateRow(org: fixtureOrg, prId: '8348', authorId: adaId, reviewers: {bobId: 0}));
      final candidates = evaluate(
        HookKind.prUpdatedReviewers,
        pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId), reviewer(cleoId)]),
      );
      expect(candidates.map((c) => c.userId), [cleoId]);
    });

    test('on first sight every current reviewer counts as added', () {
      final candidates = evaluate(
        HookKind.prUpdatedReviewers,
        pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId), reviewer(cleoId)]),
      );
      expect(candidates.map((c) => c.userId), [bobId, cleoId]);
    });

    test('the author is never asked to review their own PR', () {
      final candidates = evaluate(
        HookKind.prUpdatedReviewers,
        pullRequestUpdated(subId: 'sub', reviewers: [reviewer(adaId), reviewer(bobId)]),
      );
      expect(candidates.map((c) => c.userId), [bobId]);
    });
  });

  group('updated / ReviewerVote', () {
    /// research/14 §2.2: 10, 5, −5, −10.
    const labels = {10: 'approved', 5: 'approvedWithSuggestions', -5: 'waitingForAuthor', -10: 'rejected'};

    for (final entry in labels.entries) {
      test('vote ${entry.key} tells the author "${entry.value}"', () {
        state.savePullRequest(const PrStateRow(org: fixtureOrg, prId: '8348', authorId: adaId, reviewers: {bobId: 0}));
        final body = pullRequestUpdated(
          subId: 'sub',
          reviewers: [reviewer(bobId, vote: entry.key)],
        );
        final candidates = evaluate(HookKind.prUpdatedVote, body);
        expect(candidates.map((c) => (c.userId, c.verb, c.detail)), [(adaId, Verb.voted, entry.value)]);
      });
    }

    test('a vote reset (0) tells nobody', () {
      state.savePullRequest(const PrStateRow(org: fixtureOrg, prId: '8348', authorId: adaId, reviewers: {bobId: 10}));
      expect(evaluate(HookKind.prUpdatedVote, pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId)])), isEmpty);
    });

    test('the actor is the reviewer whose vote moved, which the payload never names', () {
      state.savePullRequest(
        const PrStateRow(org: fixtureOrg, prId: '8348', authorId: adaId, reviewers: {bobId: 10, cleoId: 0}),
      );
      final view = viewOf(
        HookKind.prUpdatedVote,
        pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId, vote: 10), reviewer(cleoId, vote: -10)]),
      );
      expect(view.actorId, isNull, reason: 'the vote body carries no actor');
      final actor = pullRequestActor(view, state);
      expect(actor.id, cleoId);
      expect(actor.name, 'Cleo Example');
    });

    test('two votes at once are ambiguous: the author still hears, with no actor and no label', () {
      final candidates = evaluate(
        HookKind.prUpdatedVote,
        pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId, vote: 10), reviewer(cleoId, vote: 5)]),
      );
      expect(candidates.map((c) => (c.userId, c.verb, c.detail)), [(adaId, Verb.voted, null)]);
    });
  });

  group('updated / StatusUpdate', () {
    test('completed and abandoned tell the author', () {
      expect(
        evaluate(
          HookKind.prUpdatedStatus,
          pullRequestUpdated(subId: 'sub', status: 'completed'),
        ).map((c) => (c.userId, c.verb)),
        [(adaId, Verb.prCompleted)],
      );
      state = MemoryRoutingState();
      expect(
        evaluate(
          HookKind.prUpdatedStatus,
          pullRequestUpdated(subId: 'sub', status: 'abandoned'),
        ).map((c) => (c.userId, c.verb)),
        [(adaId, Verb.prAbandoned)],
      );
    });

    test('a draft that is published asks its reviewers', () {
      state.savePullRequest(
        const PrStateRow(org: fixtureOrg, prId: '8348', authorId: adaId, isDraft: true, reviewers: {bobId: 0}),
      );
      final candidates = evaluate(
        HookKind.prUpdatedStatus,
        pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId), reviewer(cleoId)]),
      );
      expect(candidates.map((c) => (c.userId, c.verb)), [
        (bobId, Verb.reviewRequested),
        (cleoId, Verb.reviewRequested),
      ]);
      expect(state.pullRequest(fixtureOrg, '8348')!.isDraft, isFalse);
    });

    test('an active PR that was never a draft tells nobody', () {
      expect(evaluate(HookKind.prUpdatedStatus, pullRequestUpdated(subId: 'sub')), isEmpty);
    });
  });

  group('updated / Push', () {
    test('only the reviewers who have already voted are told, on the Files tab', () {
      state.savePullRequest(
        const PrStateRow(
          org: fixtureOrg,
          prId: '8348',
          authorId: adaId,
          sourceCommit: 'old-commit',
          reviewers: {bobId: 10, cleoId: 0},
        ),
      );
      final candidates = evaluate(
        HookKind.prUpdatedPush,
        pullRequestUpdated(
          subId: 'sub',
          sourceCommit: otherCommit,
          reviewers: [reviewer(bobId, vote: 10), reviewer(cleoId)],
        ),
      );
      expect(candidates.map((c) => (c.userId, c.verb, c.anchor)), [(bobId, Verb.pushed, 'tab:files')]);
    });

    test('a reviewer whose vote the push has just reset still counts as having voted', () {
      state.savePullRequest(
        const PrStateRow(
          org: fixtureOrg,
          prId: '8348',
          authorId: adaId,
          sourceCommit: 'old-commit',
          reviewers: {bobId: 10},
        ),
      );
      final candidates = evaluate(
        HookKind.prUpdatedPush,
        pullRequestUpdated(subId: 'sub', sourceCommit: otherCommit, reviewers: [reviewer(bobId)]),
      );
      expect(candidates.map((c) => c.userId), [bobId]);
    });

    test('the same source commit is not a push', () {
      state.savePullRequest(
        const PrStateRow(org: fixtureOrg, prId: '8348', sourceCommit: otherCommit, reviewers: {bobId: 10}),
      );
      expect(
        evaluate(
          HookKind.prUpdatedPush,
          pullRequestUpdated(subId: 'sub', sourceCommit: otherCommit, reviewers: [reviewer(bobId, vote: 10)]),
        ),
        isEmpty,
      );
    });

    test('with no prior state the relay stays quiet rather than guessing', () {
      expect(
        evaluate(HookKind.prUpdatedPush, pullRequestUpdated(subId: 'sub', reviewers: [reviewer(bobId, vote: 10)])),
        isEmpty,
      );
    });
  });

  group('the PR comment event', () {
    test('the author, the voted reviewers and the mentioned person are selected', () {
      final candidates = evaluate(
        HookKind.prComment,
        pullRequestComment(subId: 'sub', parentCommentId: 0, reviewers: [reviewer(bobId, vote: 10), reviewer(cleoId)]),
      );
      expect(candidates.map((c) => (c.userId, c.verb)), [
        // The fixture's comment mentions Cleo.
        (cleoId, Verb.mentioned),
        (adaId, Verb.commented),
        (bobId, Verb.commented),
      ]);
      expect(candidates.every((c) => c.anchor == 'thread:4821'), isTrue);
    });

    test('parentCommentId > 0 makes it a reply', () {
      final candidates = evaluate(HookKind.prComment, pullRequestComment(subId: 'sub'));
      expect(candidates.where((c) => c.verb != Verb.mentioned).map((c) => c.verb), everyElement(Verb.replied));
    });

    test('a system comment is dropped: the vote and status subscriptions cover it', () {
      expect(evaluate(HookKind.prComment, pullRequestComment(subId: 'sub', commentType: 'system')), isEmpty);
    });

    test('thread participants accumulate across two comments', () {
      evaluate(HookKind.prComment, pullRequestComment(subId: 'sub', authorId: bobId));
      expect(state.thread(fixtureOrg, '8348', '4821')!.participantIds, [bobId]);

      final second = evaluate(HookKind.prComment, pullRequestComment(subId: 'sub', authorId: cleoId));
      // Bob is now in the thread, so the second comment reaches him.
      expect(second.map((c) => c.userId), contains(bobId));
      expect(state.thread(fixtureOrg, '8348', '4821')!.participantIds, [bobId, cleoId]);
    });

    test('a participant is recorded once, however often they comment', () {
      evaluate(HookKind.prComment, pullRequestComment(subId: 'sub', authorId: bobId));
      evaluate(HookKind.prComment, pullRequestComment(subId: 'sub', authorId: bobId));
      expect(state.thread(fixtureOrg, '8348', '4821')!.participantIds, [bobId]);
    });
  });

  group('git.pullrequest.merged', () {
    for (final status in ['conflicts', 'failure', 'rejectedByPolicy']) {
      test('$status tells the author the merge failed', () {
        final candidates = evaluate(HookKind.prMerged, pullRequestMerged(subId: 'sub', mergeStatus: status));
        expect(candidates.map((c) => (c.userId, c.verb, c.detail)), [(adaId, Verb.mergeFailed, status)]);
      });
    }

    test('a successful merge tells nobody, even if the filter lets it through', () {
      expect(evaluate(HookKind.prMerged, pullRequestMerged(subId: 'sub', mergeStatus: 'succeeded')), isEmpty);
    });
  });

  test('a group reviewer is never a recipient and never reaches pr_state', () {
    evaluate(
      HookKind.prCreated,
      pullRequestCreated(subId: 'sub', reviewers: [reviewer(bobId), reviewer(groupId, isContainer: true)]),
    );
    expect(state.pullRequest(fixtureOrg, '8348')!.reviewers.keys, [bobId]);
  });
}
