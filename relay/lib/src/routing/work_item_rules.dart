import '../hooks/hook_kind.dart';
import '../hooks/routing_view.dart';
import '../verb.dart';
import 'candidate.dart';
import 'routing_state.dart';

/// The fields a work item update touches that are nobody's business: the
/// comment noise set plus the bookkeeping a state change drags along. A change
/// made only of these is not an "edit" worth a notification.
const workItemHousekeepingFields = <String>{
  ...commentNoiseFields,
  'System.Reason',
  'System.BoardColumn',
  'System.BoardColumnDone',
  'System.BoardLane',
  'Microsoft.VSTS.Common.StateChangeDate',
  'Microsoft.VSTS.Common.ActivatedDate',
  'Microsoft.VSTS.Common.ActivatedBy',
  'Microsoft.VSTS.Common.ResolvedDate',
  'Microsoft.VSTS.Common.ResolvedBy',
  'Microsoft.VSTS.Common.ClosedDate',
  'Microsoft.VSTS.Common.ClosedBy',
};

/// research/14 §5.2 rule 3 as rewritten by the R2.1 finding: a `workitem.updated`
/// whose changed fields are all in the comment-noise set **and include
/// `System.History`** is the work item comment event. The paired
/// `workitem.commented` names nobody by id and is dropped.
bool isWorkItemComment(RoutingView view) =>
    view.kind == HookKind.wiUpdated &&
    view.changedFields.contains('System.History') &&
    view.changedFields.every(commentNoiseFields.contains);

/// A bare revision bump — the noise set without `System.History` — which is
/// what a `workitem.updated` looks like when nothing a person did changed.
bool isWorkItemNoise(RoutingView view) =>
    view.kind == HookKind.wiUpdated &&
    view.changedFields.isNotEmpty &&
    !view.changedFields.contains('System.History') &&
    view.changedFields.every(commentNoiseFields.contains);

/// Who caused it. `workitem.created` has no `revisedBy`, so the creator is the
/// actor there.
ResolvedActor workItemActor(RoutingView view, RoutingState state) => switch (view.kind) {
  HookKind.wiCreated => (id: view.actorId ?? view.creatorId, name: view.actorName),
  _ => (id: view.actorId, name: view.actorName),
};

/// research/14 §2.1, every row.
List<Candidate> evaluateWorkItem(RoutingView view, RoutingState state) {
  _rememberProject(view, state);

  // The `workitem.commented` post carries no identity at all (R2.1 finding),
  // so it cannot say who commented and is dropped; its paired `updated` is the
  // comment event below.
  if (view.kind == HookKind.wiCommented) return const [];
  if (view.artifactId == null) return const [];

  if (view.kind == HookKind.wiCreated) return _created(view);
  if (view.kind != HookKind.wiUpdated) return const [];
  if (isWorkItemNoise(view)) return const [];
  if (isWorkItemComment(view)) return _comment(view);
  return _updated(view);
}

void _rememberProject(RoutingView view, RoutingState state) {
  final id = view.projectId;
  final name = view.projectName;
  if (id != null && name != null) state.saveProject(view.org, id, name);
}

/// "created #{id} for you": only when it lands on somebody who is not the one
/// creating it (research/14 §2.1).
List<Candidate> _created(RoutingView view) {
  final assignee = view.assigneeId;
  if (assignee == null) return const [];
  return [candidate(assignee, Verb.created, CandidateReason.assignee)];
}

/// The comment-shaped update. Assignee and creator hear "commented"; anyone
/// named in the History HTML hears "mentioned you" instead, which the engine's
/// priority merge takes care of.
List<Candidate> _comment(RoutingView view) {
  final anchor = view.commentId == null ? null : Anchors.comment(view.commentId!);
  final out = <Candidate>[
    for (final id in view.mentionIds) candidate(id, Verb.mentioned, CandidateReason.mention, anchor: anchor),
    if (view.assigneeId != null) candidate(view.assigneeId!, Verb.commented, CandidateReason.assignee, anchor: anchor),
    if (view.creatorId != null && view.creatorId != view.assigneeId)
      candidate(view.creatorId!, Verb.commented, CandidateReason.creator, anchor: anchor),
  ];
  return out;
}

List<Candidate> _updated(RoutingView view) {
  final out = <Candidate>[];
  final changed = view.changedFields;

  // A comment written through the History field of an ordinary edit: the
  // mention is the only audience (research/14 §2.1).
  if (changed.contains('System.History') && view.mentionIds.isNotEmpty) {
    final anchor = view.commentId == null ? null : Anchors.comment(view.commentId!);
    for (final id in view.mentionIds) {
      out.add(candidate(id, Verb.mentioned, CandidateReason.mention, anchor: anchor));
    }
  }

  if (changed.contains('System.AssignedTo')) {
    if (view.assigneeId != null) out.add(candidate(view.assigneeId!, Verb.assigned, CandidateReason.assignee));
    if (view.previousAssigneeId != null && view.previousAssigneeId != view.assigneeId) {
      out.add(candidate(view.previousAssigneeId!, Verb.reassigned, CandidateReason.previousAssignee));
    }
  }

  if (changed.contains('System.State')) {
    final detail = view.newState;
    if (view.assigneeId != null) {
      out.add(candidate(view.assigneeId!, Verb.stateChanged, CandidateReason.assignee, detail: detail));
    }
    if (view.creatorId != null && view.creatorId != view.assigneeId) {
      out.add(candidate(view.creatorId!, Verb.stateChanged, CandidateReason.creator, detail: detail));
    }
  }

  // "any other field, incl. Title, Priority, Iteration, Description, tags,
  // links": nobody in the beta, because `workItems.anyChangeOnMine` is off by
  // default and the engine asks the preferences, not this rule.
  final meaningful = changed.where(
    (field) => !workItemHousekeepingFields.contains(field) && field != 'System.AssignedTo' && field != 'System.State',
  );
  if (meaningful.isNotEmpty && view.assigneeId != null) {
    out.add(candidate(view.assigneeId!, Verb.edited, CandidateReason.assignee));
  }
  return out;
}
