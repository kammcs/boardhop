import '../db.dart';
import '../hooks/hook_kind.dart';
import '../hooks/routing_view.dart';
import '../verb.dart';
import 'candidate.dart';
import 'routing_state.dart';

/// A build's actor is `requestedBy` — and research/14 §5.2 rule 1 makes builds
/// the exception to "never the actor": you want to hear that your own push
/// failed. The engine keeps the actor for [HookKind.buildComplete].
ResolvedActor buildActor(RoutingView view, RoutingState state) => (id: view.actorId, name: view.actorName);

/// research/14 §2.3 and decision D3: failures always, a success only when it
/// is a **fix** (the last known result for this definition and branch was a
/// failure) or when the person has asked for all successes.
List<Candidate> evaluateBuild(RoutingView view, RoutingState state) {
  final projectId = view.projectId;
  final projectName = view.projectName;
  if (projectId != null && projectName != null) state.saveProject(view.org, projectId, projectName);

  final result = view.buildResult;
  var verb = Verb.forBuildResult(result);
  final prior = _priorResult(view, state);
  _remember(view, state);

  if (verb == null) return const [];
  if (verb == Verb.buildSucceeded && (prior?.wasFailure ?? false)) verb = Verb.buildFixed;

  final requestedFor = view.requestedForId;
  final requestedBy = view.requestedById;
  final detail = _detail(result);

  // A success (or a fix) is the requester's business alone; a failure is also
  // the business of whoever queued it, when that is somebody else.
  final out = <Candidate>[
    if (requestedFor != null) candidate(requestedFor, verb, CandidateReason.requester, detail: detail),
    if (!verb.isSuccessLike && requestedBy != null && requestedBy != requestedFor)
      candidate(requestedBy, verb, CandidateReason.requester, detail: detail),
  ];
  // A scheduled or CI build requested for a build service account has nobody
  // to notify; such an identity never registers a device, so the device lookup
  // in R2.3 drops it (research/14 §5.2 rule 7) without a name check here.
  return out;
}

/// The closed `buildResultDetails` spelling of a result, whatever case the
/// payload used.
String? _detail(String? result) {
  for (final known in buildResultDetails) {
    if (known.toLowerCase() == result?.toLowerCase()) return known;
  }
  return null;
}

BuildStateRow? _priorResult(RoutingView view, RoutingState state) {
  final projectId = view.projectId;
  final definitionId = view.definitionId;
  final branch = view.sourceBranch;
  if (projectId == null || definitionId == null || branch == null) return null;
  return state.build(view.org, projectId, definitionId, branch);
}

void _remember(RoutingView view, RoutingState state) {
  final projectId = view.projectId;
  final definitionId = view.definitionId;
  final branch = view.sourceBranch;
  if (projectId == null || definitionId == null || branch == null) return;
  state.saveBuild(
    BuildStateRow(
      org: view.org,
      projectId: projectId,
      definitionId: definitionId,
      branch: branch,
      lastResult: view.buildResult,
      buildId: view.artifactId,
    ),
  );
}

extension on Verb {
  bool get isSuccessLike => this == Verb.buildSucceeded || this == Verb.buildFixed;
}
