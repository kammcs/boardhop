import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/models/analytics.dart';
import 'package:boardhop/data/models/dashboard.dart';
import 'package:boardhop/data/repositories/analytics_repository.dart';
import 'package:boardhop/data/repositories/dashboard_repository.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/features/dashboards/chart_focus_page.dart';
import 'package:boardhop/features/dashboards/charts/chart_format.dart';
import 'package:boardhop/features/dashboards/charts/chart_payload.dart';
import 'package:boardhop/features/dashboards/charts/work_state_bars.dart';
import 'package:boardhop/features/dashboards/team_overview.dart';
import 'package:boardhop/features/dashboards/widgets/chart_card.dart';
import 'package:boardhop/features/dashboards/widgets/dashboard_card.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart';

class _Analytics extends Mock implements AnalyticsRepository {}

class _Sprints extends Mock implements SprintRepository {}

class _Pipelines extends Mock implements PipelineRepository {}

class _Dashboards extends Mock implements DashboardRepository {}

class _AuthService extends Mock implements AuthService {}

/// The chart focus view (research/19 D7, D15): the chart larger, the legend
/// under it in portrait and beside it in landscape, and the series as a
/// list of numbers either way.
void main() {
  const org = 'o';
  const project = 'p';
  const team = 'team-1';

  final today = DateTime.utc(2026, 9, 15);

  const phonePortrait = Size(1170, 2532);
  const phoneLandscape = Size(2532, 1170);
  const tabletPortrait = Size(2048, 2732);

  late _Analytics analytics;
  late _Sprints sprints;
  late _Pipelines pipelines;
  late _Dashboards dashboards;
  late _AuthService auth;

  WorkByStatePayload payload() => WorkByStatePayload(
    title: 'Work by state',
    counts: const [
      WorkStateCount(
        workItemType: 'Bug',
        state: 'New',
        stateCategory: 'Proposed',
        count: 3,
      ),
      WorkStateCount(
        workItemType: 'User Story',
        state: 'Closed',
        stateCategory: 'Completed',
        count: 7,
      ),
    ],
  );

  setUpAll(() {
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    analytics = _Analytics();
    sprints = _Sprints();
    pipelines = _Pipelines();
    dashboards = _Dashboards();
    auth = _AuthService();

    when(() => auth.accountById(any())).thenReturn(
      Account(id: 'a', username: 'kelly@kammcs.com', name: 'Kelly Kamm'),
    );
    when(() => auth.knownAccounts).thenReturn(const []);
    when(() => sprints.defaultTeamId(org, project))
        .thenAnswer((_) async => team);
    when(
      () =>
          analytics.teamSk(org, project, any(), refresh: any(named: 'refresh')),
    ).thenAnswer((_) async => team);
  });

  Future<void> pumpView(
    WidgetTester tester,
    ChartPayload chart, {
    Size size = phonePortrait,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(body: ChartFocusView(payload: chart)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    ChartFocusArgs? initial,
    String widgetId = 'boardhop.by-state',
    String? dashboardId,
    Size size = phonePortrait,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bloc = AuthBloc(auth);
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AnalyticsRepository>.value(value: analytics),
          RepositoryProvider<SprintRepository>.value(value: sprints),
          RepositoryProvider<PipelineRepository>.value(value: pipelines),
          RepositoryProvider<DashboardRepository>.value(value: dashboards),
          RepositoryProvider<AuthService>.value(value: auth),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: MaterialApp(
            theme: BoardhopTheme.light(),
            home: AccountScope(
              accountId: 'u1',
              child: ChartFocusPage(
                org: org,
                project: project,
                widgetId: widgetId,
                dashboardId: dashboardId,
                initial: initial,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the route', () {
    test('carries the widget and the dashboard it sits on', () {
      expect(
        Routes.chartFocus(
          'u1',
          'puremedia',
          'DevOps Mobile App',
          widget: 'boardhop.velocity',
          dashboard: TeamOverview.id,
        ),
        '/a/u1/orgs/puremedia/projects/DevOps%20Mobile%20App'
        '/chart/boardhop.velocity?dashboard=boardhop-team-overview',
      );
    });

    test('leaves the dashboard out when there is none', () {
      expect(
        Routes.chartFocus('u1', 'o', 'p', widget: 'w1'),
        '/a/u1/orgs/o/projects/p/chart/w1',
      );
    });
  });

  group('layout', () {
    testWidgets('portrait puts the legend under the chart and the data '
        'below it (D15)', (tester) async {
      await pumpView(tester, payload());

      final legend = tester.getTopLeft(find.byType(ChartLegend));
      final chart = tester.getTopLeft(find.byType(WorkStateBars));
      expect(legend.dy, greaterThan(chart.dy));
      expect(
        legend.dx,
        lessThan(tester.getSize(find.byType(Scaffold)).width / 2),
      );
      expect(find.text('By type and state'), findsOneWidget);
      expect(find.text('Bug · New'), findsOneWidget);
      expect(find.text('User Story · Closed'), findsOneWidget);
    });

    testWidgets('landscape puts the legend beside the chart (D15)', (
      tester,
    ) async {
      await pumpView(tester, payload(), size: phoneLandscape);

      final legend = tester.getTopLeft(find.byType(ChartLegend));
      final width = tester.getSize(find.byType(Scaffold)).width;
      expect(legend.dx, greaterThan(width / 2));
      expect(find.text('By type and state'), findsOneWidget);
    });

    testWidgets('a tablet in portrait keeps the portrait layout', (
      tester,
    ) async {
      await pumpView(tester, payload(), size: tabletPortrait);

      final legend = tester.getTopLeft(find.byType(ChartLegend));
      final chart = tester.getTopLeft(find.byType(WorkStateBars));
      expect(legend.dy, greaterThan(chart.dy));
    });

    testWidgets('the headline and its summary are on the page', (tester) async {
      await pumpView(tester, payload());

      expect(find.text('10'), findsOneWidget);
      expect(find.textContaining('work items across 2 types'), findsOneWidget);
    });
  });

  group('the page', () {
    testWidgets('draws the payload the card handed over, without a read', (
      tester,
    ) async {
      final args = DashboardCardArgs(
        org: org,
        project: project,
        widget: TeamOverview.forTeam(team).widgets[1],
        teamId: team,
        dashboardId: TeamOverview.id,
      );
      await pumpPage(
        tester,
        initial: ChartFocusArgs(args: args, payload: payload()),
      );

      expect(find.text('Work by state'), findsOneWidget);
      expect(find.text('Bug · New'), findsOneWidget);
      verifyNever(
        () => analytics.workByState(
          any(),
          any(),
          any(),
          refresh: any(named: 'refresh'),
        ),
      );
    });

    testWidgets('a cold open loads the chart from the cache (D7)', (
      tester,
    ) async {
      when(
        () => analytics.workByState(
          org,
          project,
          team,
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => const [
          WorkStateCount(
            workItemType: 'Bug',
            state: 'New',
            stateCategory: 'Proposed',
            count: 4,
          ),
        ],
      );

      await pumpPage(tester, dashboardId: TeamOverview.id);

      expect(find.text('Work by state'), findsOneWidget);
      expect(find.text('Bug · New'), findsOneWidget);
      verify(() => analytics.workByState(org, project, team, refresh: false))
          .called(1);
    });

    testWidgets('a cold open finds the widget on the cached dashboard', (
      tester,
    ) async {
      when(() => dashboards.cachedDashboard(org, project, 'dash-1')).thenAnswer(
        (_) async => (
          dashboard: Dashboard(
            id: 'dash-1',
            name: 'Overview',
            teamId: team,
            widgets: [
              DashboardWidget(
                id: 'w5',
                name: 'Cycle time',
                contributionId:
                    'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.'
                    'Dashboards.CycleTimeWidget',
                settings: '{"teamId":"$team","timePeriodInDays":30}',
              ),
            ],
          ),
          fetchedAt: today,
        ),
      );
      when(
        () => analytics.requirementTypes(
          org,
          project,
          team,
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => const ['User Story']);
      when(
        () => analytics.cycleAndLeadTime(
          org,
          project,
          team,
          any(),
          types: any(named: 'types'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => CycleLeadTime(
          items: [
            for (var i = 0; i < 4; i++)
              CycleLeadItem(
                workItemId: 200 + i,
                workItemType: 'User Story',
                cycleTimeDays: 3,
                leadTimeDays: 6,
                completedDate: today.subtract(Duration(days: i)),
              ),
          ],
        ),
      );

      await pumpPage(tester, widgetId: 'w5', dashboardId: 'dash-1');

      expect(find.text('Cycle time'), findsWidgets);
      expect(find.text('3 days'), findsWidgets);
      expect(find.text('Completed items'), findsOneWidget);
    });

    testWidgets('a widget that is no longer there says so', (tester) async {
      when(() => dashboards.cachedDashboard(org, project, 'dash-1'))
          .thenAnswer((_) async => null);

      await pumpPage(tester, widgetId: 'gone', dashboardId: 'dash-1');

      expect(
        find.text('This chart is no longer on the dashboard.'),
        findsOneWidget,
      );
    });

    testWidgets('Analytics refusing is the D14 notice, not a sign-in', (
      tester,
    ) async {
      when(
        () => analytics.workByState(
          org,
          project,
          team,
          refresh: any(named: 'refresh'),
        ),
      ).thenThrow(const AnalyticsUnavailable(statusCode: 403));

      await pumpPage(tester, dashboardId: TeamOverview.id);

      expect(find.textContaining('Analytics unavailable'), findsOneWidget);
    });
  });
}
