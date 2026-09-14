import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/git_repository.dart';
import '../models/pull_request.dart';
import '../models/search.dart';
import 'pull_request_repository.dart';

/// A search answer with when it was read, for the "showing the cached copy"
/// line the pages draw.
typedef CachedSearch<T> = ({T value, DateTime fetchedAt});

/// Search across one organization: work items and code through the Search
/// service (`almsearch`), pull requests matched on the device.
///
/// Design and decisions in research/15; the wire shapes come from spike s44.
/// Three things are worth knowing before reading on:
///
/// * **Project scope travels in the body, not the path.** The service accepts
///   either, but `filters.System.TeamProject` means the project scope and the
///   All-projects scope are the same call with one filter more, so there is
///   one code path and one cache key shape for both (decision D1).
/// * **Every API read is cached** under a key built from everything that
///   changes the answer, so a re-opened search paints from the cache first
///   and an offline phone still sees the last answer. At most
///   [maxCacheEntries] searches are kept per account; the oldest goes.
/// * **The minimum term length is ours, not the service's** — s44 showed a
///   two-character term answering `count: 0` rather than an error, which
///   would look like "nothing matched" while the user is still typing.
class SearchRepository {
  SearchRepository(
    this._client,
    this._pullRequests, [
    AppDatabase? db,
    String? userId,
  ]) : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final PullRequestRepository _pullRequests;
  final JsonCache _cache;

  static const apiVersion = '7.1';

  /// Shorter than this and nothing is sent: the service would answer a happy
  /// "no results" to a half-typed word (spike s44).
  static const minLength = 3;

  /// Results per page, matching the See-all list's paging (research/15 §3).
  static const pageSize = 50;

  /// Active pull requests scanned for a local match; the org list the app
  /// already fetches is capped at the same number.
  static const pullRequestScan = 100;

  /// Searches kept per account. A query is a few kilobytes of JSON, and the
  /// cache exists to reopen the last searches, not to be a search index.
  static const maxCacheEntries = 30;

  static const workItemKind = 'wi';
  static const codeKind = 'code';

  /// The eviction index: the cached search keys, oldest first. Not itself a
  /// tracked entry.
  static const indexKey = 'search:index';

  /// Everything that changes an answer, in one key:
  /// `search:{kind}:{org}:{project|*}:{order}:{skip}:{types|states|repo}:{text}`.
  ///
  /// The text is trimmed and lower-cased (the service is case-insensitive),
  /// and the filter lists are sorted, so picking two chips in either order
  /// hits the same entry.
  static String cacheKey({
    required String kind,
    required String org,
    String? project,
    required String text,
    List<String> types = const [],
    List<String> states = const [],
    String? repository,
    SearchOrder order = SearchOrder.relevance,
    int skip = 0,
  }) {
    String list(List<String> values) => (values.toList()..sort()).join(',');
    final filters = '${list(types)}|${list(states)}|${repository ?? ''}';
    return 'search:$kind:$org:${project ?? '*'}:${order.name}:$skip:'
        '$filters:${text.trim().toLowerCase()}';
  }

  /// True when [text] is long enough to send (see [minLength]).
  static bool isSearchable(String text) => text.trim().length >= minLength;

  // ------------------------------------------------------------ work items

  /// `POST search/workitemsearchresults` over the organization, narrowed to
  /// [project] and to the picked type and state chips by body filters.
  Future<SearchResults<WorkItemSearchHit>> searchWorkItems(
    String org, {
    String? project,
    required String text,
    List<String> types = const [],
    List<String> states = const [],
    int skip = 0,
    SearchOrder order = SearchOrder.relevance,
  }) async {
    if (!isSearchable(text)) return const SearchResults<WorkItemSearchHit>();
    final json = await _client.send(
      method: 'POST',
      host: AdoHost.search,
      org: org,
      path: '_apis/search/workitemsearchresults',
      apiVersion: apiVersion,
      body: {
        'searchText': text.trim(),
        r'$skip': skip,
        r'$top': pageSize,
        'includeFacets': true,
        'filters': {
          if (project != null) 'System.TeamProject': [project],
          if (types.isNotEmpty) 'System.WorkItemType': types,
          if (states.isNotEmpty) 'System.State': states,
        },
        if (order == SearchOrder.changedDate)
          r'$orderBy': [
            {'field': 'system.changeddate', 'sortOrder': 'DESC'},
          ],
      },
    );
    await _store(
      cacheKey(
        kind: workItemKind,
        org: org,
        project: project,
        text: text,
        types: types,
        states: states,
        order: order,
        skip: skip,
      ),
      json,
    );
    return SearchResults.fromJson(json, WorkItemSearchHit.fromJson, skip: skip);
  }

  /// The last answer stored for exactly this query, or null.
  Future<CachedSearch<SearchResults<WorkItemSearchHit>>?> cachedWorkItems(
    String org, {
    String? project,
    required String text,
    List<String> types = const [],
    List<String> states = const [],
    int skip = 0,
    SearchOrder order = SearchOrder.relevance,
  }) => _cached(
    cacheKey(
      kind: workItemKind,
      org: org,
      project: project,
      text: text,
      types: types,
      states: states,
      order: order,
      skip: skip,
    ),
    (json) =>
        SearchResults.fromJson(json, WorkItemSearchHit.fromJson, skip: skip),
  );

  // ------------------------------------------------------------------ code

  /// `POST search/codesearchresults`, org-wide when [project] is null.
  ///
  /// Moved here from `RepoRepository` (research/15 §5): the only change is
  /// that the project is optional, so the All-projects scope works, and that
  /// the answer is cached like every other search. A repository filter still
  /// has to come with a project filter (spike s17), so [repositoryName]
  /// without [project] is a caller error.
  Future<CodeSearchResults> searchCode(
    String org, {
    String? project,
    required String text,
    String? repositoryName,
    int skip = 0,
  }) async {
    assert(
      repositoryName == null || project != null,
      'A repository filter needs its project (spike s17)',
    );
    if (!isSearchable(text)) {
      return const CodeSearchResults(count: 0, hits: [], infoCode: 0);
    }
    final Map<String, dynamic> json;
    try {
      json = await _client.send(
        method: 'POST',
        host: AdoHost.search,
        org: org,
        path: '_apis/search/codesearchresults',
        apiVersion: apiVersion,
        body: {
          'searchText': text.trim(),
          r'$skip': skip,
          r'$top': pageSize,
          'filters': {
            if (project != null) 'Project': [project],
            if (repositoryName != null) 'Repository': [repositoryName],
          },
          'includeFacets': false,
        },
      );
    } on AdoNotFoundException catch (e) {
      // The search host has no other 404: the extension is not installed.
      throw CodeSearchUnavailable(statusCode: e.statusCode, url: e.url);
    }
    await _store(
      cacheKey(
        kind: codeKind,
        org: org,
        project: project,
        text: text,
        repository: repositoryName,
        skip: skip,
      ),
      json,
    );
    return CodeSearchResults.fromJson(json);
  }

  Future<CachedSearch<CodeSearchResults>?> cachedCode(
    String org, {
    String? project,
    required String text,
    String? repositoryName,
    int skip = 0,
  }) => _cached(
    cacheKey(
      kind: codeKind,
      org: org,
      project: project,
      text: text,
      repository: repositoryName,
      skip: skip,
    ),
    CodeSearchResults.fromJson,
  );

  // ---------------------------------------------------------- pull requests

  /// Active pull requests of the organization whose title, branch or author
  /// contains [text] (decision D7: there is no pull request search API).
  ///
  /// The list is the one the inbox already reads and caches, so a match is
  /// instant on a warm cache and still works offline.
  Future<SearchResults<PullRequestSearchHit>> searchPullRequests(
    String org, {
    String? project,
    required String text,
  }) async {
    if (!isSearchable(text)) return const SearchResults<PullRequestSearchHit>();
    List<PullRequest> all;
    try {
      all = await _pullRequests.list(
        org,
        filter: PrListFilter.all,
        status: 'active',
        top: pullRequestScan,
      );
    } on AdoNetworkException {
      // Offline: the inbox's last list is better than an error, and it is
      // the same list this would have fetched.
      final cached = await _pullRequests.cachedList(
        org,
        filter: PrListFilter.all,
      );
      if (cached == null) rethrow;
      all = cached.items;
    }
    return _matchPullRequests(all, project: project, text: text);
  }

  /// The same match over the cached active list, without a call.
  Future<SearchResults<PullRequestSearchHit>?> cachedPullRequests(
    String org, {
    String? project,
    required String text,
  }) async {
    if (!isSearchable(text)) return null;
    final cached = await _pullRequests.cachedList(
      org,
      filter: PrListFilter.all,
    );
    if (cached == null) return null;
    return _matchPullRequests(cached.items, project: project, text: text);
  }

  /// Title first, then branch, then author, each group keeping the order the
  /// list came in (newest first). `List.sort` is not stable, so the original
  /// position is part of the comparison.
  static SearchResults<PullRequestSearchHit> _matchPullRequests(
    List<PullRequest> all, {
    String? project,
    required String text,
  }) {
    final needle = text.trim().toLowerCase();
    bool has(String? value) =>
        value != null && value.toLowerCase().contains(needle);
    final ranked = <(int, PullRequestSearchHit)>[];
    for (var i = 0; i < all.length; i++) {
      final pr = all[i];
      if (project != null &&
          pr.projectName != project &&
          pr.projectId != project) {
        continue;
      }
      final PrMatchField field;
      if (has(pr.title)) {
        field = PrMatchField.title;
      } else if (has(pr.sourceBranch) || has(pr.targetBranch)) {
        field = PrMatchField.branch;
      } else if (has(pr.createdBy.displayName)) {
        field = PrMatchField.author;
      } else {
        continue;
      }
      ranked.add((i, PullRequestSearchHit(pullRequest: pr, match: field)));
    }
    ranked.sort((a, b) {
      final byField = a.$2.match.index.compareTo(b.$2.match.index);
      return byField != 0 ? byField : a.$1.compareTo(b.$1);
    });
    final items = [for (final r in ranked) r.$2];
    return SearchResults<PullRequestSearchHit>(
      items: items,
      total: items.length,
    );
  }

  // ----------------------------------------------------------------- cache

  Future<CachedSearch<T>?> _cached<T>(
    String key,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final hit = await _cache.get(key);
    final json = hit?.json;
    if (hit == null || json is! Map) return null;
    return (
      value: parse(json.cast<String, dynamic>()),
      fetchedAt: hit.fetchedAt,
    );
  }

  /// Writes one answer and keeps the account's search cache to
  /// [maxCacheEntries] entries, dropping the least recently written.
  Future<void> _store(String key, Object json) async {
    await _cache.put(key, json);
    final index = await _keys();
    index
      ..remove(key)
      ..add(key);
    while (index.length > maxCacheEntries) {
      await _cache.remove(index.removeAt(0));
    }
    await _cache.put(indexKey, index);
  }

  Future<List<String>> _keys() async {
    final stored = (await _cache.get(indexKey))?.json;
    if (stored is! List) return <String>[];
    return [for (final k in stored) k.toString()];
  }

  /// The cached search keys, oldest first. For tests and diagnostics.
  Future<List<String>> cachedKeys() => _keys();
}
