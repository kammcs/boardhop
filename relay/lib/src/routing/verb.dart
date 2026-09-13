/// What the actor did, as the app renders it after their name: "Javier Perez
/// *replied on* !8261" (research/14 §3.2).
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
