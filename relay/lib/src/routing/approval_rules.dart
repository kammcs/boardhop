import '../db.dart';
import '../hooks/hook_kind.dart';
import '../hooks/routing_view.dart';
import '../verb.dart';
import 'candidate.dart';
import 'routing_state.dart';

/// `approval-pending` has no actor: the pipeline reached a checkpoint, nobody
/// did anything. `approval-completed` names the person who decided in
/// `steps[].actualApprover` (verified, w25).
ResolvedActor approvalActor(RoutingView view, RoutingState state) => switch (view.kind) {
  HookKind.approvalCompleted => (id: view.actualApproverId, name: view.actorName),
  _ => noActor,
};

/// research/14 §2.4. The run's requester is not in the approval payload as an
/// identity — only as a display name — so it comes from `run_state`, which
/// `run-state-changed` filled at queue time.
List<Candidate> evaluateApproval(RoutingView view, RoutingState state) {
  final approvalId = view.artifactId;
  if (approvalId == null) return const [];
  final runId = view.runId;
  final requester = runId == null ? null : state.run(view.org, runId)?.requestedForId;
  final approvers = view.approverIds;

  if (view.kind == HookKind.approvalPending) {
    final anchor = Anchors.approval(approvalId);
    final detail = view.stageName ?? view.environmentName;
    return [
      for (final id in approvers)
        // Approving your own run is common on a small team, so the requester is
        // skipped only when somebody else can approve instead.
        if (id != requester || approvers.length == 1)
          candidate(id, Verb.approvalPending, CandidateReason.approver, detail: detail, anchor: anchor),
    ];
  }

  // Completed: the other approvers and the person whose run it is. The actor is
  // dropped by the engine, as everywhere outside builds.
  final detail = _status(view.approvalStatus);
  return [
    for (final id in approvers) candidate(id, Verb.approvalCompleted, CandidateReason.approver, detail: detail),
    if (requester != null && !approvers.contains(requester))
      candidate(requester, Verb.approvalCompleted, CandidateReason.requester, detail: detail),
  ];
}

/// `run-state-changed` notifies nobody. It exists for one thing: it is the only
/// event that gives a run's requester as an identity (research/14 §1.4).
List<Candidate> evaluatePipelineState(RoutingView view, RoutingState state) {
  final projectId = view.projectId;
  final projectName = view.projectName;
  if (projectId != null && projectName != null) state.saveProject(view.org, projectId, projectName);

  final runId = view.runId;
  if (view.kind == HookKind.runState && runId != null) {
    state.saveRun(
      RunStateRow(
        org: view.org,
        runId: runId,
        pipelineId: view.definitionId,
        requestedForId: view.requestedForId,
        requestedById: view.requestedById,
      ),
    );
  }
  return const [];
}

/// The closed `approvalDetails` spelling of a status.
String? _status(String? raw) {
  for (final known in approvalDetails) {
    if (known.toLowerCase() == raw?.toLowerCase()) return known;
  }
  return null;
}
