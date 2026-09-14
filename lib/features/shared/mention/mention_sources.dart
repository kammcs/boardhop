import 'dart:async';

import '../../../core/http/ado_exceptions.dart';
import '../../../core/text/mention.dart';
import '../../../data/mention_recents.dart';
import '../../../data/models/pull_request.dart';
import '../../../data/models/search.dart';
import '../../../data/models/work_item.dart';
import '../../../data/repositories/people_repository.dart';
import '../../../data/repositories/pr_diff_source.dart';
import '../../../data/repositories/pull_request_repository.dart';
import '../../../data/repositories/search_repository.dart';
import '../../../data/repositories/work_item_form_repository.dart';
import '../../../data/repositories/work_item_repository.dart';
import 'mention_source.dart';

/// Assembles the [MentionSource] a page hands its composers, and caches the
/// lookups every band shares (research/16 §4.5).
///
/// One of these lives as long as the page does, so the project id, the
/// default team and the team's members are read once however many composers
/// the page builds — a pull request with twelve threads has twelve reply
/// boxes, and each of them would otherwise ask again.
///
/// Nothing here throws: a band that cannot be read comes back empty and the
/// field simply offers the ones that could (M13). The page's own reads are
/// what raise `AuthInteractionRequired`.
class MentionSources {
  MentionSources({
    required this.org,
    required this.project,
    required this.people,
    required this.forms,
    required this.recents,
    required this.workItems,
    required this.pullRequests,
    required this.search,
    String? projectId,
    this.extraWorkItems,
  }) : _projectId = projectId == null ? null : Future<String>.value(projectId);

  /// The organization every read is made against.
  final String org;

  /// The project's **name**: it keys the recents (M2), filters the work item
  /// search and the cached pull request lists, and is what the routes carry.
  /// The Graph reads take the id, which [projectId] resolves.
  final String project;

  final PeopleRepository people;

  /// Only for the two project lookups it owns (the project id and the
  /// default team); everything about people comes from [people].
  final WorkItemFormRepository forms;

  final MentionRecents recents;
  final WorkItemRepository workItems;
  final PullRequestRepository pullRequests;
  final SearchRepository search;

  /// Work items the page already has in hand — the detail page's linked
  /// items — offered beside the cached lists (M8).
  final List<WorkItem> Function()? extraWorkItems;

  /// The secondary line on the work item detail page's participants.
  static const onThisItem = 'On this item';

  /// The same, on a pull request. One wording for the author, the reviewers
  /// and every commenter: splitting "In this thread" out of "On this pull
  /// request" would mean a different source per thread card, and the band is
  /// ordered so the thread's own people come first anyway.
  static const onThisPullRequest = 'On this pull request';

  /// Below this a `#` query is answered from the cache alone; from here the
  /// work item search API is asked as well (M8).
  static const searchFrom = 3;

  Future<String>? _projectId;
  Future<List<IdentityRef>>? _members;
  Future<List<WorkItem>>? _cachedItems;
  Future<List<PullRequest>>? _activePullRequests;

  // ------------------------------------------------------------- the source

  /// The source for one page's composers.
  ///
  /// [participants] is a closure rather than a list because the page keeps
  /// reading: a comment posted while the page is open adds its author.
  MentionSource source({
    required Future<List<IdentityRef>> Function() participants,
    required String participantReason,
    IdentityRef? me,
  }) => MentionSource(
    participants: participants,
    participantReason: participantReason,
    recents: () => recents.list(org, project),
    members: members,
    search: searchPeople,
    resolve: (person) => people.resolveIdentityId(org, person),
    workItems: workItemMatches,
    pullRequests: pullRequestMatches,
    me: me,
    onPicked: remember,
  );

  /// Seeds the recents and the identity memory with somebody just picked, so
  /// the next `@` offers them first and the posted comment can name them
  /// without a call.
  void remember(IdentityRef person) {
    unawaited(recents.add(org, project, person));
    unawaited(people.rememberIdentity(org, person));
  }

  // -------------------------------------------------------------- the bands

  /// The project's id, which the Graph reads need (spike s30: the name
  /// answers HTTP 400 and silently widens the search org-wide). Falls back
  /// to the name, exactly as the work item form does.
  Future<String> projectId() => _projectId ??= _readProjectId();

  Future<String> _readProjectId() async {
    try {
      return await forms.projectId(org, project);
    } on AdoException {
      return project;
    }
  }

  /// The project's default team, cached by [JsonCache] under the same keys
  /// the form uses, so it is there offline (M13).
  Future<List<IdentityRef>> members() => _members ??= _readMembers();

  Future<List<IdentityRef>> _readMembers() async {
    try {
      final id = await projectId();
      final team = await forms.defaultTeamId(org, project);
      final found = await people.teamMembers(org, id, team);
      return found;
    } on AdoException {
      // Not remembered: a refused or offline read must not leave the band
      // empty for the life of the page.
      _members = null;
      return const [];
    }
  }

  Future<List<IdentityRef>> searchPeople(String query) async =>
      people.searchPeople(org, await projectId(), query);

  /// The signed-in person as a mention candidate — which means with a GUID.
  ///
  /// The team member row is preferred because it carries the name and the
  /// avatar as well; failing that, the identity behind [id] is asked for.
  Future<IdentityRef?> me({String? id, String? uniqueName}) async {
    final wanted = id?.toLowerCase();
    final address = uniqueName?.toLowerCase();
    for (final member in await members()) {
      if (wanted != null && member.id?.toLowerCase() == wanted) return member;
      if (address != null && member.uniqueName?.toLowerCase() == address) {
        return member;
      }
    }
    if (id == null || id.isEmpty) return null;
    return people.identityById(org, id);
  }

  // ---------------------------------------------------------- the artifacts

  /// `#` — the cached lists at once, the search API from [searchFrom]
  /// characters, the cached hits first and never twice (M8).
  Future<List<ArtifactSuggestion>> workItemMatches(String query) async {
    final q = query.trim();
    final seen = <String>{};
    final found = <ArtifactSuggestion>[];
    for (final item in await _localItems()) {
      final id = '${item.id}';
      if (!_matches(id, item.title, q)) continue;
      if (!seen.add(id)) continue;
      found.add(
        ArtifactSuggestion(
          MentionKind.workItem,
          id,
          item.title,
          typeName: item.type,
          state: item.state,
        ),
      );
    }
    if (q.length < searchFrom) return found;
    for (final hit in await _searchItems(q)) {
      final id = '${hit.id}';
      if (!seen.add(id)) continue;
      found.add(
        ArtifactSuggestion(
          MentionKind.workItem,
          id,
          hit.title,
          typeName: hit.workItemType,
          state: hit.state,
        ),
      );
    }
    return found;
  }

  /// `!` — the active pull requests this account has already listed. There
  /// is no pull request search API (decision D7), so this is the inbox's own
  /// list: cached, and read once if nothing is cached yet.
  Future<List<ArtifactSuggestion>> pullRequestMatches(String query) async {
    final q = query.trim();
    final found = <ArtifactSuggestion>[];
    for (final pr in await _pullRequestList()) {
      if (pr.projectName != project && pr.projectId != project) continue;
      final id = '${pr.id}';
      if (!_matches(id, pr.title, q)) continue;
      found.add(
        ArtifactSuggestion(
          MentionKind.pullRequest,
          id,
          pr.title,
          state: pr.isDraft ? 'Draft' : null,
        ),
      );
    }
    return found;
  }

  /// The id by prefix (so `#155` finds 15545) or the title by substring.
  static bool _matches(String id, String title, String query) {
    if (query.isEmpty) return true;
    return id.startsWith(query) ||
        title.toLowerCase().contains(query.toLowerCase());
  }

  Future<List<WorkItem>> _localItems() async {
    final cached = await (_cachedItems ??= _readCachedItems());
    final extra = extraWorkItems?.call() ?? const <WorkItem>[];
    return [...extra, ...cached];
  }

  /// The lists the app already keeps in drift for this project.
  Future<List<WorkItem>> _readCachedItems() async {
    final out = <WorkItem>[];
    for (final key in const [
      WorkItemRepository.assignedToMeKey,
      WorkItemRepository.recentlyUpdatedKey,
    ]) {
      try {
        out.addAll(await workItems.watchList(org, project, key).first);
      } catch (_) {
        // A list that was never read is simply not offered.
      }
    }
    return out;
  }

  /// The stored answer for exactly this query first — it is instant and it
  /// works offline — then the search API.
  Future<List<WorkItemSearchHit>> _searchItems(String query) async {
    try {
      final cached = await search.cachedWorkItems(
        org,
        project: project,
        text: query,
      );
      if (cached != null) return cached.value.items;
      final fresh = await search.searchWorkItems(
        org,
        project: project,
        text: query,
      );
      return fresh.items;
    } on AdoException {
      return const [];
    }
  }

  Future<List<PullRequest>> _pullRequestList() =>
      _activePullRequests ??= _readPullRequests();

  Future<List<PullRequest>> _readPullRequests() async {
    final seen = <int>{};
    final out = <PullRequest>[];
    for (final filter in PrListFilter.values) {
      for (final scope in <String?>[project, null]) {
        try {
          final cached = await pullRequests.cachedList(
            org,
            project: scope,
            filter: filter,
          );
          for (final pr in cached?.items ?? const <PullRequest>[]) {
            if (seen.add(pr.id)) out.add(pr);
          }
        } catch (_) {
          // An unreadable cache entry is not worth failing a picker over.
        }
      }
    }
    if (out.isNotEmpty) return out;
    // Nothing cached: one read of the same list the inbox reads, which fills
    // the cache for next time. Not remembered when it fails.
    try {
      return await pullRequests.list(
        org,
        project: project,
        filter: PrListFilter.all,
      );
    } on AdoException {
      _activePullRequests = null;
      return const [];
    }
  }

  // --------------------------------------------------------- participants

  /// The people already on a work item, most recent first: the commenters,
  /// then the assignee, then who created and last changed it.
  ///
  /// Only people carrying an identity GUID are offered — `System.CreatedBy`
  /// reads back as `"Name <mail>"` in some payloads and carries none, and a
  /// mention without a GUID notifies nobody (research/16 §1).
  static List<IdentityRef> workItemParticipants({
    WorkItem? item,
    List<WorkItemComment> comments = const [],
  }) => _withIds([
    for (final comment in comments.reversed) comment.createdBy,
    item?.assignedTo,
    item?.createdBy,
    item?.changedBy,
  ]);

  /// The people on a pull request: this thread's commenters first (the reply
  /// box is usually meant for one of them), then the author, the reviewers
  /// and everybody else who has commented.
  static List<IdentityRef> pullRequestParticipants({
    required PullRequest pr,
    List<PrThread> threads = const [],
    PrThread? thread,
  }) => _withIds([
    for (final comment in thread?.comments ?? const <PrComment>[])
      comment.identity,
    pr.createdBy,
    for (final reviewer in pr.reviewers)
      if (!reviewer.isContainer) reviewer.identity,
    for (final t in threads)
      for (final comment in t.comments) comment.identity,
  ]);

  /// Everybody on the artifact, for [PeopleRepository.rememberIdentities]:
  /// seeding the identity memory is what lets a `@<guid>` in a comment be
  /// named without a network call (M9).
  static List<IdentityRef> _withIds(List<IdentityRef?> people) {
    final seen = <String>{};
    final out = <IdentityRef>[];
    for (final person in people) {
      final id = person?.id?.trim().toLowerCase();
      if (person == null || id == null || id.isEmpty) continue;
      if (!seen.add(id)) continue;
      out.add(person);
    }
    return out;
  }

  /// The display names for every `@<guid>` in [bodies], for the read side.
  ///
  /// The identities the page already knows answer for free; the rest go
  /// through one batched `identities` read, and a GUID nobody answers for is
  /// simply absent, which draws `@someone` (M9).
  static Future<Map<String, String>> namesFor(
    PeopleRepository people,
    String org,
    Iterable<String> bodies,
  ) async {
    final wanted = <String>{};
    for (final body in bodies) {
      for (final match in Mentions.personAngle.allMatches(body)) {
        wanted.add(Mentions.identityId(match.group(1)!));
      }
    }
    if (wanted.isEmpty) return const {};
    final found = await people.identitiesByIds(org, wanted);
    return {
      for (final entry in found.entries)
        if (entry.value.displayName.trim().isNotEmpty)
          entry.key: entry.value.displayName,
    };
  }
}

/// A pull request reviewer as a person the picker can offer.
extension PrReviewerIdentity on PrReviewer {
  IdentityRef get identity => IdentityRef(
    displayName: displayName,
    uniqueName: uniqueName,
    id: id.isEmpty ? null : id,
    imageUrl: imageUrl,
    descriptor: descriptor,
  );
}
