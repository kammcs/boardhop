/// What the actor did, as the app renders it after their name: "Javier Perez
/// *replied on* !8261" (research/14 §3.2).
///
/// This file is the **shared** vocabulary: `routing/` produces verbs and
/// `gateway/` validates and renders them, so it sits above both and imports
/// nothing itself. (The one allowed direction between those two directories is
/// `routing/` → `gateway/`; the gateway never imports a routing file.)
///
/// The relay never sends words: it sends the enum name, and the app localises
/// it. [priority] is research/14 §5.2 rule 2 — when several rules select the
/// same person for one event, the highest priority wins and that person gets
/// exactly one notification.
///
/// mentioned > assigned / reviewRequested > voted / stateChanged / approval >
/// commented / replied > edited / pushed
enum Verb {
  // --- mention: always the loudest thing that can happen to you.
  mentioned(100),

  // --- "this is yours now".
  assigned(90),
  reviewRequested(90),
  reassigned(85),
  created(80),

  // --- something went wrong, or finished.
  mergeFailed(75, detailVocabulary: mergeStatusDetails),
  buildFailed(74, detailVocabulary: buildResultDetails),
  buildPartial(73, detailVocabulary: buildResultDetails),
  buildCanceled(72, detailVocabulary: buildResultDetails),
  buildFixed(71, detailVocabulary: buildResultDetails),
  buildSucceeded(70, detailVocabulary: buildResultDetails),

  // --- a decision was taken on something of yours.
  voted(65, detailVocabulary: voteDetails),
  stateChanged(65),
  approvalPending(65),
  approvalCompleted(65, detailVocabulary: approvalDetails),
  prCompleted(60),
  prAbandoned(60),
  prPublished(60),

  // --- discussion.
  commented(50),
  replied(50),

  // --- the quiet tail, both off by default (research/14 §6).
  edited(20),
  pushed(20),

  // --- `/v1/test-push`.
  test(0);

  const Verb(this.priority, {this.detailVocabulary});

  /// Higher wins the per-person collapse (research/14 §5.2 rule 2).
  final int priority;

  /// The closed list this verb's `detail` must come from, where
  /// research/14 §3.2 asks for one: vote labels, build results, approval
  /// statuses and merge statuses. Null means the detail is free-form metadata
  /// (a state name, a stage name) and is only length-capped.
  final Set<String>? detailVocabulary;

  /// research/14 §3.2: `detail` is at most 40 characters and never free text
  /// out of a comment or a description.
  static const maxDetail = 40;

  /// The verb with this name, or null. The closed list of research/14 §3.2 is
  /// the validation: a pointer whose `verb` is not one of these carries none.
  static Verb? tryParse(String? name) {
    if (name == null) return null;
    for (final verb in Verb.values) {
      if (verb.name == name) return verb;
    }
    return null;
  }

  /// The vote labels of research/14 §2.2, by the `vote` value the payload
  /// carries. `0` is a vote reset and notifies nobody, so it has no label.
  static String? voteLabel(int? vote) => switch (vote) {
    10 => 'approved',
    5 => 'approvedWithSuggestions',
    -5 => 'waitingForAuthor',
    -10 => 'rejected',
    _ => null,
  };

  /// The verb a finished build gets, before "fixed" is considered.
  static Verb? forBuildResult(String? result) => switch (result?.toLowerCase()) {
    'failed' => Verb.buildFailed,
    'partiallysucceeded' => Verb.buildPartial,
    'canceled' || 'cancelled' || 'stopped' => Verb.buildCanceled,
    'succeeded' => Verb.buildSucceeded,
    _ => null,
  };

  /// True for the verbs quiet hours let through by default
  /// (`quietHours.exceptApprovals`, research/14 §6).
  bool get isApproval => this == Verb.approvalPending || this == Verb.approvalCompleted;

  bool get isBuild => const {
    Verb.buildFailed,
    Verb.buildPartial,
    Verb.buildCanceled,
    Verb.buildFixed,
    Verb.buildSucceeded,
  }.contains(this);

  /// [raw] if this verb allows it, else null. A closed-vocabulary verb rejects
  /// anything not on its list; every other verb caps the length.
  String? sanitizeDetail(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final vocabulary = detailVocabulary;
    if (vocabulary != null) return vocabulary.contains(trimmed) ? trimmed : null;
    return trimmed.length <= maxDetail ? trimmed : trimmed.substring(0, maxDetail);
  }
}

/// research/14 §2.2: `vote` 10, 5, −5, −10.
const voteDetails = <String>{'approved', 'approvedWithSuggestions', 'waitingForAuthor', 'rejected'};

/// The `result` values `build.complete` delivers (s41).
const buildResultDetails = <String>{'failed', 'partiallySucceeded', 'canceled', 'succeeded'};

/// `approval.status` once the approval is decided (w25).
const approvalDetails = <String>{'approved', 'rejected', 'pending', 'canceled', 'timedOut', 'skipped'};

/// `mergeStatus` on a failed merge attempt (research/14 §2.2).
const mergeStatusDetails = <String>{'conflicts', 'failure', 'rejectedByPolicy', 'queued', 'notSet'};

/// The fallback body line of research/14 §3.1, in English and in **one
/// place**: `{actor} {verb phrase}` ("Ada Example assigned you", "Ada Example
/// replied on !8348"), or the phrase alone when the payload named no actor or
/// the actor is a service identity ("Needs your approval", "Build failed").
///
/// The app localises the verb itself (research/14 §3.2); this is only what the
/// OS shows before enrichment runs, or when it fails.
///
/// [artifactRef] is `#15545` / `!8348` — the id the phrase points at, empty for
/// builds and approvals, which name themselves in the title. [detail] is the
/// verb's own closed-vocabulary metadata (a state name, a vote label, a build
/// result), already sanitised by [Verb.sanitizeDetail].
String verbPhrase(Verb verb, {String? actor, String? detail, String? artifactRef}) {
  final ref = (artifactRef == null || artifactRef.isEmpty) ? null : artifactRef;
  final withActor = actor != null && actor.isNotEmpty;
  final phrase = withActor
      ? _actorPhrase(verb, detail: detail, ref: ref)
      : _standalonePhrase(verb, detail: detail, ref: ref);
  return withActor ? '$actor $phrase' : phrase;
}

/// "{actor} …".
String _actorPhrase(Verb verb, {String? detail, String? ref}) {
  final on = ref == null ? '' : ' $ref';
  return switch (verb) {
    Verb.mentioned => 'mentioned you',
    Verb.assigned => 'assigned you',
    Verb.reassigned => 'reassigned$on',
    Verb.created => 'created$on for you',
    Verb.stateChanged => detail == null ? 'changed the state$on' : 'moved$on to $detail',
    Verb.edited => 'edited$on',
    Verb.commented => 'commented on${on.isEmpty ? ' it' : on}',
    Verb.replied => 'replied on${on.isEmpty ? ' it' : on}',
    Verb.reviewRequested => 'asked you to review$on',
    Verb.voted => _votePhrase(detail, on),
    Verb.prCompleted => 'completed$on',
    Verb.prAbandoned => 'abandoned$on',
    Verb.prPublished => 'published$on',
    Verb.pushed => 'pushed new changes to$on',
    Verb.mergeFailed => detail == null ? 'could not merge$on' : 'could not merge$on ($detail)',
    Verb.buildFailed ||
    Verb.buildPartial ||
    Verb.buildCanceled ||
    Verb.buildFixed ||
    Verb.buildSucceeded => 'queued a build that ${_buildOutcome(verb)}',
    Verb.approvalPending => 'needs your approval',
    Verb.approvalCompleted => detail == null ? 'decided the approval' : '$detail the approval',
    Verb.test => 'sent a test push',
  };
}

/// The same line without an actor: a service identity, or one of the events
/// whose body names nobody (a PR vote with two movements, a status change).
String _standalonePhrase(Verb verb, {String? detail, String? ref}) {
  final on = ref == null ? '' : ' $ref';
  return switch (verb) {
    Verb.mentioned => 'You were mentioned',
    Verb.assigned => 'Assigned to you',
    Verb.reassigned => 'Reassigned$on',
    Verb.created => 'Created$on for you',
    Verb.stateChanged => detail == null ? 'State changed' : 'Moved to $detail',
    Verb.edited => 'Edited$on',
    Verb.commented => 'New comment$on',
    Verb.replied => 'New reply$on',
    Verb.reviewRequested => 'Needs your review$on',
    Verb.voted => _voteStandalone(detail, on),
    Verb.prCompleted => 'Completed$on',
    Verb.prAbandoned => 'Abandoned$on',
    Verb.prPublished => 'Published$on',
    Verb.pushed => 'New changes pushed$on',
    Verb.mergeFailed => detail == null ? 'Merge failed$on' : 'Merge failed$on ($detail)',
    Verb.buildFailed ||
    Verb.buildPartial ||
    Verb.buildCanceled ||
    Verb.buildFixed ||
    Verb.buildSucceeded => 'Build ${_buildOutcome(verb)}',
    Verb.approvalPending => 'Needs your approval',
    Verb.approvalCompleted => detail == null ? 'Approval decided' : 'Approval $detail',
    Verb.test => 'Push is working',
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

String _buildOutcome(Verb verb) => switch (verb) {
  Verb.buildFailed => 'failed',
  Verb.buildPartial => 'partially succeeded',
  Verb.buildCanceled => 'was canceled',
  Verb.buildFixed => 'is fixed',
  _ => 'succeeded',
};
