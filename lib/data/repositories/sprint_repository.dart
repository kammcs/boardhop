import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/sprint.dart';
import '../models/work_item.dart';
import '../models/work_item_form.dart';
import 'board_repository.dart';
import 'work_item_form_repository.dart';
import 'work_item_repository.dart';

/// The sprint (Sprints hub) data layer: iterations, taskboard columns, the
/// sprint's rows and cards, capacity, and the four writes decision S3 allows
/// (move a task, set Remaining Work, reorder within a cell, move an item
/// into or out of the sprint). Design: research/18 §4.1.
///
/// Three things shape this repository, all from the spikes (research/18 §1):
///
/// * **One call gives rows and cards.** `iterations/{id}/workitems` answers
///   `workItemRelations`, already in ascending StackRank, with parents from
///   other iterations pulled in and hidden types dropped. WIQL is a
///   different (and worse) set.
/// * **Most taskboards are not customized**, so `taskboardcolumns` answers
///   an empty list and `taskboardworkitems` is a 400. The columns are then
///   derived from the state categories, which is what the web draws.
/// * **A plain `System.State` patch moves a card.** The taskboard column
///   call only picks between columns that map the item's *current* state,
///   so it is sent second and only when the target state is ambiguous.
///
/// Reads go through [_cached] against `JsonCache` under `sprint:*` keys and
/// fall back to the stale copy when the network fails, like the other
/// repositories; the snapshot is additionally written to the drift work item
/// list `sprint:{iterationId}` so [watchItems] can render it offline.
class SprintRepository {
  SprintRepository(
    this._client,
    this._workItems,
    this._forms, [
    AppDatabase? db,
    String? userId,
  ]) : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final WorkItemRepository _workItems;
  final WorkItemFormRepository _forms;
  final JsonCache _cache;

  static const apiVersion = '7.1';

  /// The taskboard routes are preview-only at 7.1.
  static const taskboardApiVersion = '7.1-preview.1';

  /// Iterations, columns and backlog configuration change rarely; a cold
  /// `teamsettings/iterations` on a 100-iteration team took 19 s once
  /// (spike s54), so this cache is what keeps it off the critical path.
  static const cacheTtl = Duration(hours: 24);

  static const remainingWorkField = 'Microsoft.VSTS.Scheduling.RemainingWork';
  static const storyPointsField = 'Microsoft.VSTS.Scheduling.StoryPoints';
  static const effortField = 'Microsoft.VSTS.Scheduling.Effort';

  static String teamsKey(String org, String project) =>
      'sprint:teams:$org:$project';

  static String columnsKey(String org, String project, String team) =>
      'sprint:columns:$org:$project:$team';
  static String snapshotKey(
    String org,
    String project,
    String team,
    String iteration,
  ) => 'sprint:snapshot:$org:$project:$team:$iteration';
  static String snapshotPrefix(String org, String project) =>
      'sprint:snapshot:$org:$project:';
  static String capacityKey(
    String org,
    String project,
    String team,
    String iteration,
  ) => 'sprint:capacity:$org:$project:$team:$iteration';

  /// The drift list key the cards are stored under, so the taskboard opens
  /// from the cache the way every other list does.
  static String listKey(String iterationId) => 'sprint:$iterationId';

  // ---------------------------------------------------------------- reads

  /// The project's default team. Every sprint route is team-scoped and no
  /// project in puremedia has a second team (spike s54), so this is the
  /// team unless a caller passes one.
  Future<String> defaultTeamId(String org, String project) =>
      _forms.defaultTeamId(org, project);

  /// The default team's display name, for the picker's header (S8). Comes
  /// off the same single project read [defaultTeamId] already makes, so it
  /// costs nothing; null when the read failed or the service gave no name.
  Future<String?> defaultTeamName(String org, String project) =>
      _forms.defaultTeamName(org, project);

  /// Every team of the project, for the picker's team switch (S8).
  ///
  /// `GET {org}/_apis/projects/{project}/teams` — project-level, not
  /// team-scoped, and it takes the project name as well as its id. Teams
  /// change about as often as iterations do, so it shares the day-long
  /// cache; the picker hides the switch when the answer has one entry,
  /// which is every puremedia project (spike s54).
  Future<List<SprintTeamRef>> teams(
    String org,
    String project, {
    bool refresh = false,
  }) => _cached<List<SprintTeamRef>>(
    teamsKey(org, project),
    () => _client.getJson(
      org: org,
      path: '_apis/projects/$project/teams',
      apiVersion: apiVersion,
    ),
    (json) => [
      for (final t in ((json as Map?)?['value'] as List?) ?? const [])
        if (t is Map) SprintTeamRef.fromJson(t.cast<String, dynamic>()),
    ],
    refresh: refresh,
  );

  /// Every iteration of the team, split into current / future / past.
  ///
  /// `$timeframe` accepts only `current` (anything else is HTTP 400), so
  /// the list is read whole and split client-side — which is also what the
  /// picker needs. Reuses the form's cached read rather than making a
  /// second one.
  Future<SprintIterations> iterations(
    String org,
    String project, {
    String? team,
    bool refresh = false,
  }) async {
    final all = await _forms.teamIterations(
      org,
      project,
      team: team,
      refresh: refresh,
    );
    return SprintIterations(all: all);
  }

  /// The taskboard's columns: the team's own when it customized them, else
  /// To Do / In Progress / Done derived from the state categories.
  ///
  /// Both paths read the task types' states, because the customized answer
  /// carries no state *category* and the app needs to know which column is
  /// Done for a rollup.
  Future<List<TaskboardColumn>> columns(
    String org,
    String project, {
    String? team,
    bool refresh = false,
  }) async {
    final teamId = team ?? await defaultTeamId(org, project);
    return _cached<List<TaskboardColumn>>(
      columnsKey(org, project, teamId),
      () async {
        final config = await _client.getJson(
          org: org,
          project: project,
          team: teamId,
          path: '_apis/work/backlogconfiguration',
          apiVersion: apiVersion,
        );
        final taskTypes = taskTypeNames(config);
        final states = <String, List<WorkItemState>>{};
        for (final type in taskTypes) {
          states[type] = await _typeStates(org, project, type);
        }
        final custom = await _maybe(
          () => _client.getJson(
            org: org,
            project: project,
            team: teamId,
            path: '_apis/work/taskboardcolumns',
            apiVersion: taskboardApiVersion,
          ),
        );
        final columns = parseColumns(
          taskboardColumns: custom,
          config: config,
          typeStates: states,
        );
        return {
          'columns': [for (final c in columns) c.toJson()],
        };
      },
      (json) => [
        for (final c in ((json as Map?)?['columns'] as List?) ?? const [])
          if (c is Map) TaskboardColumn.fromJson(c.cast<String, dynamic>()),
      ],
      refresh: refresh,
    );
  }

  Future<List<WorkItemState>> _typeStates(
    String org,
    String project,
    String type,
  ) async {
    final json = await _client.getJson(
      org: org,
      project: project,
      path: '_apis/wit/workitemtypes/$type/states',
      apiVersion: apiVersion,
    );
    return [
      for (final s in (json['value'] as List?) ?? const [])
        if (s is Map) WorkItemState.fromJson(s.cast<String, dynamic>()),
    ];
  }

  /// The whole sprint in two calls plus the columns.
  ///
  /// [iterationId] is the team iteration GUID. The snapshot is cached whole
  /// and its cards are written to the drift list so the page opens offline.
  Future<SprintSnapshot> load(
    String org,
    String project,
    String iterationId, {
    String? team,
    bool refresh = false,
  }) async {
    final teamId = team ?? await defaultTeamId(org, project);
    final iterationList = await iterations(org, project, team: teamId);
    final iteration =
        iterationList.byId(iterationId) ??
        TeamIteration(id: iterationId, name: 'Sprint', path: project);
    final columnList = await columns(
      org,
      project,
      team: teamId,
      refresh: refresh,
    );
    final taskTypes = taskTypesOf(
      await _forms.backlogTypes(org, project, team: teamId),
    );

    final relationsJson = await _client.getJson(
      org: org,
      project: project,
      team: teamId,
      path: '_apis/work/teamsettings/iterations/$iterationId/workitems',
      apiVersion: apiVersion,
    );
    final relations = parseRelations(relationsJson);
    final items = relations.ids.isEmpty
        ? const <WorkItem>[]
        : await _workItems.batch(
            org,
            project,
            relations.ids,
            fields: await _fields(org),
          );

    // Only a customized board answers `taskboardworkitems`; everywhere else
    // it is 400 TaskboardColumnNotCustomizedException.
    var explicit = const <int, String>{};
    if (columnList.any((c) => c.isCustomized)) {
      final json = await _maybe(
        () => _client.getJson(
          org: org,
          project: project,
          team: teamId,
          path: '_apis/work/taskboardworkitems/$iterationId',
          apiVersion: taskboardApiVersion,
        ),
      );
      if (json != null) explicit = parseExplicitColumns(json);
    }

    final snapshot = buildSnapshot(
      iteration: iteration,
      columns: columnList,
      relations: relations,
      items: items,
      taskTypes: taskTypes,
      explicitColumns: explicit,
    );
    await _workItems.storeList(org, project, listKey(iterationId), items);
    await _cache.put(
      snapshotKey(org, project, teamId, iterationId),
      snapshot.toJson(),
    );
    return snapshot;
  }

  /// The last snapshot read for this sprint, or null when there is none.
  ///
  /// [team] may be unknown offline (resolving the default team is itself a
  /// network read), in which case the cache is scanned for this
  /// org/project/iteration instead.
  Future<SprintSnapshot?> cachedSnapshot(
    String org,
    String project,
    String iterationId, {
    String? team,
  }) async {
    var key = team == null
        ? null
        : snapshotKey(org, project, team, iterationId);
    if (key == null) {
      final keys = await _cache.keysWithPrefix(snapshotPrefix(org, project));
      key = keys.where((k) => k.endsWith(':$iterationId')).firstOrNull;
    }
    if (key == null) return null;
    final hit = await _cache.get(key);
    final json = hit?.json;
    if (json is! Map) return null;
    try {
      return SprintSnapshot.fromJson(json.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  /// The sprint's cards from drift, for a page that renders the cache first.
  Stream<List<WorkItem>> watchItems(
    String org,
    String project,
    String iterationId,
  ) => _workItems.watchList(org, project, listKey(iterationId));

  /// Capacity, team days off and working days. Read lazily: no team in
  /// puremedia fills any of it in, so the strip is hidden more often than
  /// it is shown (decision S7).
  Future<SprintCapacity> capacities(
    String org,
    String project,
    String iterationId, {
    String? team,
    bool refresh = false,
  }) async {
    final teamId = team ?? await defaultTeamId(org, project);
    return _cached<SprintCapacity>(
      capacityKey(org, project, teamId, iterationId),
      () async {
        final capacity = await _maybe(
          () => _client.getJson(
            org: org,
            project: project,
            team: teamId,
            path: '_apis/work/teamsettings/iterations/$iterationId/capacities',
            apiVersion: apiVersion,
          ),
        );
        final daysOff = await _maybe(
          () => _client.getJson(
            org: org,
            project: project,
            team: teamId,
            path: '_apis/work/teamsettings/iterations/$iterationId/teamdaysoff',
            apiVersion: apiVersion,
          ),
        );
        final settings = await _maybe(
          () => _client.getJson(
            org: org,
            project: project,
            team: teamId,
            path: '_apis/work/teamsettings',
            apiVersion: apiVersion,
          ),
        );
        return parseCapacity(
          capacities: capacity,
          teamDaysOff: daysOff,
          teamSettings: settings,
        ).toJson();
      },
      (json) => SprintCapacity.fromJson((json as Map).cast<String, dynamic>()),
      refresh: refresh,
    );
  }

  /// The batch field list, with the scheduling fields dropped when the
  /// organization does not define them: naming a field the process does not
  /// have is a 400 on `workitemsbatch`, the same guard the board applies to
  /// its WEF fields.
  Future<List<String>> _fields(String org) async {
    Map<String, FieldSpec> orgFields;
    try {
      orgFields = await _forms.orgFieldTypes(org);
    } on AdoAuthException {
      rethrow;
    } on AdoException {
      orgFields = const {};
    }
    bool has(String field) => orgFields.isEmpty || orgFields.containsKey(field);
    return [
      ...WorkItemRepository.listFields,
      // The relation list already carries parentage; the field is only a
      // convenience for the card badge, so it is guarded like the rest.
      if (has('System.Parent')) 'System.Parent',
      if (has(remainingWorkField)) remainingWorkField,
      if (has(storyPointsField)) storyPointsField,
      if (has(effortField)) effortField,
      if (has(BoardRepository.stackRank)) BoardRepository.stackRank,
    ];
  }

  // -------------------------------------------------------------- parsing

  /// Backlog rank of the task level; `backlogconfiguration` ranks bottom-up
  /// (Tasks 1, Stories 2, Features 3, Epics 4).
  static const _taskRank = 1;

  static const _taskCategory = 'Microsoft.TaskCategory';

  /// The types that are cards rather than rows. `bugsBehavior` decides
  /// where Bug lands and the service has already applied it to the backlog
  /// levels, so this only has to find the task level.
  static Set<String> taskTypesOf(BacklogTypes backlog) {
    final level =
        backlog.levels.where((l) => l.id == _taskCategory).firstOrNull ??
        backlog.levels.where((l) => l.rank == _taskRank).firstOrNull ??
        backlog.levels.lastOrNull;
    return {...?level?.typeNames};
  }

  /// `taskBacklog.workItemTypes` — Task and, when `bugsBehavior` is
  /// `asTasks`, Bug.
  static List<String> taskTypeNames(Map<String, dynamic> config) {
    final task = config['taskBacklog'];
    if (task is! Map) return const ['Task'];
    return [
      for (final t in (task['workItemTypes'] as List?) ?? const [])
        if (t is Map && t['name'] is String) t['name'] as String,
    ];
  }

  /// `workItemTypeMappedStates`: type → state → category.
  static Map<String, Map<String, String>> mappedStates(
    Map<String, dynamic> config,
  ) => {
    for (final m in (config['workItemTypeMappedStates'] as List?) ?? const [])
      if (m is Map && m['workItemTypeName'] is String)
        m['workItemTypeName'] as String: {
          for (final e in ((m['states'] as Map?) ?? const {}).entries)
            e.key.toString(): '${e.value}',
        },
  };

  /// The customized columns when there are any, else the derived ones.
  static List<TaskboardColumn> parseColumns({
    Map<String, dynamic>? taskboardColumns,
    required Map<String, dynamic> config,
    Map<String, List<WorkItemState>> typeStates = const {},
  }) {
    final wire = (taskboardColumns?['columns'] as List?) ?? const [];
    final customized =
        (taskboardColumns?['isCustomized'] as bool? ?? false) &&
        wire.isNotEmpty;
    if (!customized) {
      return deriveColumns(
        taskTypes: taskTypeNames(config),
        typeStates: typeStates,
        mappedStates: mappedStates(config),
      );
    }
    final categories = _categoriesOf(typeStates, mappedStates(config));
    final columns = [
      for (final c in wire)
        if (c is Map) TaskboardColumn.fromWire(c.cast<String, dynamic>()),
    ]..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (final c in columns)
        c.copyWith(stateCategory: _categoryOf(c, categories)),
    ];
  }

  /// Type → state → category, from the states read with the
  /// `workItemTypeMappedStates` map as the fallback.
  static Map<String, Map<String, String>> _categoriesOf(
    Map<String, List<WorkItemState>> typeStates,
    Map<String, Map<String, String>> mapped,
  ) {
    final out = <String, Map<String, String>>{};
    for (final entry in mapped.entries) {
      out[entry.key] = {...entry.value};
    }
    for (final entry in typeStates.entries) {
      final byState = out.putIfAbsent(entry.key, () => <String, String>{});
      for (final state in entry.value) {
        final category = state.category;
        if (category != null && category.isNotEmpty) {
          byState[state.name] = category;
        }
      }
    }
    return out;
  }

  /// The category a customized column stands for: the furthest-along
  /// category any of its mapped states belongs to, so a column mapping a
  /// Completed state counts as Done for the rollups.
  static String? _categoryOf(
    TaskboardColumn column,
    Map<String, Map<String, String>> categories,
  ) {
    String? best;
    for (final entry in column.mappings.entries) {
      final category = categories[entry.key]?[entry.value];
      if (category == null) continue;
      if (best == null || _categoryRank(category) > _categoryRank(best)) {
        best = category;
      }
    }
    return best;
  }

  static int _categoryRank(String category) => switch (category) {
    'Proposed' => 0,
    'InProgress' => 1,
    'Resolved' => 2,
    'Completed' => 3,
    _ => -1,
  };

  /// To Do / In Progress / Done from the state categories, the fallback the
  /// majority of projects take (research/18 §1). Proposed is To Do,
  /// InProgress and Resolved are In Progress, Completed is Done; Removed is
  /// not a column. Each column's state order follows the type's own list,
  /// so the state a card takes when it is dropped there is the first one
  /// the process defines.
  static List<TaskboardColumn> deriveColumns({
    required List<String> taskTypes,
    Map<String, List<WorkItemState>> typeStates = const {},
    Map<String, Map<String, String>> mappedStates = const {},
  }) {
    const buckets = <(String, String)>[
      ('To Do', 'Proposed'),
      ('In Progress', 'InProgress'),
      ('Done', 'Completed'),
    ];
    final states = <int, Map<String, List<String>>>{
      for (var i = 0; i < buckets.length; i++) i: <String, List<String>>{},
    };
    for (final type in taskTypes) {
      final byName = <String, String>{...?mappedStates[type]};
      for (final s in typeStates[type] ?? const <WorkItemState>[]) {
        final category = s.category;
        if (category != null && category.isNotEmpty) byName[s.name] = category;
      }
      // Wire order where the states were read, otherwise the mapped-states
      // order, which is also the process's.
      final ordered = [
        for (final s in typeStates[type] ?? const <WorkItemState>[]) s.name,
        for (final name in byName.keys)
          if (!(typeStates[type] ?? const <WorkItemState>[]).any(
            (s) => s.name == name,
          ))
            name,
      ];
      for (final name in ordered) {
        final index = switch (byName[name]) {
          'Proposed' => 0,
          'InProgress' || 'Resolved' => 1,
          'Completed' => 2,
          _ => -1,
        };
        if (index < 0) continue;
        (states[index]![type] ??= <String>[]).add(name);
      }
    }
    final out = <TaskboardColumn>[];
    for (var i = 0; i < buckets.length; i++) {
      final byType = states[i]!;
      if (byType.isEmpty) continue;
      out.add(
        TaskboardColumn(
          name: buckets[i].$1,
          order: out.length,
          mappings: {
            for (final e in byType.entries)
              if (e.value.isNotEmpty) e.key: e.value.first,
          },
          states: byType,
          stateCategory: buckets[i].$2,
        ),
      );
    }
    return out;
  }

  /// `workItemRelations`: `source: null` rows are the sprint's roots (in
  /// ascending StackRank), the rest are children of the row they name.
  static ({List<int> roots, Map<int, List<int>> children, List<int> ids})
  parseRelations(Map<String, dynamic> json) {
    final roots = <int>[];
    final children = <int, List<int>>{};
    final ids = <int>[];
    final seen = <int>{};
    for (final r in (json['workItemRelations'] as List?) ?? const []) {
      if (r is! Map) continue;
      final target = (r['target'] as Map?)?['id'];
      if (target is! int) continue;
      if (seen.add(target)) ids.add(target);
      final source = (r['source'] as Map?)?['id'];
      if (source is int) {
        (children[source] ??= <int>[]).add(target);
      } else {
        roots.add(target);
      }
    }
    return (roots: roots, children: children, ids: ids);
  }

  /// `taskboardworkitems`: work item id → the column it was explicitly
  /// placed in. Sticky across a state round trip, which is why it is read
  /// at all (spike w35).
  static Map<int, String> parseExplicitColumns(Map<String, dynamic> json) => {
    for (final r in (json['value'] as List?) ?? const [])
      if (r is Map && r['workItemId'] is int && r['column'] is String)
        r['workItemId'] as int: r['column'] as String,
  };

  static SprintCapacity parseCapacity({
    Map<String, dynamic>? capacities,
    Map<String, dynamic>? teamDaysOff,
    Map<String, dynamic>? teamSettings,
  }) => SprintCapacity.fromJson({
    'teamMembers': capacities?['teamMembers'] ?? const [],
    'teamDaysOff': teamDaysOff?['daysOff'] ?? const [],
    'workingDays': teamSettings?['workingDays'] ?? const [],
  });

  /// Rows, unparented tasks and rollups from the relation list and the
  /// batched items. A root whose type is a task type is unparented; every
  /// other root is a requirement row, in the order the service returned.
  static SprintSnapshot buildSnapshot({
    required TeamIteration iteration,
    required List<TaskboardColumn> columns,
    required ({List<int> roots, Map<int, List<int>> children, List<int> ids})
    relations,
    required List<WorkItem> items,
    required Set<String> taskTypes,
    Map<int, String> explicitColumns = const {},
    DateTime? fetchedAt,
  }) {
    final byId = {for (final i in items) i.id: i};
    final rows = <SprintRow>[];
    final unparented = <WorkItem>[];
    for (final rootId in relations.roots) {
      final root = byId[rootId];
      if (root == null) continue;
      final children = [
        for (final childId in relations.children[rootId] ?? const <int>[])
          if (byId[childId] != null) byId[childId]!,
      ];
      // A task-category root is a task whose parent is not in this sprint:
      // the web gathers those into one "Unparented" row at the top. A task
      // nested under such a task has nowhere else to go either.
      if (taskTypes.contains(root.type)) {
        unparented
          ..add(root)
          ..addAll(children);
        continue;
      }
      rows.add(_row(root, children, columns, explicitColumns));
    }
    return SprintSnapshot(
      iteration: iteration,
      columns: columns,
      rows: rows,
      unparented: _row(null, unparented, columns, explicitColumns),
      explicitColumns: explicitColumns,
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }

  static SprintRow _row(
    WorkItem? parent,
    List<WorkItem> tasks,
    List<TaskboardColumn> columns,
    Map<int, String> explicitColumns,
  ) {
    final totals = rollup(tasks, columns, explicitColumns: explicitColumns);
    return SprintRow(
      parent: parent,
      tasks: tasks,
      remaining: totals.remaining,
      done: totals.done,
    );
  }

  // -------------------------------------------------------- pure helpers

  /// Which column a card sits in: its explicit placement when the board is
  /// customized and one was recorded, else the first column that accepts
  /// its state. -1 when nothing matches.
  static int columnIndexFor(
    List<TaskboardColumn> columns,
    WorkItem item, {
    Map<int, String> explicitColumns = const {},
  }) {
    final explicit = explicitColumns[item.id];
    if (explicit != null) {
      final i = columns.indexWhere((c) => c.name == explicit);
      if (i >= 0) return i;
    }
    return columns.indexWhere((c) => c.accepts(item.type, item.state));
  }

  static TaskboardColumn? columnFor(
    List<TaskboardColumn> columns,
    WorkItem item, {
    Map<int, String> explicitColumns = const {},
  }) {
    final i = columnIndexFor(columns, item, explicitColumns: explicitColumns);
    return i < 0 ? null : columns[i];
  }

  /// Cards per column, in the order given (the service's StackRank order).
  /// A card whose state matches no column goes in the first one rather than
  /// disappearing, as the board does.
  static List<List<WorkItem>> distribute(
    List<TaskboardColumn> columns,
    List<WorkItem> tasks, {
    Map<int, String> explicitColumns = const {},
  }) {
    final out = List.generate(columns.length, (_) => <WorkItem>[]);
    if (out.isEmpty) return out;
    for (final task in tasks) {
      final i = columnIndexFor(columns, task, explicitColumns: explicitColumns);
      out[i < 0 ? 0 : i].add(task);
    }
    return out;
  }

  /// The JSON Patch that moves [item] to [target]: the state the column
  /// maps for that type, and nothing when the card's current state already
  /// belongs there (dragging a Resolved task within In Progress, or a move
  /// that only changes the explicit column).
  ///
  /// **A move never writes Remaining Work, not even into a Done column.**
  /// The first cut of this did, because the web clears the hours when a
  /// task finishes and the move sheet promises the same. The service
  /// refused it on the scratch project, verbatim:
  ///
  /// > TF401320: Rule Error for field Remaining Work. Error code:
  /// > InvalidNotEmpty.
  ///
  /// The stock Agile and Scrum processes carry a rule on the task's
  /// completed state that Remaining Work must be **empty**, so a zero is
  /// as invalid as a four — and the rule empties the field itself the
  /// moment the state lands. Writing it here would also have put a doomed
  /// patch in the offline queue. The page checks the refreshed item after
  /// a move into a Done column and only then, on a process whose rule is
  /// missing, sends the zero as a patch of its own
  /// (P-C, verified on the iPhone 17 against DevOps Mobile App,
  /// 2026-09-15).
  static List<Map<String, Object?>> moveOps(
    TaskboardColumn target,
    WorkItem item,
  ) {
    if (target.accepts(item.type, item.state)) {
      return const <Map<String, Object?>>[];
    }
    final state = target.mappings[item.type];
    if (state == null || state == item.state) {
      return const <Map<String, Object?>>[];
    }
    return [
      {'op': 'add', 'path': '/fields/System.State', 'value': state},
    ];
  }

  /// Whether the move also needs the taskboard column call.
  ///
  /// The state patch alone lands the card in the *first* column mapping
  /// that state, so the extra call is needed only when the target's state
  /// for this type maps to more than one column — which cannot happen on a
  /// derived board, and is what makes a column like "Verify" work
  /// (spike w34).
  static bool needsColumnCall(
    List<TaskboardColumn> columns,
    WorkItem item,
    TaskboardColumn target,
  ) {
    if (!target.isCustomized) return false;
    final state =
        target.mappings[item.type] ??
        (target.accepts(item.type, item.state) ? item.state : null);
    if (state == null) return false;
    var n = 0;
    for (final c in columns) {
      if (c.accepts(item.type, state)) n++;
    }
    return n > 1;
  }

  /// A row's rollups: Remaining Work summed over the tasks that are not
  /// done, and how many are. Remaining is null when no task carries the
  /// field at all, which is every project checked (spike s54) — the UI must
  /// then show no rollup rather than "0 h".
  static ({double? remaining, int done}) rollup(
    List<WorkItem> tasks,
    List<TaskboardColumn> columns, {
    Map<int, String> explicitColumns = const {},
  }) {
    double? remaining;
    var done = 0;
    for (final task in tasks) {
      final column = columnFor(columns, task, explicitColumns: explicitColumns);
      final isDone = column?.isDone ?? false;
      if (isDone) done++;
      final hours = task.field<num>(remainingWorkField)?.toDouble();
      if (hours != null) remaining = (remaining ?? 0) + (isDone ? 0 : hours);
    }
    return (remaining: remaining, done: done);
  }

  // --------------------------------------------------------------- writes

  /// Move a task to [target]: the state patch (guarded by `test /rev`) and,
  /// only when the target state is ambiguous, the taskboard column call.
  ///
  /// [columns] and [iterationId] are what the second call needs; without
  /// them only the state is written, which is the right answer on the
  /// majority of boards.
  Future<WorkItem> move(
    String org,
    String project,
    WorkItem item,
    TaskboardColumn target, {
    List<TaskboardColumn> columns = const [],
    String? iterationId,
    String? team,
  }) async {
    final ops = moveOps(target, item);
    var updated = item;
    if (ops.isNotEmpty) {
      updated = await _workItems.patch(org, project, item, ops);
    }
    if (iterationId != null && needsColumnCall(columns, item, target)) {
      await setColumn(
        org,
        project,
        iterationId,
        item.id,
        target.name,
        team: team,
      );
    }
    return updated;
  }

  /// `PATCH taskboardworkitems/{iteration}/{id}` `{"newColumn": name}`,
  /// 204 with no body. It never writes `System.State` and refuses a column
  /// that is not mapped to the item's current state, so it always follows
  /// the state patch.
  Future<void> setColumn(
    String org,
    String project,
    String iterationId,
    int workItemId,
    String column, {
    String? team,
  }) async {
    final teamId = team ?? await defaultTeamId(org, project);
    await _client.send(
      method: 'PATCH',
      org: org,
      project: project,
      team: teamId,
      path: '_apis/work/taskboardworkitems/$iterationId/$workItemId',
      apiVersion: taskboardApiVersion,
      body: {'newColumn': column},
    );
  }

  /// `PATCH {team}/_apis/work/workitemsorder` with the parent: the same
  /// route the board reorders with, and [BoardRepository.reorderBlock]
  /// computes the block (a card plus its run of unranked neighbours)
  /// unchanged.
  Future<Map<int, double>> reorder(
    String org,
    String project,
    List<int> ids, {
    required int previousId,
    required int nextId,
    int parentId = 0,
    String? team,
  }) async {
    final teamId = team ?? await defaultTeamId(org, project);
    final json = await _client.send(
      method: 'PATCH',
      org: org,
      project: project,
      team: teamId,
      path: '_apis/work/workitemsorder',
      apiVersion: apiVersion,
      body: {
        'ids': ids,
        'previousId': previousId,
        'nextId': nextId,
        'parentId': parentId,
      },
    );
    return {
      for (final r in ((json['value'] as List?) ?? const []).whereType<Map>())
        r['id'] as int: (r['order'] as num?)?.toDouble() ?? 0,
    };
  }

  /// Remaining Work in hours. **Never null**: the field refuses `null` with
  /// a 400 `VssPropertyValidationException`, so clearing it is a 0
  /// (spike w33). There is no server-side rollup to the parent.
  Future<WorkItem> setRemainingWork(
    String org,
    String project,
    WorkItem item,
    double? hours,
  ) => _workItems.patch(org, project, item, remainingWorkOps(hours));

  static List<Map<String, Object?>> remainingWorkOps(double? hours) {
    final value = hours == null || hours < 0 ? 0 : hours;
    return [
      {
        'op': 'add',
        'path': '/fields/$remainingWorkField',
        // A whole number of hours is written as an int so the field does
        // not read back as "3.0" in the web.
        'value': value == value.roundToDouble() ? value.round() : value,
      },
    ];
  }

  /// Move an item into or out of the sprint (decision S3): an iteration
  /// path patch, which is all the service needs.
  Future<WorkItem> setIteration(
    String org,
    String project,
    WorkItem item,
    String path,
  ) => _workItems.patch(org, project, item, iterationOps(path));

  static List<Map<String, Object?>> iterationOps(String path) => [
    {'op': 'add', 'path': '/fields/System.IterationPath', 'value': path},
  ];

  // --------------------------------------------------------------- shared

  Future<T> _cached<T>(
    String key,
    Future<Object> Function() fetch,
    T Function(Object? json) parse, {
    bool refresh = false,
    Duration maxAge = cacheTtl,
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

  /// An optional read: a taskboard that is not customized answers 400, a
  /// team without capacity 403 or 404, and none of that is a failure of the
  /// sprint.
  Future<Map<String, dynamic>?> _maybe(
    Future<Map<String, dynamic>> Function() read,
  ) async {
    try {
      return await read();
    } on AdoForbiddenException {
      return null;
    } on AdoNotFoundException {
      return null;
    } on AdoValidationException {
      return null;
    } on AdoServerException catch (e) {
      if (e.statusCode == 400) return null;
      rethrow;
    }
  }
}
