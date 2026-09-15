import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/analytics.dart';
import 'package:boardhop/data/models/dashboard.dart';
import 'package:boardhop/data/models/pipeline.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/analytics_repository.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/features/dashboards/charts/chart_format.dart';
import 'package:boardhop/features/dashboards/charts/chart_sources.dart';
import 'package:boardhop/features/dashboards/charts/cumulative_flow_chart.dart';
import 'package:boardhop/features/dashboards/charts/cycle_time_chart.dart';
import 'package:boardhop/features/dashboards/team_overview.dart';
import 'package:boardhop/features/dashboards/widgets/cards/burndown_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/cfd_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/cycle_time_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/pipeline_outcomes_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/sprint_burndown_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/velocity_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/work_by_state_card.dart';
import 'package:boardhop/features/dashboards/widgets/dashboard_card.dart';
import 'package:boardhop/features/dashboards/widgets/registry.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart';

class _Analytics extends Mock implements AnalyticsRepository {}

class _Sprints extends Mock implements SprintRepository {}

class _Pipelines extends Mock implements PipelineRepository {}

class _AuthService extends Mock implements AuthService {}

/// The chart cards (research/19 phase D-C): what each draws on canned
/// Analytics models, what it says when there is nothing to draw, what it
/// does when Analytics refuses the token (D14), and where a tap goes (D7).
///
/// Every fixture here is invented; no client data is in the repository.
void main() {
  const org = 'o';
  const project = 'p';
  const team = 'team-1';
  const teamSk = 'team-1';

  final today = DateTime.utc(2026, 9, 15);

  late _Analytics analytics;
  late _Sprints sprints;
  late _Pipelines pipelines;
  late _AuthService auth;
  late List<String> visited;

  DashboardWidget aWidget(
    String name,
    String suffix, {
    String? settings,
    String id = 'w1',
  }) => DashboardWidget(
    id: id,
    name: name,
    contributionId:
        'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.$suffix',
    settings: settings,
  );

  DashboardWidget builtIn(String kind, String name) => DashboardWidget(
    id: 'boardhop.$kind',
    name: name,
    contributionId: '',
    builtInKind: kind,
  );

  DashboardCardArgs argsFor(DashboardWidget widget) => DashboardCardArgs(
    org: org,
    project: project,
    widget: widget,
    teamId: team,
    dashboardId: TeamOverview.id,
  );

  List<BurndownDay> burndownDays() => [
    for (var i = 0; i < 10; i++)
      BurndownDay(
        date: today.subtract(Duration(days: 9 - i)),
        remaining: 20 - i,
        done: i * 2,
        points: (20 - i) * 1.5,
      ),
  ];

  setUpAll(() {
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    analytics = _Analytics();
    sprints = _Sprints();
    pipelines = _Pipelines();
    auth = _AuthService();
    visited = <String>[];

    when(() => auth.accountById(any())).thenReturn(
      Account(id: 'a', username: 'kelly@kammcs.com', name: 'Kelly Kamm'),
    );
    when(() => auth.knownAccounts).thenReturn(const []);

    when(() => sprints.defaultTeamId(org, project))
        .thenAnswer((_) async => team);
    when(
      () =>
          analytics.teamSk(org, project, any(), refresh: any(named: 'refresh')),
    ).thenAnswer((_) async => teamSk);
    when(
      () => analytics.requirementTypes(
        org,
        project,
        any(),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => const ['User Story']);
  });

  Future<void> pump(WidgetTester tester, Widget card) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final bloc = AuthBloc(auth);
    addTearDown(bloc.close);
    final router = GoRouter(
      initialLocation: '/a/u1/orgs/$org/projects/$project/dashboards',
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/dashboards',
          builder: (context, state) => AccountScope(
            accountId: 'u1',
            child: Scaffold(body: SingleChildScrollView(child: card)),
          ),
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/chart/:widget',
          builder: (context, state) {
            visited.add(state.uri.toString());
            return const Scaffold(body: Text('focus'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AnalyticsRepository>.value(value: analytics),
          RepositoryProvider<SprintRepository>.value(value: sprints),
          RepositoryProvider<PipelineRepository>.value(value: pipelines),
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
    await tester.pumpAndSettle();
  }

  group('burndown and burnup', () {
    const settings = BurndownSettings(
      teams: [WidgetTeamRef(projectId: 'pid', teamId: team)],
    );

    testWidgets('a burndown draws the remaining series and its ideal line', (
      tester,
    ) async {
      when(
        () => analytics.teamBurndown(
          org,
          project,
          teamSk,
          any(),
          any(),
          any(),
          sumField: any(named: 'sumField'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => burndownDays());

      await pump(
        tester,
        BurndownCard(
          args: argsFor(aWidget('Team burndown', 'BurndownWidget')),
          settings: settings,
        ),
      );

      expect(find.text('Team burndown'), findsOneWidget);
      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text('Ideal'), findsOneWidget);
      // The last day's remaining work is the headline, and the sentence a
      // screen reader hears says the same thing (DESIGN.md §8).
      expect(find.text('11'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              (w.properties.label ?? '').contains('11 items remaining'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a burnup names its series Completed', (tester) async {
      when(
        () => analytics.teamBurndown(
          org,
          project,
          teamSk,
          any(),
          any(),
          any(),
          sumField: any(named: 'sumField'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => burndownDays());

      await pump(
        tester,
        BurndownCard(
          args: argsFor(aWidget('Team burnup', 'BurnupWidget')),
          settings: settings,
          burnup: true,
        ),
      );

      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Remaining'), findsNothing);
    });

    testWidgets('the type filter narrows the Analytics call', (tester) async {
      when(
        () => analytics.teamBurndown(
          org,
          project,
          teamSk,
          any(),
          any(),
          any(),
          sumField: any(named: 'sumField'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => burndownDays());

      await pump(
        tester,
        BurndownCard(
          args: argsFor(aWidget('Bugs down', 'BurndownWidget')),
          settings: const BurndownSettings(
            teams: [WidgetTeamRef(teamId: team)],
            workItemTypeFilter: WidgetTypeFilter(
              identifier: 'WorkItemType',
              settings: 'Bug,Task',
            ),
          ),
        ),
      );

      final types = verify(
        () => analytics.teamBurndown(
          org,
          project,
          teamSk,
          captureAny(),
          any(),
          any(),
          sumField: any(named: 'sumField'),
          refresh: any(named: 'refresh'),
        ),
      ).captured.single;
      expect(types, ['Bug', 'Task']);
    });

    testWidgets('a backlog category adds Bug when the widget asks', (
      tester,
    ) async {
      when(
        () => analytics.teamBurndown(
          org,
          project,
          teamSk,
          any(),
          any(),
          any(),
          sumField: any(named: 'sumField'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => burndownDays());

      await pump(
        tester,
        BurndownCard(
          args: argsFor(aWidget('With bugs', 'BurndownWidget')),
          settings: const BurndownSettings(
            teams: [WidgetTeamRef(teamId: team)],
            workItemTypeFilter: WidgetTypeFilter(
              identifier: 'BacklogCategory',
              settings: 'Microsoft.RequirementCategory',
            ),
            includeBugsForRequirementCategory: true,
          ),
        ),
      );

      final types = verify(
        () => analytics.teamBurndown(
          org,
          project,
          teamSk,
          captureAny(),
          any(),
          any(),
          sumField: any(named: 'sumField'),
          refresh: any(named: 'refresh'),
        ),
      ).captured.single;
      expect(types, ['Bug', 'User Story']);
    });

    testWidgets('Analytics refusing is the card state, not an error (D14)', (
      tester,
    ) async {
      when(
        () => analytics.teamBurndown(
          org,
          project,
          teamSk,
          any(),
          any(),
          any(),
          sumField: any(named: 'sumField'),
          refresh: any(named: 'refresh'),
        ),
      ).thenThrow(const AnalyticsUnavailable(statusCode: 403));

      await pump(
        tester,
        BurndownCard(
          args: argsFor(aWidget('Team burndown', 'BurndownWidget')),
          settings: settings,
        ),
      );

      expect(find.textContaining('Analytics unavailable'), findsOneWidget);
      expect(find.text('Remaining'), findsNothing);
    });

    testWidgets('a tap opens the chart focus route (D7)', (tester) async {
      when(
        () => analytics.teamBurndown(
          org,
          project,
          teamSk,
          any(),
          any(),
          any(),
          sumField: any(named: 'sumField'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => burndownDays());

      await pump(
        tester,
        BurndownCard(
          args: argsFor(aWidget('Team burndown', 'BurndownWidget')),
          settings: settings,
        ),
      );

      await tester.tap(find.text('Team burndown'));
      await tester.pumpAndSettle();

      expect(visited.single, contains('/chart/w1'));
      expect(visited.single, contains('dashboard=${TeamOverview.id}'));
    });
  });

  group('sprint burndown', () {
    testWidgets('the built-in card charts the team’s current sprint', (
      tester,
    ) async {
      when(
        () => sprints.iterations(
          org,
          project,
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => SprintIterations(
          all: [
            TeamIteration(
              id: 'iter-1',
              name: 'Sprint 24',
              path: 'p\\Sprint 24',
              timeFrame: 'current',
              startDate: today.subtract(const Duration(days: 9)),
              finishDate: today.add(const Duration(days: 4)),
            ),
          ],
        ),
      );
      when(
        () => analytics.burndown(
          org,
          project,
          'iter-1',
          start: any(named: 'start'),
          end: any(named: 'end'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => burndownDays());

      await pump(
        tester,
        SprintBurndownCard(
          args: argsFor(
            builtIn(TeamOverview.sprintBurndown, 'Sprint burndown'),
          ),
        ),
      );

      expect(find.text('Sprint burndown'), findsOneWidget);
      expect(find.text('Sprint 24'), findsOneWidget);
      expect(find.text('Remaining'), findsOneWidget);
    });

    testWidgets('a team with no sprints says so instead of a chart', (
      tester,
    ) async {
      when(
        () => sprints.iterations(
          org,
          project,
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => const SprintIterations());

      await pump(
        tester,
        SprintBurndownCard(
          args: argsFor(
            builtIn(TeamOverview.sprintBurndown, 'Sprint burndown'),
          ),
        ),
      );

      expect(find.text('This team has no sprints.'), findsOneWidget);
      verifyNever(
        () => analytics.burndown(
          any(),
          any(),
          any(),
          start: any(named: 'start'),
          end: any(named: 'end'),
          refresh: any(named: 'refresh'),
        ),
      );
    });

    testWidgets('the legacy widget draws the same Analytics chart (D14)', (
      tester,
    ) async {
      when(
        () => analytics.burndown(
          org,
          project,
          'iter-9',
          start: any(named: 'start'),
          end: any(named: 'end'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => burndownDays());

      await pump(
        tester,
        SprintBurndownCard(
          args: argsFor(aWidget('Sprint burndown', 'SprintBurndownWidget')),
          settings: SprintBurndownSettings(
            team: const WidgetTeamRef(teamId: team),
            iterationId: 'iter-9',
            isLegacy: true,
            startDate: today.subtract(const Duration(days: 9)),
            endDate: today,
          ),
        ),
      );

      expect(find.text('Remaining'), findsOneWidget);
      expect(find.text('Ideal'), findsOneWidget);
    });
  });

  group('velocity', () {
    List<VelocityIteration> velocities(int count) => [
      for (var i = 0; i < count; i++)
        VelocityIteration(
          iteration: AnalyticsIteration(
            sk: 'it-$i',
            name: 'Sprint ${24 - i}',
            startDate: today.subtract(Duration(days: 14 * (i + 1))),
            endDate: today.subtract(Duration(days: 14 * i)),
          ),
          planned: 10,
          completed: 6,
          completedLate: 2,
          incomplete: 2,
        ),
    ];

    testWidgets('draws six iterations, named in the legend', (tester) async {
      when(
        () => analytics.velocity(
          org,
          project,
          teamSk,
          any(),
          iterations: any(named: 'iterations'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => velocities(6));

      await pump(
        tester,
        VelocityCard(
          args: argsFor(builtIn(TeamOverview.velocity, 'Velocity')),
          settings: VelocitySettings.defaults,
        ),
      );

      expect(find.text('Planned'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Completed late'), findsOneWidget);
      expect(find.text('Incomplete'), findsOneWidget);
      // Eight completed and late per sprint, every sprint.
      expect(find.text('8'), findsOneWidget);
      verify(
        () => analytics.velocity(
          org,
          project,
          teamSk,
          any(),
          iterations: 6,
          refresh: any(named: 'refresh'),
        ),
      ).called(1);
    });

    testWidgets('a team with no dated iterations says so', (tester) async {
      when(
        () => analytics.velocity(
          org,
          project,
          teamSk,
          any(),
          iterations: any(named: 'iterations'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => const []);

      await pump(
        tester,
        VelocityCard(
          args: argsFor(builtIn(TeamOverview.velocity, 'Velocity')),
          settings: VelocitySettings.defaults,
        ),
      );

      expect(find.text('This team has no dated iterations.'), findsOneWidget);
    });
  });

  group('cumulative flow', () {
    CumulativeFlow flow({
      List<String> columns = const ['New', 'Doing', 'Done'],
    }) => CumulativeFlow(
      columns: columns,
      days: [
        for (var i = 0; i < 8; i++)
          CumulativeFlowDay(
            date: today.subtract(Duration(days: 7 - i)),
            counts: {for (final c in columns) c: 2 + i},
          ),
      ],
    );

    testWidgets('the built-in card takes the team’s requirement board', (
      tester,
    ) async {
      when(
        () => analytics.requirementBoardName(
          org,
          project,
          teamSk,
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => 'Stories');
      when(
        () => analytics.cumulativeFlow(
          org,
          project,
          teamSk,
          'Stories',
          any(),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => flow());

      await pump(
        tester,
        CfdCard(
          args: argsFor(
            builtIn(TeamOverview.cumulativeFlow, 'Cumulative flow'),
          ),
        ),
      );

      expect(find.text('New'), findsOneWidget);
      expect(find.text('Doing'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('Stories'), findsOneWidget);
    });

    testWidgets('a team Analytics has no board for says so', (tester) async {
      when(
        () => analytics.requirementBoardName(
          org,
          project,
          teamSk,
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => null);

      await pump(
        tester,
        CfdCard(
          args: argsFor(
            builtIn(TeamOverview.cumulativeFlow, 'Cumulative flow'),
          ),
        ),
      );

      expect(
        find.text('This team has no board Analytics knows about.'),
        findsOneWidget,
      );
    });

    testWidgets('the widget’s own board and window are used', (tester) async {
      when(
        () => analytics.cumulativeFlow(
          org,
          project,
          teamSk,
          'Features',
          any(),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => flow());

      await pump(
        tester,
        CfdCard(
          args: argsFor(aWidget('Flow', 'CumulativeFlowDiagramWidget')),
          settings: const CfdSettings(boardName: 'Features', days: 14),
        ),
      );

      expect(find.textContaining('Features'), findsOneWidget);
      verifyNever(
        () => analytics.requirementBoardName(
          any(),
          any(),
          any(),
          refresh: any(named: 'refresh'),
        ),
      );
    });
  });

  group('cycle and lead time', () {
    CycleLeadTime completed(int count) => CycleLeadTime(
      items: [
        for (var i = 0; i < count; i++)
          CycleLeadItem(
            workItemId: 100 + i,
            workItemType: 'User Story',
            state: 'Closed',
            cycleTimeDays: 4,
            leadTimeDays: 9,
            completedDate: today.subtract(Duration(days: count - i)),
          ),
      ],
    );

    testWidgets('the built-in card names both averages (D9)', (tester) async {
      when(
        () => analytics.cycleAndLeadTime(
          org,
          project,
          teamSk,
          any(),
          types: any(named: 'types'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => completed(12));

      await pump(
        tester,
        CycleTimeCard(
          args: argsFor(
            builtIn(TeamOverview.cycleLeadTime, 'Cycle and lead time'),
          ),
          showBoth: true,
        ),
      );

      expect(find.text('4 days'), findsOneWidget);
      expect(find.textContaining('average lead time 9 days'), findsOneWidget);
      expect(find.text('Cycle time'), findsOneWidget);
      expect(find.text('Rolling average'), findsOneWidget);
    });

    testWidgets('the Lead Time widget charts lead time over its window', (
      tester,
    ) async {
      when(
        () => analytics.cycleAndLeadTime(
          org,
          project,
          teamSk,
          any(),
          types: any(named: 'types'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => completed(6));

      await pump(
        tester,
        CycleTimeCard(
          args: argsFor(aWidget('Lead time', 'LeadTimeWidget')),
          settings: const CycleTimeSettings(
            team: WidgetTeamRef(teamId: team),
            days: 30,
          ),
          lead: true,
        ),
      );

      expect(find.text('9 days'), findsOneWidget);
      expect(find.text('Lead time'), findsWidgets);
    });

    testWidgets('nothing completed says so', (tester) async {
      when(
        () => analytics.cycleAndLeadTime(
          org,
          project,
          teamSk,
          any(),
          types: any(named: 'types'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => const CycleLeadTime());

      await pump(
        tester,
        CycleTimeCard(
          args: argsFor(
            builtIn(TeamOverview.cycleLeadTime, 'Cycle and lead time'),
          ),
          showBoth: true,
        ),
      );

      expect(
        find.text('Nothing was completed in the last 60 days.'),
        findsOneWidget,
      );
    });
  });

  group('work by state', () {
    testWidgets('one bar per type, with the categories named', (tester) async {
      when(
        () => analytics.workByState(
          org,
          project,
          teamSk,
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => const [
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

      await pump(
        tester,
        WorkByStateCard(
          args: argsFor(builtIn(TeamOverview.workByState, 'Work by state')),
        ),
      );

      expect(find.text('10'), findsOneWidget);
      expect(find.text('User Story · 7'), findsOneWidget);
      expect(find.text('Not started'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('a team with no work items says so', (tester) async {
      when(
        () => analytics.workByState(
          org,
          project,
          teamSk,
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => const []);

      await pump(
        tester,
        WorkByStateCard(
          args: argsFor(builtIn(TeamOverview.workByState, 'Work by state')),
        ),
      );

      expect(find.text('This team has no work items.'), findsOneWidget);
    });
  });

  group('pipeline pass rate', () {
    PipelineDefinition definition(int id, String name, DateTime? finished) =>
        PipelineDefinition(
          id: id,
          name: name,
          latestCompletedBuild: finished == null
              ? null
              : BuildRun(
                  id: id * 10,
                  buildNumber: '$id.1',
                  definitionId: id,
                  definitionName: name,
                  status: 'completed',
                  result: 'succeeded',
                  sourceBranch: 'refs/heads/main',
                  finishTime: finished,
                ),
        );

    testWidgets('the pass rate of the most recently run pipeline', (
      tester,
    ) async {
      when(() => pipelines.definitions(org, project)).thenAnswer(
        (_) async => [
          definition(
            1,
            'old-pipeline',
            today.subtract(const Duration(days: 9)),
          ),
          definition(139, 'boardhop-scratch', today),
        ],
      );
      when(
        () => analytics.pipelineOutcomes(
          org,
          project,
          139,
          any(),
          top: any(named: 'top'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => PipelineOutcomes(
          total: 10,
          succeeded: 8,
          failed: 2,
          runs: [
            for (var i = 0; i < 4; i++)
              AnalyticsPipelineRun(
                runId: 500 + i,
                runNumber: '2026.$i',
                outcome: i == 1 ? 'Failed' : 'Succeed',
                completedDate: today.subtract(Duration(days: i)),
                durationSeconds: 120,
              ),
          ],
        ),
      );

      await pump(
        tester,
        PipelineOutcomesCard(
          args: argsFor(
            builtIn(TeamOverview.pipelineOutcomes, 'Pipeline pass rate'),
          ),
        ),
      );

      expect(find.text('80%'), findsOneWidget);
      expect(find.textContaining('boardhop-scratch'), findsOneWidget);
      expect(find.text('Succeeded'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('a project with no pipelines says so and asks Analytics '
        'nothing', (tester) async {
      when(() => pipelines.definitions(org, project))
          .thenAnswer((_) async => const []);

      await pump(
        tester,
        PipelineOutcomesCard(
          args: argsFor(
            builtIn(TeamOverview.pipelineOutcomes, 'Pipeline pass rate'),
          ),
        ),
      );

      expect(find.text('No runs in the last 90 days.'), findsOneWidget);
      verifyNever(
        () => analytics.pipelineOutcomes(
          any(),
          any(),
          any(),
          any(),
          top: any(named: 'top'),
          refresh: any(named: 'refresh'),
        ),
      );
    });

    test(
      'mostRecentlyRun prefers the newest finish and skips the never-run',
      () {
        final chosen = PipelineOutcomesCard.mostRecentlyRun([
          definition(1, 'never-run', null),
          definition(2, 'older', today.subtract(const Duration(days: 4))),
          definition(3, 'newest', today),
        ]);
        expect(chosen?.name, 'newest');
        expect(PipelineOutcomesCard.mostRecentlyRun([]), isNull);
        expect(
          PipelineOutcomesCard.mostRecentlyRun([definition(1, 'never', null)]),
          isNull,
        );
      },
    );
  });

  group('the registry', () {
    test('every chart kind and every built-in has a card', () {
      for (final widget in TeamOverview.forTeam('t').widgets) {
        expect(DashboardRegistry.cardFor(widget), isNotNull);
        expect(DashboardRegistry.isChart(widget), isTrue);
      }
      const settings = {
        'BurndownWidget': '{"teams":[{"teamId":"t"}]}',
        'BurnupWidget': '{"teams":[{"teamId":"t"}]}',
        'AnalyticsSprintBurndownWidget':
            '{"team":{"teamId":"t"},"iterationId":"i"}',
        'SprintBurndownWidget': '{"team":{"teamId":"t"},"iterationId":"i"}',
        'CycleTimeWidget': '{"teamId":"t","timePeriodInDays":30}',
        'LeadTimeWidget': '{"teamId":"t","timePeriodInDays":30}',
        'CumulativeFlowDiagramWidget': '{"teamId":"t","boardName":"Stories"}',
        'VelocityWidget': null,
      };
      for (final entry in settings.entries) {
        final widget = aWidget('A chart', entry.key, settings: entry.value);
        expect(DashboardRegistry.cardFor(widget), isNotNull, reason: entry.key);
        expect(DashboardRegistry.isChart(widget), isTrue, reason: entry.key);
      }
    });

    test('a chart whose settings do not parse is still hidden (D10)', () {
      final widget = aWidget(
        'Broken',
        'CumulativeFlowDiagramWidget',
        settings: '{"nothing":"useful"}',
      );
      expect(DashboardRegistry.cardFor(widget), isNull);
    });
  });

  group('the pure pieces', () {
    test('a burnup climbs to the scope it ended with', () {
      final days = [
        for (var i = 0; i < 5; i++)
          BurndownDay(
            date: today.subtract(Duration(days: 4 - i)),
            remaining: 10 - i,
            done: i,
          ),
      ];
      final line = burnupIdealLine(days, finish: today);
      expect(line.first, 0);
      expect(line.last, closeTo(10, 0.001));
      expect(line[2], closeTo(5, 0.001));
    });

    test('the rolling-average window is a fifth of the period, odd', () {
      expect(rollingWindowForDays(60), 11);
      expect(rollingWindowForDays(30), 5);
      expect(rollingWindowForDays(14), 1);
      expect(rollingWindowForDays(0), 1);
    });

    test('the rolling average is centred and keeps the ends', () {
      final average = rollingAverage([1, 2, 3, 4, 5], 3);
      expect(average.first, closeTo(1.5, 0.001));
      expect(average[2], closeTo(3, 0.001));
      expect(average.last, closeTo(4.5, 0.001));
      expect(rollingAverage([2, 4], 1), [2, 4]);
      expect(rollingAverage(const [], 3), isEmpty);
    });

    test('a board with more than six columns folds the rest into Other', () {
      final columns = [for (var i = 0; i < 9; i++) 'Column $i'];
      final series = CumulativeFlowSeries.from(
        CumulativeFlow(
          columns: columns,
          days: [
            for (var d = 0; d < 3; d++)
              CumulativeFlowDay(
                date: today.subtract(Duration(days: 2 - d)),
                counts: {for (final c in columns) c: 1},
              ),
          ],
        ),
      );
      expect(series.columns.length, 7);
      expect(series.columns.last, CumulativeFlowSeries.otherLabel);
      // Three folded columns of one item each.
      expect(series.days.first.counts.last, 3);
      expect(series.totalOn(0), 9);
      expect(series.cumulative(0, 1), 2);
    });

    test('an iteration label is short enough for an axis at xxxL', () {
      expect(shortIterationName('Sprint 24'), '24');
      expect(shortIterationName('Iteration 4 (hardening)'), '4');
      expect(shortIterationName('Hardening'), 'Harden');
      expect(shortIterationName(''), '');
    });
  });
}
