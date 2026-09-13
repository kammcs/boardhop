/// Synthetic service-hook payloads, shaped like the key trees in
/// `research/spikes/results/w24_r2_capture_shapes.md` but written here from
/// scratch: a fictional organization, invented GUIDs and invented names. No
/// captured payload, id, name or address is copied into this file — the
/// captures hold client data even from the scratch project.
library;

import 'package:boardhop_relay/src/hooks/hook_kind.dart';
import 'package:boardhop_relay/src/hooks/routing_view.dart';

/// The canary every content-bearing field carries, so a redaction test can
/// prove no body ever reaches a log line or the database.
const canary = 'SECRET-BODY-CANARY';

const fixtureOrg = 'contoso';

const adaId = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa';
const bobId = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
const cleoId = 'cccccccc-3333-4333-8333-cccccccccccc';
const groupId = 'dddddddd-4444-4444-8444-dddddddddddd';
const projectGuid = 'eeeeeeee-5555-4555-8555-eeeeeeeeeeee';
const repoGuid = 'ffffffff-6666-4666-8666-ffffffffffff';

/// The display name that goes with a fixture id, so a parameterised author or
/// approver still carries the name the redaction tests look for.
String nameFor(String id) => switch (id) {
  adaId => 'Ada Example',
  bobId => 'Bob Example',
  cleoId => 'Cleo Example',
  groupId => 'Contoso Approvers',
  _ => 'Dana Example',
};

/// An identity ref the way every payload spells one.
Map<String, Object?> identity(String id, String name) => {
  '_links': {
    'avatar': {'href': 'https://example.invalid/avatar/$id'},
  },
  'descriptor': 'aad.$id',
  'displayName': name,
  'id': id,
  'imageUrl': 'https://example.invalid/image/$id',
  'uniqueName': '${name.toLowerCase().replaceAll(' ', '.')}@example.invalid',
  'url': 'https://example.invalid/identities/$id',
};

Map<String, Object?> _containers({bool withProject = true}) => {
  'account': {'baseUrl': 'https://example.invalid/', 'id': '00000000-0000-4000-8000-000000000001'},
  'collection': {'baseUrl': 'https://example.invalid/', 'id': '00000000-0000-4000-8000-000000000002'},
  if (withProject) 'project': {'baseUrl': 'https://example.invalid/', 'id': projectGuid},
};

Map<String, Object?> _envelope({
  required String eventType,
  required String subId,
  required String resourceVersion,
  required Map<String, Object?> resource,
  bool withProjectContainer = true,
  String? eventId,
}) => {
  'id': eventId ?? '11111111-aaaa-4aaa-8aaa-111111111111',
  'eventType': eventType,
  'publisherId': eventType.startsWith('ms.vss-pipeline') ? 'pipelines' : 'tfs',
  'scope': 'all',
  'message': {'text': 'A thing happened to $canary', 'html': 'A thing happened to $canary'},
  'detailedMessage': {'text': 'Long form, with $canary in it'},
  'resource': resource,
  'resourceVersion': resourceVersion,
  'resourceContainers': _containers(withProject: withProjectContainer),
  'createdDate': '2026-09-13T15:36:17.4Z',
  'subscriptionId': subId,
};

// ----------------------------------------------------------------- work items

Map<String, Object?> _workItemFields({
  String state = 'Active',
  String? history,
  Object? assignedTo,
  String creatorId = cleoId,
}) => {
  'Microsoft.VSTS.Common.Priority': 2,
  'Microsoft.VSTS.Common.StateChangeDate': '2026-09-13T15:38:00Z',
  'System.AreaPath': 'Contoso Demo',
  'System.ChangedBy': 'Ada Example <ada.example@example.invalid>',
  'System.ChangedDate': '2026-09-13T15:38:34Z',
  'System.CommentCount': 3,
  'System.CreatedBy': identity(creatorId, nameFor(creatorId)),
  'System.CreatedDate': '2026-09-10T09:00:00Z',
  if (assignedTo != null) 'System.AssignedTo': assignedTo,
  if (history != null) 'System.History': history,
  'System.IterationPath': 'Contoso Demo\\Sprint 1',
  'System.Reason': 'New',
  'System.State': state,
  'System.TeamProject': 'Contoso Demo',
  'System.Title': 'Fix the thing — $canary',
  'System.WorkItemType': 'User Story',
};

/// `workitem.updated` v1.0. [changes] is the `resource.fields` change map.
Map<String, Object?> workItemUpdated({
  required String subId,
  required Map<String, Object?> changes,
  int workItemId = 15545,
  String state = 'Active',
  String? currentHistory,
  Object? currentAssignedTo,
  int? commentId,
  String actorId = adaId,
  String creatorId = cleoId,
  String? eventId,
}) => _envelope(
  eventType: 'workitem.updated',
  subId: subId,
  resourceVersion: '1.0',
  eventId: eventId,
  resource: {
    '_links': {
      'self': {'href': 'https://example.invalid/wit/workItems/$workItemId'},
    },
    'fields': changes,
    'id': 987654,
    'rev': 12,
    'revisedBy': identity(actorId, nameFor(actorId)),
    'revisedDate': '2026-09-13T15:38:34Z',
    'revision': {
      if (commentId != null)
        'commentVersionRef': {'commentId': commentId, 'url': 'https://example.invalid/c', 'version': 1},
      'fields': _workItemFields(
        state: state,
        history: currentHistory,
        assignedTo: currentAssignedTo,
        creatorId: creatorId,
      ),
      'id': workItemId,
      'multilineFieldsFormat': <String, Object?>{if (currentHistory != null) 'System.History': 'html'},
      'rev': 12,
      'url': 'https://example.invalid/wit/workItems/$workItemId/revisions/12',
    },
    'url': 'https://example.invalid/wit/updates/987654',
    'workItemId': workItemId,
  },
);

/// The `workitem.updated` a **comment** produces: exactly the noise field set
/// verified in w24.
Map<String, Object?> workItemCommentNoise({
  required String subId,
  int workItemId = 15545,
  String? history,
  String actorId = adaId,
  String creatorId = cleoId,
  Object? currentAssignedTo,
}) => workItemUpdated(
  subId: subId,
  workItemId: workItemId,
  commentId: 4,
  actorId: actorId,
  creatorId: creatorId,
  currentAssignedTo: currentAssignedTo,
  currentHistory: history ?? 'A comment with $canary',
  changes: {
    'System.AuthorizedDate': {'newValue': '2026-09-13T15:38:34Z', 'oldValue': '2026-09-13T15:37:00Z'},
    'System.ChangedDate': {'newValue': '2026-09-13T15:38:34Z', 'oldValue': '2026-09-13T15:37:00Z'},
    'System.CommentCount': {'newValue': 3, 'oldValue': 2},
    'System.History': {'newValue': history ?? 'A comment with $canary'},
    'System.Rev': {'newValue': 12, 'oldValue': 11},
    'System.RevisedDate': {'newValue': '9999-01-01T00:00:00Z', 'oldValue': '2026-09-13T15:38:34Z'},
    'System.Watermark': {'newValue': 77, 'oldValue': 76},
  },
);

/// `workitem.commented` v1.0: flat current fields, no `revision`, no identity.
Map<String, Object?> workItemCommented({
  required String subId,
  int workItemId = 15545,
  int commentId = 7,
  String? text,
  String? eventId,
}) => _envelope(
  eventType: 'workitem.commented',
  subId: subId,
  resourceVersion: '1.0',
  eventId: eventId,
  resource: {
    '_links': {
      'self': {'href': 'https://example.invalid/wit/workItems/$workItemId'},
    },
    'commentVersionRef': {'commentId': commentId, 'url': 'https://example.invalid/c', 'version': 1},
    'fields': _workItemFields(history: text ?? 'Please look at this, $canary'),
    'id': workItemId,
    'multilineFieldsFormat': {'System.History': 'html'},
    'rev': 13,
    'url': 'https://example.invalid/wit/workItems/$workItemId',
  },
);

Map<String, Object?> workItemCreated({
  required String subId,
  int workItemId = 15546,
  Object? assignedTo,
  String creatorId = cleoId,
}) => _envelope(
  eventType: 'workitem.created',
  subId: subId,
  resourceVersion: '1.0',
  resource: {
    'fields': _workItemFields(
      state: 'New',
      assignedTo: assignedTo ?? identity(bobId, 'Bob Example'),
      creatorId: creatorId,
    ),
    'id': workItemId,
    'rev': 1,
    'url': 'https://example.invalid/wit/workItems/$workItemId',
  },
);

// -------------------------------------------------------------- pull requests

Map<String, Object?> _pullRequest({
  int pullRequestId = 8348,
  String status = 'active',
  bool isDraft = false,
  String mergeStatus = 'succeeded',
  String sourceCommit = '0123456789abcdef0123456789abcdef01234567',
  String authorId = adaId,
  List<Map<String, Object?>>? reviewers,
}) => {
  'artifactId': 'vstfs:///Git/PullRequestId/$projectGuid%2f$repoGuid%2f$pullRequestId',
  'codeReviewId': 4321,
  'createdBy': identity(authorId, nameFor(authorId)),
  'creationDate': '2026-09-13T15:36:09Z',
  'description': 'Why this change: $canary',
  'isDraft': isDraft,
  'lastMergeSourceCommit': {'commitId': sourceCommit, 'url': 'https://example.invalid/commits/$sourceCommit'},
  'lastMergeTargetCommit': {'commitId': 'fedcba9876543210fedcba9876543210fedcba98', 'url': 'https://example.invalid/c'},
  'mergeId': '22222222-cccc-4ccc-8ccc-222222222222',
  'mergeStatus': mergeStatus,
  'pullRequestId': pullRequestId,
  'repository': {
    'id': repoGuid,
    'isDisabled': false,
    'name': 'contoso-demo',
    'project': {
      'id': projectGuid,
      'name': 'Contoso Demo',
      'revision': 11,
      'state': 'wellFormed',
      'url': 'https://example.invalid/projects/$projectGuid',
      'visibility': 'private',
    },
    'url': 'https://example.invalid/repos/$repoGuid',
  },
  'reviewers':
      reviewers ??
      [
        {'displayName': 'Bob Example', 'hasDeclined': false, 'id': bobId, 'isFlagged': false, 'vote': 0},
      ],
  'sourceRefName': 'refs/heads/spike/demo',
  'status': status,
  'supportsIterations': true,
  'targetRefName': 'refs/heads/main',
  'title': 'Tidy the thing — $canary',
  'url': 'https://example.invalid/pullRequests/$pullRequestId',
};

Map<String, Object?> pullRequestCreated({
  required String subId,
  int pullRequestId = 8348,
  bool isDraft = false,
  String authorId = adaId,
  List<Map<String, Object?>>? reviewers,
}) => _envelope(
  eventType: 'git.pullrequest.created',
  subId: subId,
  resourceVersion: '1.0',
  resource: _pullRequest(pullRequestId: pullRequestId, isDraft: isDraft, authorId: authorId, reviewers: reviewers),
);

Map<String, Object?> pullRequestUpdated({
  required String subId,
  int pullRequestId = 8348,
  String status = 'active',
  bool isDraft = false,
  String sourceCommit = '0123456789abcdef0123456789abcdef01234567',
  String authorId = adaId,
  List<Map<String, Object?>>? reviewers,
}) => _envelope(
  eventType: 'git.pullrequest.updated',
  subId: subId,
  resourceVersion: '1.0',
  resource: _pullRequest(
    pullRequestId: pullRequestId,
    status: status,
    isDraft: isDraft,
    sourceCommit: sourceCommit,
    authorId: authorId,
    reviewers: reviewers,
  ),
);

Map<String, Object?> pullRequestMerged({
  required String subId,
  String mergeStatus = 'conflicts',
  String authorId = adaId,
}) => _envelope(
  eventType: 'git.pullrequest.merged',
  subId: subId,
  resourceVersion: '1.0',
  resource: _pullRequest(mergeStatus: mergeStatus, authorId: authorId),
);

/// `ms.vss-code.git-pullrequest-comment-event` v2.0: the comment plus the whole
/// PR, and the thread id only inside the comment's links.
Map<String, Object?> pullRequestComment({
  required String subId,
  int pullRequestId = 8348,
  int commentId = 7,
  int parentCommentId = 3,
  int threadId = 4821,
  String commentType = 'text',
  String authorId = bobId,
  String prAuthorId = adaId,
  List<Map<String, Object?>>? reviewers,
  String? content,
  String? eventId,
}) => _envelope(
  eventType: 'ms.vss-code.git-pullrequest-comment-event',
  subId: subId,
  resourceVersion: '2.0',
  eventId: eventId,
  resource: {
    'comment': {
      '_links': {
        'self': {'href': 'https://example.invalid/pullRequests/$pullRequestId/threads/$threadId/comments/$commentId'},
        'threads': {'href': 'https://example.invalid/pullRequests/$pullRequestId/threads/$threadId'},
      },
      'author': identity(authorId, nameFor(authorId)),
      'commentType': commentType,
      'content': content ?? 'Nice one @<$cleoId> — $canary',
      'id': commentId,
      'lastUpdatedDate': '2026-09-13T15:36:33Z',
      'parentCommentId': parentCommentId,
      'publishedDate': '2026-09-13T15:36:33Z',
      'usersLiked': <Object?>[],
    },
    'pullRequest': _pullRequest(pullRequestId: pullRequestId, authorId: prAuthorId, reviewers: reviewers),
  },
);

// ------------------------------------------------------------------- pipeline

Map<String, Object?> buildComplete({
  required String subId,
  int buildId = 20163,
  String result = 'failed',
  String reason = 'manual',
  String requestedForId = bobId,
  String requestedById = adaId,
  String sourceBranch = 'refs/heads/main',
  int definitionId = 139,
}) => _envelope(
  eventType: 'build.complete',
  subId: subId,
  resourceVersion: '2.0',
  resource: {
    'buildNumber': '20260913.1',
    'definition': {
      'id': definitionId,
      'name': 'contoso-scratch',
      'path': '\\',
      'project': {'id': projectGuid, 'name': 'Contoso Demo'},
      'type': 'build',
    },
    'finishTime': '2026-09-13T15:51:30Z',
    'id': buildId,
    'lastChangedBy': identity(adaId, 'Ada Example'),
    'project': {'id': projectGuid, 'name': 'Contoso Demo'},
    'queueTime': '2026-09-13T15:37:00Z',
    'reason': reason,
    'repository': {'id': repoGuid, 'name': 'contoso-demo', 'type': 'TfsGit'},
    'requestedBy': identity(requestedById, nameFor(requestedById)),
    'requestedFor': identity(requestedForId, nameFor(requestedForId)),
    'result': result,
    'sourceBranch': sourceBranch,
    'sourceVersion': '0123456789abcdef0123456789abcdef01234567',
    'status': 'completed',
    'tags': <Object?>[],
    'templateParameters': {'note': canary},
    'triggerInfo': <String, Object?>{},
    'uri': 'vstfs:///Build/Build/$buildId',
  },
);

Map<String, Object?> runStateChanged({
  required String subId,
  int runId = 20163,
  String state = 'completed',
  String result = 'succeeded',
  String requestedForId = bobId,
  String requestedById = adaId,
}) => _envelope(
  eventType: 'ms.vss-pipelines.run-state-changed-event',
  subId: subId,
  resourceVersion: '5.1-preview.1',
  resource: {
    'pipeline': {'folder': '\\', 'id': 139, 'name': 'contoso-scratch', 'revision': 3},
    'projectId': projectGuid,
    'requestedBy': identity(requestedById, nameFor(requestedById)),
    'requestedFor': identity(requestedForId, nameFor(requestedForId)),
    'run': {
      'createdDate': '2026-09-13T15:37:00Z',
      'id': runId,
      'name': '20260913.1',
      'result': result,
      'state': state,
      'templateParameters': {'note': canary},
    },
    'runId': runId,
    'stages': <Object?>[],
  },
);

Map<String, Object?> stageStateChanged({
  required String subId,
  int runId = 20163,
  String stageName = 'Deploy',
  String state = 'running',
}) => _envelope(
  eventType: 'ms.vss-pipelines.stage-state-changed-event',
  subId: subId,
  resourceVersion: '5.1-preview.1',
  resource: {
    'pipeline': {'folder': '\\', 'id': 139, 'name': 'contoso-scratch', 'revision': 3},
    'projectId': projectGuid,
    'run': {'createdDate': '2026-09-13T15:37:00Z', 'id': runId, 'name': '20260913.1', 'state': 'inProgress'},
    'runId': runId,
    'stage': {
      'attempt': 1,
      'displayName': stageName,
      'id': '33333333-dddd-4ddd-8ddd-333333333333',
      'name': stageName,
      'state': state,
    },
    'stageName': stageName,
  },
);

/// `approval-pending` / `approval-completed`. Note the two facts from w25 that
/// the routing view depends on: `run.requestedFor` is a display-name **string**
/// (null once completed), and the pipelines publisher sends no
/// `resourceContainers.project`.
Map<String, Object?> approvalEvent({
  required String subId,
  bool completed = false,
  String approvalId = '44444444-eeee-4eee-8eee-444444444444',
  String status = 'pending',
  int runId = 20163,
  String stageName = 'Deploy',
  bool withGroupApprover = false,
  List<String> approverIds = const [adaId],
  String? actualApproverId,
}) => _envelope(
  eventType: completed
      ? 'ms.vss-pipelinechecks-events.approval-completed'
      : 'ms.vss-pipelinechecks-events.approval-pending',
  subId: subId,
  resourceVersion: '5.1-preview.1',
  withProjectContainer: false,
  resource: {
    'approval': {
      'blockedApprovers': <Object?>[],
      'createdOn': '2026-09-13T15:38:56Z',
      'executionOrder': 'anyOrder',
      'id': approvalId,
      'instructions': 'Check the thing before approving — $canary',
      'lastModifiedOn': '2026-09-13T15:51:13Z',
      if (completed) 'minRequiredApprovers': 1,
      'pipeline': {
        'id': '139',
        'name': 'contoso-scratch',
        'owner': {'id': runId, 'name': '20260913.1'},
      },
      'status': status,
      'steps': [
        for (final (index, approverId) in approverIds.indexed)
          {
            if (completed && (actualApproverId ?? approverIds.first) == approverId)
              'actualApprover': identity(approverId, nameFor(approverId)),
            'assignedApprover': identity(approverId, nameFor(approverId)),
            'history': <Object?>[],
            'initiatedOn': '2026-09-13T15:38:56Z',
            'lastModifiedBy': identity(approverId, nameFor(approverId)),
            'order': index + 1,
            'status': status,
          },
        if (withGroupApprover)
          {
            'assignedApprover': {...identity(groupId, 'Contoso Approvers'), 'isContainer': true},
            'history': <Object?>[],
            'order': approverIds.length + 1,
            'status': status,
          },
      ],
    },
    'approvalId': approvalId,
    'attemptId': 1,
    'pipeline': {'id': '139', 'name': 'contoso-scratch'},
    'projectId': projectGuid,
    'resource': {'id': '7', 'name': 'Production', 'resourceType': 'environment'},
    'run': {
      'id': '$runId',
      'name': '20260913.1',
      'queuedOn': completed ? null : '2026-09-13T15:37:00Z',
      // A display name, never an identity ref (w25).
      'requestedFor': completed ? null : 'Bob Example',
      'runReason': completed ? null : 'Manual',
    },
    'runId': runId,
    'stage': {'id': '33333333-dddd-4ddd-8ddd-333333333333', 'name': stageName},
    'stageName': stageName,
  },
);

/// A mention the way a work item's History spells one.
String htmlMention(String id, String name) => '<a href="#" data-vss-mention="version:2.0,$id">@$name</a>';

/// A PR reviewer entry, with the vote the payload spells as an int.
Map<String, Object?> reviewer(String id, {int vote = 0, bool isContainer = false}) => {
  'displayName': nameFor(id),
  'hasDeclined': false,
  'id': id,
  'isContainer': isContainer,
  'isFlagged': false,
  'vote': vote,
};

/// The routing projection of a fixture body, the way the ingest builds it.
RoutingView viewOf(
  HookKind kind,
  Map<String, Object?> body, {
  String org = fixtureOrg,
  String? subId,
  String? activityId,
}) => RoutingView.parse(
  org: org,
  kind: kind,
  eventType: kind.eventType,
  body: body,
  subId: subId ?? 'sub-${kind.label}',
  activityId: activityId ?? 'activity-${kind.label}',
);
