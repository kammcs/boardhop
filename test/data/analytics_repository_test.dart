import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/repositories/analytics_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';
const org = 'puremedia';
const project = 'CloudCover 2.0';
const iterationId = 'cc106106-0000-0000-0000-000000000106';
const iterationSk = 'ffffffff-0000-0000-0000-000000000106';
const secondIterationSk = 'ffffffff-0000-0000-0000-000000000105';
const team = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6';

class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final Map<String, Object> answers = <String, Object>{};
  int status = 200;

  RequestOptions get last => requests.last;
  RequestOptions? firstMatching(String part) =>
      requests.where((r) => r.uri.toString().contains(part)).firstOrNull;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final path = options.uri.toString();
    final keys = answers.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final key = keys.firstWhere(path.contains, orElse: () => '');
    return ResponseBody.fromString(
      jsonEncode(answers[key] ?? const <String, dynamic>{'value': []}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Two days x three categories, the shape spike s55 saw on CloudCover 106.
Map<String, dynamic> snapshotRows() => {
  '@odata.context': 'https://analytics.dev.azure.com/$org/_odata/\$metadata',
  'value': [
    _row('2026-08-25T00:00:00Z', 'Completed', 8, 3),
    _row('2026-08-25T00:00:00Z', 'InProgress', 72, 47),
    _row('2026-08-25T00:00:00Z', 'Proposed', 39, 16),
    _row('2026-08-26T00:00:00Z', 'Completed', 11, 5),
    _row('2026-08-26T00:00:00Z', 'InProgress', 76, 49),
    _row('2026-08-26T00:00:00Z', 'Proposed', 26, 4),
    _row('2026-08-26T00:00:00Z', 'Removed', 2, 1),
  ],
};

Map<String, dynamic> _row(String date, String category, int count, num sp) => {
  'DateValue': date,
  'StateCategory': category,
  'Count': count,
  'SP': sp,
};

void main() {
  late _FakeAdapter adapter;
  late AppDatabase db;
  late AnalyticsRepository repository;

  final start = DateTime.utc(2026, 8, 25);
  final end = DateTime.utc(2026, 8, 26);

  setUp(() {
    adapter = _FakeAdapter()..answers['WorkItemSnapshot'] = snapshotRows();
    db = AppDatabase(NativeDatabase.memory());
    repository = AnalyticsRepository(
      AdoClient(
        tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
        dio: Dio()..httpClientAdapter = adapter,
      ),
      db,
      account,
    );
  });

  tearDown(() => db.close());

  test(
    r'calls the project-scoped OData host with the $apply pipeline',
    () async {
      await repository.burndown(
        org,
        project,
        iterationId,
        start: start,
        end: end,
      );

      final uri = adapter.last.uri;
      expect(uri.host, 'analytics.dev.azure.com');
      // The org-level route with no project segment is 403 for everyone.
      expect(
        uri.path,
        '/$org/CloudCover%202.0/_odata/v4.0-preview/WorkItemSnapshot',
      );
      expect(uri.query, contains('IterationSK%20eq%20$iterationId'));
      expect(uri.query, contains('DateValue%20ge%202026-08-25Z'));
      expect(uri.query, contains('DateValue%20le%202026-08-26Z'));
      expect(uri.query, contains('groupby((DateValue,StateCategory)'));
      expect(uri.query, contains(r'aggregate($count%20as%20Count'));
      expect(uri.query, contains('StoryPoints%20with%20sum%20as%20SP'));
      expect(uri.query, contains(r'$orderby=DateValue%20asc'));
      // No api-version: the version is the path segment.
      expect(uri.query, isNot(contains('api-version')));
      expect(adapter.last.headers['Authorization'], 'Bearer tok');
    },
  );

  test('groups the rows into one day each', () async {
    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(days.length, 2);
    expect(days.first.date, DateTime.utc(2026, 8, 25));
    expect(days.first.remaining, 111); // 72 InProgress + 39 Proposed
    expect(days.first.done, 8);
    expect(days.first.points, 63); // 47 + 16
    expect(days.first.scope, 119);
    // Removed counts towards neither series.
    expect(days.last.remaining, 102);
    expect(days.last.done, 11);
  });

  test('keeps the days in date order whatever the rows do', () async {
    adapter.answers['WorkItemSnapshot'] = {
      'value': [
        _row('2026-08-26T00:00:00Z', 'Proposed', 1, 1),
        _row('2026-08-25T00:00:00Z', 'Proposed', 2, 2),
      ],
    };

    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(days.map((d) => d.date.day), [25, 26]);
  });

  test('an empty answer retries through the Iterations lookup', () async {
    adapter.answers['WorkItemSnapshot'] = {'value': const []};
    adapter.answers['Iterations?'] = {
      'value': [
        {
          'IterationSK': iterationSk,
          'IterationName': 'Iteration 106',
          'StartDate': '2026-08-25T00:00:00-05:00',
          'EndDate': '2026-09-07T00:00:00-05:00',
        },
      ],
    };
    // The retry finds rows under the real SK.
    adapter.answers['IterationSK%20eq%20$iterationSk'] = snapshotRows();

    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(adapter.requests.length, 3);
    expect(
      adapter.firstMatching('Iterations?')!.uri.query,
      contains('IterationId%20eq%20$iterationId'),
    );
    expect(days.length, 2);
  });

  test('no lookup when the first call already answered', () async {
    await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(adapter.requests.length, 1);
    expect(adapter.firstMatching('Iterations?'), isNull);
  });

  test('403 is AnalyticsUnavailable, not a sign-in prompt', () async {
    adapter.status = 403;

    await expectLater(
      repository.burndown(org, project, iterationId, start: start, end: end),
      throwsA(isA<AnalyticsUnavailable>()),
    );
    // A page that catches AdoAuthException must not see this one, or it
    // would throw the user into interactive sign-in for a chart.
    expect(
      await repository
          .burndown(org, project, iterationId, start: start, end: end)
          .then<Object?>((_) => null, onError: (Object e) => e),
      isNot(isA<AdoAuthException>()),
    );
  });

  test('401 is AnalyticsUnavailable too', () async {
    adapter.status = 401;

    await expectLater(
      repository.burndown(org, project, iterationId, start: start, end: end),
      throwsA(isA<AnalyticsUnavailable>()),
    );
  });

  test('a second call is answered from the cache', () async {
    await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );

    expect(adapter.requests.length, 1);
    expect(days.length, 2);
  });

  test('the cache answers when the network is gone', () async {
    await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
    );
    adapter.status = 500;

    final days = await repository.burndown(
      org,
      project,
      iterationId,
      start: start,
      end: end,
      refresh: true,
    );

    expect(days.length, 2);
  });

  test('the cache key is the last day the window covers', () {
    expect(
      AnalyticsRepository.burndownKey(
        org,
        project,
        iterationId,
        DateTime.utc(2026, 9, 7, 23),
      ),
      'analytics:burndown:$org:$project:$iterationId:2026-09-07',
    );
  });

  // ------------------------------------------- the dashboard queries (D-A)

  group('teamSk', () {
    test('confirms the surrogate key and caches it for a week', () async {
      adapter.answers['Teams?'] = {
        'value': [
          {'TeamSK': team, 'TeamName': 'A Team'},
        ],
      };

      expect(await repository.teamSk(org, project, team), team);
      expect(adapter.last.uri.query, contains('TeamSK%20eq%20$team'));

      await repository.teamSk(org, project, team);
      expect(adapter.requests.length, 1);
    });

    test('falls back to the team GUID when Analytics knows nothing', () async {
      adapter.answers['Teams?'] = {'value': const []};
      expect(await repository.teamSk(org, project, team), team);
    });
  });

  group('requirementTypes', () {
    test('lists the non-hidden types of the requirement backlog', () async {
      adapter.answers['Processes?'] = {
        'value': [
          {
            'WorkItemType': 'User Story',
            'BacklogType': 'RequirementBacklog',
            'IsHiddenType': false,
          },
          {
            'WorkItemType': 'Hidden Thing',
            'BacklogType': 'RequirementBacklog',
            'IsHiddenType': true,
          },
          {'WorkItemType': 'Bug', 'BacklogType': 'RequirementBacklog'},
        ],
      };

      final types = await repository.requirementTypes(org, project, team);

      expect(types, ['Bug', 'User Story']);
      expect(
        adapter.last.uri.query,
        contains("BacklogType%20eq%20'RequirementBacklog'"),
      );
    });
  });

  group('teamBurndown', () {
    test('is the snapshot query filtered by team, types and range', () async {
      adapter.answers['WorkItemSnapshot'] = snapshotRows();

      final days = await repository.teamBurndown(
        org,
        project,
        team,
        const ['User Story', 'Bug'],
        DateTime.utc(2026, 8, 25),
        DateTime.utc(2026, 8, 26),
      );

      final query = adapter.last.uri.query;
      expect(query, contains('Teams/any(t:t/TeamSK%20eq%20$team)'));
      expect(query, contains("WorkItemType%20eq%20'User%20Story'"));
      expect(query, contains("WorkItemType%20eq%20'Bug'"));
      expect(query, contains('DateValue%20ge%202026-08-25Z'));
      expect(query, contains('DateValue%20le%202026-08-26Z'));
      expect(query, contains('StoryPoints%20with%20sum%20as%20SP'));
      // Same parser as the sprint burndown.
      expect(days.length, 2);
      expect(days.first.remaining, 111);
    });

    test('no types at all means no type clause', () async {
      adapter.answers['WorkItemSnapshot'] = snapshotRows();
      await repository.teamBurndown(
        org,
        project,
        team,
        const [],
        DateTime.utc(2026, 8, 25),
        DateTime.utc(2026, 8, 26),
      );
      expect(adapter.last.uri.query, isNot(contains('WorkItemType')));
    });

    test('a sum field other than story points rides in the aggregate',
        () async {
      adapter.answers['WorkItemSnapshot'] = snapshotRows();
      await repository.teamBurndown(
        org,
        project,
        team,
        const [],
        DateTime.utc(2026, 8, 25),
        DateTime.utc(2026, 8, 26),
        sumField: 'Effort',
      );
      expect(adapter.last.uri.query, contains('Effort%20with%20sum%20as%20SP'));
    });
  });

  group('velocity', () {
    void seedVelocity() {
      adapter.answers['Iterations?'] = {
        'value': [
          {
            'IterationSK': iterationSk,
            'IterationName': 'Iteration 1',
            'StartDate': '2026-09-08T00:00:00-07:00',
            'EndDate': '2026-09-21T23:59:59.999-07:00',
            'IsEnded': false,
          },
          {
            'IterationSK': secondIterationSk,
            'IterationName': 'Iteration 0',
            'StartDate': '2026-08-25T00:00:00-07:00',
            'EndDate': '2026-09-07T23:59:59.999-07:00',
            'IsEnded': true,
          },
        ],
      };
      adapter.answers['CompletedDate%20le%20Iteration/EndDate'] = {
        'value': [
          {'IterationSK': iterationSk, 'Count': 3, 'SP': 8.0},
        ],
      };
      adapter.answers['CompletedDate%20gt%20Iteration/EndDate'] = {
        'value': [
          {'IterationSK': iterationSk, 'Count': 1, 'SP': 2.0},
        ],
      };
      adapter.answers['groupby((IterationSK,StateCategory)'] = {
        'value': [
          {
            'IterationSK': iterationSk,
            'StateCategory': 'Completed',
            'Count': 4,
            'SP': 10.0,
          },
          {
            'IterationSK': iterationSk,
            'StateCategory': 'InProgress',
            'Count': 2,
            'SP': 5.0,
          },
        ],
      };
      adapter.answers['WorkItemSnapshot'] = {
        'value': [
          {'Planned': 7, 'SP': 18.0},
        ],
      };
    }

    test('fans the four groupbys and the per-iteration snapshots out',
        () async {
      seedVelocity();

      final bars = await repository.velocity(
        org,
        project,
        team,
        const ['User Story'],
        iterations: 2,
      );

      // 1 Iterations + 3 groupbys + one snapshot per iteration.
      expect(adapter.requests.length, 1 + 3 + 2);
      // The three groupbys and both snapshots go out together, never an
      // or-chain of (IterationSK, DateSK) pairs: six of those took 55 s.
      final snapshots = adapter.requests
          .where((r) => r.uri.path.endsWith('WorkItemSnapshot'))
          .toList();
      expect(snapshots.length, 2);
      for (final snapshot in snapshots) {
        expect(snapshot.uri.query, contains('IterationSK%20eq%20'));
        expect(snapshot.uri.query, contains('DateSK%20eq%20'));
        expect(snapshot.uri.query, isNot(contains('%20or%20(IterationSK')));
      }
      expect(bars.length, 2);
    });

    test('asks for the last N dated iterations, newest first', () async {
      seedVelocity();
      await repository.velocity(org, project, team, const [], iterations: 6);

      final iterations = adapter.firstMatching('Iterations?')!.uri.query;
      expect(iterations, contains('Teams/any(t:t/TeamSK%20eq%20$team)'));
      expect(iterations, contains('StartDate%20ne%20null'));
      expect(iterations, contains(r'$orderby=StartDate%20desc'));
      expect(iterations, contains(r'$top=6'));
    });

    test('splits completed, late and incomplete per iteration', () async {
      seedVelocity();

      final bars = await repository.velocity(
        org,
        project,
        team,
        const ['User Story'],
        iterations: 2,
      );
      final first = bars.first;

      expect(first.iteration.sk, iterationSk);
      expect(first.iteration.name, 'Iteration 1');
      expect(first.completed, 3);
      expect(first.completedPoints, 8);
      expect(first.completedLate, 1);
      expect(first.totalCompleted, 4);
      // 6 in the iteration - 3 on time - 1 late.
      expect(first.incomplete, 2);
      expect(first.planned, 7);
      expect(first.plannedPoints, 18);
      // The second iteration has no rows in any bucket.
      expect(bars.last.completed, 0);
      expect(bars.last.incomplete, 0);
    });

    test('no dated iterations is an empty chart, not a failure', () async {
      adapter.answers['Iterations?'] = {'value': const []};
      expect(await repository.velocity(org, project, team, const []), isEmpty);
      // Nothing else was asked for.
      expect(adapter.requests.length, 1);
    });

    test('caches the whole fan-out under one key', () async {
      seedVelocity();
      await repository.velocity(org, project, team, const [], iterations: 2);
      final first = adapter.requests.length;
      await repository.velocity(org, project, team, const [], iterations: 2);
      expect(adapter.requests.length, first);
    });
  });

  group('cumulativeFlow', () {
    void seedCfd() {
      adapter.answers['BoardLocations'] = {
        'value': [
          {'ColumnName': 'Active', 'ColumnOrder': 1},
          {'ColumnName': 'New', 'ColumnOrder': 0},
          {'ColumnName': 'Closed', 'ColumnOrder': 3},
          {'ColumnName': 'Resolved', 'ColumnOrder': 2},
        ],
      };
      adapter.answers['WorkItemBoardSnapshot'] = {
        'value': [
          {
            'DateValue': '2026-09-14T00:00:00-07:00',
            'ColumnName': 'Active',
            'Count': 5,
          },
          {
            'DateValue': '2026-09-14T00:00:00-07:00',
            'ColumnName': 'New',
            'Count': 2,
          },
          {
            'DateValue': '2026-09-15T00:00:00-07:00',
            'ColumnName': 'Active',
            'Count': 6,
          },
          {
            'DateValue': '2026-09-15T00:00:00-07:00',
            'ColumnName': 'Closed',
            'Count': 1,
          },
        ],
      };
    }

    test('reads the current columns and the snapshots, in parallel', () async {
      seedCfd();

      final cfd = await repository.cumulativeFlow(
        org,
        project,
        team,
        'Stories',
        DateTime.utc(2026, 8, 16),
      );

      final columns = adapter.firstMatching('BoardLocations')!.uri.query;
      expect(columns, contains('Team/TeamSK%20eq%20$team'));
      expect(columns, contains("BoardName%20eq%20'Stories'"));
      expect(columns, contains('IsCurrent%20eq%20true'));

      final snapshot = adapter.firstMatching('WorkItemBoardSnapshot')!.uri.query;
      // Grouped by name alone: ColumnOrder splits a renamed column in two.
      expect(snapshot, contains('groupby((DateValue,ColumnName)'));
      expect(snapshot, contains('DateValue%20ge%202026-08-16Z'));

      expect(cfd.columns, ['New', 'Active', 'Resolved', 'Closed']);
      expect(cfd.days.length, 2);
      expect(cfd.days.first.date, DateTime.utc(2026, 9, 14));
      expect(cfd.days.first.countFor('Active'), 5);
      // Every column gets a value on every day, even when it had no rows.
      expect(cfd.days.first.countFor('Closed'), 0);
      expect(cfd.days.last.total, 7);
    });

    test('a column the board no longer has keeps its history, at the end',
        () async {
      seedCfd();
      adapter.answers['WorkItemBoardSnapshot'] = {
        'value': [
          {
            'DateValue': '2026-09-15T00:00:00-07:00',
            'ColumnName': 'Retired',
            'Count': 3,
          },
        ],
      };

      final cfd = await repository.cumulativeFlow(
        org,
        project,
        team,
        'Stories',
        DateTime.utc(2026, 8, 16),
      );
      expect(cfd.columns.last, 'Retired');
      expect(cfd.days.single.countFor('Retired'), 3);
    });

    test('a board name with an apostrophe is escaped, not broken', () async {
      seedCfd();
      await repository.cumulativeFlow(
        org,
        project,
        team,
        "Kelly's board",
        DateTime.utc(2026, 8, 16),
      );
      expect(
        adapter.firstMatching('BoardLocations')!.uri.query,
        contains("BoardName%20eq%20'Kelly''s%20board'"),
      );
    });
  });

  group('cycleAndLeadTime', () {
    test('lists the completed items and averages them here', () async {
      adapter.answers['WorkItems?'] = {
        'value': [
          {
            'WorkItemId': 15540,
            'WorkItemType': 'User Story',
            'State': 'Closed',
            'CycleTimeDays': 2.0,
            'LeadTimeDays': 10.0,
            'CompletedDate': '2026-09-01T00:00:00Z',
          },
          {
            'WorkItemId': 15541,
            'WorkItemType': 'User Story',
            'State': 'Closed',
            'CycleTimeDays': 4.0,
            'LeadTimeDays': 20.0,
            'CompletedDate': '2026-09-02T00:00:00Z',
          },
          {
            'WorkItemId': 15542,
            'WorkItemType': 'Bug',
            'State': 'Closed',
            'CycleTimeDays': null,
            'LeadTimeDays': 6.0,
            'CompletedDate': '2026-09-03T00:00:00Z',
          },
        ],
      };

      final result = await repository.cycleAndLeadTime(
        org,
        project,
        team,
        DateTime.utc(2026, 7, 17),
      );

      final query = adapter.last.uri.query;
      expect(query, contains("StateCategory%20eq%20'Completed'"));
      expect(query, contains('CompletedDate%20ge%202026-07-17Z'));
      expect(query, contains('CycleTimeDays'));
      expect(query, contains('LeadTimeDays'));
      expect(result.count, 3);
      // An item that was never started has no cycle time and is not averaged.
      expect(result.averageCycleDays, 3);
      expect(result.averageLeadDays, 12);
    });

    test('an empty window has no averages at all', () async {
      adapter.answers['WorkItems?'] = {'value': const []};
      final result = await repository.cycleAndLeadTime(
        org,
        project,
        team,
        DateTime.utc(2026, 7, 17),
      );
      expect(result.isEmpty, isTrue);
      expect(result.averageCycleDays, isNull);
    });
  });

  group('workByState', () {
    test('groups by type, state and category, without Removed', () async {
      adapter.answers['WorkItems?'] = {
        'value': [
          {
            'WorkItemType': 'User Story',
            'State': 'Active',
            'StateCategory': 'InProgress',
            'Count': 6,
          },
          {
            'WorkItemType': 'Bug',
            'State': 'New',
            'StateCategory': 'Proposed',
            'Count': 1,
          },
        ],
      };

      final rows = await repository.workByState(org, project, team);

      final query = adapter.last.uri.query;
      expect(query, contains("StateCategory%20ne%20'Removed'"));
      expect(query, contains('groupby((WorkItemType,State,StateCategory)'));
      expect(rows.length, 2);
      expect(rows.first.workItemType, 'User Story');
      expect(rows.first.count, 6);
    });
  });

  group('pipelineOutcomes', () {
    test('reads the aggregate and the last runs together', () async {
      adapter.answers[r'$apply=filter(PipelineId'] = {
        'value': [
          {
            'TotalCount': 19,
            'Succeeded': 7,
            'Failed': 10,
            'Partial': 0,
            'Canceled': 2,
          },
        ],
      };
      adapter.answers[r'$filter=PipelineId'] = {
        'value': [
          {
            'PipelineRunId': 501,
            'RunNumber': '20260914.1',
            'RunOutcome': 'Succeed',
            'CompletedDate': '2026-09-14T10:00:00Z',
            'RunDurationSeconds': 95.0,
          },
          {
            'PipelineRunId': 500,
            'RunNumber': '20260913.2',
            'RunOutcome': 'Failed',
            'CompletedDate': '2026-09-13T10:00:00Z',
          },
        ],
      };

      final outcomes = await repository.pipelineOutcomes(
        org,
        project,
        139,
        DateTime.utc(2026, 6, 17),
      );

      expect(adapter.requests.length, 2);
      expect(
        adapter.firstMatching(r'$apply=filter(PipelineId')!.uri.query,
        contains('CompletedDate%20ge%202026-06-17Z'),
      );
      expect(
        adapter.firstMatching(r'$filter=PipelineId')!.uri.query,
        contains(r'$top=20'),
      );
      expect(outcomes.total, 19);
      expect(outcomes.succeeded, 7);
      expect(outcomes.failed, 10);
      expect(outcomes.canceled, 2);
      // Canceled runs never reached a verdict.
      expect(outcomes.passRate, closeTo(7 / 17, 0.001));
      expect(outcomes.runs.length, 2);
      // `Succeed`, not `Succeeded`.
      expect(outcomes.runs.first.succeeded, isTrue);
      expect(outcomes.runs.last.failed, isTrue);
    });

    test('a pipeline that never ran has no pass rate', () async {
      final outcomes = await repository.pipelineOutcomes(
        org,
        project,
        139,
        DateTime.utc(2026, 6, 17),
      );
      expect(outcomes.total, 0);
      expect(outcomes.passRate, isNull);
    });
  });

  group('refusals and caching (D14)', () {
    test('a 401 from the Analytics host is AnalyticsUnavailable', () async {
      adapter.status = 401;
      await expectLater(
        repository.workByState(org, project, team),
        throwsA(isA<AnalyticsUnavailable>()),
      );
    });

    test('a 403 is AnalyticsUnavailable too, on every query', () async {
      adapter.status = 403;
      await expectLater(
        repository.cycleAndLeadTime(org, project, team, DateTime.utc(2026)),
        throwsA(isA<AnalyticsUnavailable>()),
      );
      await expectLater(
        repository.cumulativeFlow(
          org,
          project,
          team,
          'Stories',
          DateTime.utc(2026),
        ),
        throwsA(isA<AnalyticsUnavailable>()),
      );
      await expectLater(
        repository.velocity(org, project, team, const []),
        throwsA(isA<AnalyticsUnavailable>()),
      );
      await expectLater(
        repository.pipelineOutcomes(org, project, 139, DateTime.utc(2026)),
        throwsA(isA<AnalyticsUnavailable>()),
      );
    });

    test('a server error falls back to the cached answer', () async {
      adapter.answers['WorkItems?'] = {
        'value': [
          {
            'WorkItemType': 'Bug',
            'State': 'New',
            'StateCategory': 'Proposed',
            'Count': 1,
          },
        ],
      };
      await repository.workByState(org, project, team);

      adapter.status = 500;
      final rows = await repository.workByState(
        org,
        project,
        team,
        refresh: true,
      );
      expect(rows.single.count, 1);
    });

    test('a server error with nothing cached rethrows', () async {
      adapter.status = 500;
      await expectLater(
        repository.workByState(org, project, team),
        throwsA(isA<AdoException>()),
      );
    });

    test('the cache key carries the kind, the scope and the day', () {
      final key = AnalyticsRepository.cacheKey(
        'velocity',
        org,
        project,
        team,
        '6',
      );
      expect(key, startsWith('analytics:velocity:$org:$project:$team:6:'));
      expect(AnalyticsRepository.dashboardTtl, const Duration(hours: 1));
    });
  });

}
