import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/http/ado_client.dart';
import '../db/app_database.dart';
import '../models/work_item.dart';

/// Work item reads and the one write the first milestone needs (a JSON
/// Patch guarded by `test /rev`). Lists are cached in drift under a key so
/// screens render from the cache and refresh behind a progress bar.
class WorkItemRepository {
  WorkItemRepository(this._client, this._db);

  final AdoClient _client;
  final AppDatabase _db;

  static const apiVersion = '7.1';
  static const commentsApiVersion = '7.1-preview.4';
  static const assignedToMeKey = 'assigned-to-me';
  static const recentlyUpdatedKey = 'recently-updated';
  static String queryKey(String queryId) => 'query:$queryId';

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
    await _db.transaction(() async {
      await (_db.delete(_db.workItemListEntries)..where(
            (t) =>
                t.orgName.equals(org) &
                t.project.equals(project) &
                t.listKey.equals(listKey),
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
                listKey: listKey,
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
    final query =
        (_db.select(entries)..where(
              (t) =>
                  t.orgName.equals(org) &
                  t.project.equals(project) &
                  t.listKey.equals(listKey),
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
      body: [
        {'op': 'test', 'path': '/rev', 'value': item.rev},
        ...ops,
      ],
      contentType: AdoClient.jsonPatchContentType,
    );
    final updated = WorkItem.fromJson(json);
    await _upsert(org, project, updated, DateTime.now());
    return updated;
  }
}
