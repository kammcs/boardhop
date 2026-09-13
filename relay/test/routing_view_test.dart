import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/hooks/routing_view.dart';
import 'package:test/test.dart';

import 'hook_fixtures.dart';

RoutingView view(HookKind kind, Map<String, Object?> body, {String subId = 'sub-1', String activityId = 'act-1'}) =>
    RoutingView.parse(
      org: fixtureOrg,
      kind: kind,
      eventType: body['eventType']! as String,
      body: body,
      subId: subId,
      activityId: activityId,
    );

void main() {
  group('HookKind', () {
    test('maps the four filtered pull request update kinds', () {
      expect(HookKind.fromEventTypeAndFilter('git.pullrequest.updated', 'PushNotification'), HookKind.prUpdatedPush);
      expect(
        HookKind.fromEventTypeAndFilter('git.pullrequest.updated', 'ReviewersUpdateNotification'),
        HookKind.prUpdatedReviewers,
      );
      expect(
        HookKind.fromEventTypeAndFilter('git.pullrequest.updated', 'StatusUpdateNotification'),
        HookKind.prUpdatedStatus,
      );
      expect(
        HookKind.fromEventTypeAndFilter('git.pullrequest.updated', 'ReviewerVoteNotification'),
        HookKind.prUpdatedVote,
      );
    });

    test('an unfiltered pull request update subscription is not routable', () {
      expect(HookKind.fromEventTypeAndFilter('git.pullrequest.updated', null), isNull);
      expect(HookKind.fromEventTypeAndFilter('git.pullrequest.updated', ''), isNull);
    });

    test('events with one kind ignore the filter', () {
      expect(HookKind.fromEventTypeAndFilter('workitem.updated', ''), HookKind.wiUpdated);
      expect(HookKind.fromEventTypeAndFilter('workitem.updated', 'somethingElse'), HookKind.wiUpdated);
      expect(HookKind.fromEventTypeAndFilter('build.complete', null), HookKind.buildComplete);
    });

    test('unknown events and labels resolve to null', () {
      expect(HookKind.fromEventTypeAndFilter('git.push', null), isNull);
      expect(HookKind.tryParse('pr.retitled'), isNull);
      expect(HookKind.tryParse(null), isNull);
    });

    test('every label round-trips and is unique', () {
      final labels = HookKind.values.map((k) => k.label).toSet();
      expect(labels.length, HookKind.values.length);
      for (final kind in HookKind.values) {
        expect(HookKind.tryParse(kind.label), kind);
      }
    });
  });

  group('work items', () {
    test('an assignment names both sides and the project', () {
      final parsed = view(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub-1',
          currentAssignedTo: identity(bobId, 'Bob Example'),
          changes: {
            'System.AssignedTo': {
              'newValue': identity(bobId, 'Bob Example'),
              'oldValue': identity(cleoId, 'Cleo Example'),
            },
            'System.ChangedDate': {'newValue': '2026-09-13T15:38:34Z'},
          },
        ),
      );
      expect(parsed.artifactId, '15545');
      expect(parsed.projectId, projectGuid);
      expect(parsed.projectName, 'Contoso Demo');
      expect(parsed.actorId, adaId);
      expect(parsed.actorName, 'Ada Example');
      expect(parsed.assigneeId, bobId);
      expect(parsed.previousAssigneeId, cleoId);
      expect(parsed.creatorId, cleoId);
      expect(parsed.changedFields, {'System.AssignedTo', 'System.ChangedDate'});
      expect(parsed.isCommentNoise, isFalse);
    });

    test('a state change carries the new state only', () {
      final parsed = view(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub-1',
          state: 'Resolved',
          changes: {
            'System.State': {'newValue': 'Resolved', 'oldValue': 'Active'},
            'System.Rev': {'newValue': 12, 'oldValue': 11},
          },
        ),
      );
      expect(parsed.newState, 'Resolved');
      expect(parsed.isCommentNoise, isFalse);
    });

    test('the comment noise field set is classified as noise', () {
      final parsed = view(HookKind.wiUpdated, workItemCommentNoise(subId: 'sub-1'));
      expect(parsed.changedFields, {
        'System.AuthorizedDate',
        'System.ChangedDate',
        'System.CommentCount',
        'System.History',
        'System.Rev',
        'System.RevisedDate',
        'System.Watermark',
      });
      expect(parsed.changedFields.every(commentNoiseFields.contains), isTrue);
      expect(parsed.isCommentNoise, isTrue);
      // The comment anchor survives even on the noise event.
      expect(parsed.commentId, '4');
    });

    test('a title edit alongside noise fields is not noise', () {
      final parsed = view(
        HookKind.wiUpdated,
        workItemUpdated(
          subId: 'sub-1',
          changes: {
            'System.Title': {'newValue': 'New title', 'oldValue': 'Old title'},
            'System.ChangedDate': {'newValue': '2026-09-13T15:38:34Z'},
            'System.Rev': {'newValue': 12, 'oldValue': 11},
          },
        ),
      );
      expect(parsed.isCommentNoise, isFalse);
    });

    test('mentions come out of History as GUIDs and the text stays behind', () {
      final mentions = '${htmlMention(bobId, 'Bob Example')} and ${htmlMention(cleoId, 'Cleo Example')}';
      final history = 'Hello $mentions — $canary';
      final parsed = view(HookKind.wiUpdated, workItemCommentNoise(subId: 'sub-1', history: history));
      expect(parsed.mentionIds, [bobId, cleoId]);
      expect(parsed.toLogFields()['mentions'], 2);
      expect(parsed.toLogFields().values.join(' '), isNot(contains(canary)));
    });

    test('workitem.commented reads the flat fields and the comment id', () {
      final parsed = view(
        HookKind.wiCommented,
        workItemCommented(subId: 'sub-1', commentId: 9, text: 'See ${htmlMention(adaId, 'Ada Example')}'),
      );
      expect(parsed.artifactId, '15545');
      expect(parsed.commentId, '9');
      expect(parsed.projectName, 'Contoso Demo');
      expect(parsed.mentionIds, [adaId]);
      // v1.0 carries no identity ref for the commenter; a "Name <mail>" string
      // is not an id, so nothing is invented.
      expect(parsed.actorId, isNull);
      expect(parsed.actorName, isNull);
    });

    test('workitem.created reads the assignee out of the flat fields', () {
      final parsed = view(HookKind.wiCreated, workItemCreated(subId: 'sub-1'));
      expect(parsed.artifactId, '15546');
      expect(parsed.assigneeId, bobId);
      expect(parsed.newState, 'New');
    });
  });

  group('pull requests', () {
    test('created names the author, the reviewers and the project', () {
      final parsed = view(
        HookKind.prCreated,
        pullRequestCreated(
          subId: 'sub-1',
          reviewers: [
            {'id': bobId, 'vote': 0, 'displayName': 'Bob Example'},
            {'id': groupId, 'vote': 0, 'displayName': 'Contoso Approvers', 'isContainer': true},
          ],
        ),
      );
      expect(parsed.artifactId, '8348');
      expect(parsed.prAuthorId, adaId);
      expect(parsed.actorId, adaId);
      expect(parsed.projectId, projectGuid);
      expect(parsed.projectName, 'Contoso Demo');
      expect(parsed.isDraft, isFalse);
      expect(parsed.prStatus, 'active');
      expect(parsed.reviewers.map((r) => r.id), [bobId, groupId]);
      expect(parsed.reviewers.last.isContainer, isTrue);
      expect(parsed.reviewers.first.isContainer, isFalse);
    });

    test('a vote update carries the votes but does not claim an actor', () {
      final parsed = view(
        HookKind.prUpdatedVote,
        pullRequestUpdated(
          subId: 'sub-1',
          reviewers: [
            {'id': bobId, 'vote': 10, 'displayName': 'Bob Example'},
          ],
        ),
      );
      expect(parsed.reviewers.single.vote, 10);
      expect(parsed.prAuthorId, adaId);
      // The body's one identity is the PR author, not whoever voted.
      expect(parsed.actorId, isNull);
    });

    test('a push update carries the source commit', () {
      final parsed = view(HookKind.prUpdatedPush, pullRequestUpdated(subId: 'sub-1', sourceCommit: 'abc123abc123'));
      expect(parsed.sourceCommitId, 'abc123abc123');
    });

    test('a status update carries status and draft', () {
      final parsed = view(HookKind.prUpdatedStatus, pullRequestUpdated(subId: 'sub-1', status: 'abandoned'));
      expect(parsed.prStatus, 'abandoned');
      expect(parsed.isDraft, isFalse);
    });

    test('merged carries the merge status', () {
      final parsed = view(HookKind.prMerged, pullRequestMerged(subId: 'sub-1', mergeStatus: 'conflicts'));
      expect(parsed.mergeStatus, 'conflicts');
      expect(parsed.artifactId, '8348');
    });

    test('a comment gives the thread id from the href, the mention and the parent', () {
      final parsed = view(HookKind.prComment, pullRequestComment(subId: 'sub-1', threadId: 4821, commentId: 7));
      expect(parsed.threadId, '4821');
      expect(parsed.commentId, '7');
      expect(parsed.parentCommentId, '3');
      expect(parsed.actorId, bobId);
      expect(parsed.actorName, 'Bob Example');
      expect(parsed.mentionIds, [cleoId]);
      expect(parsed.isSystemComment, isFalse);
      expect(parsed.prAuthorId, adaId);
      expect(parsed.title, isNotNull);
    });

    test('a system comment is flagged so the rules can drop it', () {
      final parsed = view(
        HookKind.prComment,
        pullRequestComment(subId: 'sub-1', commentType: 'system', content: 'Bob Example voted 10'),
      );
      expect(parsed.isSystemComment, isTrue);
    });

    test('the thread id falls back to the self href', () {
      final body = pullRequestComment(subId: 'sub-1', threadId: 999);
      final resource = body['resource']! as Map<String, Object?>;
      final comment = resource['comment']! as Map<String, Object?>;
      (comment['_links']! as Map<String, Object?>).remove('threads');
      expect(view(HookKind.prComment, body).threadId, '999');
    });
  });

  group('builds and pipeline state', () {
    test('build.complete carries the result, the requester and the title', () {
      final parsed = view(HookKind.buildComplete, buildComplete(subId: 'sub-1', result: 'failed'));
      expect(parsed.artifactId, '20163');
      expect(parsed.buildResult, 'failed');
      expect(parsed.buildReason, 'manual');
      expect(parsed.sourceBranch, 'refs/heads/main');
      expect(parsed.definitionId, '139');
      expect(parsed.requestedForId, bobId);
      expect(parsed.requestedById, adaId);
      expect(parsed.actorId, adaId);
      expect(parsed.title, 'contoso-scratch · 20260913.1');
      expect(parsed.projectName, 'Contoso Demo');
    });

    test('run-state-changed is the only event with the requester as an identity', () {
      final parsed = view(HookKind.runState, runStateChanged(subId: 'sub-1'));
      expect(parsed.runId, '20163');
      expect(parsed.requestedForId, bobId);
      expect(parsed.requestedById, adaId);
      expect(parsed.newState, 'completed');
      expect(parsed.buildResult, 'succeeded');
      expect(parsed.definitionId, '139');
      expect(parsed.projectId, projectGuid);
    });

    test('stage-state-changed names the stage and no identity', () {
      final parsed = view(HookKind.stageState, stageStateChanged(subId: 'sub-1', state: 'running'));
      expect(parsed.stageName, 'Deploy');
      expect(parsed.newState, 'running');
      expect(parsed.runId, '20163');
      expect(parsed.actorId, isNull);
      expect(parsed.requestedForId, isNull);
    });
  });

  group('approvals', () {
    test('pending lists user approvers, skips groups and finds the project', () {
      final parsed = view(HookKind.approvalPending, approvalEvent(subId: 'sub-1', withGroupApprover: true));
      expect(parsed.artifactId, '44444444-eeee-4eee-8eee-444444444444');
      expect(parsed.runId, '20163');
      expect(parsed.approvalStatus, 'pending');
      expect(parsed.approverIds, [adaId]);
      expect(parsed.actualApproverId, isNull);
      expect(parsed.stageName, 'Deploy');
      expect(parsed.environmentName, 'Production');
      expect(parsed.title, 'contoso-scratch → Deploy');
      // resourceContainers has no project on the pipelines publisher.
      expect(parsed.projectId, projectGuid);
    });

    test('run.requestedFor is a string, so requestedForId stays null', () {
      final pending = view(HookKind.approvalPending, approvalEvent(subId: 'sub-1'));
      expect(pending.requestedForId, isNull);
      final completed = view(HookKind.approvalCompleted, approvalEvent(subId: 'sub-1', completed: true));
      expect(completed.requestedForId, isNull);
    });

    test('completed names the actual approver as the actor', () {
      final parsed = view(
        HookKind.approvalCompleted,
        approvalEvent(subId: 'sub-1', completed: true, status: 'approved'),
      );
      expect(parsed.approvalStatus, 'approved');
      expect(parsed.actualApproverId, adaId);
      expect(parsed.actorId, adaId);
    });
  });

  group('the view is a projection, not a copy', () {
    test('toLogFields returns ids, the kind and counts only', () {
      final parsed = view(HookKind.prComment, pullRequestComment(subId: 'sub-9', commentId: 7));
      final fields = parsed.toLogFields();
      expect(fields['kind'], 'pr.comment');
      expect(fields['org'], fixtureOrg);
      expect(fields['artifactId'], '8348');
      expect(fields['threadId'], '4821');
      expect(fields.containsKey('title'), isFalse);
      expect(fields.containsKey('actorName'), isFalse);
      expect(fields.containsKey('projectName'), isFalse);
      expect(fields.values.map((v) => '$v').join(' '), isNot(contains(canary)));
    });

    test('a body it does not understand yields nulls rather than throwing', () {
      final parsed = RoutingView.parse(
        org: fixtureOrg,
        kind: HookKind.wiUpdated,
        eventType: 'workitem.updated',
        body: const {'resource': 'not a map', 'resourceContainers': 7},
      );
      expect(parsed.artifactId, isNull);
      expect(parsed.changedFields, isEmpty);
      expect(parsed.isCommentNoise, isFalse);
    });
  });
}
