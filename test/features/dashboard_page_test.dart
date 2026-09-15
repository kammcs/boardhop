import 'dart:async';

import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/dashboard.dart';
import 'package:boardhop/data/models/pipeline.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/dashboard_repository.dart';
import 'package:boardhop/data/repositories/people_repository.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/features/dashboards/dashboard_page.dart';
import 'package:boardhop/features/dashboards/team_overview.dart';
import 'package:boardhop/features/dashboards/widgets/dashboard_card.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Dashboards extends Mock implements DashboardRepository {}

class _Sprints extends Mock implements SprintRepository {}

class _WorkItems extends Mock implements WorkItemRepository {}

class _PullRequests extends Mock implements PullRequestRepository {}

class _Pipelines extends Mock implements PipelineRepository {}

class _People extends Mock implements PeopleRepository {}

class _Projects extends Mock implements ProjectRepository {}

class _AuthService extends Mock implements AuthService {}

/// The Dashboards view (research/19 D-B): what it opens on, what it hides,
/// how it lays out, and what pull-to-refresh does.
void main() {
  const org = 'o';
  const project = 'p';
  const team = 'team-1';
  const overviewId = 'dash-1';
  const me = 'kelly@kammcs.com';

  const phone = Size(1170, 2532);
  const tablet = Size(2048, 1536);

  DashboardWidget widget(
    String id,
    String name,
    String suffix, {
    int row = 1,
    int column = 1,
    int rowSpan = 1,
    int columnSpan = 1,
    String? settings,
    bool isEnabled = true,
  }) => DashboardWidget(
    id: id,
    name: name,
    contributionId:
        'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.$suffix',
    row: row,
    column: column,
    rowSpan: rowSpan,
    columnSpan: columnSpan,
    settings: settings,
    isEnabled: isEnabled,
  );

  Dashboard populated() => Dashboard(
    id: overviewId,
    name: 'Overview',
    scope: DashboardScope.team,
    teamId: team,
    widgets: [
      widget(
        'w1',
        'Open bugs',
        'QueryScalarWidget',
        settings: '{"queryId":"q-1","queryName":"Open bugs"}',
      ),
      widget('w2', 'My work', 'AssignedToMeWidget', column: 2, columnSpan: 2),
      widget('w3', 'Team', 'TeamMembersWidget', row: 2, columnSpan: 2),
      widget('w4', 'Links', 'WorkLinksWidget', row: 2, column: 3),
      // Named and laid out, drawn by the placeholder until D-C.
      widget(
        'w5',
        'Sprint burndown',
        'AnalyticsSprintBurndownWidget',
        row: 3,
        columnSpan: 2,
        settings:
            '{"team":{"projectId":"pid","teamId":"$team"},'
            '"iterationId":"iter-1"}',
      ),
      // Hidden: D2 (no chart route) and D10 (an iframe, a Marketplace
      // widget, and a query tile whose settings do not parse).
      widget('w6', 'Chart for work items', 'WitChartWidget', row: 4),
      widget('w7', 'Embedded page', 'IFrameWidget', row: 4, column: 2),
      widget(
        'w8',
        'Broken tile',
        'QueryScalarWidget',
        row: 4,
        column: 3,
        settings: '{"nothing":"useful"}',
      ),
    ],
  );

  Dashboard emptyDashboard() => const Dashboard(
    id: overviewId,
    name: 'Overview',
    scope: DashboardScope.team,
    teamId: team,
  );

  const summary = DashboardSummary(
    id: overviewId,
    name: 'Overview',
    scope: DashboardScope.team,
    teamId: team,
    position: 0,
  );
  const other = DashboardSummary(
    id: 'dash-2',
    name: 'Release board',
    scope: DashboardScope.team,
    teamId: team,
    position: 1,
  );

  late _Dashboards dashboards;
  late _Sprints sprints;
  late _WorkItems workItems;
  late _PullRequests pullRequests;
  late _Pipelines pipelines;
  late _People people;
  late _Projects projects;
  late _AuthService auth;
  late List<String> visited;
  late String location;

  setUpAll(() {
    registerFallbackValue(PrListFilter.toReview);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dashboards = _Dashboards();
    sprints = _Sprints();
    workItems = _WorkItems();
    pullRequests = _PullRequests();
    pipelines = _Pipelines();
    people = _People();
    projects = _Projects();
    auth = _AuthService();
    visited = <String>[];
    location = '';

    when(() => auth.accountById(any()))
        .thenReturn(Account(id: 'a', username: me, name: 'Kelly Kamm'));
    when(() => auth.knownAccounts).thenReturn(const []);

    when(() => dashboards.list(org, project, refresh: any(named: 'refresh')))
        .thenAnswer((_) async => const [summary, other]);
    when(() => dashboards.cachedDashboard(org, project, any()))
        .thenAnswer((_) async => null);
    when(
      () => dashboards.get(
        org,
        project,
        any(),
        any(),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => populated());
    when(
      () => dashboards.favorites(org, project, refresh: any(named: 'refresh')),
    ).thenAnswer((_) async => {overviewId});

    when(() => sprints.defaultTeamId(org, project))
        .thenAnswer((_) async => team);
    when(() => sprints.teams(org, project, refresh: any(named: 'refresh')))
        .thenAnswer(
          (_) async => const [SprintTeamRef(id: team, name: 'Probe team')],
        );
    when(
      () => sprints.iterations(
        org,
        project,
        team: any(named: 'team'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => const SprintIterations());

    when(() => workItems.types(org, project)).thenAnswer(
      (_) async => const [
        WorkItemType(name: 'Bug', referenceName: 'Microsoft.VSTS.Bug'),
      ],
    );
    when(() => workItems.watchList(org, project, any()))
        .thenAnswer((_) => Stream<List<WorkItem>>.value(const []));
    when(() => workItems.refreshAssignedToMe(org, project))
        .thenAnswer((_) async => const []);
    when(
      () => workItems.queryCount(org, project, any(), top: any(named: 'top')),
    ).thenAnswer((_) async => 7);
    when(
      () => workItems.refreshQuery(org, project, any(), top: any(named: 'top')),
    ).thenAnswer((_) async => const []);

    when(
      () => pullRequests.cachedList(
        org,
        project: any(named: 'project'),
        filter: any(named: 'filter'),
        repositoryId: any(named: 'repositoryId'),
      ),
    ).thenAnswer((_) async => null);
    when(
      () => pullRequests.list(
        org,
        project: any(named: 'project'),
        filter: any(named: 'filter'),
        status: any(named: 'status'),
        top: any(named: 'top'),
        repositoryId: any(named: 'repositoryId'),
      ),
    ).thenAnswer((_) async => const <PullRequest>[]);

    when(
      () => pipelines.runs(
        org,
        project,
        definitionId: any(named: 'definitionId'),
        top: any(named: 'top'),
        cache: any(named: 'cache'),
        queryOrder: any(named: 'queryOrder'),
      ),
    ).thenAnswer((_) async => const <BuildRun>[]);

    when(() => projects.watch(org))
        .thenAnswer((_) => Stream<List<Project>>.value(const []));
    when(
      () =>
          people.teamMembers(org, any(), any(), refresh: any(named: 'refresh')),
    ).thenAnswer(
      (_) async => const [
        IdentityRef(displayName: 'Ada Example', id: 'ada-id'),
      ],
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = phone,
    double devicePixelRatio = 3,
    String query = '',
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    final bloc = AuthBloc(auth);
    addTearDown(bloc.close);
    final router = GoRouter(
      initialLocation: '/a/u1/orgs/$org/projects/$project/dashboards$query',
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/dashboards',
          builder: (context, state) {
            location = state.uri.toString();
            return AccountScope(
              accountId: 'u1',
              child: DashboardPage(
                org: org,
                project: project,
                dashboardId: state.uri.queryParameters['dashboard'],
              ),
            );
          },
        ),
        for (final path in [
          '/a/:account/orgs/:org/projects/:project/work-items',
          '/a/:account/orgs/:org/projects/:project/work-items/:id',
          '/a/:account/orgs/:org/projects/:project/sprint',
          '/a/:account/orgs/:org/projects/:project/pipelines',
          '/a/:account/orgs/:org/projects/:project/repos',
          '/a/:account/orgs/:org/projects',
        ])
          GoRoute(
            path: path,
            builder: (context, state) {
              visited.add(state.uri.toString());
              return const Scaffold(body: Text('elsewhere'));
            },
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DashboardRepository>.value(value: dashboards),
          RepositoryProvider<SprintRepository>.value(value: sprints),
          RepositoryProvider<WorkItemRepository>.value(value: workItems),
          RepositoryProvider<PullRequestRepository>.value(value: pullRequests),
          RepositoryProvider<PipelineRepository>.value(value: pipelines),
          RepositoryProvider<PeopleRepository>.value(value: people),
          RepositoryProvider<ProjectRepository>.value(value: projects),
          RepositoryProvider<AuthService>.value(value: auth),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: MaterialApp.router(
            theme: BoardhopTheme.light(),
            routerConfig: router,
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  group('what the page opens on', () {
    testWidgets('the default team’s Overview, with its cards', (tester) async {
      await pump(tester);

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Probe team'), findsOneWidget);
      expect(find.text('Open bugs'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('My work'), findsOneWidget);
      expect(find.text('Team'), findsOneWidget);
      expect(find.text('Links'), findsOneWidget);
    });

    testWidgets('?dashboard= wins over the remembered one (deep link)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.dashboard_last_id:$org/$project': overviewId,
      });
      await pump(tester, query: '?dashboard=dash-2');

      verify(
        () => dashboards.get(
          org,
          project,
          team,
          'dash-2',
          refresh: any(named: 'refresh'),
        ),
      ).called(1);
    });

    testWidgets('the remembered dashboard is used when the route is plain', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.dashboard_last_id:$org/$project': 'dash-2',
      });
      await pump(tester);

      verify(
        () => dashboards.get(
          org,
          project,
          team,
          'dash-2',
          refresh: any(named: 'refresh'),
        ),
      ).called(1);
    });

    testWidgets('the cached copy draws first and says how old it is', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.dashboard_last_id:$org/$project': overviewId,
      });
      when(() => dashboards.cachedDashboard(org, project, overviewId))
          .thenAnswer(
            (_) async => (
              dashboard: populated(),
              fetchedAt: DateTime.now().subtract(const Duration(minutes: 8)),
            ),
          );
      // The network never answers, so what is on screen can only be cached.
      final never = Completer<List<DashboardSummary>>();
      when(() => dashboards.list(org, project, refresh: any(named: 'refresh')))
          .thenAnswer((_) => never.future);

      await pump(tester, settle: false);
      await tester.pump();
      await tester.pump();

      expect(find.text('Open bugs'), findsOneWidget);
      expect(find.textContaining('Updated 8m ago'), findsOneWidget);
      never.complete(const [summary]);
      await tester.pumpAndSettle();
    });
  });

  group('what is hidden', () {
    testWidgets('the D10 kinds are left out and counted in the footer', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Chart for work items'), findsNothing);
      expect(find.text('Embedded page'), findsNothing);
      expect(find.text('Broken tile'), findsNothing);
      expect(find.text('3 widgets not shown in Boardhop'), findsOneWidget);
    });

    testWidgets('one hidden widget reads in the singular', (tester) async {
      when(
        () => dashboards.get(
          org,
          project,
          any(),
          any(),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => Dashboard(
          id: overviewId,
          name: 'Overview',
          teamId: team,
          widgets: [
            widget('w1', 'Links', 'WorkLinksWidget'),
            widget('w2', 'Embedded page', 'IFrameWidget', column: 2),
          ],
        ),
      );
      await pump(tester);

      expect(find.text('1 widget not shown in Boardhop'), findsOneWidget);
    });

    testWidgets('a chart kind is named, not hidden', (tester) async {
      await pump(tester);

      expect(find.text('Sprint burndown'), findsOneWidget);
      expect(find.byType(ComingCard), findsOneWidget);
    });

    testWidgets('a disabled widget is dropped and not counted', (tester) async {
      when(
        () => dashboards.get(
          org,
          project,
          any(),
          any(),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => Dashboard(
          id: overviewId,
          name: 'Overview',
          teamId: team,
          widgets: [
            widget('w1', 'Links', 'WorkLinksWidget'),
            widget('w2', 'Off', 'IFrameWidget', column: 2, isEnabled: false),
          ],
        ),
      );
      await pump(tester);

      expect(find.textContaining('not shown in Boardhop'), findsNothing);
    });
  });

  group('empty dashboards', () {
    testWidgets('offer the Team overview (D1)', (tester) async {
      when(
        () => dashboards.get(
          org,
          project,
          any(),
          any(),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => emptyDashboard());
      await pump(tester);

      expect(find.text('This dashboard has no widgets.'), findsOneWidget);
      expect(find.text('Show the Team overview'), findsOneWidget);
    });

    testWidgets('the offer opens the six built-in cards', (tester) async {
      when(
        () => dashboards.get(
          org,
          project,
          any(),
          any(),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => emptyDashboard());
      await pump(tester);

      await tester.tap(find.text('Show the Team overview'));
      await tester.pumpAndSettle();

      expect(find.text(TeamOverview.name), findsOneWidget);
      expect(find.byType(ComingCard), findsNWidgets(6));
      expect(location, contains('dashboard=${TeamOverview.id}'));
    });
  });

  group('the picker', () {
    testWidgets('groups by team, stars favorites and lists Team overview', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();

      expect(find.text('Dashboards'), findsOneWidget);
      expect(find.text('Probe team'), findsWidgets);
      expect(find.text('Release board'), findsOneWidget);
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.text(TeamOverview.name), findsOneWidget);
    });

    testWidgets('picking another dashboard navigates with ?dashboard=', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byIcon(Icons.arrow_drop_down));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Release board'));
      await tester.pumpAndSettle();

      expect(location, contains('dashboard=dash-2'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dashboard_last_id:$org/$project'), 'dash-2');
    });
  });

  group('refresh', () {
    testWidgets('pull-to-refresh refetches and asks every card to reload', (
      tester,
    ) async {
      await pump(tester);
      clearInteractions(dashboards);
      clearInteractions(workItems);

      await tester.fling(find.text('Open bugs'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();

      verify(
        () => dashboards.get(org, project, team, overviewId, refresh: true),
      ).called(1);
      // The card reloaded itself off the page's bump.
      verify(
        () => workItems.queryCount(org, project, 'q-1', top: any(named: 'top')),
      ).called(greaterThanOrEqualTo(1));
    });
  });

  group('errors', () {
    testWidgets('a failure with nothing on screen is shown inline', (
      tester,
    ) async {
      when(() => dashboards.list(org, project, refresh: any(named: 'refresh')))
          .thenThrow(const AdoServerException('TF400813: no access'));
      await pump(tester);

      expect(find.text('TF400813: no access'), findsOneWidget);
    });

    testWidgets('the dashboard API refusing falls back to the Team overview', (
      tester,
    ) async {
      final askedToSignIn = Completer<void>();
      when(
        () => auth.signIn(
          loginHint: any(named: 'loginHint'),
          claims: any(named: 'claims'),
        ),
      ).thenAnswer((_) async {
        if (!askedToSignIn.isCompleted) askedToSignIn.complete();
        throw const AdoAuthException('sign-in cancelled');
      });
      // Verified on the simulator 2026-09-15: the dashboard resource
      // answers 401 TF400813 to a token every other resource accepts, so a
      // sign-in sheet cannot help and would loop.
      when(() => dashboards.list(org, project, refresh: any(named: 'refresh')))
          .thenThrow(
            const AdoAuthException(
              'TF400813: The user is not authorized to access this resource.',
              statusCode: 401,
            ),
          );
      await pump(tester);

      expect(askedToSignIn.isCompleted, isFalse);
      expect(find.text(TeamOverview.name), findsOneWidget);
      expect(find.byType(ComingCard), findsNWidgets(6));
      expect(
        find.textContaining('cannot read this project’s dashboards'),
        findsOneWidget,
      );
      expect(find.textContaining('TF400813'), findsOneWidget);
    });

    testWidgets('offline over a cached dashboard keeps the cards', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.dashboard_last_id:$org/$project': overviewId,
      });
      when(() => dashboards.cachedDashboard(org, project, overviewId))
          .thenAnswer(
            (_) async => (
              dashboard: populated(),
              fetchedAt: DateTime.now().subtract(const Duration(minutes: 2)),
            ),
          );
      when(() => dashboards.list(org, project, refresh: any(named: 'refresh')))
          .thenThrow(const AdoNetworkException('no route to host'));
      await pump(tester);

      expect(find.text('Open bugs'), findsOneWidget);
      expect(
        find.textContaining('offline · showing the cached copy'),
        findsOneWidget,
      );
    });
  });

  group('layout', () {
    testWidgets('a phone stacks every card in one column', (tester) async {
      await pump(tester);

      final cards = tester.widgetList<Card>(find.byType(Card)).toList();
      expect(cards, isNotEmpty);
      final boxes = [
        for (final card in find.byType(Card).evaluate())
          tester.getRect(find.byWidget(card.widget)),
      ];
      // One column: every card starts at the same left edge.
      expect(boxes.map((r) => r.left).toSet().length, 1);
    });

    testWidgets('a tablet packs the web’s spans into a grid', (tester) async {
      await pump(tester, size: tablet, devicePixelRatio: 2);

      final tile = tester.getRect(
        find.ancestor(of: find.text('Open bugs'), matching: find.byType(Card)),
      );
      final mine = tester.getRect(
        find.ancestor(of: find.text('My work'), matching: find.byType(Card)),
      );
      // Side by side, and the two-wide card is wider than the one-wide one.
      expect(mine.left, greaterThan(tile.left));
      expect(mine.top, closeTo(tile.top, 1));
      expect(mine.width, greaterThan(tile.width));
    });
  });
}
