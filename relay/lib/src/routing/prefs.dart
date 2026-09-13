import 'dart:convert';

import '../db.dart';
import '../verb.dart';
import 'candidate.dart';

/// One person's push preferences for one organization (research/14 §6 and
/// decision D5).
///
/// The engine only ever sees this interface; [StoredPrefs] is what the
/// `user_prefs` table and `GET/PUT /v1/prefs` fill it with, and the defaults
/// live in exactly one place ([PushPrefs.defaults]), so a brand-new
/// registration and a stored document are read by the same code.
abstract interface class UserPrefs {
  /// Whether this person wants to hear about [verb] at all.
  ///
  /// [reason] is why a rule selected them (research/14 §6): the "mentions only"
  /// and "my threads only" narrowings are the same verb with a different
  /// reason. [detail] is the verb's closed-vocabulary metadata, which
  /// `pullRequests.votes: rejectionsAndWaitsOnly` needs. [artifactKey] is
  /// `wi.15545` / `pr.8334` / `build.20163` for the muted artifact list; null
  /// when there is nothing to mute.
  bool allows(Verb verb, {required CandidateReason reason, String? detail, String? artifactKey});

  /// True when the person's quiet hours cover [nowUtc] for this [verb].
  /// [tzOffsetMinutes] is the device's offset east of UTC, sent with the
  /// heartbeat; null when the relay has never been told one, in which case the
  /// window is evaluated in UTC.
  ///
  /// Approvals are exempt by default (`quietHours.exceptApprovals`, D5), which
  /// is why the verb is a parameter: turning that off has to be able to
  /// silence them too.
  bool quietHoursSuppress(Verb verb, DateTime nowUtc, int? tzOffsetMinutes);
}

/// `workItems.comments` (research/14 §6).
enum CommentPref { on, mentionsOnly, off }

/// `pullRequests.comments`, which has the extra "my threads only" narrowing
/// of decision D4.
enum PrCommentPref { on, mentionsOnly, myThreadsOnly, off }

/// `pullRequests.votes`.
enum VotePref { on, rejectionsAndWaitsOnly, off }

/// `builds` (decision D3: failures plus "fixed" by default).
enum BuildPref { failures, failuresAndFixed, all, off }

/// The quiet window, in the **device's** local time (research/14 §6). A
/// notification it covers is dropped, not delayed.
class QuietHours {
  const QuietHours({this.enabled = false, this.start = '22:00', this.end = '07:00', this.exceptApprovals = true});

  final bool enabled;

  /// `HH:mm`, inclusive.
  final String start;

  /// `HH:mm`, exclusive. Earlier than [start] means the window crosses
  /// midnight, which is the normal case; equal to [start] means all day.
  final String end;

  /// D5: an approval is worth waking up for unless this is turned off.
  final bool exceptApprovals;

  Map<String, Object?> toJson() => {'enabled': enabled, 'start': start, 'end': end, 'exceptApprovals': exceptApprovals};

  /// True when [minuteOfDay] (local) falls inside the window.
  bool covers(int minuteOfDay) {
    final from = _minutes(start);
    final to = _minutes(end);
    if (from == null || to == null) return false;
    if (from == to) return true;
    if (from < to) return minuteOfDay >= from && minuteOfDay < to;
    return minuteOfDay >= from || minuteOfDay < to;
  }

  /// `HH:mm` as minutes past midnight, or null when it is not a time.
  static int? _minutes(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  static bool isValidTime(String value) => _minutes(value) != null;
}

/// One entry of `mutedArtifacts`: "mute this PR for a day" from the app's
/// app-bar menu (research/14 §6).
class MutedArtifact {
  const MutedArtifact({required this.type, required this.id, this.until});

  /// The artifact **family**: `wi`, `pr`, `build` or `approval`, the same
  /// prefix the collapse key and the artifact key use.
  final String type;
  final String id;

  /// When the mute lapses. Null means "until it is removed".
  final DateTime? until;

  /// What it matches against: the engine's `artifactKey`.
  String get key => '$type.$id';

  bool coversNow(DateTime nowUtc) => until?.isAfter(nowUtc) ?? true;

  Map<String, Object?> toJson() => {'type': type, 'id': id, if (until != null) 'until': until!.toIso8601String()};
}

/// The preference document of research/14 §6, with its defaults.
///
/// Everything here is a switch or a closed vocabulary — there is no free text
/// in a preference, so the table that holds it holds no content either.
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

  /// The one place the §6 defaults live: a person with no row gets this, and
  /// `PUT /v1/prefs` fills every key the client left out from it.
  static const defaults = PushPrefs();

  /// A muted list longer than this is a client bug, not a preference.
  static const maxMutedArtifacts = 200;

  /// The master switch; registration itself is the opt-in, so it starts on.
  final bool enabled;

  final bool workItemsAssigned;
  final bool workItemsStateChanged;
  final CommentPref workItemsComments;

  /// research/14 D2: other field edits are silent unless this is turned on.
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

  /// research/14 §6: `notActor` is on and **not editable** — the rule of §5.2
  /// rule 1. It is reported so the app can show the fixed line that explains
  /// why you never hear about your own edits.
  static const notActor = true;

  Map<String, Object?> toJson() => {
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
    'notActor': notActor,
  };

  String encode() => jsonEncode(toJson());

  /// Reads a stored document back. Anything unreadable falls back to the
  /// defaults rather than throwing on the send path.
  static PushPrefs decode(String? stored) {
    if (stored == null || stored.isEmpty) return defaults;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map<String, Object?>) return defaults;
      // The stored form is what `toJson` wrote, `notActor` included; the
      // parser refuses that key from a client, so it is dropped on the way in.
      final parsed = PrefsParser.parse({...decoded}..remove('notActor'));
      return parsed.prefs ?? defaults;
    } catch (_) {
      return defaults;
    }
  }
}

/// What [PrefsParser.parse] answers: the document, or the first thing wrong
/// with it. A typo must not silently switch a notification off, so an unknown
/// key is an error and not an ignored field (research/14 §6).
typedef PrefsParse = ({PushPrefs? prefs, String? error});

/// Validates a `PUT /v1/prefs` body against §6, key by key and value by value.
abstract final class PrefsParser {
  static PrefsParse parse(Map<String, Object?> json) {
    final base = PushPrefs.defaults;
    try {
      // `notActor` is the §5.2 rule 1 line the UI shows; a client that tries
      // to set it is told so, rather than quietly ignored.
      if (json.containsKey('notActor')) throw _Invalid('notActor is not editable');
      _rejectUnknown(json, const {
        'enabled',
        'workItems',
        'pullRequests',
        'builds',
        'approvals',
        'quietHours',
        'mutedArtifacts',
      }, 'body');

      final workItems = _object(json['workItems'], 'workItems');
      _rejectUnknown(workItems, const {'assigned', 'stateChanged', 'comments', 'anyChangeOnMine'}, 'workItems');
      final pullRequests = _object(json['pullRequests'], 'pullRequests');
      _rejectUnknown(pullRequests, const {
        'reviewRequested',
        'votes',
        'comments',
        'completedAbandoned',
        'pushes',
      }, 'pullRequests');
      final quiet = _object(json['quietHours'], 'quietHours');
      _rejectUnknown(quiet, const {'enabled', 'start', 'end', 'exceptApprovals'}, 'quietHours');

      return (
        prefs: PushPrefs(
          enabled: _bool(json['enabled'], 'enabled', base.enabled),
          workItemsAssigned: _bool(workItems['assigned'], 'workItems.assigned', base.workItemsAssigned),
          workItemsStateChanged: _bool(workItems['stateChanged'], 'workItems.stateChanged', base.workItemsStateChanged),
          workItemsComments: _enum(
            workItems['comments'],
            'workItems.comments',
            CommentPref.values,
            base.workItemsComments,
          ),
          workItemsAnyChangeOnMine: _bool(
            workItems['anyChangeOnMine'],
            'workItems.anyChangeOnMine',
            base.workItemsAnyChangeOnMine,
          ),
          pullRequestsReviewRequested: _bool(
            pullRequests['reviewRequested'],
            'pullRequests.reviewRequested',
            base.pullRequestsReviewRequested,
          ),
          pullRequestsVotes: _enum(
            pullRequests['votes'],
            'pullRequests.votes',
            VotePref.values,
            base.pullRequestsVotes,
          ),
          pullRequestsComments: _enum(
            pullRequests['comments'],
            'pullRequests.comments',
            PrCommentPref.values,
            base.pullRequestsComments,
          ),
          pullRequestsCompletedAbandoned: _bool(
            pullRequests['completedAbandoned'],
            'pullRequests.completedAbandoned',
            base.pullRequestsCompletedAbandoned,
          ),
          pullRequestsPushes: _bool(pullRequests['pushes'], 'pullRequests.pushes', base.pullRequestsPushes),
          builds: _enum(json['builds'], 'builds', BuildPref.values, base.builds),
          approvals: _bool(json['approvals'], 'approvals', base.approvals),
          quietHours: QuietHours(
            enabled: _bool(quiet['enabled'], 'quietHours.enabled', base.quietHours.enabled),
            start: _time(quiet['start'], 'quietHours.start', base.quietHours.start),
            end: _time(quiet['end'], 'quietHours.end', base.quietHours.end),
            exceptApprovals: _bool(
              quiet['exceptApprovals'],
              'quietHours.exceptApprovals',
              base.quietHours.exceptApprovals,
            ),
          ),
          mutedArtifacts: _muted(json['mutedArtifacts']),
        ),
        error: null,
      );
    } on _Invalid catch (e) {
      return (prefs: null, error: e.message);
    }
  }

  /// The artifact families a mute may name, and the `PushArtifactType` names
  /// the app uses for the same four things.
  static const _mutableFamilies = {
    'wi': 'wi',
    'workItem': 'wi',
    'pr': 'pr',
    'pullRequest': 'pr',
    'build': 'build',
    'approval': 'approval',
  };

  static void _rejectUnknown(Map<String, Object?> json, Set<String> allowed, String where) {
    for (final key in json.keys) {
      if (!allowed.contains(key)) throw _Invalid('unknown preference "$key" in $where');
    }
  }

  static Map<String, Object?> _object(Object? value, String where) {
    if (value == null) return const <String, Object?>{};
    if (value is Map<String, Object?>) return value;
    throw _Invalid('$where must be an object');
  }

  static bool _bool(Object? value, String where, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    throw _Invalid('$where must be true or false');
  }

  static T _enum<T extends Enum>(Object? value, String where, List<T> values, T fallback) {
    if (value == null) return fallback;
    if (value is String) {
      for (final option in values) {
        if (option.name == value) return option;
      }
    }
    throw _Invalid('$where must be one of ${values.map((v) => v.name).join(', ')}');
  }

  static String _time(Object? value, String where, String fallback) {
    if (value == null) return fallback;
    if (value is String && QuietHours.isValidTime(value)) return value;
    throw _Invalid('$where must be "HH:mm"');
  }

  static List<MutedArtifact> _muted(Object? value) {
    if (value == null) return const <MutedArtifact>[];
    if (value is! List) throw _Invalid('mutedArtifacts must be a list');
    if (value.length > PushPrefs.maxMutedArtifacts) {
      throw _Invalid('mutedArtifacts holds at most ${PushPrefs.maxMutedArtifacts} entries');
    }
    final out = <MutedArtifact>[];
    for (final entry in value) {
      if (entry is! Map<String, Object?>) throw _Invalid('mutedArtifacts entries must be objects');
      _rejectUnknown(entry, const {'type', 'id', 'until'}, 'mutedArtifacts');
      final type = _mutableFamilies[entry['type']];
      if (type == null) throw _Invalid('mutedArtifacts type must be one of wi, pr, build, approval');
      final id = entry['id'];
      if (id is! String || id.isEmpty || id.length > 64) throw _Invalid('mutedArtifacts id must be a short string');
      final rawUntil = entry['until'];
      DateTime? until;
      if (rawUntil != null) {
        if (rawUntil is! String) throw _Invalid('mutedArtifacts until must be an ISO-8601 time');
        until = DateTime.tryParse(rawUntil)?.toUtc();
        if (until == null) throw _Invalid('mutedArtifacts until must be an ISO-8601 time');
      }
      out.add(MutedArtifact(type: type, id: id, until: until));
    }
    return List.unmodifiable(out);
  }
}

class _Invalid implements Exception {
  _Invalid(this.message);
  final String message;
}

DateTime _utcNow() => DateTime.now().toUtc();

/// [PushPrefs] read as the engine's questions (research/14 §6).
///
/// One place decides what a preference **means**, so the stored document and
/// the defaults behave identically — `DefaultPrefs` is this class over
/// [PushPrefs.defaults].
class StoredPrefs implements UserPrefs {
  const StoredPrefs(this.prefs, {this.clock = _utcNow});

  final PushPrefs prefs;

  /// Only `mutedArtifacts` needs a clock: an entry's `until` has to be in the
  /// future for the mute to still hold.
  final DateTime Function() clock;

  @override
  bool allows(Verb verb, {required CandidateReason reason, String? detail, String? artifactKey}) {
    if (!prefs.enabled) return false;
    if (_muted(artifactKey)) return false;

    final family = artifactKey?.split('.').first;
    return switch (verb) {
      // A work item landing on you, or leaving you.
      Verb.assigned || Verb.created || Verb.reassigned => prefs.workItemsAssigned,
      Verb.stateChanged => prefs.workItemsStateChanged,
      Verb.edited => prefs.workItemsAnyChangeOnMine,

      // Discussion: the family decides which of the two comment settings asks.
      Verb.mentioned => _mentionAllowed(family),
      Verb.commented || Verb.replied => _commentAllowed(family, reason),

      // Pull requests.
      Verb.reviewRequested || Verb.prPublished => prefs.pullRequestsReviewRequested,
      Verb.voted => _voteAllowed(detail),
      Verb.prCompleted || Verb.prAbandoned || Verb.mergeFailed => prefs.pullRequestsCompletedAbandoned,
      Verb.pushed => prefs.pullRequestsPushes,

      // Builds (D3).
      Verb.buildFailed || Verb.buildPartial || Verb.buildCanceled => prefs.builds != BuildPref.off,
      Verb.buildFixed => prefs.builds == BuildPref.failuresAndFixed || prefs.builds == BuildPref.all,
      Verb.buildSucceeded => prefs.builds == BuildPref.all,

      Verb.approvalPending || Verb.approvalCompleted => prefs.approvals,

      // `/v1/test-push` is the person pressing a button; it is never filtered.
      Verb.test => true,
    };
  }

  @override
  bool quietHoursSuppress(Verb verb, DateTime nowUtc, int? tzOffsetMinutes) {
    final quiet = prefs.quietHours;
    if (!quiet.enabled) return false;
    if (verb.isApproval && quiet.exceptApprovals) return false;
    final local = nowUtc.toUtc().add(Duration(minutes: tzOffsetMinutes ?? 0));
    return quiet.covers(local.hour * 60 + local.minute);
  }

  /// "Mute this PR for a day": an entry that names this artifact and has not
  /// lapsed drops everything about it.
  bool _muted(String? artifactKey) {
    if (artifactKey == null || prefs.mutedArtifacts.isEmpty) return false;
    final now = clock();
    for (final muted in prefs.mutedArtifacts) {
      if (muted.key == artifactKey && muted.coversNow(now)) return true;
    }
    return false;
  }

  /// A mention is the one thing "mentions only" and "my threads only" keep;
  /// only `off` silences it.
  bool _mentionAllowed(String? family) => switch (family) {
    'pr' => prefs.pullRequestsComments != PrCommentPref.off,
    _ => prefs.workItemsComments != CommentPref.off,
  };

  bool _commentAllowed(String? family, CandidateReason reason) {
    if (family == 'pr') {
      return switch (prefs.pullRequestsComments) {
        PrCommentPref.on => true,
        // A thread you are already in — the participant list of
        // `pr_thread_state` — or one that names you.
        PrCommentPref.myThreadsOnly => reason == CandidateReason.threadParticipant || reason == CandidateReason.mention,
        PrCommentPref.mentionsOnly => reason == CandidateReason.mention,
        PrCommentPref.off => false,
      };
    }
    return switch (prefs.workItemsComments) {
      CommentPref.on => true,
      CommentPref.mentionsOnly => reason == CandidateReason.mention,
      CommentPref.off => false,
    };
  }

  bool _voteAllowed(String? detail) => switch (prefs.pullRequestsVotes) {
    VotePref.on => true,
    // The two votes that ask the author to do something.
    VotePref.rejectionsAndWaitsOnly => detail == 'rejected' || detail == 'waitingForAuthor',
    VotePref.off => false,
  };
}

/// The defaults of research/14 §6 and decisions D2 and D3, read through the
/// same code as a stored document: everything on except
/// `workItems.anyChangeOnMine` ([Verb.edited]), `pullRequests.pushes`
/// ([Verb.pushed]) and plain build successes ([Verb.buildSucceeded]; failures
/// and "fixed" are on). Quiet hours off, nothing muted.
class DefaultPrefs extends StoredPrefs {
  const DefaultPrefs() : super(PushPrefs.defaults);
}

/// Where the engine gets a person's preferences.
abstract interface class PrefsSource {
  UserPrefs prefsFor(String org, String userId);

  /// Minutes east of UTC for this person's device, for quiet hours. Null when
  /// no device has reported one.
  int? timeZoneOffsetMinutes(String org, String userId);
}

class DefaultPrefsSource implements PrefsSource {
  const DefaultPrefsSource();

  static const _prefs = DefaultPrefs();

  @override
  UserPrefs prefsFor(String org, String userId) => _prefs;

  @override
  int? timeZoneOffsetMinutes(String org, String userId) => null;
}

/// The production source: `user_prefs` keyed by `(org, userId)`, and the
/// device's own time-zone offset for the quiet window.
///
/// A person with no row is on [PushPrefs.defaults]; a row that will not parse
/// falls back to them too, because a corrupt document must not be a silent
/// "everything off".
class DbPrefsSource implements PrefsSource {
  DbPrefsSource(this.db, {this.clock = _utcNow});

  final RelayDb db;
  final DateTime Function() clock;

  @override
  UserPrefs prefsFor(String org, String userId) =>
      StoredPrefs(PushPrefs.decode(db.userPrefs(org, userId)), clock: clock);

  @override
  int? timeZoneOffsetMinutes(String org, String userId) => db.timeZoneOffsetMinutes(org, userId);
}
