/// The verb vocabulary a pushed pointer carries, and the English words the app
/// puts around it (research/14 §3.2 and §3.1).
///
/// The relay never sends words: it sends the enum **name** in the pointer's
/// `verb` field, and the app turns it into a phrase. That is why this table
/// lives in exactly one place — the day Boardhop is localised, this file is the
/// only thing that gains an `.arb` — and why the names here have to match
/// `relay/lib/src/verb.dart` exactly.
///
/// The phrases are the same English the relay puts in `fallbackBody`, so a
/// notification reads identically whether the app built the line or the relay
/// did.
library;

/// What the actor did. The closed list of research/14 §3.2; anything else in a
/// pointer is dropped rather than shown.
enum PushVerb {
  mentioned,
  assigned,
  reviewRequested,
  reassigned,
  created,
  mergeFailed,
  buildFailed,
  buildPartial,
  buildCanceled,
  buildFixed,
  buildSucceeded,
  voted,
  stateChanged,
  approvalPending,
  approvalCompleted,
  prCompleted,
  prAbandoned,
  prPublished,
  commented,
  replied,
  edited,
  pushed,
  test;

  /// The verb with this name, or null. A pointer whose `verb` is not one of
  /// these simply has none, and the fallback body is used instead.
  static PushVerb? tryParse(String? name) {
    if (name == null || name.isEmpty) return null;
    for (final verb in PushVerb.values) {
      if (verb.name == name) return verb;
    }
    return null;
  }

  /// True for the two approval verbs; quiet hours let them through by default
  /// (research/14 §6) and the app shows them with the approval icon.
  bool get isApproval =>
      this == PushVerb.approvalPending || this == PushVerb.approvalCompleted;

  bool get isBuild => const {
    PushVerb.buildFailed,
    PushVerb.buildPartial,
    PushVerb.buildCanceled,
    PushVerb.buildFixed,
    PushVerb.buildSucceeded,
  }.contains(this);
}

/// `{actor} {phrase}` — "Ada Example assigned you", "Ada Example replied on
/// !8348" — or the phrase alone when the pointer named no actor (a service
/// identity, or one of the events whose body names nobody).
///
/// [artifactRef] is `#15545` / `!8348`, empty for builds and approvals, which
/// name themselves in the title. [detail] is the verb's own closed-vocabulary
/// metadata: a state name, a vote label, a build result.
String pushVerbPhrase(
  PushVerb verb, {
  String? actor,
  String? detail,
  String? artifactRef,
}) {
  final ref = (artifactRef == null || artifactRef.isEmpty) ? null : artifactRef;
  final withActor = actor != null && actor.isNotEmpty;
  final phrase = withActor
      ? _actorPhrase(verb, detail: detail, ref: ref)
      : _standalonePhrase(verb, detail: detail, ref: ref);
  return withActor ? '$actor $phrase' : phrase;
}

String _actorPhrase(PushVerb verb, {String? detail, String? ref}) {
  final on = ref == null ? '' : ' $ref';
  return switch (verb) {
    PushVerb.mentioned => 'mentioned you',
    PushVerb.assigned => 'assigned you',
    PushVerb.reassigned => 'reassigned$on',
    PushVerb.created => 'created$on for you',
    PushVerb.stateChanged =>
      detail == null ? 'changed the state$on' : 'moved$on to $detail',
    PushVerb.edited => 'edited$on',
    PushVerb.commented => 'commented on${on.isEmpty ? ' it' : on}',
    PushVerb.replied => 'replied on${on.isEmpty ? ' it' : on}',
    PushVerb.reviewRequested => 'asked you to review$on',
    PushVerb.voted => _votePhrase(detail, on),
    PushVerb.prCompleted => 'completed$on',
    PushVerb.prAbandoned => 'abandoned$on',
    PushVerb.prPublished => 'published$on',
    PushVerb.pushed => 'pushed new changes to$on',
    PushVerb.mergeFailed =>
      detail == null ? 'could not merge$on' : 'could not merge$on ($detail)',
    PushVerb.buildFailed ||
    PushVerb.buildPartial ||
    PushVerb.buildCanceled ||
    PushVerb.buildFixed ||
    PushVerb.buildSucceeded => 'queued a build that ${_buildOutcome(verb)}',
    PushVerb.approvalPending => 'needs your approval',
    PushVerb.approvalCompleted =>
      detail == null ? 'decided the approval' : '$detail the approval',
    PushVerb.test => 'sent a test push',
  };
}

String _standalonePhrase(PushVerb verb, {String? detail, String? ref}) {
  final on = ref == null ? '' : ' $ref';
  return switch (verb) {
    PushVerb.mentioned => 'You were mentioned',
    PushVerb.assigned => 'Assigned to you',
    PushVerb.reassigned => 'Reassigned$on',
    PushVerb.created => 'Created$on for you',
    PushVerb.stateChanged =>
      detail == null ? 'State changed' : 'Moved to $detail',
    PushVerb.edited => 'Edited$on',
    PushVerb.commented => 'New comment$on',
    PushVerb.replied => 'New reply$on',
    PushVerb.reviewRequested => 'Needs your review$on',
    PushVerb.voted => _voteStandalone(detail, on),
    PushVerb.prCompleted => 'Completed$on',
    PushVerb.prAbandoned => 'Abandoned$on',
    PushVerb.prPublished => 'Published$on',
    PushVerb.pushed => 'New changes pushed$on',
    PushVerb.mergeFailed =>
      detail == null ? 'Merge failed$on' : 'Merge failed$on ($detail)',
    PushVerb.buildFailed ||
    PushVerb.buildPartial ||
    PushVerb.buildCanceled ||
    PushVerb.buildFixed ||
    PushVerb.buildSucceeded => 'Build ${_buildOutcome(verb)}',
    PushVerb.approvalPending => 'Needs your approval',
    PushVerb.approvalCompleted =>
      detail == null ? 'Approval decided' : 'Approval $detail',
    PushVerb.test => 'Push is working',
  };
}

String _votePhrase(String? detail, String on) => switch (detail) {
  'approved' => 'approved$on',
  'approvedWithSuggestions' => 'approved$on with suggestions',
  'waitingForAuthor' => 'is waiting for the author$on',
  'rejected' => 'rejected$on',
  _ => 'voted on${on.isEmpty ? ' it' : on}',
};

String _voteStandalone(String? detail, String on) => switch (detail) {
  'approved' => 'Approved$on',
  'approvedWithSuggestions' => 'Approved with suggestions$on',
  'waitingForAuthor' => 'Waiting for the author$on',
  'rejected' => 'Rejected$on',
  _ => 'New vote$on',
};

String _buildOutcome(PushVerb verb) => switch (verb) {
  PushVerb.buildFailed => 'failed',
  PushVerb.buildPartial => 'partially succeeded',
  PushVerb.buildCanceled => 'was canceled',
  PushVerb.buildFixed => 'is fixed',
  _ => 'succeeded',
};
