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
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/people_repository.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/features/dashboards/team_overview.dart';
import 'package:boardhop/features/dashboards/widgets/cards/assigned_to_me_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/build_history_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/code_tile_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/links_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/markdown_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/pull_requests_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/query_results_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/query_tile_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/sprint_overview_card.dart';
import 'package:boardhop/features/dashboards/widgets/cards/team_members_card.dart';
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

class _Sprints extends Mock implements SprintRepository {}

class _WorkItems extends Mock implements WorkItemRepository {}

class _PullRequests extends Mock implements PullRequestRepository {}

class _Pipelines extends Mock implements PipelineRepository {}

class _People extends Mock implements PeopleRepository {}

class _Projects extends Mock implements ProjectRepository {}

class _AuthService extends Mock implements AuthService {}

/// A card whose only job is to fail the way an Analytics card fails, so the
/// frame's D14 treatment is covered before any Analytics card exists.
class _RefusedCard extends StatefulWidget {
  const _RefusedCard({required this.args});

  final DashboardCardArgs args;

  @override
  State<_RefusedCard> createState() => _RefusedCardState();
}

class _RefusedCardState extends State<_RefusedCard> with DashboardCardMixin {
  @override
  Future<void> fetch({required bool refresh}) async {
    throw const AnalyticsUnavailable(statusCode: 403);
  }

  @override
  Widget build(BuildContext context) => DashboardCard(
    title: widget.args.widget.name,
    unavailable: unavailable,
    loading: loading,
    error: error,
    child: const Text('never drawn'),
  );
}

void main() {
  const org = 'o';
  const project = 'p';
  const team = 'team-1';

  late _Sprints sprints;
  late _WorkItems workItems;
  late _PullRequests pullRequests;
  late _Pipelines pipelines;
  late _People people;
  late _Projects projects;
  late _AuthService auth;
  late List<String> visited;

  DashboardWidget aWidget(
    String name,
    String suffix, {
    String? settings,
    int rowSpan = 1,
  }) => DashboardWidget(
    id: 'w',
    name: name,
    contributionId:
        'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.$suffix',
    rowSpan: rowSpan,
    settings: settings,
  );

  DashboardCardArgs argsFor(DashboardWidget widget) => DashboardCardArgs(
    org: org,
    project: project,
    widget: widget,
    teamId: team,
  );

  WorkItem item(int id, String title, {String state = 'Active'}) =>
      WorkItem.fromJson({
        'id': id,
        'rev': 1,
        'fields': {
          'System.Id': id,
          'System.WorkItemType': 'Bug',
          'System.Title': title,
          'System.State': state,
        },
      });

  setUpAll(() {
    registerFallbackValue(PrListFilter.toReview);
  });

  setUp(() {
    sprints = _Sprints();
    workItems = _WorkItems();
    pullRequests = _PullRequests();
    pipelines = _Pipelines();
    people = _People();
    projects = _Projects();
    auth = _AuthService();
    visited = <String>[];

    when(() => auth.accountById(any())).thenReturn(
      Account(id: 'a', username: 'kelly@kammcs.com', name: 'Kelly Kamm'),
    );
    when(() => auth.knownAccounts).thenReturn(const []);
    when(() => auth.accounts()).thenAnswer((_) async => const []);
    when(() => workItems.types(org, project)).thenAnswer(
      (_) async => const [
        WorkItemType(name: 'Bug', referenceName: 'Microsoft.VSTS.Bug'),
      ],
    );
    when(() => projects.watch(org))
        .thenAnswer((_) => Stream<List<Project>>.value(const []));
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
        for (final path in [
          '/a/:account/orgs/:org/projects/:project/work-items',
          '/a/:account/orgs/:org/projects/:project/work-items/:id',
          '/a/:account/orgs/:org/projects/:project/sprint',
          '/a/:account/orgs/:org/projects/:project/pipelines',
          '/a/:account/orgs/:org/projects/:project/pipelines/runs/:id',
          '/a/:account/orgs/:org/projects/:project/repos/:repo',
          '/a/:account/orgs/:org/pull-requests/:id',
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
    await tester.pumpAndSettle();
  }

  group('query tile', () {
    const settings = QueryTileSettings(queryId: 'q-1', queryName: 'Open bugs');

    testWidgets('shows the count and opens the query in Work items', (
      tester,
    ) async {
      when(
        () => workItems.queryCount(org, project, 'q-1', top: any(named: 'top')),
      ).thenAnswer((_) async => 12);
      await pump(
        tester,
        QueryTileCard(
          args: argsFor(aWidget('Open bugs', 'QueryScalarWidget')),
          settings: settings,
        ),
      );

      expect(find.text('12'), findsOneWidget);

      await tester.tap(find.text('12'));
      await tester.pumpAndSettle();

      expect(visited.single, contains('query=q-1'));
      expect(visited.single, contains('queryName=Open+bugs'));
    });

    testWidgets('a failed read is one inline line, not a blank card', (
      tester,
    ) async {
      when(
        () => workItems.queryCount(org, project, 'q-1', top: any(named: 'top')),
      ).thenThrow(const AdoServerException('TF401019: no such query'));
      await pump(
        tester,
        QueryTileCard(
          args: argsFor(aWidget('Open bugs', 'QueryScalarWidget')),
          settings: settings,
        ),
      );

      expect(find.text('TF401019: no such query'), findsOneWidget);
      expect(find.text('Open bugs'), findsOneWidget);
    });

    testWidgets('a colour rule that matches paints the tile', (tester) async {
      when(
        () => workItems.queryCount(org, project, 'q-1', top: any(named: 'top')),
      ).thenAnswer((_) async => 30);
      await pump(
        tester,
        QueryTileCard(
          args: argsFor(aWidget('Open bugs', 'QueryScalarWidget')),
          settings: const QueryTileSettings(
            queryId: 'q-1',
            defaultBackgroundColor: '#1177DD',
            colorRules: [
              QueryTileColorRule(
                backgroundColor: '#CC0000',
                operator: '>',
                threshold: 20,
              ),
            ],
          ),
        ),
      );

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.color, const Color(0xFFCC0000));
    });
  });

  group('query results and assigned to me', () {
    testWidgets('draw the cached rows before the network answers', (
      tester,
    ) async {
      when(() => workItems.watchList(org, project, 'query:q-1'))
          .thenAnswer((_) => Stream.value([item(1, 'A cached bug')]));
      final never = Completer<List<WorkItem>>();
      when(
        () =>
            workItems.refreshQuery(org, project, 'q-1', top: any(named: 'top')),
      ).thenAnswer((_) => never.future);
      await pump(
        tester,
        QueryResultsCard(
          args: argsFor(aWidget('Recent work', 'WitViewWidget')),
          settings: const QueryResultsSettings(queryId: 'q-1'),
        ),
      );

      expect(find.text('A cached bug'), findsOneWidget);
      never.complete(const []);
      await tester.pumpAndSettle();
    });

    testWidgets('cap the rows and offer See all', (tester) async {
      final many = [for (var i = 1; i <= 9; i++) item(i, 'Row $i')];
      when(() => workItems.watchList(org, project, any()))
          .thenAnswer((_) => Stream<List<WorkItem>>.value(const []));
      when(
        () =>
            workItems.refreshQuery(org, project, 'q-1', top: any(named: 'top')),
      ).thenAnswer((_) async => many);
      await pump(
        tester,
        QueryResultsCard(
          args: argsFor(aWidget('Recent work', 'WitViewWidget')),
          settings: const QueryResultsSettings(queryId: 'q-1'),
        ),
      );

      expect(find.text('Row 1'), findsOneWidget);
      expect(find.text('Row 5'), findsNothing);
      expect(find.text('See all 9'), findsOneWidget);
    });

    testWidgets('an Assigned to me row opens the work item in the shell', (
      tester,
    ) async {
      when(
        () => workItems.watchList(
          org,
          project,
          WorkItemRepository.assignedToMeKey,
        ),
      ).thenAnswer((_) => Stream<List<WorkItem>>.value(const []));
      when(() => workItems.refreshAssignedToMe(org, project))
          .thenAnswer((_) async => [item(42, 'Mine to do')]);
      await pump(
        tester,
        AssignedToMeCard(
          args: argsFor(aWidget('My work', 'AssignedToMeWidget')),
        ),
      );

      await tester.tap(find.text('Mine to do'));
      await tester.pumpAndSettle();

      expect(visited.single, endsWith('/work-items/42'));
    });

    testWidgets('nothing assigned says so rather than drawing an empty list', (
      tester,
    ) async {
      when(() => workItems.watchList(org, project, any()))
          .thenAnswer((_) => Stream<List<WorkItem>>.value(const []));
      when(() => workItems.refreshAssignedToMe(org, project))
          .thenAnswer((_) async => const []);
      await pump(
        tester,
        AssignedToMeCard(
          args: argsFor(aWidget('My work', 'AssignedToMeWidget')),
        ),
      );

      expect(find.text('Nothing is assigned to you here.'), findsOneWidget);
    });
  });

  group('pull requests', () {
    PullRequest pr(int id, String title) => PullRequest.fromJson({
      'pullRequestId': id,
      'title': title,
      'status': 'active',
      'sourceRefName': 'refs/heads/feature',
      'targetRefName': 'refs/heads/main',
      'repository': {
        'name': 'boardhop',
        'project': {'name': project},
      },
      'createdBy': {'displayName': 'Ada Example', 'id': 'ada'},
    });

    testWidgets('merges review-first, then mine, and opens one', (
      tester,
    ) async {
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
          project: project,
          filter: PrListFilter.toReview,
        ),
      ).thenAnswer((_) async => [pr(1, 'Review me')]);
      when(
        () =>
            pullRequests.list(org, project: project, filter: PrListFilter.mine),
      ).thenAnswer((_) async => [pr(2, 'Mine')]);
      await pump(
        tester,
        PullRequestsCard(args: argsFor(aWidget('PRs', 'PullrequestsWidget'))),
      );

      expect(find.text('Review me'), findsOneWidget);
      expect(find.text('Mine'), findsOneWidget);

      await tester.tap(find.text('Review me'));
      await tester.pumpAndSettle();

      expect(visited.single, endsWith('/pull-requests/1'));
    });

    testWidgets('offline draws the cached lists', (tester) async {
      when(
        () => pullRequests.cachedList(
          org,
          project: any(named: 'project'),
          filter: PrListFilter.toReview,
          repositoryId: any(named: 'repositoryId'),
        ),
      ).thenAnswer(
        (_) async => (
          items: [pr(7, 'From the cache')],
          fetchedAt: DateTime.now(),
          fromCache: true,
        ),
      );
      when(
        () => pullRequests.cachedList(
          org,
          project: any(named: 'project'),
          filter: PrListFilter.mine,
          repositoryId: any(named: 'repositoryId'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => pullRequests.list(
          org,
          project: any(named: 'project'),
          filter: any(named: 'filter'),
        ),
      ).thenThrow(const AdoNetworkException('offline'));
      await pump(
        tester,
        PullRequestsCard(args: argsFor(aWidget('PRs', 'PullrequestsWidget'))),
      );

      expect(find.text('From the cache'), findsOneWidget);
      expect(find.text('offline'), findsOneWidget);
    });
  });

  group('team members', () {
    testWidgets('draws every member with a name', (tester) async {
      when(
        () => people.teamMembers(
          org,
          any(),
          team,
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => const [
          IdentityRef(displayName: 'Ada Example', id: 'ada'),
          IdentityRef(displayName: 'Grace Example', id: 'grace'),
        ],
      );
      await pump(
        tester,
        TeamMembersCard(args: argsFor(aWidget('Team', 'TeamMembersWidget'))),
      );

      expect(find.text('Ada Example'), findsOneWidget);
      expect(find.text('Grace Example'), findsOneWidget);
    });

    testWidgets('a refusal is inline', (tester) async {
      when(
        () => people.teamMembers(
          org,
          any(),
          team,
          refresh: any(named: 'refresh'),
        ),
      ).thenThrow(const AdoForbiddenException('no team read'));
      await pump(
        tester,
        TeamMembersCard(args: argsFor(aWidget('Team', 'TeamMembersWidget'))),
      );

      expect(find.text('no team read'), findsOneWidget);
    });
  });

  group('markdown', () {
    testWidgets('renders the settings string and clamps with More', (
      tester,
    ) async {
      final long = List.filled(40, 'A line of notes.').join('\n\n');
      await pump(
        tester,
        MarkdownCard(
          args: argsFor(aWidget('Notes', 'MarkdownWidget', settings: long)),
          settings: MarkdownSettings(content: long),
        ),
      );

      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('short text needs no More', (tester) async {
      await pump(
        tester,
        MarkdownCard(
          args: argsFor(aWidget('Notes', 'MarkdownWidget', settings: 'Hi')),
          settings: const MarkdownSettings(content: 'Hi'),
        ),
      );

      expect(find.text('More'), findsNothing);
    });
  });

  group('links', () {
    testWidgets('lists the app’s own destinations and goes to one', (
      tester,
    ) async {
      await pump(
        tester,
        LinksCard(args: argsFor(aWidget('Handy links', 'WorkLinksWidget'))),
      );

      expect(find.text('Work items'), findsOneWidget);
      expect(find.text('Board'), findsOneWidget);
      expect(find.text('Pipelines'), findsOneWidget);

      await tester.tap(find.text('Pipelines'));
      await tester.pumpAndSettle();

      expect(visited.single, endsWith('/pipelines'));
    });

    testWidgets('New Work Item stays a single-purpose card', (tester) async {
      await pump(
        tester,
        LinksCard(args: argsFor(aWidget('New work item', 'NewWorkItemWidget'))),
      );

      expect(find.text('New work item'), findsWidgets);
      expect(find.text('Board'), findsNothing);
    });
  });

  group('build history', () {
    BuildRun run(int id, String result, int seconds) => BuildRun.fromJson({
      'id': id,
      'buildNumber': '2026.09.$id',
      'status': 'completed',
      'result': result,
      'definition': {'name': 'boardhop-scratch', 'id': 139},
      'startTime': '2026-09-15T09:00:00Z',
      'finishTime': DateTime.utc(2026, 9, 15, 9, 0, seconds).toIso8601String(),
      'sourceBranch': 'refs/heads/main',
    });

    testWidgets('draws one bar per run and opens one', (tester) async {
      when(
        () => pipelines.runs(
          org,
          project,
          definitionId: 139,
          top: any(named: 'top'),
          queryOrder: any(named: 'queryOrder'),
        ),
      ).thenAnswer(
        (_) async => [
          run(3, 'failed', 30),
          run(2, 'succeeded', 90),
          run(1, 'succeeded', 60),
        ],
      );
      await pump(
        tester,
        BuildHistoryCard(
          args: argsFor(aWidget('Build history', 'BuildHistogramWidget')),
          settings: const BuildHistorySettings(definitionId: 139),
        ),
      );

      expect(find.textContaining('3 runs'), findsOneWidget);
      expect(find.byType(Tooltip), findsNWidgets(3));
    });

    testWidgets('no runs says so', (tester) async {
      when(
        () => pipelines.runs(
          org,
          project,
          definitionId: 139,
          top: any(named: 'top'),
          queryOrder: any(named: 'queryOrder'),
        ),
      ).thenAnswer((_) async => const []);
      await pump(
        tester,
        BuildHistoryCard(
          args: argsFor(aWidget('Build history', 'BuildHistogramWidget')),
          settings: const BuildHistorySettings(definitionId: 139),
        ),
      );

      expect(find.text('No runs yet.'), findsOneWidget);
    });
  });

  group('sprint overview', () {
    testWidgets('counts by state category and names every segment', (
      tester,
    ) async {
      final iteration = TeamIteration(
        id: 'iter-1',
        name: 'Iteration 1',
        path: '$project\\Iteration 1',
        timeFrame: 'current',
        startDate: DateTime.utc(2026, 9, 8),
        finishDate: DateTime.utc(2026, 9, 21),
      );
      when(
        () => sprints.iterations(
          org,
          project,
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => SprintIterations(all: [iteration]));
      when(
        () => sprints.cachedSnapshot(
          org,
          project,
          'iter-1',
          team: any(named: 'team'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => sprints.load(
          org,
          project,
          'iter-1',
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => SprintSnapshot(
          iteration: iteration,
          columns: const [],
          rows: [
            SprintRow(
              parent: item(1, 'A story', state: 'Active'),
              tasks: [
                item(2, 'Done task', state: 'Done'),
                item(3, 'New task', state: 'New'),
              ],
            ),
          ],
          fetchedAt: DateTime.utc(2026, 9, 15),
        ),
      );
      await pump(
        tester,
        SprintOverviewCard(
          args: argsFor(aWidget('Sprint', 'SprintOverviewWidget')),
        ),
      );

      expect(find.text('Iteration 1'), findsOneWidget);
      expect(
        find.text('1 not started · 1 in progress · 1 done'),
        findsOneWidget,
      );
      expect(find.textContaining('working day'), findsOneWidget);
    });

    testWidgets('a team with no sprints says so', (tester) async {
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
        SprintOverviewCard(
          args: argsFor(aWidget('Sprint', 'SprintOverviewWidget')),
        ),
      );

      expect(find.text('This team has no sprints.'), findsOneWidget);
    });

    test('working days left counts Monday to Friday, inclusive', () {
      // Tuesday 15 Sep 2026 → Monday 21 Sep 2026 is Tue–Fri plus the Monday.
      expect(
        workingDaysLeft(DateTime(2026, 9, 21), now: DateTime(2026, 9, 15)),
        5,
      );
      expect(workingDaysLeft(null), 0);
    });
  });

  group('code tile', () {
    testWidgets('names the repository and branch and opens the repo', (
      tester,
    ) async {
      await pump(
        tester,
        CodeTileCard(
          args: argsFor(aWidget('Code', 'CodeScalarWidget')),
          settings: const CodeTileSettings(
            repositoryId: 'r-1',
            repositoryName: 'boardhop',
            branchName: 'refs/heads/main',
          ),
        ),
      );

      expect(find.text('boardhop'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);

      await tester.tap(find.text('boardhop'));
      await tester.pumpAndSettle();

      expect(visited.single, endsWith('/repos/boardhop'));
    });
  });

  group('the frame', () {
    testWidgets('Analytics refusing is a card state, not an error (D14)', (
      tester,
    ) async {
      await pump(
        tester,
        _RefusedCard(args: argsFor(aWidget('Burndown', 'BurndownWidget'))),
      );

      expect(find.textContaining('Analytics unavailable'), findsOneWidget);
      expect(find.text('never drawn'), findsNothing);
    });

    testWidgets('a bump on the reload scope reloads the card', (tester) async {
      final reload = DashboardReload();
      addTearDown(reload.dispose);
      when(
        () => workItems.queryCount(org, project, 'q-1', top: any(named: 'top')),
      ).thenAnswer((_) async => 1);
      await pump(
        tester,
        DashboardReloadScope(
          notifier: reload,
          child: QueryTileCard(
            args: argsFor(aWidget('Open bugs', 'QueryScalarWidget')),
            settings: const QueryTileSettings(queryId: 'q-1'),
          ),
        ),
      );
      verify(
        () => workItems.queryCount(org, project, 'q-1', top: any(named: 'top')),
      ).called(1);

      reload.bump();
      await tester.pumpAndSettle();

      verify(
        () => workItems.queryCount(org, project, 'q-1', top: any(named: 'top')),
      ).called(1);
    });
  });

  group('the registry', () {
    DashboardWidget kind(String suffix, {String? settings}) => DashboardWidget(
      id: 'w',
      name: 'A widget',
      contributionId:
          'ms.vss-dashboards-web.Microsoft.VisualStudioOnline.Dashboards.'
          '$suffix',
      settings: settings,
    );

    test('hides the D2 and D10 kinds', () {
      expect(DashboardRegistry.renders(kind('WitChartWidget')), isFalse);
      expect(DashboardRegistry.renders(kind('IFrameWidget')), isFalse);
      expect(DashboardRegistry.renders(kind('SprintCapacityWidget')), isFalse);
      expect(
        DashboardRegistry.renders(kind('TestResultsTrendWidget')),
        isFalse,
      );
      expect(
        DashboardRegistry.renders(
          DashboardWidget(
            id: 'w',
            name: 'Someone else’s widget',
            contributionId: 'acme.widgets.ShinyWidget',
          ),
        ),
        isFalse,
      );
    });

    test('hides a widget whose typed settings do not parse', () {
      expect(
        DashboardRegistry.renders(
          kind('QueryScalarWidget', settings: '{"no":"queryId"}'),
        ),
        isFalse,
      );
      expect(
        DashboardRegistry.renders(
          kind('QueryScalarWidget', settings: '{"queryId":"q-1"}'),
        ),
        isTrue,
      );
    });

    test('a kind that stores null settings on purpose still renders', () {
      for (final suffix in [
        'AssignedToMeWidget',
        'TeamMembersWidget',
        'PullrequestsWidget',
        'WorkLinksWidget',
        'OtherLinksWidget',
        'HowToLinksWidget',
        'VSLinksWidget',
        'NewWorkItemWidget',
      ]) {
        expect(DashboardRegistry.renders(kind(suffix)), isTrue, reason: suffix);
      }
    });

    test('every Team overview card has a builder', () {
      for (final w in TeamOverview.forTeam('t').widgets) {
        expect(DashboardRegistry.renders(w), isTrue, reason: w.builtInKind);
      }
    });
  });
}
