import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/work_item.dart';

/// Work item reads and the one write the first milestone needs (a JSON
/// Patch guarded by `test /rev`). Lists are cached in drift under a key so
/// screens render from the cache and refresh behind a progress bar.
class WorkItemRepository {
  WorkItemRepository(this._client, this._db, {String? userId})
    : _listPrefix = userId == null ? '' : listPrefixFor(userId),
      _cache = JsonCache(_db, namespace: userId);

  final AdoClient _client;
  final AppDatabase _db;

  /// Small JSON blobs that are not work item lists (a saved query's
  /// definition), account-namespaced like every other cache.
  final JsonCache _cache;

  /// Lists are personal ("assigned to me") or permission-dependent, so
  /// their keys are prefixed with the account they were read as.
  final String _listPrefix;

  static String listPrefixFor(String userId) => '$userId/';

  static const apiVersion = '7.1';
  static const commentsApiVersion = '7.1-preview.4';
  static const assignedToMeKey = 'assigned-to-me';
  static const recentlyUpdatedKey = 'recently-updated';
  static String queryKey(String queryId) => 'query:$queryId';

  /// A saved query's definition, which the dashboard's query-backed widgets
  /// read before they run it.
  static String queryMetaKey(String queryId) => 'query:meta:$queryId';

  /// A query's shape changes when somebody edits it, which is rare.
  static const queryMetaTtl = Duration(hours: 24);

  /// Fields every list and card needs. Kept to System.* plus Priority so the
  /// batch never names a field a process does not have (that is a 400).
  static const listFields = <String>[
    'System.Id',
    'System.Rev',
    'System.WorkItemType',
    'System.Title',
    'System.State',
    'System.Reason',
    'System.AssignedTo',
    'System.ChangedDate',
    'System.CreatedDate',
    'System.AreaPath',
    'System.IterationPath',
    'System.Tags',
    'System.TeamProject',
    'System.BoardColumn',
    'System.BoardColumnDone',
    'Microsoft.VSTS.Common.Priority',
  ];

  final Map<String, (DateTime, List<WorkItemType>)> _types = {};

  /// `POST wiql`: ids only, in query order. Silently capped by the service
  /// at 20,000; we ask for [top].
  Future<List<int>> queryIds(
    String org,
    String project,
    String wiql, {
    int top = 200,
  }) async {
    final json = await _client.send(
      method: 'POST',
      org: org,
      project: project,
      path: '_apis/wit/wiql',
      apiVersion: apiVersion,
      query: {r'$top': '$top'},
      body: {'query': wiql},
    );
    return ((json['workItems'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m['id'] as int)
        .toList();
  }

  /// `POST workitemsbatch` in chunks of 200 with `errorPolicy: omit`.
  Future<List<WorkItem>> batch(
    String org,
    String project,
    List<int> ids, {
    List<String> fields = listFields,
  }) async {
    final out = <WorkItem>[];
    for (var i = 0; i < ids.length; i += 200) {
      final chunk = ids.sublist(i, i + 200 > ids.length ? ids.length : i + 200);
      final json = await _client.send(
        method: 'POST',
        org: org,
        project: project,
        path: '_apis/wit/workitemsbatch',
        apiVersion: apiVersion,
        body: {'ids': chunk, 'fields': fields, 'errorPolicy': 'omit'},
      );
      out.addAll(
        ((json['value'] as List?) ?? const []).whereType<Map>().map(
          (m) => WorkItem.fromJson(m.cast<String, dynamic>()),
        ),
      );
    }
    // Keep the query's order.
    final index = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    out.sort((a, b) => (index[a.id] ?? 0).compareTo(index[b.id] ?? 0));
    return out;
  }

  static String assignedToMeWiql() =>
      'SELECT [System.Id] FROM WorkItems '
      'WHERE [System.TeamProject] = @project AND [System.AssignedTo] = @Me '
      "AND [System.State] <> 'Closed' AND [System.State] <> 'Removed' "
      "AND [System.State] <> 'Done' "
      'ORDER BY [System.ChangedDate] DESC';

  Future<List<WorkItem>> refreshAssignedToMe(String org, String project) =>
      _refreshWiql(org, project, assignedToMeKey, assignedToMeWiql());

  static String recentlyUpdatedWiql({int days = 7}) =>
      'SELECT [System.Id] FROM WorkItems '
      'WHERE [System.TeamProject] = @project '
      'AND [System.ChangedDate] >= @Today - $days '
      "AND [System.State] <> 'Removed' "
      'ORDER BY [System.ChangedDate] DESC';

  Future<List<WorkItem>> refreshRecentlyUpdated(String org, String project) =>
      _refreshWiql(org, project, recentlyUpdatedKey, recentlyUpdatedWiql());

  Future<List<WorkItem>> _refreshWiql(
    String org,
    String project,
    String listKey,
    String wiql,
  ) async {
    final ids = await queryIds(org, project, wiql);
    final items = ids.isEmpty ? <WorkItem>[] : await batch(org, project, ids);
    await storeList(org, project, listKey, items);
    return items;
  }

  /// The query tree two levels deep: My Queries and Shared Queries with
  /// their folders and queries.
  Future<List<SavedQuery>> queries(String org, String project) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/wit/queries',
      apiVersion: apiVersion,
      query: {r'$depth': '2', r'$expand': 'none'},
    );
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => SavedQuery.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// Ids from a `wiql/{id}` result: flat queries list `workItems`, tree and
  /// one-hop queries list `workItemRelations` whose targets are the items.
  static List<int> idsFromQueryResult(Map<String, dynamic> json) {
    final seen = <int>{};
    final out = <int>[];
    void add(Object? id) {
      if (id is int && seen.add(id)) out.add(id);
    }

    for (final w
        in ((json['workItems'] as List?) ?? const []).whereType<Map>()) {
      add(w['id']);
    }
    for (final r
        in ((json['workItemRelations'] as List?) ?? const [])
            .whereType<Map>()) {
      add((r['target'] as Map?)?['id']);
    }
    return out;
  }

  /// Runs a saved query by id and caches the result under `query:{id}`.
  Future<List<WorkItem>> refreshQuery(
    String org,
    String project,
    String queryId, {
    int top = 200,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/wit/wiql/$queryId',
      apiVersion: apiVersion,
      query: {r'$top': '$top'},
    );
    final ids = idsFromQueryResult(json);
    final items = ids.isEmpty ? <WorkItem>[] : await batch(org, project, ids);
    await storeList(org, project, queryKey(queryId), items);
    return items;
  }

  /// Replaces the members of a list and upserts the items.
  Future<void> storeList(
    String org,
    String project,
    String listKey,
    List<WorkItem> items,
  ) async {
    final now = DateTime.now();
    final key = _listPrefix + listKey;
    await _db.transaction(() async {
      await (_db.delete(_db.workItemListEntries)..where(
            (t) =>
                t.orgName.equals(org) &
                t.project.equals(project) &
                t.listKey.equals(key),
          ))
          .go();
      for (var i = 0; i < items.length; i++) {
        await _upsert(org, project, items[i], now);
        await _db
            .into(_db.workItemListEntries)
            .insertOnConflictUpdate(
              WorkItemListEntriesCompanion.insert(
                orgName: org,
                project: project,
                listKey: key,
                workItemId: items[i].id,
                position: i,
              ),
            );
      }
    });
  }

  Future<void> _upsert(
    String org,
    String project,
    WorkItem item,
    DateTime now,
  ) async {
    // A list read carries fewer fields than a detail read; never let it
    // erase a richer cached copy of the same revision.
    final existing =
        await (_db.select(_db.workItems)
              ..where((t) => t.orgName.equals(org) & t.id.equals(item.id)))
            .getSingleOrNull();
    var merged = item;
    if (existing != null && existing.rev == item.rev) {
      final old = WorkItem.fromJson(
        (jsonDecode(existing.json) as Map).cast<String, dynamic>(),
      );
      merged = WorkItem(
        id: item.id,
        rev: item.rev,
        url: item.url ?? old.url,
        fields: {...old.fields, ...item.fields},
        multilineFieldsFormat: item.multilineFieldsFormat.isEmpty
            ? old.multilineFieldsFormat
            : item.multilineFieldsFormat,
        // A list read carries no relations either; keep the ones the detail
        // read stored for this revision.
        relations: item.relations.isEmpty ? old.relations : item.relations,
      );
    }
    await _db
        .into(_db.workItems)
        .insertOnConflictUpdate(
          WorkItemsCompanion.insert(
            orgName: org,
            id: merged.id,
            project: project,
            rev: merged.rev,
            json: jsonEncode(merged.toJson()),
            changedDate: Value(merged.changedDate),
            fetchedAt: now,
          ),
        );
  }

  Stream<List<WorkItem>> watchList(String org, String project, String listKey) {
    final entries = _db.workItemListEntries;
    final items = _db.workItems;
    final key = _listPrefix + listKey;
    final query =
        (_db.select(entries)..where(
              (t) =>
                  t.orgName.equals(org) &
                  t.project.equals(project) &
                  t.listKey.equals(key),
            ))
            .join([
              innerJoin(
                items,
                items.id.equalsExp(entries.workItemId) &
                    items.orgName.equalsExp(entries.orgName),
              ),
            ])
          ..orderBy([OrderingTerm.asc(entries.position)]);
    return query.watch().map(
      (rows) => rows
          .map(
            (r) => WorkItem.fromJson(
              (jsonDecode(r.readTable(items).json) as Map)
                  .cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }

  Stream<WorkItem?> watchItem(String org, int id) =>
      (_db.select(_db.workItems)
            ..where((t) => t.orgName.equals(org) & t.id.equals(id)))
          .watchSingleOrNull()
          .map(
            (r) => r == null
                ? null
                : WorkItem.fromJson(
                    (jsonDecode(r.json) as Map).cast<String, dynamic>(),
                  ),
          );

  /// Full read without a `fields` filter so `multilineFieldsFormat` and
  /// relations come back (spike S5b).
  Future<WorkItem> refreshItem(String org, String project, int id) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/wit/workitems/$id',
      apiVersion: apiVersion,
      query: {r'$expand': 'all'},
    );
    final item = WorkItem.fromJson(json);
    await _upsert(org, project, item, DateTime.now());
    return item;
  }

  /// Comments, newest first, with the server-rendered HTML.
  Future<List<WorkItemComment>> comments(
    String org,
    String project,
    int id, {
    int top = 200,
  }) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/wit/workItems/$id/comments',
      apiVersion: commentsApiVersion,
      query: {r'$expand': 'renderedText', 'order': 'desc', r'$top': '$top'},
    );
    return ((json['comments'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => WorkItemComment.fromJson(m.cast<String, dynamic>()))
        .where((c) => c.text.isNotEmpty || c.renderedText.isNotEmpty)
        .toList();
  }

  /// `POST comments?format=markdown` (spike w01): the service stores the
  /// Markdown and returns the rendered HTML.
  Future<WorkItemComment> addComment(
    String org,
    String project,
    int id,
    String text, {
    String format = 'markdown',
  }) async {
    final json = await _client.send(
      method: 'POST',
      org: org,
      project: project,
      path: '_apis/wit/workItems/$id/comments',
      apiVersion: commentsApiVersion,
      query: {'format': format},
      body: {'text': text},
    );
    return WorkItemComment.fromJson(json);
  }

  /// Sets plain fields (state, assignee, title…) in one guarded patch.
  Future<WorkItem> updateFields(
    String org,
    String project,
    WorkItem item,
    Map<String, Object?> values,
  ) => patch(org, project, item, [
    for (final e in values.entries)
      {'op': 'add', 'path': '/fields/${e.key}', 'value': e.value},
  ]);

  /// Work item types with their colors and icons, cached for a day.
  Future<List<WorkItemType>> types(String org, String project) async {
    final key = '$org/$project';
    final cached = _types[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(hours: 24)) {
      return cached.$2;
    }
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/wit/workitemtypes',
      apiVersion: apiVersion,
    );
    final types = ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => WorkItemType.fromJson(m.cast<String, dynamic>()))
        .where((t) => !t.isDisabled)
        .toList();
    _types[key] = (DateTime.now(), types);
    return types;
  }

  /// Puts one item (a fresh create, or a detail read made elsewhere) into
  /// the cache, merging with a richer copy of the same revision.
  Future<void> cacheItem(String org, String project, WorkItem item) =>
      _upsert(org, project, item, DateTime.now());

  /// Writes field values into the cached copy only (same rev), for changes
  /// that are queued while offline.
  Future<WorkItem> applyLocally(
    String org,
    String project,
    WorkItem item,
    Map<String, dynamic> values,
  ) async {
    final updated = item.copyWithFields(values);
    await _upsert(org, project, updated, DateTime.now());
    return updated;
  }

  /// JSON Patch guarded by `test /rev`; a stale revision is an
  /// [AdoStaleRevisionException] (HTTP 412) from the client.
  Future<WorkItem> patch(
    String org,
    String project,
    WorkItem item,
    List<Map<String, Object?>> ops,
  ) async {
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: project,
      path: '_apis/wit/workitems/${item.id}',
      apiVersion: apiVersion,
      // Without `$expand` the answer carries no relations, and because a
      // patch bumps `rev` the cache merge cannot keep the ones it had: the
      // links and attachments would vanish from the cached copy until the
      // next detail read, and a form that just wrote a relation would think
      // the write had not landed (phase 5).
      query: {r'$expand': 'relations'},
      body: [
        // The form's own patch (`buildEditOps`) already opens with the
        // guard; never send it twice.
        if (ops.isEmpty || ops.first['path'] != '/rev')
          {'op': 'test', 'path': '/rev', 'value': item.rev},
        ...ops,
      ],
      contentType: AdoClient.jsonPatchContentType,
    );
    final updated = WorkItem.fromJson(json);
    await _upsert(org, project, updated, DateTime.now());
    return updated;
  }

  /// The artifact url of a pull request as a work item relation stores it.
  ///
  /// The separators are percent-encoded (`%2F`): the service stores `%2f`
  /// and accepts a plain `/` as a *second*, duplicate relation, so the app
  /// always writes the encoded form and matches case-insensitively
  /// (research/22 §1).
  static String pullRequestArtifactUrl(
    String projectId,
    String repositoryId,
    int pullRequestId,
  ) => 'vstfs:///Git/PullRequestId/$projectId%2F$repositoryId%2F$pullRequestId';

  /// True when [url] points at the same pull request, whichever separator
  /// and case the service stored it with.
  static bool _sameArtifact(String url, String artifactUrl) =>
      url.toLowerCase().replaceAll('%2f', '/') ==
      artifactUrl.toLowerCase().replaceAll('%2f', '/');

  /// Links a pull request to a work item. `POST pullRequests/{id}/workitems`
  /// is HTTP 405 (spike w39 §5): the link is a work item write.
  ///
  /// [project] is only the scope the answer is cached under; the route
  /// itself is happy with the project GUID.
  Future<WorkItem> linkPullRequest(
    String org,
    int workItemId,
    String projectId,
    String repositoryId,
    int pullRequestId, {
    String? project,
  }) async {
    final scope = project ?? projectId;
    final item = await refreshItem(org, scope, workItemId);
    final url = pullRequestArtifactUrl(projectId, repositoryId, pullRequestId);
    // Already linked: the service would take a duplicate relation happily.
    if (item.relations.any(
      (r) =>
          r.rel == WorkItemRelation.artifactLinkRel &&
          _sameArtifact(r.url, url),
    )) {
      return item;
    }
    return patch(org, scope, item, [
      {
        'op': 'add',
        'path': '/relations/-',
        'value': {
          'rel': WorkItemRelation.artifactLinkRel,
          'url': url,
          'attributes': {'name': 'Pull Request'},
        },
      },
    ]);
  }

  /// Removes the link by index, which is the only way json-patch addresses a
  /// relation; the index comes from a fresh `$expand=relations` read so it
  /// cannot be stale, and the `test /rev` guard in [patch] catches the race.
  Future<WorkItem> unlinkPullRequest(
    String org,
    int workItemId,
    String projectId,
    String repositoryId,
    int pullRequestId, {
    String? project,
  }) async {
    final scope = project ?? projectId;
    final item = await refreshItem(org, scope, workItemId);
    final url = pullRequestArtifactUrl(projectId, repositoryId, pullRequestId);
    final index = item.relations.indexWhere(
      (r) =>
          r.rel == WorkItemRelation.artifactLinkRel &&
          _sameArtifact(r.url, url),
    );
    // Nothing to remove is not an error: the link may have gone from the
    // web while the page was open.
    if (index < 0) return item;
    return patch(org, scope, item, [
      {'op': 'remove', 'path': '/relations/$index'},
    ]);
  }

  /// One saved query's definition, cached under `query:meta:{id}`.
  ///
  /// `$expand=wiql` is the smallest expansion that carries `queryType` and
  /// `columns` (spike s60: 0.006 TSTU); `$expand=none` carries neither, and
  /// the query-backed dashboard widgets need the type to know whether the
  /// result is rows or relations.
  Future<SavedQueryMeta> queryMeta(
    String org,
    String project,
    String queryId, {
    bool refresh = false,
  }) async {
    final key = queryMetaKey(queryId);
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null &&
          DateTime.now().difference(hit.fetchedAt) < queryMetaTtl) {
        final cached = _tryQueryMeta(hit.json);
        if (cached != null) return cached;
      }
    }
    try {
      final json = await _client.getJson(
        org: org,
        project: project,
        path: '_apis/wit/queries/$queryId',
        apiVersion: apiVersion,
        query: const {r'$expand': 'wiql'},
      );
      await _cache.put(key, json);
      return SavedQueryMeta.fromJson(json);
    } on AdoAuthException {
      rethrow;
    } on AdoException {
      final stale = await _cache.get(key);
      final cached = stale == null ? null : _tryQueryMeta(stale.json);
      if (cached != null) return cached;
      rethrow;
    }
  }

  /// How many work items a saved query returns, without fetching their ids.
  ///
  /// `HEAD wiql/{id}` answers `X-Total-Count` and no body — the only ids-free
  /// count the service offers (spike s60; `$top=0` is a 400). Not every proxy
  /// or future API version has to honour a HEAD, so a missing or unparsable
  /// header falls back to the ordinary GET and counts the ids it returns,
  /// which is what [refreshQuery] already does for the rows themselves.
  Future<int> queryCount(
    String org,
    String project,
    String queryId, {
    int top = 200,
  }) async {
    final uri = AdoClient.buildUri(
      host: AdoHost.core,
      path: '_apis/wit/wiql/$queryId',
      apiVersion: apiVersion,
      org: org,
      project: project,
    );
    try {
      final response = await _client.sendRaw(method: 'HEAD', uri: uri);
      final header = response.headers.value('X-Total-Count');
      final count = int.tryParse(header ?? '');
      if (count != null) return count;
    } on AdoAuthException {
      rethrow;
    } on AdoException {
      // Fall through to the GET: a service that refuses HEAD is not a
      // failure of the card.
    }
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/wit/wiql/$queryId',
      apiVersion: apiVersion,
      query: {r'$top': '$top'},
    );
    return idsFromQueryResult(json).length;
  }

  SavedQueryMeta? _tryQueryMeta(Object? json) {
    if (json is! Map) return null;
    try {
      return SavedQueryMeta.fromJson(json.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}
