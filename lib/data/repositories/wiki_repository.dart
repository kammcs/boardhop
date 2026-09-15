import 'dart:typed_data';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/git_repository.dart';
import '../models/wiki.dart';
import 'repo_repository.dart';

/// A cached page with the time it was read, for the "Updated N min ago"
/// line the reader shows above a cache-first open (K7).
typedef CachedWikiPage = ({WikiPage page, DateTime fetchedAt});

/// The Wiki hub's reads (research/20 §4.1). **Reads only**: editing is out
/// of v1 (§6), so nothing here writes.
///
/// Four facts from the spikes shape this class:
///
/// * **The tree call carries no ids.** `pages?path=/&recursionLevel=full`
///   answers the whole tree in one request, `POST pagesbatch` answers the
///   ids, and the two are joined on `path` — never by deriving one path form
///   from the other (research/01 §8, research/20 §1).
/// * **The `ETag` header is the page's git blob SHA**, and the service
///   ignores `If-None-Match` (it always answers 200), so it is a
///   client-side change key that has to be lifted off the response and
///   stored with the body.
/// * **Attachments have no wiki route.** `/.attachments/x.png` is a file in
///   the wiki's git repository and comes back through the Items API with
///   the bearer token, which `RepoRepository.fileBytes` already does.
/// * **A 401 on the wiki routes is not always a sign-out** — see
///   [WikiUnavailable].
class WikiRepository {
  WikiRepository(this._client, this._repos, [AppDatabase? db, String? userId])
    : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final RepoRepository _repos;
  final JsonCache _cache;

  /// Every wiki route is released at 7.1; none of them needs a preview
  /// version (spike s62).
  static const apiVersion = '7.1';

  /// A project gains or loses a wiki about as often as it gains a
  /// repository.
  static const listTtl = Duration(hours: 24);

  /// The tree is one cheap call (0.07 TSTU for 134 pages) but it is what a
  /// cold, offline open draws, so it is kept for a day and refreshed by
  /// pull-to-refresh.
  static const treeTtl = Duration(hours: 24);

  /// Page content is the one thing that changes under a reader; an hour is
  /// short enough that a re-open is current and long enough that walking
  /// back up a tree costs nothing.
  static const pageTtl = Duration(hours: 1);

  /// The footer's "last changed" line (K9).
  static const changeTtl = Duration(hours: 1);

  /// `pagesbatch` page size. The service caps `top` at 100.
  static const batchSize = 100;

  /// A stop for the continuation loop: 100 pages of [batchSize] is 10 000
  /// pages, far past the largest wiki, and a server that kept handing back
  /// a fresh token would otherwise spin forever.
  static const maxBatchPages = 100;

  static String listKey(String org, String project) =>
      'wiki:list:$org:$project';

  static String treeKey(
    String org,
    String project,
    String wikiId, {
    String? version,
  }) =>
      'wiki:tree:$org:$project:$wikiId'
      '${version == null || version.isEmpty ? '' : ':$version'}';

  /// Keyed by path when the path is known and by `#id` when it is not; a
  /// read by id stores under both, so the next open from the tree hits the
  /// cache (K7).
  static String pageKey(
    String org,
    String project,
    String wikiId, {
    String? path,
    int? id,
    String? version,
  }) {
    final suffix = version == null || version.isEmpty ? '' : ':$version';
    final leaf = path != null && path.isNotEmpty ? path : '#$id';
    return 'wiki:page:$org:$project:$wikiId:$leaf$suffix';
  }

  static String changeKey(
    String org,
    String project,
    String wikiId,
    String gitItemPath, {
    String? version,
  }) =>
      'wiki:change:$org:$project:$wikiId:$gitItemPath'
      '${version == null || version.isEmpty ? '' : ':$version'}';

  // ---------------------------------------------------------------- wikis

  /// Every wiki of the project, project wiki first.
  Future<List<Wiki>> wikis(
    String org,
    String project, {
    bool refresh = false,
  }) => _cached<List<Wiki>>(
    listKey(org, project),
    () => _wikiCall(
      () => _client.getJson(
        org: org,
        project: project,
        path: '_apis/wiki/wikis',
        apiVersion: apiVersion,
      ),
    ),
    _parseWikis,
    refresh: refresh,
    maxAge: listTtl,
  );

  /// The cached wiki list without touching the network, for a first paint
  /// while the refresh is in flight.
  Future<List<Wiki>?> cachedWikis(String org, String project) async {
    final hit = await _cache.get(listKey(org, project));
    if (hit == null) return null;
    return _tryParse(hit.json, _parseWikis)?.$1;
  }

  static List<Wiki> _parseWikis(Object? json) {
    final wikis = [
      for (final w in _values(json))
        if (w is Map) Wiki.fromJson(w.cast<String, dynamic>()),
    ];
    // The project wiki is the one a project has at most one of and the one
    // the picker opens by default (K1).
    wikis.sort((a, b) {
      if (a.isProjectWiki != b.isProjectWiki) return a.isProjectWiki ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return wikis;
  }

  // ----------------------------------------------------------------- tree

  /// The whole page tree with ids: one `recursionLevel=full` call for the
  /// structure, `pagesbatch` paged for the ids, joined on `path`.
  ///
  /// The root node is returned; its [WikiPageNode.subPages] are the
  /// top-level pages.
  Future<WikiPageNode> tree(
    String org,
    String project,
    String wikiId, {
    String? version,
    bool refresh = false,
  }) => _cached<WikiPageNode>(
    treeKey(org, project, wikiId, version: version),
    () => _fetchTree(org, project, wikiId, version: version),
    (json) => WikiPageNode.fromJson(_asMap(json)),
    refresh: refresh,
    maxAge: treeTtl,
  );

  Future<WikiPageNode?> cachedTree(
    String org,
    String project,
    String wikiId, {
    String? version,
  }) async {
    final hit = await _cache.get(
      treeKey(org, project, wikiId, version: version),
    );
    if (hit == null) return null;
    return _tryParse(
      hit.json,
      (json) => WikiPageNode.fromJson(_asMap(json)),
    )?.$1;
  }

  Future<Object> _fetchTree(
    String org,
    String project,
    String wikiId, {
    String? version,
  }) async {
    final json = await _wikiCall(
      () => _client.getJson(
        org: org,
        project: project,
        path: '_apis/wiki/wikis/$wikiId/pages',
        apiVersion: apiVersion,
        query: {
          'path': '/',
          'recursionLevel': 'full',
          'includeContent': 'false',
          ..._versionQuery(version),
        },
      ),
    );
    final root = WikiPageNode.fromJson(json);
    final ids = await _pageIds(org, project, wikiId, version: version);
    return root.withIds(ids).toJson();
  }

  /// Every page's id, by path, from `POST pagesbatch`.
  ///
  /// The continuation token rides in the `x-ms-continuationtoken`
  /// **response header**, not in the body; the loop stops when it is
  /// missing or repeats.
  Future<Map<String, int>> _pageIds(
    String org,
    String project,
    String wikiId, {
    String? version,
  }) async {
    final byPath = <String, int>{};
    String? token;
    for (var page = 0; page < maxBatchPages; page++) {
      final uri = AdoClient.buildUri(
        host: AdoHost.core,
        org: org,
        project: project,
        path: '_apis/wiki/wikis/$wikiId/pagesbatch',
        apiVersion: apiVersion,
        query: _versionQuery(version),
      );
      final response = await _wikiCall(
        () => _client.sendRaw(
          method: 'POST',
          uri: uri,
          body: {'top': batchSize, 'continuationToken': ?token},
        ),
      );
      for (final row in _values(response.data)) {
        if (row is! Map) continue;
        final path = row['path'] as String?;
        final id = row['id'];
        if (path == null || path.isEmpty) continue;
        final value = id is num ? id.toInt() : int.tryParse('$id');
        if (value != null) byPath[path] = value;
      }
      final next = response.headers.value('x-ms-continuationtoken');
      if (next == null || next.isEmpty || next == token) break;
      token = next;
    }
    return byPath;
  }

  // ----------------------------------------------------------------- page

  /// One page with its markdown, by [path] (title form) or by [id].
  ///
  /// The `ETag` header is stored on the page as [WikiPage.etag]. A read by
  /// id is stored under the path key as well, and the other way round, so
  /// the next open finds it whichever the caller knows.
  Future<WikiPage> page(
    String org,
    String project,
    String wikiId, {
    String? path,
    int? id,
    String? version,
    bool refresh = false,
  }) async {
    assert(
      (path != null && path.isNotEmpty) || id != null,
      'a wiki page is read by path or by id',
    );
    final key = pageKey(
      org,
      project,
      wikiId,
      path: path,
      id: id,
      version: version,
    );
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null && DateTime.now().difference(hit.fetchedAt) < pageTtl) {
        final parsed = _tryParse(hit.json, _parsePage);
        if (parsed != null) return parsed.$1;
      }
    }
    try {
      final stored = await _fetchPage(
        org,
        project,
        wikiId,
        path: path,
        id: id,
        version: version,
      );
      await _cache.put(key, stored);
      final page = _parsePage(stored);
      await _alias(org, project, wikiId, page, stored, version: version);
      return page;
    } on AdoAuthException {
      rethrow;
    } on AdoException {
      final stale = await _cache.get(key);
      final parsed = stale == null ? null : _tryParse(stale.json, _parsePage);
      if (parsed != null) return parsed.$1;
      rethrow;
    }
  }

  /// The cached page and when it was read, so the reader can draw before
  /// the network answers and say how old what it drew is (K7).
  Future<CachedWikiPage?> cachedPage(
    String org,
    String project,
    String wikiId, {
    String? path,
    int? id,
    String? version,
  }) async {
    final hit = await _cache.get(
      pageKey(org, project, wikiId, path: path, id: id, version: version),
    );
    if (hit == null) return null;
    final parsed = _tryParse(hit.json, _parsePage);
    if (parsed == null) return null;
    return (page: parsed.$1, fetchedAt: hit.fetchedAt);
  }

  static WikiPage _parsePage(Object? json) => WikiPage.fromJson(_asMap(json));

  Future<Map<String, dynamic>> _fetchPage(
    String org,
    String project,
    String wikiId, {
    String? path,
    int? id,
    String? version,
  }) async {
    final byPath = path != null && path.isNotEmpty;
    final uri = AdoClient.buildUri(
      host: AdoHost.core,
      org: org,
      project: project,
      path: byPath
          ? '_apis/wiki/wikis/$wikiId/pages'
          : '_apis/wiki/wikis/$wikiId/pages/$id',
      apiVersion: apiVersion,
      query: {
        if (byPath) 'path': path,
        'includeContent': 'true',
        ..._versionQuery(version),
      },
    );
    final response = await _wikiCall(
      () => _client.sendRaw(method: 'GET', uri: uri),
    );
    final data = response.data;
    final json = data is Map
        ? data.cast<String, dynamic>()
        : <String, dynamic>{};
    final etag = response.headers.value('etag');
    return {...json, if (etag != null && etag.isNotEmpty) 'etag': etag};
  }

  /// Stores the answer under the key the caller did *not* use, so a page
  /// read by id is found by path afterwards and the other way round.
  Future<void> _alias(
    String org,
    String project,
    String wikiId,
    WikiPage page,
    Map<String, dynamic> stored, {
    String? version,
  }) async {
    if (page.path.isNotEmpty) {
      await _cache.put(
        pageKey(org, project, wikiId, path: page.path, version: version),
        stored,
      );
    }
    if (page.id != null) {
      await _cache.put(
        pageKey(org, project, wikiId, id: page.id, version: version),
        stored,
      );
    }
  }

  // ---------------------------------------------------------- attachments

  /// The bytes of `/.attachments/name.png`: a file in the wiki's git
  /// repository, read with the bearer token. There is no wiki route for it
  /// (research/20 §1).
  Future<Uint8List> attachmentBytes(
    String org,
    String project,
    Wiki wiki,
    String path,
  ) => _repos.fileBytes(
    org,
    project,
    wiki.repositoryId,
    ref: wiki.version,
    path: repositoryPath(wiki, path),
  );

  /// The same file as a URL, for `CachedNetworkImageProvider(url, headers)`
  /// so an image in a page goes through the disk cache (K7).
  Uri attachmentUri(String org, String project, Wiki wiki, String path) =>
      AdoClient.buildUri(
        host: AdoHost.core,
        org: org,
        project: project,
        path: '_apis/git/repositories/${wiki.repositoryId}/items',
        apiVersion: apiVersion,
        query: {
          'path': repositoryPath(wiki, path),
          r'$format': 'octetStream',
          'download': 'false',
          ...GitVersion.query(wiki.version),
        },
      );

  /// A wiki path as a path in the wiki's repository.
  ///
  /// A project wiki is published from the repository root, so the two are
  /// the same. A **code wiki** is published from [Wiki.mappedPath], and a
  /// page's `/…` is relative to that folder, so the folder is prefixed
  /// (K8 — unverified: no code wiki exists in puremedia).
  static String repositoryPath(Wiki wiki, String path) {
    var p = path.trim();
    if (!p.startsWith('/')) p = '/$p';
    if (!wiki.hasMappedPath) return p;
    var prefix = wiki.mappedPath.trim();
    if (!prefix.startsWith('/')) prefix = '/$prefix';
    while (prefix.length > 1 && prefix.endsWith('/')) {
      prefix = prefix.substring(0, prefix.length - 1);
    }
    if (p.toLowerCase() == prefix.toLowerCase() ||
        p.toLowerCase().startsWith('${prefix.toLowerCase()}/')) {
      return p;
    }
    return '$prefix$p';
  }

  // ----------------------------------------------------------- last change

  /// The last commit that touched a page's markdown file, for the K9 footer
  /// line. Null when the file has no history the caller can see.
  Future<WikiPageChange?> lastChange(
    String org,
    String project,
    Wiki wiki,
    String gitItemPath, {
    String? version,
  }) async {
    if (gitItemPath.trim().isEmpty) return null;
    final ref = version == null || version.isEmpty ? wiki.version : version;
    return _cached<WikiPageChange?>(
      changeKey(org, project, wiki.id, gitItemPath, version: ref),
      () => _client.getJson(
        org: org,
        project: project,
        path: '_apis/git/repositories/${wiki.repositoryId}/commits',
        apiVersion: apiVersion,
        query: {
          'searchCriteria.itemPath': gitItemPath,
          r'searchCriteria.$top': '1',
          ...GitVersion.query(ref, prefix: 'searchCriteria.itemVersion'),
        },
      ),
      _parseChange,
      maxAge: changeTtl,
    );
  }

  static WikiPageChange? _parseChange(Object? json) {
    final first = _values(json).whereType<Map>().firstOrNull;
    if (first == null) return null;
    final change = WikiPageChange.fromJson(first.cast<String, dynamic>());
    return change.isEmpty ? null : change;
  }

  // -------------------------------------------------------------- parsing

  static Map<String, dynamic> _asMap(Object? json) => switch (json) {
    Map() => json.cast<String, dynamic>(),
    _ => const <String, dynamic>{},
  };

  static List<Object?> _values(Object? json) => switch (json) {
    List() => json,
    Map() => (json['value'] as List?) ?? const [],
    _ => const [],
  };

  /// `versionDescriptor.version={branch}` when a code wiki's branch, or a
  /// caller, names one (K8). A project wiki has exactly one version and the
  /// service picks it.
  ///
  /// The version travels **alone**: that is the form spike w37 verified on
  /// the wiki routes (a bad value there is a 500
  /// `GitUnresolvableToCommitException`, so the shape is worth keeping to),
  /// and `branch` is the default `versionType` anyway. The git routes an
  /// attachment goes through are a different matter — those use
  /// `GitVersion.query`, which spells the type out.
  static Map<String, String> _versionQuery(String? version) =>
      version == null || version.isEmpty
      ? const {}
      : {'versionDescriptor.version': version};

  // --------------------------------------------------------------- shared

  /// Runs a wiki call and turns the TF400813 refusal into [WikiUnavailable]
  /// so the page shows it inline instead of looping the sign-in sheet.
  Future<T> _wikiCall<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AdoAuthException catch (e) {
      if (WikiUnavailable.refuses(e)) {
        throw WikiUnavailable(statusCode: e.statusCode, url: e.url);
      }
      rethrow;
    }
  }

  Future<T> _cached<T>(
    String key,
    Future<Object> Function() fetch,
    T Function(Object? json) parse, {
    bool refresh = false,
    Duration maxAge = listTtl,
  }) async {
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null && DateTime.now().difference(hit.fetchedAt) < maxAge) {
        final parsed = _tryParse(hit.json, parse);
        if (parsed != null) return parsed.$1;
      }
    }
    try {
      final raw = await fetch();
      await _cache.put(key, raw);
      return parse(raw);
    } on AdoAuthException {
      // Sign-in is needed; never mask that with a stale copy.
      rethrow;
    } on AdoException {
      final stale = await _cache.get(key);
      final parsed = stale == null ? null : _tryParse(stale.json, parse);
      if (parsed != null) return parsed.$1;
      rethrow;
    }
  }

  static (T,)? _tryParse<T>(Object? json, T Function(Object? json) parse) {
    try {
      return (parse(json),);
    } catch (_) {
      return null;
    }
  }
}
