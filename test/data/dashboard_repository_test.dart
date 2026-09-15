import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/db/json_cache.dart';
import 'package:boardhop/data/models/dashboard.dart';
import 'package:boardhop/data/repositories/dashboard_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const account = 'kelly@kammcs.com-home';
const org = 'puremedia';
const project = 'DevOps Mobile App';
const team = '8c08e1e1-7afd-411e-b414-4f9e1d14d8d6';
const dashboardId = '985ff75c-bdf6-4b2d-a2b0-0ef63431e6ec';
const dashboards = 'ms.vss-dashboards-web.Microsoft.VisualStudioOnline'
    '.Dashboards';

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

/// The scratch project's Overview, as the project route answers it: no
/// widgets, and `groupId` naming the team.
Map<String, dynamic> listAnswer() => {
  'count': 1,
  'value': [
    {
      'id': dashboardId,
      'name': 'Overview',
      'dashboardScope': 'project_Team',
      'groupId': team,
      'ownerId': team,
      'position': 1,
      'refreshInterval': 0,
    },
  ],
};

/// The same dashboard from the team-scoped GET by id, with three of the
/// thirteen widgets spike w36 wrote.
Map<String, dynamic> dashboardAnswer() => {
  'id': dashboardId,
  'name': 'Overview',
  'dashboardScope': 'project_Team',
  'groupId': team,
  'position': 1,
  'refreshInterval': 0,
  'eTag': '13',
  'widgets': [
    {
      'id': 'a36028f2-463a-43fa-89ef-f94d5eb4beac',
      'name': 'Query Tile',
      'contributionId': '$dashboards.QueryScalarWidget',
      'position': {'row': 1, 'column': 1},
      'size': {'rowSpan': 1, 'columnSpan': 1},
      'settings': '{"queryId":"8c808ce9-51d6-4cdf-a17a-17a70930d2f0"}',
      'settingsVersion': {'major': 1, 'minor': 0, 'patch': 0},
      'isEnabled': true,
    },
    {
      'id': '2d3d8855-ca6f-4229-984d-962dce3373a2',
      'name': 'Markdown',
      'contributionId': '$dashboards.MarkdownWidget',
      'position': {'row': 1, 'column': 7},
      'size': {'rowSpan': 2, 'columnSpan': 2},
      'settings': '## Boardhop scratch\n',
      'isEnabled': true,
    },
    {
      'id': '5a66bab2-181e-4ae4-8950-d355a94a0bae',
      'name': 'Pull Requests',
      'contributionId': '$dashboards.PullrequestsWidget',
      'position': {'row': 6, 'column': 4},
      'size': {'rowSpan': 2, 'columnSpan': 3},
      'settings': null,
      'isEnabled': true,
    },
  ],
};

void main() {
  late _FakeAdapter adapter;
  late AppDatabase db;
  late DashboardRepository repository;

  setUp(() {
    adapter = _FakeAdapter();
    db = AppDatabase(NativeDatabase.memory());
    repository = DashboardRepository(
      AdoClient(
        tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
        dio: Dio()..httpClientAdapter = adapter,
      ),
      db,
      account,
    );
  });

  tearDown(() => db.close());

  group('list', () {
    test('uses the project route at the preview version', () async {
      adapter.answers['dashboard/dashboards'] = listAnswer();

      final list = await repository.list(org, project);

      final uri = adapter.last.uri;
      expect(uri.host, 'dev.azure.com');
      // Project scope, no team segment: this route lists every team's.
      expect(
        uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/dashboard/dashboards',
      );
      // `api-version=7.1` is a 400 on every Dashboard resource.
      expect(uri.queryParameters['api-version'], '7.1-preview.3');
      expect(list.single.id, dashboardId);
      expect(list.single.name, 'Overview');
      // groupId is the team, which the GET by id needs.
      expect(list.single.teamId, team);
      expect(list.single.scope, DashboardScope.team);
      // The list carries no widgets at all.
      expect(list.single.widgetCount, isNull);
    });

    test('caches under dashboard:list and serves the second call', () async {
      adapter.answers['dashboard/dashboards'] = listAnswer();

      await repository.list(org, project);
      await repository.list(org, project);

      expect(adapter.requests.length, 1);
      final cached = await JsonCache(
        db,
        namespace: account,
      ).get(DashboardRepository.listKey(org, project));
      expect(cached, isNotNull);
    });

    test('refresh goes back to the service', () async {
      adapter.answers['dashboard/dashboards'] = listAnswer();

      await repository.list(org, project);
      await repository.list(org, project, refresh: true);

      expect(adapter.requests.length, 2);
    });

    test('cachedList answers without a request, or null', () async {
      expect(await repository.cachedList(org, project), isNull);
      adapter.answers['dashboard/dashboards'] = listAnswer();
      await repository.list(org, project);

      final before = adapter.requests.length;
      final cached = await repository.cachedList(org, project);
      expect(cached!.single.id, dashboardId);
      expect(adapter.requests.length, before);
    });

    test('a failure after a cached read keeps the cached list', () async {
      adapter.answers['dashboard/dashboards'] = listAnswer();
      await repository.list(org, project);

      adapter.status = 503;
      final list = await repository.list(org, project, refresh: true);
      expect(list.single.id, dashboardId);
    });

    test('a failure with nothing cached throws', () async {
      adapter.status = 500;
      expect(() => repository.list(org, project), throwsA(isA<Exception>()));
    });
  });

  group('get', () {
    test('takes the team segment, which the route needs', () async {
      adapter.answers['dashboards/$dashboardId'] = dashboardAnswer();

      final dashboard = await repository.get(org, project, team, dashboardId);

      expect(
        adapter.last.uri.path,
        '/$org/DevOps%20Mobile%20App/$team/_apis/dashboard/dashboards'
        '/$dashboardId',
      );
      expect(
        adapter.last.uri.queryParameters['api-version'],
        '7.1-preview.3',
      );
      expect(dashboard.widgets.length, 3);
      expect(dashboard.eTag, '13');
    });

    test('parses the widget kinds and their settings', () async {
      adapter.answers['dashboards/$dashboardId'] = dashboardAnswer();

      final dashboard = await repository.get(org, project, team, dashboardId);
      final byKind = {for (final w in dashboard.widgets) w.kind: w};

      expect(byKind.keys, containsAll(<WidgetKind>[
        WidgetKind.queryTile,
        WidgetKind.markdown,
        WidgetKind.pullRequests,
      ]));
      expect(
        (parseWidgetSettings(byKind[WidgetKind.queryTile]!)
                as QueryTileSettings)
            .queryId,
        '8c808ce9-51d6-4cdf-a17a-17a70930d2f0',
      );
      // Plain-text settings survive the cache and are not JSON.
      expect(byKind[WidgetKind.markdown]!.settingsJson, isNull);
      expect(
        (parseWidgetSettings(byKind[WidgetKind.markdown]!) as MarkdownSettings)
            .content,
        startsWith('## Boardhop scratch'),
      );
      expect(byKind[WidgetKind.pullRequests]!.settings, isNull);
    });

    test('is cache-first and cachedDashboard says how old the copy is',
        () async {
      adapter.answers['dashboards/$dashboardId'] = dashboardAnswer();

      await repository.get(org, project, team, dashboardId);
      await repository.get(org, project, team, dashboardId);
      expect(adapter.requests.length, 1);

      final cached = await repository.cachedDashboard(
        org,
        project,
        dashboardId,
      );
      expect(cached!.dashboard.widgets.length, 3);
      expect(
        DateTime.now().difference(cached.fetchedAt),
        lessThan(const Duration(minutes: 1)),
      );
    });

    test('cachedDashboard is null for a dashboard never opened', () async {
      expect(
        await repository.cachedDashboard(org, project, 'nope'),
        isNull,
      );
    });

    test('a failure falls back to the cached dashboard', () async {
      adapter.answers['dashboards/$dashboardId'] = dashboardAnswer();
      await repository.get(org, project, team, dashboardId);

      adapter.status = 500;
      final again = await repository.get(
        org,
        project,
        team,
        dashboardId,
        refresh: true,
      );
      expect(again.widgets.length, 3);
    });

    test('a 401 is never masked by the cache', () async {
      adapter.answers['dashboards/$dashboardId'] = dashboardAnswer();
      await repository.get(org, project, team, dashboardId);

      adapter.status = 401;
      await expectLater(
        repository.get(org, project, team, dashboardId, refresh: true),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('favorites', () {
    Map<String, dynamic> favoritesAnswer() => {
      'count': 2,
      'value': [
        {
          'id': 'f1',
          'artifactId': dashboardId,
          'artifactType': DashboardRepository.favoriteArtifactType,
          'artifactScope': {
            'id': '98720989-0195-48cb-ae2e-0e58ec1bb9a9',
            'type': 'Project',
            'name': project,
          },
        },
        {
          'id': 'f2',
          'artifactId': '11111111-1111-1111-1111-111111111111',
          'artifactType': DashboardRepository.favoriteArtifactType,
          'artifactScope': {
            'id': '22222222-2222-2222-2222-222222222222',
            'type': 'Project',
            'name': 'Another project',
          },
        },
      ],
    };

    test('asks the org-level Favorites API for dashboards', () async {
      adapter.answers['favorite/favorites'] = favoritesAnswer();

      final ids = await repository.favorites(org, project);

      final uri = adapter.last.uri;
      expect(uri.path, '/$org/_apis/favorite/favorites');
      expect(
        uri.queryParameters['artifactType'],
        'Microsoft.TeamFoundation.Dashboards.Dashboard',
      );
      expect(uri.queryParameters['artifactScopeType'], 'Project');
      expect(uri.queryParameters['api-version'], '7.1-preview.1');
      // Another project's favorite is not this project's.
      expect(ids, {dashboardId});
    });

    test('keeps an entry whose scope has no name', () async {
      adapter.answers['favorite/favorites'] = {
        'value': [
          {'artifactId': dashboardId},
        ],
      };
      expect(await repository.favorites(org, project), {dashboardId});
    });

    test('no favorites at all is an empty set, not a failure', () async {
      adapter.answers['favorite/favorites'] = {'count': 0, 'value': []};
      expect(await repository.favorites(org, project), isEmpty);
    });

    test('is cached per project', () async {
      adapter.answers['favorite/favorites'] = favoritesAnswer();
      await repository.favorites(org, project);
      await repository.favorites(org, project);
      expect(adapter.requests.length, 1);
    });
  });

  group('catalog', () {
    Map<String, dynamic> catalogAnswer() => {
      'widgetTypes': [
        {
          'contributionId': '$dashboards.IFrameWidget',
          'name': 'Embedded Webpage',
          'analyticsServiceRequired': false,
          'isVisibleFromCatalog': true,
        },
        {
          'contributionId': '$dashboards.CumulativeFlowDiagramWidget',
          'name': 'Cumulative Flow Diagram (CFD)',
          'analyticsServiceRequired': true,
          'isVisibleFromCatalog': true,
        },
      ],
    };

    test('reads widgettypes at project_Team scope', () async {
      adapter.answers['widgettypes'] = catalogAnswer();

      final types = await repository.catalog(org, project);

      final uri = adapter.last.uri;
      expect(
        uri.path,
        '/$org/DevOps%20Mobile%20App/_apis/dashboard/widgettypes',
      );
      expect(uri.queryParameters[r'$scope'], 'project_Team');
      expect(uri.queryParameters['api-version'], '7.1-preview.1');
      // The catalog answers `widgetTypes`, not `value`.
      expect(types.length, 2);
      expect(types.last.analyticsServiceRequired, isTrue);
    });

    test('catalogNames maps contributionId to the display name', () async {
      adapter.answers['widgettypes'] = catalogAnswer();

      final names = await repository.catalogNames(org, project);
      expect(names['$dashboards.IFrameWidget'], 'Embedded Webpage');
    });

    test('is cached for a week', () async {
      adapter.answers['widgettypes'] = catalogAnswer();
      await repository.catalog(org, project);
      await repository.catalog(org, project);
      expect(adapter.requests.length, 1);
      expect(DashboardRepository.catalogTtl, const Duration(days: 7));
    });
  });

  test('webUri is the web dashboard page', () {
    expect(
      DashboardRepository.webUri(org, project, dashboardId).toString(),
      'https://dev.azure.com/puremedia/DevOps%20Mobile%20App'
      '/_dashboards/dashboard/$dashboardId',
    );
  });

  test('cache keys are namespaced per account, org and project', () async {
    expect(
      DashboardRepository.listKey(org, project),
      'dashboard:list:$org:$project',
    );
    expect(
      DashboardRepository.dashboardKey(org, project, dashboardId),
      'dashboard:$org:$project:$dashboardId',
    );
  });
}
