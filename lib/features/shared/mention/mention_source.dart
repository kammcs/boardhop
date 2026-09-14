import 'package:flutter/widgets.dart';

import '../../../data/models/work_item.dart';
import '../../../core/text/mention.dart';

/// Everything a [MentionField] needs from its host, as closures.
///
/// Closures rather than a repository for the same reason `IdentitySource`
/// uses them: the widget stays testable without a mock, and each host
/// assembles the bands from what it has already loaded (research/16 §4.5).
/// Every field is optional; a source that supplies nothing simply never opens
/// a list, which is what `MentionField(source: null)` means too.
class MentionSource {
  const MentionSource({
    this.participants,
    this.participantReason,
    this.recents,
    this.members,
    this.search,
    this.resolve,
    this.workItems,
    this.pullRequests,
    this.me,
    this.onPicked,
  });

  /// People already on this artifact: comment authors, the assignee, the PR's
  /// author and reviewers. Never let a stranger float above one (research/16
  /// §2).
  final Future<List<IdentityRef>> Function()? participants;

  /// The secondary line for the participants band: "On this item" from a work
  /// item, "In this thread" from a pull request. The host words it because
  /// only the host knows what the artifact is.
  final String? participantReason;

  /// People recently mentioned in this project, most recent first.
  final Future<List<IdentityRef>> Function()? recents;

  /// The project's cached team members. Available offline (M13).
  final Future<List<IdentityRef>> Function()? members;

  /// Project-scoped Graph subject query. Called only from
  /// [MentionSuggestions.minSearchQuery] characters, debounced 300 ms, last
  /// request wins (M5).
  final Future<List<IdentityRef>> Function(String query)? search;

  /// `graph/storagekeys` for a Graph hit, which carries no identity id.
  /// Called when that person is picked, so a failure surfaces while the list
  /// is open rather than at post time (M15).
  final Future<IdentityRef> Function(IdentityRef person)? resolve;

  /// Work items for the `#` trigger: the cached lists at once, the search API
  /// from three characters (M8). The host decides which; the field only
  /// debounces the longer queries.
  final Future<List<ArtifactSuggestion>> Function(String query)? workItems;

  /// Active pull requests for the `!` trigger, from cache only (M8).
  final Future<List<ArtifactSuggestion>> Function(String query)? pullRequests;

  /// The signed-in user. Mentioning yourself is allowed — it is how the relay
  /// gets tested (M14) — so `me` is offered when no band already carries
  /// them, and never pinned.
  final IdentityRef? me;

  /// Called with the resolved person after a pick, to seed the recents.
  final void Function(IdentityRef person)? onPicked;

  bool supports(MentionKind kind) => switch (kind) {
    MentionKind.person =>
      participants != null ||
          recents != null ||
          members != null ||
          search != null ||
          me != null,
    MentionKind.workItem => workItems != null,
    MentionKind.pullRequest => pullRequests != null,
  };
}

/// One person offered in the list.
@immutable
class PersonSuggestion {
  const PersonSuggestion(
    this.person, {
    this.reason,
    this.resolved = true,
    this.secondary,
    this.matches = const [],
  });

  final IdentityRef person;

  /// Why this person is here, as the host worded it ("On this item").
  final String? reason;

  /// False when the person carries no identity GUID yet — a Graph hit. It is
  /// resolved when picked (M15); a person who cannot be resolved is never
  /// inserted, because a mention without a GUID routes to nobody.
  final bool resolved;

  /// The line under the name: [reason], else the e-mail when two visible
  /// names would read alike, else nothing (M14).
  final String? secondary;

  /// Ranges of [IdentityRef.displayName] the query matched, for bolding.
  final List<TextRange> matches;

  PersonSuggestion _with({String? secondary, List<TextRange>? matches}) =>
      PersonSuggestion(
        person,
        reason: reason,
        resolved: resolved,
        secondary: secondary ?? this.secondary,
        matches: matches ?? this.matches,
      );
}

/// One work item or pull request offered in the list.
@immutable
class ArtifactSuggestion {
  const ArtifactSuggestion(
    this.kind,
    this.id,
    this.title, {
    this.typeName,
    this.state,
    this.matches = const [],
  });

  /// [MentionKind.workItem] or [MentionKind.pullRequest].
  final MentionKind kind;

  /// `15545` — the number without its trigger character.
  final String id;

  final String title;

  /// The work item's type, which picks the tile's glyph and colour. Null for
  /// a pull request, and an unknown name draws the neutral tile.
  final String? typeName;

  final String? state;

  /// Ranges of [title] the query matched, for bolding.
  final List<TextRange> matches;

  /// What is inserted, and what Azure DevOps links by itself (research/16
  /// §1: `#123` and `!456` need no client syntax).
  String get label => kind == MentionKind.pullRequest ? '!$id' : '#$id';
}

/// The merge, order, filter and match rules, with no widget in sight.
///
/// Kept pure so the interesting half of the picker — which stranger may float
/// above which colleague — is unit tested without pumping anything.
abstract final class MentionSuggestions {
  /// The directory is searched only from two characters (M5), the same
  /// minimum the assignee sheet uses.
  static const int minSearchQuery = 2;

  /// The same dedup key the assignee sheet uses
  /// (`identity_picker.dart`): the unique name first, because a team member
  /// carries an identity id and the same person from the Graph search carries
  /// only a descriptor, so keying on the id would list them twice.
  static String key(IdentityRef person) =>
      (person.uniqueName ?? person.id ?? person.displayName).toLowerCase();

  /// The query split into words. `kel ka` is two.
  static List<String> words(String query) => [
    for (final word in query.toLowerCase().split(RegExp(r'\s+')))
      if (word.isNotEmpty) word,
  ];

  /// M14: case-insensitive, and every word of the query has to appear
  /// somewhere in the display name or the e-mail.
  static bool matches(IdentityRef person, String query) {
    final parts = words(query);
    if (parts.isEmpty) return true;
    final name = person.displayName.toLowerCase();
    final unique = (person.uniqueName ?? '').toLowerCase();
    return parts.every((w) => name.contains(w) || unique.contains(w));
  }

  /// Where each query word sits in [text], merged and in order, so the row
  /// can bold the letters the user typed (GitLab 18132).
  static List<TextRange> matchRanges(String text, String query) {
    final parts = words(query);
    if (parts.isEmpty || text.isEmpty) return const [];
    final lower = text.toLowerCase();
    final found = <TextRange>[];
    for (final word in parts) {
      var from = 0;
      while (from <= lower.length - word.length) {
        final at = lower.indexOf(word, from);
        if (at < 0) break;
        found.add(TextRange(start: at, end: at + word.length));
        from = at + 1;
      }
    }
    if (found.isEmpty) return const [];
    found.sort((a, b) => a.start.compareTo(b.start));
    final merged = <TextRange>[found.first];
    for (final range in found.skip(1)) {
      final last = merged.last;
      if (range.start <= last.end) {
        if (range.end > last.end) {
          merged[merged.length - 1] = TextRange(
            start: last.start,
            end: range.end,
          );
        }
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  /// The people list, in the order the survey settled on (research/16 §2 and
  /// M2): participants of this artifact, then people recently mentioned in
  /// this project, then cached team members, then the directory hits.
  ///
  /// `me` comes last and only when no band already carried them, so
  /// mentioning yourself always works without pinning a row nobody needs.
  static List<PersonSuggestion> people({
    required String query,
    List<IdentityRef> participants = const [],
    String? participantReason,
    List<IdentityRef> recents = const [],
    List<IdentityRef> members = const [],
    List<IdentityRef> hits = const [],
    IdentityRef? me,
  }) {
    final seen = <String>{};
    final ordered = <PersonSuggestion>[];

    void band(Iterable<IdentityRef> people, String? reason) {
      for (final person in people) {
        if (person.displayName.isEmpty && person.uniqueName == null) continue;
        if (!matches(person, query)) continue;
        if (!seen.add(key(person))) continue;
        ordered.add(
          PersonSuggestion(
            person,
            reason: reason,
            resolved: person.id != null && person.id!.isNotEmpty,
          ),
        );
      }
    }

    band(participants, participantReason);
    band(recents, null);
    band(members, null);
    band(hits, null);
    if (me != null) band([me], null);

    // Two rows reading "Kelly Kamm" need the e-mail to tell them apart
    // (Slack's January 2026 fix).
    final byName = <String, int>{};
    for (final suggestion in ordered) {
      final name = suggestion.person.displayName.toLowerCase();
      byName[name] = (byName[name] ?? 0) + 1;
    }
    return [
      for (final suggestion in ordered)
        suggestion._with(
          secondary:
              suggestion.reason ??
              ((byName[suggestion.person.displayName.toLowerCase()] ?? 0) > 1
                  ? suggestion.person.uniqueName
                  : null),
          matches: matchRanges(suggestion.person.displayName, query),
        ),
    ];
  }

  /// Dedup an artifact band on (kind, id), keeping the host's order — the
  /// cached items first, then the search hits — and mark the matched letters
  /// in the title.
  static List<ArtifactSuggestion> artifacts(
    List<ArtifactSuggestion> found, {
    String query = '',
  }) {
    final seen = <String>{};
    final out = <ArtifactSuggestion>[];
    for (final item in found) {
      if (!seen.add('${item.kind.name}:${item.id}')) continue;
      out.add(
        ArtifactSuggestion(
          item.kind,
          item.id,
          item.title,
          typeName: item.typeName,
          state: item.state,
          matches: matchRanges(item.title, query),
        ),
      );
    }
    return out;
  }
}
