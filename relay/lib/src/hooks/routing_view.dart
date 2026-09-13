import 'hook_kind.dart';

/// One reviewer as the rules see them: an identity id, the vote as delivered
/// and whether the "reviewer" is really a group (`isContainer`), which the beta
/// cannot expand (research/14 D9).
class ReviewerRef {
  const ReviewerRef({this.id, this.vote, this.isContainer = false});

  final String? id;
  final int? vote;
  final bool isContainer;

  @override
  String toString() => 'ReviewerRef($id, vote: $vote, container: $isContainer)';
}

/// The system fields a work item **comment** touches. A `workitem.updated`
/// whose changed fields are a subset of these is comment noise: the matching
/// `workitem.commented` is the event that notifies (research/14 §5.2 rule 3,
/// field list verified in w24).
const commentNoiseFields = <String>{
  'System.History',
  'System.CommentCount',
  'System.Rev',
  'System.ChangedDate',
  'System.ChangedBy',
  'System.AuthorizedDate',
  'System.RevisedDate',
  'System.Watermark',
  'System.AuthorizedAs',
  'System.PersonId',
};

const _guid = r'[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}';

/// A mention in work item History or in a work item comment.
final _htmlMention = RegExp('data-vss-mention=["\']version:2\\.0,($_guid)');

/// A mention in a pull request comment.
final _angleMention = RegExp('@<($_guid)>');

/// The thread id lives only in a comment link (`.../threads/{id}/comments/{id}`).
final _threadInHref = RegExp(r'/threads/(\d+)');

/// A typed, immutable projection of the roughly twenty fields the R2.2 rules
/// read out of a service-hook body. Everything else — comment text, field
/// values, descriptions, diffs, avatars — is discarded at parse time.
///
/// The view keeps **no reference to the raw body**, so there is nothing for a
/// later phase to serialise by accident: [toLogFields] is the only way out and
/// it returns ids, the kind and counts.
class RoutingView {
  const RoutingView({
    required this.org,
    required this.kind,
    required this.eventType,
    this.subId,
    this.activityId,
    this.projectId,
    this.projectName,
    this.artifactId,
    this.runId,
    this.title,
    this.actorId,
    this.actorName,
    this.assigneeId,
    this.previousAssigneeId,
    this.creatorId,
    this.newState,
    this.changedFields = const <String>{},
    this.mentionIds = const <String>[],
    this.commentId,
    this.parentCommentId,
    this.threadId,
    this.isSystemComment = false,
    this.prAuthorId,
    this.reviewers = const <ReviewerRef>[],
    this.prStatus,
    this.isDraft,
    this.sourceCommitId,
    this.mergeStatus,
    this.buildResult,
    this.buildReason,
    this.sourceBranch,
    this.definitionId,
    this.requestedForId,
    this.requestedById,
    this.approvalStatus,
    this.approverIds = const <String>[],
    this.actualApproverId,
    this.stageName,
    this.environmentName,
  });

  /// Reads the routing fields out of [body] for [kind]. Never throws on a shape
  /// it does not recognise: every field it cannot find stays null.
  factory RoutingView.parse({
    required String org,
    required HookKind kind,
    required String eventType,
    required Map<String, Object?> body,
    String? subId,
    String? activityId,
  }) {
    final resource = _map(body['resource']) ?? const <String, Object?>{};
    final containers = _map(body['resourceContainers']);
    final containerProjectId = _str(_at(containers, ['project', 'id']));

    if (kind.isWorkItem) {
      return _parseWorkItem(
        org: org,
        kind: kind,
        eventType: eventType,
        subId: subId,
        activityId: activityId,
        resource: resource,
        containerProjectId: containerProjectId,
      );
    }
    if (kind.isPullRequest) {
      return _parsePullRequest(
        org: org,
        kind: kind,
        eventType: eventType,
        subId: subId,
        activityId: activityId,
        resource: resource,
        containerProjectId: containerProjectId,
      );
    }
    if (kind.isBuild) {
      return _parseBuild(
        org: org,
        kind: kind,
        eventType: eventType,
        subId: subId,
        activityId: activityId,
        resource: resource,
        containerProjectId: containerProjectId,
      );
    }
    if (kind.isApproval) {
      return _parseApproval(
        org: org,
        kind: kind,
        eventType: eventType,
        subId: subId,
        activityId: activityId,
        resource: resource,
        containerProjectId: containerProjectId,
      );
    }
    return _parsePipelineState(
      org: org,
      kind: kind,
      eventType: eventType,
      subId: subId,
      activityId: activityId,
      resource: resource,
      containerProjectId: containerProjectId,
    );
  }

  // ------------------------------------------------------------------ fields

  final String org;
  final HookKind kind;
  final String eventType;
  final String? subId;
  final String? activityId;

  final String? projectId;
  final String? projectName;

  /// Work item id, pull request id, build id or approval id, by kind.
  final String? artifactId;
  final String? runId;

  /// The artifact's own title, which research/06 counts as metadata. Never a
  /// comment, a description or a field value.
  final String? title;

  final String? actorId;
  final String? actorName;

  final String? assigneeId;
  final String? previousAssigneeId;
  final String? creatorId;
  final String? newState;

  /// The **keys** of `resource.fields`; no value is kept.
  final Set<String> changedFields;

  /// Identity GUIDs pulled out of mention markup. The text is discarded.
  final List<String> mentionIds;

  final String? commentId;
  final String? parentCommentId;
  final String? threadId;
  final bool isSystemComment;

  final String? prAuthorId;
  final List<ReviewerRef> reviewers;
  final String? prStatus;
  final bool? isDraft;
  final String? sourceCommitId;
  final String? mergeStatus;

  final String? buildResult;
  final String? buildReason;
  final String? sourceBranch;
  final String? definitionId;
  final String? requestedForId;
  final String? requestedById;

  final String? approvalStatus;

  /// User approvers only: a step whose `assignedApprover` is a group is skipped.
  final List<String> approverIds;
  final String? actualApproverId;
  final String? stageName;
  final String? environmentName;

  // ------------------------------------------------------------- classifiers

  /// research/14 §5.2 rule 3: a work item comment fires `workitem.commented`
  /// **and** `workitem.updated`; the update is dropped as noise.
  bool get isCommentNoise =>
      kind == HookKind.wiUpdated && changedFields.isNotEmpty && changedFields.every(commentNoiseFields.contains);

  /// The only thing that ever leaves this object for a log line: ids, the kind
  /// and counts. No title, no name, no field value, no comment.
  Map<String, Object?> toLogFields() => {
    'kind': kind.label,
    'org': org,
    'eventType': eventType,
    if (subId != null) 'subId': subId,
    if (activityId != null) 'activityId': activityId,
    if (projectId != null) 'projectId': projectId,
    if (artifactId != null) 'artifactId': artifactId,
    if (runId != null) 'runId': runId,
    if (actorId != null) 'actorId': actorId,
    if (assigneeId != null) 'assigneeId': assigneeId,
    if (commentId != null) 'commentId': commentId,
    if (threadId != null) 'threadId': threadId,
    if (mentionIds.isNotEmpty) 'mentions': mentionIds.length,
    if (reviewers.isNotEmpty) 'reviewers': reviewers.length,
    if (changedFields.isNotEmpty) 'changedFields': changedFields.length,
    if (isCommentNoise) 'commentNoise': true,
    if (isSystemComment) 'systemComment': true,
  };

  @override
  String toString() => 'RoutingView(${kind.label} ${artifactId ?? '-'})';

  // --------------------------------------------------------------- work items

  static RoutingView _parseWorkItem({
    required String org,
    required HookKind kind,
    required String eventType,
    required String? subId,
    required String? activityId,
    required Map<String, Object?> resource,
    required String? containerProjectId,
  }) {
    final revision = _map(resource['revision']);
    // `workitem.updated` carries a change map in `resource.fields` and the new
    // revision's flat fields in `resource.revision.fields`; `created` and
    // `commented` carry the flat fields in `resource.fields` directly.
    final changes = kind == HookKind.wiUpdated ? _map(resource['fields']) : null;
    final current = _map(revision?['fields']) ?? (changes == null ? _map(resource['fields']) : null);

    final assignedChange = _map(changes?['System.AssignedTo']);
    final assigneeId = assignedChange != null
        ? _identityId(assignedChange['newValue'])
        : _identityId(current?['System.AssignedTo']);

    final historyText = <String?>[
      _str(_at(changes, ['System.History', 'newValue'])),
      _str(current?['System.History']),
    ].whereType<String>().join('\n');

    return RoutingView(
      org: org,
      kind: kind,
      eventType: eventType,
      subId: subId,
      activityId: activityId,
      projectId: containerProjectId,
      projectName: _str(current?['System.TeamProject']),
      artifactId: _idOf(resource['workItemId']) ?? _idOf(resource['id']),
      title: _str(current?['System.Title']),
      actorId: _identityId(resource['revisedBy']) ?? _identityId(_at(resource, ['comment', 'author'])),
      actorName: _identityName(resource['revisedBy']) ?? _identityName(_at(resource, ['comment', 'author'])),
      assigneeId: assigneeId,
      previousAssigneeId: assignedChange == null ? null : _identityId(assignedChange['oldValue']),
      creatorId: _identityId(current?['System.CreatedBy']),
      newState: kind == HookKind.wiUpdated
          ? _str(_at(changes, ['System.State', 'newValue']))
          : _str(current?['System.State']),
      changedFields: _keysOf(resource['fields']),
      mentionIds: _mentionsIn(historyText),
      commentId:
          _idOf(_at(resource, ['commentVersionRef', 'commentId'])) ??
          _idOf(_at(revision, ['commentVersionRef', 'commentId'])),
    );
  }

  // ------------------------------------------------------------ pull requests

  static RoutingView _parsePullRequest({
    required String org,
    required HookKind kind,
    required String eventType,
    required String? subId,
    required String? activityId,
    required Map<String, Object?> resource,
    required String? containerProjectId,
  }) {
    // The comment event (v2) nests the whole PR; every other PR event *is* the PR.
    final pr = kind == HookKind.prComment ? (_map(resource['pullRequest']) ?? const <String, Object?>{}) : resource;
    final comment = kind == HookKind.prComment ? _map(resource['comment']) : null;
    final project = _map(_at(pr, ['repository', 'project']));

    final links = _map(comment?['_links']);
    final threadHref = _str(_at(links, ['threads', 'href'])) ?? _str(_at(links, ['self', 'href']));

    // Only `git.pullrequest.created` names its actor: on an `updated` or
    // `merged` body the single identity is the PR's author, not whoever caused
    // the event (research/14 §5.2; those actors are derived in R2.2).
    final actor = switch (kind) {
      HookKind.prComment => _map(comment?['author']),
      HookKind.prCreated => _map(pr['createdBy']),
      _ => null,
    };

    return RoutingView(
      org: org,
      kind: kind,
      eventType: eventType,
      subId: subId,
      activityId: activityId,
      projectId: _str(project?['id']) ?? containerProjectId,
      projectName: _str(project?['name']),
      artifactId: _idOf(pr['pullRequestId']),
      title: _str(pr['title']),
      actorId: _identityId(actor),
      actorName: _identityName(actor),
      mentionIds: _mentionsIn(_str(comment?['content'])),
      commentId: _idOf(comment?['id']),
      parentCommentId: _idOf(comment?['parentCommentId']),
      threadId: threadHref == null ? null : _threadInHref.firstMatch(threadHref)?.group(1),
      isSystemComment: _str(comment?['commentType'])?.toLowerCase() == 'system',
      prAuthorId: _identityId(pr['createdBy']),
      reviewers: _reviewersOf(pr['reviewers']),
      prStatus: _str(pr['status']),
      isDraft: pr['isDraft'] is bool ? pr['isDraft']! as bool : null,
      sourceCommitId: _str(_at(pr, ['lastMergeSourceCommit', 'commitId'])),
      mergeStatus: _str(pr['mergeStatus']),
    );
  }

  // ------------------------------------------------------------------ builds

  static RoutingView _parseBuild({
    required String org,
    required HookKind kind,
    required String eventType,
    required String? subId,
    required String? activityId,
    required Map<String, Object?> resource,
    required String? containerProjectId,
  }) {
    final definition = _map(resource['definition']);
    final project = _map(resource['project']) ?? _map(definition?['project']);
    final requestedBy = _map(resource['requestedBy']);

    return RoutingView(
      org: org,
      kind: kind,
      eventType: eventType,
      subId: subId,
      activityId: activityId,
      projectId: _str(project?['id']) ?? containerProjectId,
      projectName: _str(project?['name']),
      artifactId: _idOf(resource['id']),
      title: _join(_str(definition?['name']), _str(resource['buildNumber']), ' · '),
      actorId: _identityId(requestedBy),
      actorName: _identityName(requestedBy),
      buildResult: _str(resource['result']),
      buildReason: _str(resource['reason']),
      sourceBranch: _str(resource['sourceBranch']),
      definitionId: _idOf(definition?['id']),
      requestedForId: _identityId(resource['requestedFor']),
      requestedById: _identityId(requestedBy),
    );
  }

  // --------------------------------------------------------------- approvals

  static RoutingView _parseApproval({
    required String org,
    required HookKind kind,
    required String eventType,
    required String? subId,
    required String? activityId,
    required Map<String, Object?> resource,
    required String? containerProjectId,
  }) {
    final approval = _map(resource['approval']);
    final steps = _list(resource['steps']).isNotEmpty ? _list(resource['steps']) : _list(approval?['steps']);
    final pipeline = _map(resource['pipeline']) ?? _map(approval?['pipeline']);
    final run = _map(resource['run']);

    final approverIds = <String>[];
    String? actualApproverId;
    Map<String, Object?>? actualApprover;
    for (final entry in steps) {
      final step = _map(entry);
      if (step == null) continue;
      final assigned = _map(step['assignedApprover']);
      // A group approver cannot be expanded without an identity of the relay's
      // own (research/14 D9); it is skipped and the gap is disclosed.
      if (assigned != null && assigned['isContainer'] != true) {
        final id = _str(assigned['id']);
        if (id != null && !approverIds.contains(id)) approverIds.add(id);
      }
      final actual = _map(step['actualApprover']);
      if (actual != null && actualApproverId == null) {
        actualApproverId = _str(actual['id']);
        actualApprover = actual;
      }
    }

    return RoutingView(
      org: org,
      kind: kind,
      eventType: eventType,
      subId: subId,
      activityId: activityId,
      // The pipelines publisher sends no `resourceContainers.project` (w25).
      projectId: _str(resource['projectId']) ?? containerProjectId,
      artifactId: _idOf(resource['approvalId']) ?? _idOf(approval?['id']),
      runId: _idOf(resource['runId']) ?? _idOf(run?['id']) ?? _idOf(_at(approval, ['pipeline', 'owner', 'id'])),
      title: _join(_str(pipeline?['name']), _str(resource['stageName']), ' → '),
      actorId: actualApproverId,
      actorName: _identityName(actualApprover),
      approvalStatus: _str(approval?['status']),
      approverIds: approverIds,
      actualApproverId: actualApproverId,
      stageName: _str(resource['stageName']) ?? _str(_at(resource, ['stage', 'name'])),
      environmentName: _str(_at(resource, ['resource', 'name'])),
      definitionId: _idOf(pipeline?['id']),
      // `run.requestedFor` is a display-name **string** here, never an identity
      // ref, so the requester id stays null and comes from `run_state` in R2.2.
      requestedForId: _identityId(run?['requestedFor']),
    );
  }

  // -------------------------------------------------------- run/stage state

  static RoutingView _parsePipelineState({
    required String org,
    required HookKind kind,
    required String eventType,
    required String? subId,
    required String? activityId,
    required Map<String, Object?> resource,
    required String? containerProjectId,
  }) {
    final run = _map(resource['run']);
    final pipeline = _map(resource['pipeline']);
    final stage = _map(resource['stage']);
    final requestedBy = _map(resource['requestedBy']);

    return RoutingView(
      org: org,
      kind: kind,
      eventType: eventType,
      subId: subId,
      activityId: activityId,
      projectId: _str(resource['projectId']) ?? containerProjectId,
      artifactId: _idOf(resource['runId']) ?? _idOf(run?['id']),
      runId: _idOf(resource['runId']) ?? _idOf(run?['id']),
      actorId: _identityId(requestedBy),
      actorName: _identityName(requestedBy),
      newState: _str(stage?['state']) ?? _str(run?['state']),
      buildResult: _str(stage?['result']) ?? _str(run?['result']),
      definitionId: _idOf(pipeline?['id']),
      requestedForId: _identityId(resource['requestedFor']),
      requestedById: _identityId(requestedBy),
      stageName: _str(resource['stageName']) ?? _str(stage?['name']),
    );
  }
}

// -------------------------------------------------------------------- helpers

Map<String, Object?>? _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return null;
}

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const <Object?>[];

Object? _at(Map<String, Object?>? from, List<String> path) {
  Object? cursor = from;
  for (final segment in path) {
    final map = _map(cursor);
    if (map == null) return null;
    cursor = map[segment];
  }
  return cursor;
}

String? _str(Object? value) => value is String && value.isNotEmpty ? value : null;

/// Ids arrive as `int` (work item, build, run, comment) or `String` (approval,
/// pipeline); both become a string, and nothing else does.
String? _idOf(Object? value) {
  if (value is int) return '$value';
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// An identity ref's GUID. Work item identity fields are an object under
/// `resourceDetailsToSend: all` but a plain `"Name <mail>"` string in some
/// revisions (w24); a string carries no id, so it yields null rather than a name.
String? _identityId(Object? value) => _str(_map(value)?['id']);

String? _identityName(Object? value) => _str(_map(value)?['displayName']);

Set<String> _keysOf(Object? value) {
  final map = _map(value);
  if (map == null) return const <String>{};
  return map.keys.toSet();
}

List<ReviewerRef> _reviewersOf(Object? value) => [
  for (final entry in _list(value))
    if (_map(entry) case final reviewer?)
      ReviewerRef(
        id: _str(reviewer['id']),
        vote: reviewer['vote'] is int ? reviewer['vote']! as int : null,
        isContainer: reviewer['isContainer'] == true,
      ),
];

/// Every mention GUID in [text], in order and without repeats. The text itself
/// is never returned, stored or logged.
List<String> _mentionsIn(String? text) {
  if (text == null || text.isEmpty) return const <String>[];
  final found = <String>[];
  for (final pattern in [_htmlMention, _angleMention]) {
    for (final match in pattern.allMatches(text)) {
      final id = match.group(1)?.toLowerCase();
      if (id != null && !found.contains(id)) found.add(id);
    }
  }
  return found;
}

String? _join(String? a, String? b, String separator) {
  if (a == null) return b;
  if (b == null) return a;
  return '$a$separator$b';
}
