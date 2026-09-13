import '../db.dart';
import '../hooks/hook_kind.dart';
import '../hooks/routing_view.dart';
import 'candidate.dart';
import 'routing_state.dart';
import 'verb.dart';

/// Who caused a pull request event.
///
/// Only two of the seven PR kinds name their actor: `created` (`createdBy`)
/// and the comment event (`comment.author`). A vote names nobody, so the actor
/// is the reviewer whose vote moved against `pr_state`; a reviewer list change
/// and a status change name nobody at all, and the w24 key tree confirms there
/// is no `closedBy` on an abandoned or completed PR.
///
/// Read-only: it runs **before** [evaluatePullRequest] writes the new state.
ResolvedActor pullRequestActor(RoutingView view, RoutingState state) {
  switch (view.kind) {
    case HookKind.prCreated:
    case HookKind.prComment:
      return (id: view.actorId, name: view.actorName);
    case HookKind.prUpdatedVote:
      final prId = view.artifactId;
      final voter = prId == null ? null : changedVoter(view, state.pullRequest(view.org, prId));
      return (id: voter?.id, name: voter?.name);
    default:
      return noActor;
  }
}

/// The reviewer whose vote this `ReviewerVote` delivery is about: the one
/// whose non-zero vote differs from what the relay last recorded. With no
/// prior state, a single non-zero vote is unambiguous and anything else is not.
ReviewerRef? changedVoter(RoutingView view, PrStateRow? prior) {
  final voted = [
    for (final reviewer in view.reviewers)
      if (reviewer.id != null && !reviewer.isContainer && (reviewer.vote ?? 0) != 0) reviewer,
  ];
  if (voted.isEmpty) return null;
  if (prior == null) return voted.length == 1 ? voted.single : null;
  final moved = [
    for (final reviewer in voted)
      if ((prior.reviewers[reviewer.id] ?? 0) != reviewer.vote) reviewer,
  ];
  return moved.length == 1 ? moved.single : null;
}

/// research/14 §2.2, every row. Reads `pr_state` and `pr_thread_state` as they
/// were before this event, then writes them forward.
List<Candidate> evaluatePullRequest(RoutingView view, RoutingState state) {
  final projectId = view.projectId;
  final projectName = view.projectName;
  if (projectId != null && projectName != null) state.saveProject(view.org, projectId, projectName);

  final prId = view.artifactId;
  if (prId == null) return const [];
  final prior = state.pullRequest(view.org, prId);

  final out = switch (view.kind) {
    HookKind.prCreated => _created(view),
    HookKind.prUpdatedReviewers => _reviewersUpdated(view, prior),
    HookKind.prUpdatedVote => _voted(view, prior),
    HookKind.prUpdatedStatus => _statusUpdated(view, prior),
    HookKind.prUpdatedPush => _pushed(view, prior),
    HookKind.prComment => _commented(view, state, prId),
    HookKind.prMerged => _merged(view),
    _ => const <Candidate>[],
  };

  _remember(view, state, prId, prior);
  return out;
}

/// Reviewers who are people (a group cannot be expanded in the beta, D9) and
/// are not the author.
List<ReviewerRef> _people(RoutingView view) => [
  for (final reviewer in view.reviewers)
    if (reviewer.id != null && !reviewer.isContainer && reviewer.id != view.prAuthorId) reviewer,
];

List<Candidate> _created(RoutingView view) {
  // A draft tells nobody; its reviewers hear when it leaves draft.
  if (view.isDraft == true) return const [];
  return [for (final reviewer in _people(view)) candidate(reviewer.id!, Verb.reviewRequested)];
}

/// The payload lists the reviewers as they are at delivery time, so "added" is
/// a diff against `pr_state`. On first sight there is nothing to diff against
/// and every current reviewer counts as added.
List<Candidate> _reviewersUpdated(RoutingView view, PrStateRow? prior) => [
  for (final reviewer in _people(view))
    if (prior == null || !prior.reviewers.containsKey(reviewer.id)) candidate(reviewer.id!, Verb.reviewRequested),
];

/// A vote that is not a reset goes to the author; the label comes from the
/// `vote` value. When the relay cannot tell which reviewer moved, the author
/// still hears about it, without an actor and without a label.
List<Candidate> _voted(RoutingView view, PrStateRow? prior) {
  final author = view.prAuthorId;
  if (author == null) return const [];
  if (!_people(view).any((reviewer) => (reviewer.vote ?? 0) != 0)) return const [];
  final voter = changedVoter(view, prior);
  return [candidate(author, Verb.voted, detail: Verb.voteLabel(voter?.vote))];
}

List<Candidate> _statusUpdated(RoutingView view, PrStateRow? prior) {
  // draft → published: the reviewers are being asked for the first time.
  if (prior?.isDraft == true && view.isDraft == false) {
    return [for (final reviewer in _people(view)) candidate(reviewer.id!, Verb.reviewRequested)];
  }
  final author = view.prAuthorId;
  if (author == null) return const [];
  return switch (view.prStatus?.toLowerCase()) {
    'completed' => [candidate(author, Verb.prCompleted)],
    'abandoned' => [candidate(author, Verb.prAbandoned)],
    _ => const <Candidate>[],
  };
}

/// A new iteration stales every vote already cast, so the people who voted are
/// the ones who need to look again. With no prior state there is no "changed"
/// to detect, and the relay stays quiet rather than guessing.
List<Candidate> _pushed(RoutingView view, PrStateRow? prior) {
  if (prior == null) return const [];
  if (view.sourceCommitId == null || view.sourceCommitId == prior.sourceCommit) return const [];
  return [
    for (final reviewer in _people(view))
      if ((reviewer.vote ?? 0) != 0 || (prior.reviewers[reviewer.id] ?? 0) != 0)
        candidate(reviewer.id!, Verb.pushed, anchor: Anchors.files),
  ];
}

/// research/14 D4: the author, the other people already in the thread, the
/// reviewers who have voted, and anyone named in the comment.
List<Candidate> _commented(RoutingView view, RoutingState state, String prId) {
  // A vote or a PR update posts a system comment; the ReviewerVote and status
  // subscriptions cover those (research/14 §5.2 rule 3).
  if (view.isSystemComment) return const [];

  final threadId = view.threadId;
  final anchor = threadId == null ? null : Anchors.thread(threadId);
  final verb = (int.tryParse(view.parentCommentId ?? '0') ?? 0) > 0 ? Verb.replied : Verb.commented;
  final participants = threadId == null
      ? const <String>[]
      : state.thread(view.org, prId, threadId)?.participantIds ?? const <String>[];

  final out = <Candidate>[
    for (final id in view.mentionIds) candidate(id, Verb.mentioned, anchor: anchor),
    if (view.prAuthorId != null) candidate(view.prAuthorId!, verb, anchor: anchor),
    for (final id in participants) candidate(id, verb, anchor: anchor),
    for (final reviewer in _people(view))
      if ((reviewer.vote ?? 0) != 0) candidate(reviewer.id!, verb, anchor: anchor),
  ];

  // This comment's author is a participant of the thread from now on.
  final authorId = view.actorId;
  if (threadId != null && authorId != null) {
    state.addThreadParticipant(org: view.org, prId: prId, threadId: threadId, userId: authorId);
  }
  return out;
}

/// Subscribed with `mergeResult` = `Unsuccessful`, but the filter is the
/// subscription's business and the rule checks the body as well.
List<Candidate> _merged(RoutingView view) {
  final author = view.prAuthorId;
  final status = view.mergeStatus;
  if (author == null || status == null || status.toLowerCase() == 'succeeded') return const [];
  return [candidate(author, Verb.mergeFailed, detail: status)];
}

void _remember(RoutingView view, RoutingState state, String prId, PrStateRow? prior) {
  state.savePullRequest(
    PrStateRow(
      org: view.org,
      prId: prId,
      status: view.prStatus ?? prior?.status,
      isDraft: view.isDraft ?? prior?.isDraft,
      sourceCommit: view.sourceCommitId ?? prior?.sourceCommit,
      reviewers: {
        for (final reviewer in view.reviewers)
          if (reviewer.id != null && !reviewer.isContainer) reviewer.id!: reviewer.vote ?? 0,
      },
      authorId: view.prAuthorId ?? prior?.authorId,
    ),
  );
}
