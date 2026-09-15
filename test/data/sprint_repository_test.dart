import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sprint_models_test.dart' show item;

const account = 'kelly@kammcs.com-home';
const org = 'contoso';
const project = 'DevOps Mobile App';
const team = '11111111-2222-3333-4444-555555555555';
const iterationId = 'aa9f2381-0000-0000-0000-000000000001';

/// Canned-response adapter keyed by a distinctive piece of the path, so the
/// repository runs through the real `AdoClient` and the URLs it builds are
/// what the tests read. The longest matching key wins, which keeps
/// `iterations/{id}/workitems` apart from the iteration list.
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Object> answers = <String, Object>{};
  final Map<String, int> statuses = <String, int>{};

  RequestOptions get last => requests.last;

  Iterable<RequestOptions> matching(String part) =>
      requests.where((r) => r.uri.toString().contains(part));

  RequestOptions? firstMatching(String part) => matching(part).firstOrNull;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final keys = answers.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final path = options.uri.toString();
    final key = keys.firstWhere(path.contains, orElse: () => '');
    final status = statuses[key] ?? 200;
    return ResponseBody.fromString(
      jsonEncode(answers[key] ?? const <String, dynamic>{}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> projectJson() => {
  'id': 'p-1',
  'name': project,
  'defaultTeam': {'id': team, 'name': 'DevOps Mobile App Team'},
};

Map<String, dynamic> iterationList() => {
  'count': 2,
  'value': [
    {
      'id': iterationId,
      'name': 'Iteration 1',
      'path': r'\Iteration 1',
      'attributes': {
        'startDate': '2026-09-08T00:00:00Z',
        'finishDate': '2026-09-21T00:00:00Z',
        'timeFrame': 'current',
      },
    },
    {
      'id': 'bb9f2381-0000-0000-0000-000000000002',
      'name': 'Iteration 2',
      'path': r'\Iteration 2',
      'attributes': {
        'startDate': '2026-09-22T00:00:00Z',
        'finishDate': '2026-10-05T00:00:00Z',
        'timeFrame': 'future',
      },
    },
  ],
};

Map<String, dynamic> backlogConfiguration() => {
  'bugsBehavior': 'asTasks',
  'taskBacklog': {
    'id': 'Microsoft.TaskCategory',
    'name': 'Tasks',
    'rank': 1,
    'workItemTypes': [
      {'name': 'Task'},
      {'name': 'Bug'},
    ],
  },
  'requirementBacklog': {
    'id': 'Microsoft.RequirementCategory',
    'name': 'Stories',
    'rank': 2,
    'workItemTypes': [
      {'name': 'User Story'},
    ],
  },
  'portfolioBacklogs': const [],
  'hiddenBacklogs': const [],
  'backlogFields': {
    'typeFields': {'Order': 'Microsoft.VSTS.Common.StackRank'},
  },
  'workItemTypeMappedStates': [
    {
      'workItemTypeName': 'Task',
      'states': {
        'New': 'Proposed',
        'Active': 'InProgress',
        'Resolved': 'Resolved',
        'Closed': 'Completed',
        'Removed': 'Removed',
      },
    },
    {
      'workItemTypeName': 'Bug',
      'states': {
        'New': 'Proposed',
        'Active': 'InProgress',
        'Closed': 'Completed',
        'Removed': 'Removed',
      },
    },
  ],
};

/// `wit/workitemtypes/{type}/states`, in wire order with the categories.
Map<String, dynamic> taskStates() => {
  'count': 5,
  'value': [
    {'name': 'New', 'color': 'b2b2b2', 'category': 'Proposed'},
    {'name': 'Active', 'color': '007acc', 'category': 'InProgress'},
    {'name': 'Resolved', 'color': 'ff9d00', 'category': 'Resolved'},
    {'name': 'Closed', 'color': '339933', 'category': 'Completed'},
    {'name': 'Removed', 'color': 'ffffff', 'category': 'Removed'},
  ],
};

Map<String, dynamic> bugStates() => {
  'count': 4,
  'value': [
    {'name': 'New', 'category': 'Proposed'},
    {'name': 'Active', 'category': 'InProgress'},
    {'name': 'Closed', 'category': 'Completed'},
    {'name': 'Removed', 'category': 'Removed'},
  ],
};

/// What three of the four puremedia projects answer.
Map<String, dynamic> uncustomizedColumns() => {
  'columns': const [],
  'isCustomized': false,
  'isValid': true,
};

/// The scratch project after w34: To Do / In Progress / Verify / Done, with
/// Verify sharing the Active state with In Progress.
Map<String, dynamic> customizedColumns() => {
  'isCustomized': true,
  'isValid': true,
  'columns': [
    {
      'id': 'c-todo',
      'name': 'To Do',
      'order': 0,
      'mappings': [
        {'workItemType': 'Task', 'state': 'New'},
        {'workItemType': 'Bug', 'state': 'New'},
      ],
    },
    {
      'id': 'c-doing',
      'name': 'In Progress',
      'order': 1,
      'mappings': [
        {'workItemType': 'Task', 'state': 'Active'},
        {'workItemType': 'Bug', 'state': 'Active'},
      ],
    },
    {
      'id': 'c-verify',
      'name': 'Verify',
      'order': 2,
      'mappings': [
        {'workItemType': 'Task', 'state': 'Active'},
        {'workItemType': 'Bug', 'state': 'Active'},
      ],
    },
    {
      'id': 'c-done',
      'name': 'Done',
      'order': 3,
      'mappings': [
        {'workItemType': 'Task', 'state': 'Closed'},
        {'workItemType': 'Bug', 'state': 'Closed'},
      ],
    },
  ],
};

/// One story with two tasks, one story with none, and two unparented tasks
/// (`source: null` rows are roots, already in StackRank order).
Map<String, dynamic> relations() => {
  'workItemRelations': [
    {'rel': null, 'source': null, 'target': _ref(15546)},
    {
      'rel': 'System.LinkTypes.Hierarchy-Forward',
      'source': _ref(15546),
      'target': _ref(15550),
    },
    {
      'rel': 'System.LinkTypes.Hierarchy-Forward',
      'source': _ref(15546),
      'target': _ref(15551),
    },
    {'rel': null, 'source': null, 'target': _ref(15547)},
    {'rel': null, 'source': null, 'target': _ref(15553)},
    {'rel': null, 'source': null, 'target': _ref(15554)},
  ],
};

Map<String, dynamic> _ref(int id) => {
  'id': id,
  'url': 'https://dev.azure.com/$org/_apis/wit/workItems/$id',
};

Map<String, dynamic> batchAnswer() => {
  'count': 6,
  'value': [
    _item(15546, 'User Story', 'Sprint view', 'New'),
    _item(15550, 'Task', 'Model the columns', 'Active', remaining: 3),
    _item(15551, 'Task', 'Write the tests', 'Closed', remaining: 2),
    _item(15547, 'User Story', 'Burndown', 'New'),
    _item(15553, 'Task', 'Orphan one', 'New'),
    _item(15554, 'Bug', 'Orphan two', 'Active'),
  ],
};

Map<String, dynamic> _item(
  int id,
  String type,
  String title,
  String state, {
  double? remaining,
}) => {
  'id': id,
  'rev': 4,
  'fields': {
    'System.Id': id,
    'System.WorkItemType': type,
    'System.Title': title,
    'System.State': state,
    'Microsoft.VSTS.Scheduling.RemainingWork': ?remaining,
  },
};

Map<String, dynamic> orgFields() => {
  'count': 4,
  'value': [
    {'referenceName': 'System.Parent', 'name': 'Parent', 'type': 'integer'},
    {
      'referenceName': 'Microsoft.VSTS.Scheduling.RemainingWork',
      'name': 'Remaining Work',
      'type': 'double',
    },
    {
      'referenceName': 'Microsoft.VSTS.Scheduling.StoryPoints',
      'name': 'Story Points',
      'type': 'double',
    },
    {
      'referenceName': 'Microsoft.VSTS.Common.StackRank',
      'name': 'Stack Rank',
      'type': 'double',
    },
  ],
};

void main() {
  late _FakeAdapter adapter;
  late AppDatabase db;
  late SprintRepository repository;
  late WorkItemRepository workItems;

  setUp(() {
    adapter = _FakeAdapter()
      ..answers['_apis/projects/'] = projectJson()
      ..answers['work/teamsettings/iterations?'] = iterationList()
      ..answers['iterations/$iterationId/workitems'] = relations()
      ..answers['backlogconfiguration'] = backlogConfiguration()
      ..answers['workitemtypecategories'] = {'count': 0, 'value': const []}
      ..answers['workitemtypes/Task/states'] = taskStates()
      ..answers['workitemtypes/Bug/states'] = bugStates()
      ..answers['taskboardcolumns'] = uncustomizedColumns()
      ..answers['wit/fields'] = orgFields()
      ..answers['workitemsbatch'] = batchAnswer();
    db = AppDatabase(NativeDatabase.memory());
    final client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = adapter,
    );
    workItems = WorkItemRepository(client, db, userId: account);
    repository = SprintRepository(
      client,
      workItems,
      WorkItemFormRepository(client, workItems, db, account),
      db,
      account,
    );
  });

  tearDown(() => db.close());

  group('iterations', () {
    test(r'reads the whole list without $timeframe and splits it', () async {
      final iterations = await repository.iterations(org, project);

      expect(
        adapter.firstMatching('teamsettings/iterations')!.uri.toString(),
        'https://dev.azure.com/$org/DevOps%20Mobile%20App/$team/_apis/work/'
        'teamsettings/iterations?api-version=7.1',
      );
      expect(iterations.all.length, 2);
      expect(iterations.current.single.name, 'Iteration 1');
      expect(iterations.future.single.name, 'Iteration 2');
      expect(iterations.past, isEmpty);
      // The wire path is project-relative; the field wants it rooted.
      expect(iterations.current.single.path, r'DevOps Mobile App\Iteration 1');
    });
  });

  group('columns', () {
    test('derives To Do / In Progress / Done when not customized', () async {
      final columns = await repository.columns(org, project);

      expect(columns.map((c) => c.name), ['To Do', 'In Progress', 'Done']);
      expect(columns.map((c) => c.order), [0, 1, 2]);
      expect(columns.every((c) => c.id == null), isTrue);
      // Resolved joins InProgress; the state a card takes is the first of
      // the category in the type's own order.
      expect(columns[1].states['Task'], ['Active', 'Resolved']);
      expect(columns[1].mappings['Task'], 'Active');
      expect(columns[1].mappings['Bug'], 'Active');
      expect(columns[0].mappings, {'Task': 'New', 'Bug': 'New'});
      expect(columns[2].mappings, {'Task': 'Closed', 'Bug': 'Closed'});
      expect(columns.last.isDone, isTrue);
      // Removed is not a column.
      expect(
        columns.any((c) => c.states.values.any((s) => s.contains('Removed'))),
        isFalse,
      );
    });

    test('reads the taskboard columns at the preview version', () async {
      await repository.columns(org, project);

      expect(
        adapter.firstMatching('taskboardcolumns')!.uri.toString(),
        'https://dev.azure.com/$org/DevOps%20Mobile%20App/$team/_apis/work/'
        'taskboardcolumns?api-version=7.1-preview.1',
      );
      expect(
        adapter.firstMatching('workitemtypes/Task/states')!.uri.toString(),
        'https://dev.azure.com/$org/DevOps%20Mobile%20App/_apis/wit/'
        'workitemtypes/Task/states?api-version=7.1',
      );
    });

    test("takes the team's own columns when it customized them", () async {
      adapter.answers['taskboardcolumns'] = customizedColumns();

      final columns = await repository.columns(org, project);

      expect(columns.map((c) => c.name), [
        'To Do',
        'In Progress',
        'Verify',
        'Done',
      ]);
      expect(columns.every((c) => c.isCustomized), isTrue);
      // The category comes from the type's states, which the wire answer
      // does not carry: without it nothing knows which column is Done.
      expect(columns.first.stateCategory, 'Proposed');
      expect(columns[2].stateCategory, 'InProgress');
      expect(columns.last.isDone, isTrue);
    });

    test('a second read is answered from the cache', () async {
      await repository.columns(org, project);
      final calls = adapter.requests.length;

      await repository.columns(org, project);

      expect(adapter.requests.length, calls);
    });

    test('a 400 on taskboardcolumns still derives the columns', () async {
      adapter
        ..answers['taskboardcolumns'] = {
          'message': 'Taskboard columns are not added.',
          'typeKey': 'TaskboardColumnNotCustomizedException',
        }
        ..statuses['taskboardcolumns'] = 400;

      final columns = await repository.columns(org, project);

      expect(columns.map((c) => c.name), ['To Do', 'In Progress', 'Done']);
    });
  });

  group('load', () {
    test('one relations call gives the rows and the unparented row', () async {
      final snapshot = await repository.load(org, project, iterationId);

      expect(
        adapter.firstMatching('/workitems?')!.uri.toString(),
        'https://dev.azure.com/$org/DevOps%20Mobile%20App/$team/_apis/work/'
        'teamsettings/iterations/$iterationId/workitems?api-version=7.1',
      );
      expect(snapshot.iteration.name, 'Iteration 1');
      expect(snapshot.rows.length, 2);
      expect(snapshot.rows.first.parent!.id, 15546);
      expect(snapshot.rows.first.tasks.map((t) => t.id), [15550, 15551]);
      // A story with no tasks is still a row (the Backlog tab shows it).
      expect(snapshot.rows[1].parent!.id, 15547);
      expect(snapshot.rows[1].tasks, isEmpty);
      // Task-type roots are the unparented row, in wire order.
      expect(snapshot.unparented.tasks.map((t) => t.id), [15553, 15554]);
      expect(snapshot.allRows.first.isUnparented, isTrue);
    });

    test('rolls up remaining work over the tasks that are not done', () async {
      final snapshot = await repository.load(org, project, iterationId);

      // 15550 Active with 3 h counts; 15551 Closed with 2 h does not.
      expect(snapshot.rows.first.remaining, 3);
      expect(snapshot.rows.first.done, 1);
      // No task in the unparented row carries the field at all, so there is
      // no rollup to show rather than a zero.
      expect(snapshot.unparented.remaining, isNull);
      expect(snapshot.unparented.done, 0);
    });

    test('guards the scheduling fields by the org field list', () async {
      await repository.load(org, project, iterationId);

      final body = (adapter.firstMatching('workitemsbatch')!.data as Map)
          .cast<String, dynamic>();
      final fields = (body['fields'] as List).cast<String>();
      expect(fields, contains('Microsoft.VSTS.Scheduling.RemainingWork'));
      expect(fields, contains('Microsoft.VSTS.Common.StackRank'));
      expect(fields, contains('System.Parent'));
      expect(body['ids'], [15546, 15550, 15551, 15547, 15553, 15554]);
    });

    test('drops a field the organization does not define', () async {
      adapter.answers['wit/fields'] = {
        'count': 1,
        'value': [
          {'referenceName': 'System.Parent', 'name': 'Parent'},
        ],
      };

      await repository.load(org, project, iterationId);

      final body = (adapter.firstMatching('workitemsbatch')!.data as Map)
          .cast<String, dynamic>();
      final fields = (body['fields'] as List).cast<String>();
      expect(
        fields,
        isNot(contains('Microsoft.VSTS.Scheduling.RemainingWork')),
      );
      expect(fields, contains('System.Parent'));
    });

    test('skips taskboardworkitems unless the board is customized', () async {
      await repository.load(org, project, iterationId);

      expect(adapter.firstMatching('taskboardworkitems'), isNull);
    });

    test('reads the explicit columns on a customized board', () async {
      adapter
        ..answers['taskboardcolumns'] = customizedColumns()
        ..answers['taskboardworkitems'] = {
          'count': 1,
          'value': [
            {
              'workItemId': 15550,
              'state': 'Active',
              'column': 'Verify',
              'columnId': 'c-verify',
            },
          ],
        };

      final snapshot = await repository.load(org, project, iterationId);

      expect(
        adapter.firstMatching('taskboardworkitems')!.uri.toString(),
        'https://dev.azure.com/$org/DevOps%20Mobile%20App/$team/_apis/work/'
        'taskboardworkitems/$iterationId?api-version=7.1-preview.1',
      );
      expect(snapshot.explicitColumns, {15550: 'Verify'});
      // Active maps to both In Progress and Verify; the explicit placement
      // decides, and it is sticky.
      expect(
        SprintRepository.columnFor(
          snapshot.columns,
          snapshot.rows.first.tasks.first,
          explicitColumns: snapshot.explicitColumns,
        )!.name,
        'Verify',
      );
    });

    test('caches the snapshot and the cards, and reads both back', () async {
      final live = await repository.load(org, project, iterationId);

      final cached = await repository.cachedSnapshot(
        org,
        project,
        iterationId,
        team: team,
      );
      expect(cached, live);

      // With no team id (offline, where resolving it is a network read) the
      // cache is found by scanning.
      final scanned = await repository.cachedSnapshot(
        org,
        project,
        iterationId,
      );
      expect(scanned, live);

      final watched = await repository
          .watchItems(org, project, iterationId)
          .first;
      expect(watched.map((w) => w.id), [
        15546,
        15550,
        15551,
        15547,
        15553,
        15554,
      ]);
    });

    test('an unknown sprint has no cached snapshot', () async {
      expect(await repository.cachedSnapshot(org, project, 'nope'), isNull);
    });
  });

  group('capacities', () {
    test('reads teamMembers, team days off and the working days', () async {
      adapter
        ..answers['capacities'] = {
          'teamMembers': [
            {
              'teamMember': {'displayName': 'Kelly Kamm', 'id': 'k'},
              'activities': [
                {'capacityPerDay': 6.0, 'name': 'Development'},
              ],
              'daysOff': const [],
            },
          ],
          'totalCapacityPerDay': 6.0,
        }
        ..answers['teamdaysoff'] = {'daysOff': const []}
        ..answers['work/teamsettings?'] = {
          'workingDays': ['monday', 'tuesday'],
          'bugsBehavior': 'asTasks',
        };

      final capacity = await repository.capacities(org, project, iterationId);

      expect(
        adapter.firstMatching('capacities')!.uri.toString(),
        'https://dev.azure.com/$org/DevOps%20Mobile%20App/$team/_apis/work/'
        'teamsettings/iterations/$iterationId/capacities?api-version=7.1',
      );
      expect(capacity.members.single.capacityPerDay, 6);
      expect(capacity.workingDays, ['monday', 'tuesday']);
    });

    test('an empty capacity read is not a failure', () async {
      final capacity = await repository.capacities(org, project, iterationId);
      expect(capacity.isEmpty, isTrue);
    });
  });

  group('moveOps and the column call', () {
    final derived = SprintRepository.deriveColumns(
      taskTypes: const ['Task', 'Bug'],
      typeStates: {
        'Task': [
          const WorkItemState(name: 'New', category: 'Proposed'),
          const WorkItemState(name: 'Active', category: 'InProgress'),
          const WorkItemState(name: 'Resolved', category: 'Resolved'),
          const WorkItemState(name: 'Closed', category: 'Completed'),
          const WorkItemState(name: 'Removed', category: 'Removed'),
        ],
      },
    );

    test("a move writes the column's mapped state for that type", () {
      final ops = SprintRepository.moveOps(derived[1], item(1));

      expect(ops, [
        {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
      ]);
    });

    test('a card already in the column writes nothing', () {
      expect(SprintRepository.moveOps(derived[0], item(1)), isEmpty);
      // Resolved belongs to In Progress: dragging it there must not demote
      // it to Active.
      expect(
        SprintRepository.moveOps(derived[1], item(1, state: 'Resolved')),
        isEmpty,
      );
    });

    test('a move into Done writes the state and nothing else', () {
      // The first cut of this put a Remaining Work zero on the same patch,
      // because the web clears the hours when a task finishes. The service
      // refused it on the scratch project:
      //
      //   TF401320: Rule Error for field Remaining Work.
      //   Error code: InvalidNotEmpty.
      //
      // The stock processes rule that the field is *empty* on a completed
      // task, so a zero is as invalid as a four — and the rule does the
      // clearing itself. The page checks the item afterwards instead.
      expect(
        SprintRepository.moveOps(
          derived[2],
          item(1, state: 'Active', remaining: 4),
        ),
        [
          {'op': 'add', 'path': '/fields/System.State', 'value': 'Closed'},
        ],
      );
    });

    test('a task already in Done writes nothing at all', () {
      expect(
        SprintRepository.moveOps(
          derived[2],
          item(1, state: 'Closed', remaining: 2),
        ),
        isEmpty,
      );
    });

    test('moving out of Done leaves Remaining Work alone', () {
      expect(
        SprintRepository.moveOps(
          derived[1],
          item(1, state: 'Closed', remaining: 2),
        ),
        [
          {'op': 'add', 'path': '/fields/System.State', 'value': 'Active'},
        ],
      );
    });

    test('a derived board never needs the taskboard column call', () {
      expect(
        SprintRepository.needsColumnCall(derived, item(1), derived[1]),
        isFalse,
      );
    });

    test('a shared state needs it, an unshared one does not', () async {
      adapter.answers['taskboardcolumns'] = customizedColumns();
      final columns = await repository.columns(org, project);
      final task = item(15550);

      // In Progress and Verify both map Task → Active.
      expect(
        SprintRepository.needsColumnCall(columns, task, columns[2]),
        isTrue,
      );
      // Only Done maps Closed.
      expect(
        SprintRepository.needsColumnCall(columns, task, columns[3]),
        isFalse,
      );
    });

    test('move sends the state patch and then the column call', () async {
      adapter
        ..answers['taskboardcolumns'] = customizedColumns()
        ..answers['wit/workitems/'] = _item(
          15550,
          'Task',
          'Model the columns',
          'Active',
        )
        ..answers['taskboardworkitems'] = const <String, dynamic>{};
      final columns = await repository.columns(org, project);
      final task = item(15550, state: 'New');

      await repository.move(
        org,
        project,
        task,
        columns[2],
        columns: columns,
        iterationId: iterationId,
        team: team,
      );

      final patch = adapter.firstMatching('wit/workitems/15550')!;
      expect(patch.method, 'PATCH');
      expect((patch.data as List).first, {
        'op': 'test',
        'path': '/rev',
        'value': 3,
      });
      expect((patch.data as List).last, {
        'op': 'add',
        'path': '/fields/System.State',
        'value': 'Active',
      });
      final column = adapter.firstMatching('taskboardworkitems')!;
      expect(column.method, 'PATCH');
      expect(
        column.uri.toString(),
        'https://dev.azure.com/$org/DevOps%20Mobile%20App/$team/_apis/work/'
        'taskboardworkitems/$iterationId/15550?api-version=7.1-preview.1',
      );
      expect(column.data, {'newColumn': 'Verify'});
    });

    test('an unambiguous move sends only the state patch', () async {
      adapter
        ..answers['taskboardcolumns'] = customizedColumns()
        ..answers['wit/workitems/'] = _item(15550, 'Task', 'x', 'Closed');
      final columns = await repository.columns(org, project);

      await repository.move(
        org,
        project,
        item(15550, state: 'Active'),
        columns[3],
        columns: columns,
        iterationId: iterationId,
        team: team,
      );

      expect(adapter.firstMatching('wit/workitems/15550'), isNotNull);
      expect(adapter.firstMatching('taskboardworkitems'), isNull);
    });
  });

  group('distribute', () {
    test('places every card and never loses one', () async {
      final snapshot = await repository.load(org, project, iterationId);
      final byColumn = SprintRepository.distribute(
        snapshot.columns,
        snapshot.tasks,
      );

      // `tasks` is the unparented row first, then each row in rank order.
      expect(byColumn.length, 3);
      expect(byColumn[0].map((t) => t.id), [15553]); // New
      expect(byColumn[1].map((t) => t.id), [15554, 15550]); // Active
      expect(byColumn[2].map((t) => t.id), [15551]); // Closed
      expect(byColumn.fold(0, (n, c) => n + c.length), snapshot.tasks.length);
    });

    test('a state no column claims still lands somewhere', () {
      const columns = [
        TaskboardColumn(
          name: 'To Do',
          order: 0,
          mappings: {'Task': 'New'},
          states: {
            'Task': ['New'],
          },
        ),
      ];

      final out = SprintRepository.distribute(columns, [
        item(1, state: 'Nonsense'),
      ]);

      expect(out.single.single.id, 1);
      expect(SprintRepository.columnFor(columns, item(1, state: 'x')), isNull);
    });
  });

  group('writes', () {
    setUp(() {
      adapter.answers['wit/workitems/'] = _item(15550, 'Task', 'x', 'Active');
    });

    test('remaining work clears with 0, never null', () async {
      await repository.setRemainingWork(org, project, item(15550), null);

      final ops = (adapter.last.data as List).cast<Map>();
      expect(ops.last, {
        'op': 'add',
        'path': '/fields/Microsoft.VSTS.Scheduling.RemainingWork',
        'value': 0,
      });
      expect(ops.last['value'], isNot(isNull));
    });

    test('a whole number of hours is written as an int', () {
      expect(SprintRepository.remainingWorkOps(3)[0]['value'], 3);
      expect(SprintRepository.remainingWorkOps(2.5)[0]['value'], 2.5);
      expect(SprintRepository.remainingWorkOps(-1)[0]['value'], 0);
    });

    test('moving a sprint writes the iteration path', () async {
      await repository.setIteration(
        org,
        project,
        item(15550),
        r'DevOps Mobile App\Iteration 2',
      );

      final ops = (adapter.last.data as List).cast<Map>();
      expect(ops.first['op'], 'test');
      expect(ops.last, {
        'op': 'add',
        'path': '/fields/System.IterationPath',
        'value': r'DevOps Mobile App\Iteration 2',
      });
    });

    test('reorder carries the parent id', () async {
      adapter.answers['workitemsorder'] = {
        'count': 1,
        'value': [
          {'id': 15553, 'order': 1999955279.0},
        ],
      };

      final ranks = await repository.reorder(
        org,
        project,
        const [15553],
        previousId: 0,
        nextId: 15550,
        parentId: 15546,
        team: team,
      );

      expect(
        adapter.last.uri.toString(),
        'https://dev.azure.com/$org/DevOps%20Mobile%20App/$team/_apis/work/'
        'workitemsorder?api-version=7.1',
      );
      expect(adapter.last.data, {
        'ids': [15553],
        'previousId': 0,
        'nextId': 15550,
        'parentId': 15546,
      });
      expect(ranks[15553], 1999955279.0);
    });
  });
}
