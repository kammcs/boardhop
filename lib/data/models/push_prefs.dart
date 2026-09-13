/// The push preference document the relay keeps per `(org, userId)`
/// (research/14 §6, decision D5), as the app reads and writes it through
/// `GET/PUT /v1/prefs?org=`.
///
/// It mirrors `relay/lib/src/routing/prefs.dart` field for field and default
/// for default: the relay refuses a PUT with an unknown key or a value outside
/// its closed list, so the two have to agree. Everything here is a switch or a
/// closed vocabulary — there is no free text in a preference.
library;

/// `workItems.comments`.
enum CommentPref {
  on('Everything'),
  mentionsOnly('Mentions only'),
  off('Off');

  const CommentPref(this.label);

  final String label;
}

/// `pullRequests.comments`, with the "my threads only" narrowing of D4.
enum PrCommentPref {
  on('Everything'),
  mentionsOnly('Mentions only'),
  myThreadsOnly('My threads only'),
  off('Off');

  const PrCommentPref(this.label);

  final String label;
}

/// `pullRequests.votes`.
enum VotePref {
  on('Every vote'),
  rejectionsAndWaitsOnly('Rejections and waits'),
  off('Off');

  const VotePref(this.label);

  final String label;
}

/// `builds` (decision D3: failures plus "fixed" by default).
enum BuildPref {
  failures('Failures'),
  failuresAndFixed('Failures and fixes'),
  all('Every build'),
  off('Off');

  const BuildPref(this.label);

  final String label;
}

T _enumOf<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw) return value;
  }
  return fallback;
}

bool _boolOf(Object? raw, bool fallback) => raw is bool ? raw : fallback;

Map<String, Object?> _mapOf(Object? raw) =>
    raw is Map ? raw.cast<String, Object?>() : const {};

/// The quiet window, in the device's local time. A notification it covers is
/// dropped, not delayed; it still reaches the Activity feed.
class QuietHours {
  const QuietHours({
    this.enabled = false,
    this.start = '22:00',
    this.end = '07:00',
    this.exceptApprovals = true,
  });

  factory QuietHours.fromJson(Map<String, Object?> json) => QuietHours(
    enabled: _boolOf(json['enabled'], false),
    start: json['start'] is String ? json['start'] as String : '22:00',
    end: json['end'] is String ? json['end'] as String : '07:00',
    exceptApprovals: _boolOf(json['exceptApprovals'], true),
  );

  final bool enabled;

  /// `HH:mm`, inclusive.
  final String start;

  /// `HH:mm`, exclusive. Earlier than [start] crosses midnight.
  final String end;

  /// D5: an approval is worth waking up for unless this is turned off.
  final bool exceptApprovals;

  QuietHours copyWith({
    bool? enabled,
    String? start,
    String? end,
    bool? exceptApprovals,
  }) => QuietHours(
    enabled: enabled ?? this.enabled,
    start: start ?? this.start,
    end: end ?? this.end,
    exceptApprovals: exceptApprovals ?? this.exceptApprovals,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'start': start,
    'end': end,
    'exceptApprovals': exceptApprovals,
  };

  static final _time = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

  static bool isValidTime(String value) => _time.hasMatch(value);

  /// `22:00` as (22, 0), or null when it is not a time.
  static (int, int)? parse(String value) {
    final match = _time.firstMatch(value);
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static String format(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// One entry of `mutedArtifacts`: "mute this PR for a day".
class MutedArtifact {
  const MutedArtifact({required this.type, required this.id, this.until});

  factory MutedArtifact.fromJson(Map<String, Object?> json) => MutedArtifact(
    type: json['type'] as String? ?? '',
    id: json['id'] as String? ?? '',
    until: DateTime.tryParse(json['until'] as String? ?? ''),
  );

  /// The artifact family: `wi`, `pr`, `build` or `approval`.
  final String type;
  final String id;

  /// When the mute lapses; null means "until it is removed".
  final DateTime? until;

  String get key => '$type.$id';

  /// How the row reads in Settings: `!8348`, `#15545`, `Build 20163`.
  String get label => switch (type) {
    'wi' || 'workItem' => '#$id',
    'pr' || 'pullRequest' => '!$id',
    'build' => 'Build $id',
    'approval' => 'Approval $id',
    _ => '$type $id',
  };

  Map<String, Object?> toJson() => {
    'type': type,
    'id': id,
    if (until != null) 'until': until!.toUtc().toIso8601String(),
  };
}

/// The preference document of research/14 §6, with its defaults.
class PushPrefs {
  const PushPrefs({
    this.enabled = true,
    this.workItemsAssigned = true,
    this.workItemsStateChanged = true,
    this.workItemsComments = CommentPref.on,
    this.workItemsAnyChangeOnMine = false,
    this.pullRequestsReviewRequested = true,
    this.pullRequestsVotes = VotePref.on,
    this.pullRequestsComments = PrCommentPref.on,
    this.pullRequestsCompletedAbandoned = true,
    this.pullRequestsPushes = false,
    this.builds = BuildPref.failuresAndFixed,
    this.approvals = true,
    this.quietHours = const QuietHours(),
    this.mutedArtifacts = const <MutedArtifact>[],
  });

  /// The §6 defaults, which is also what the relay answers for a person with
  /// no stored row.
  factory PushPrefs.fromDefaults() => const PushPrefs();

  factory PushPrefs.fromJson(Map<String, Object?> json) {
    final workItems = _mapOf(json['workItems']);
    final pullRequests = _mapOf(json['pullRequests']);
    final muted = json['mutedArtifacts'];
    return PushPrefs(
      enabled: _boolOf(json['enabled'], true),
      workItemsAssigned: _boolOf(workItems['assigned'], true),
      workItemsStateChanged: _boolOf(workItems['stateChanged'], true),
      workItemsComments: _enumOf(
        CommentPref.values,
        workItems['comments'],
        CommentPref.on,
      ),
      workItemsAnyChangeOnMine: _boolOf(workItems['anyChangeOnMine'], false),
      pullRequestsReviewRequested: _boolOf(
        pullRequests['reviewRequested'],
        true,
      ),
      pullRequestsVotes: _enumOf(
        VotePref.values,
        pullRequests['votes'],
        VotePref.on,
      ),
      pullRequestsComments: _enumOf(
        PrCommentPref.values,
        pullRequests['comments'],
        PrCommentPref.on,
      ),
      pullRequestsCompletedAbandoned: _boolOf(
        pullRequests['completedAbandoned'],
        true,
      ),
      pullRequestsPushes: _boolOf(pullRequests['pushes'], false),
      builds: _enumOf(BuildPref.values, json['builds'], BuildPref.failuresAndFixed),
      approvals: _boolOf(json['approvals'], true),
      quietHours: QuietHours.fromJson(_mapOf(json['quietHours'])),
      mutedArtifacts: [
        if (muted is List)
          for (final entry in muted.whereType<Map>())
            MutedArtifact.fromJson(entry.cast<String, Object?>()),
      ],
    );
  }

  final bool enabled;

  final bool workItemsAssigned;
  final bool workItemsStateChanged;
  final CommentPref workItemsComments;

  /// D2: other field edits are silent unless this is turned on.
  final bool workItemsAnyChangeOnMine;

  final bool pullRequestsReviewRequested;
  final VotePref pullRequestsVotes;
  final PrCommentPref pullRequestsComments;
  final bool pullRequestsCompletedAbandoned;

  /// Off by default: a new iteration is noisy on an active review.
  final bool pullRequestsPushes;

  final BuildPref builds;
  final bool approvals;
  final QuietHours quietHours;
  final List<MutedArtifact> mutedArtifacts;

  /// research/14 §6: reported by the relay, **not editable** — it is §5.2 rule
  /// 1, shown in Settings as a fixed line so people know why they never hear
  /// about their own changes. A PUT that carries it is refused.
  static const notActor = true;

  PushPrefs copyWith({
    bool? enabled,
    bool? workItemsAssigned,
    bool? workItemsStateChanged,
    CommentPref? workItemsComments,
    bool? workItemsAnyChangeOnMine,
    bool? pullRequestsReviewRequested,
    VotePref? pullRequestsVotes,
    PrCommentPref? pullRequestsComments,
    bool? pullRequestsCompletedAbandoned,
    bool? pullRequestsPushes,
    BuildPref? builds,
    bool? approvals,
    QuietHours? quietHours,
    List<MutedArtifact>? mutedArtifacts,
  }) => PushPrefs(
    enabled: enabled ?? this.enabled,
    workItemsAssigned: workItemsAssigned ?? this.workItemsAssigned,
    workItemsStateChanged: workItemsStateChanged ?? this.workItemsStateChanged,
    workItemsComments: workItemsComments ?? this.workItemsComments,
    workItemsAnyChangeOnMine:
        workItemsAnyChangeOnMine ?? this.workItemsAnyChangeOnMine,
    pullRequestsReviewRequested:
        pullRequestsReviewRequested ?? this.pullRequestsReviewRequested,
    pullRequestsVotes: pullRequestsVotes ?? this.pullRequestsVotes,
    pullRequestsComments: pullRequestsComments ?? this.pullRequestsComments,
    pullRequestsCompletedAbandoned:
        pullRequestsCompletedAbandoned ?? this.pullRequestsCompletedAbandoned,
    pullRequestsPushes: pullRequestsPushes ?? this.pullRequestsPushes,
    builds: builds ?? this.builds,
    approvals: approvals ?? this.approvals,
    quietHours: quietHours ?? this.quietHours,
    mutedArtifacts: mutedArtifacts ?? this.mutedArtifacts,
  );

  /// The document. [forWrite] leaves `notActor` out, because the relay answers
  /// `{"error":"notActor is not editable"}` to a PUT that carries it.
  Map<String, Object?> toJson({bool forWrite = false}) => {
    'enabled': enabled,
    'workItems': {
      'assigned': workItemsAssigned,
      'stateChanged': workItemsStateChanged,
      'comments': workItemsComments.name,
      'anyChangeOnMine': workItemsAnyChangeOnMine,
    },
    'pullRequests': {
      'reviewRequested': pullRequestsReviewRequested,
      'votes': pullRequestsVotes.name,
      'comments': pullRequestsComments.name,
      'completedAbandoned': pullRequestsCompletedAbandoned,
      'pushes': pullRequestsPushes,
    },
    'builds': builds.name,
    'approvals': approvals,
    'quietHours': quietHours.toJson(),
    'mutedArtifacts': [for (final muted in mutedArtifacts) muted.toJson()],
    if (!forWrite) 'notActor': notActor,
  };
}
