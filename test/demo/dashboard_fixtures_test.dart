import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/models/dashboard.dart';
import 'package:boardhop/data/repositories/analytics_repository.dart';
import 'package:boardhop/data/repositories/dashboard_repository.dart';
import 'package:boardhop/data/repositories/people_repository.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/demo/demo_backend.dart';
import 'package:boardhop/demo/demo_world.dart';
import 'package:boardhop/demo/fixtures/dashboard/demo_dashboards.dart';
import 'package:boardhop/demo/fixtures/dashboard/demo_history.dart';
import 'package:boardhop/features/dashboards/dashboard_page.dart';
import 'package:boardhop/features/dashboards/widgets/registry.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:boardhop/demo/fixtures/core_fixtures.dart';
import 'package:boardhop/demo/fixtures/dashboard_fixtures.dart';
import 'package:boardhop/demo/fixtures/pipeline_fixtures.dart';
import 'package:boardhop/demo/fixtures/work_fixtures.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';

const org = DemoWorld.org;
const project = DemoWorld.project;
const team = DemoWorld.teamId;

/// Requests the dashboard fixtures own. Anything else missing belongs to
/// another area's fixtures.
bool _mine(String miss) =>
    miss.contains('analytics.dev.azure.com') ||
    miss.contains('/_apis/dashboard/') ||
    miss.contains('/_apis/favorite/') ||
    miss.contains('/_apis/wit/queries/') ||
    RegExp(r'/_apis/wit/wiql/[0-9a-f-]{36}').hasMatch(miss);

class _AuthService extends Mock implements AuthService {}

/// `demoHarness()` with the dashboard fixtures registered **before** the
/// work fixtures. The work fixtures' `wit/wiql/{id}` and `wit/queries/{id}`
/// routes match any GUID and answer null for ids they do not know, which
/// stops the backend before it reaches this area's saved queries; in this
/// order both areas' queries are served. `buildDemoBackend()` needs the same
/// order (or the work routes narrowed to their own ids).
({AdoClient client, AppDatabase db, DemoBackend backend}) demoHarness() {
  final backend = DemoBackend(latency: Duration.zero);
  registerCoreFixtures(backend);
  registerDashboardFixtures(backend);
  registerWorkFixtures(backend);
  registerPipelineFixtures(backend);
  final client = AdoClient(
    tokenProvider: ({tenantId, accountId}) async => 'demo',
    dio: Dio()..httpClientAdapter = backend,
  );
  final db = AppDatabase(NativeDatabase.memory());
  return (client: client, db: db, backend: backend);
}

void main() {
  group('repositories', _repositories);
  group('DashboardPage', _page);
}

void _repositories() {
  late ({dynamic client, dynamic db, dynamic backend}) h;
  late DashboardRepository dashboards;
  late AnalyticsRepository analytics;
  late WorkItemRepository workItems;

  setUp(() {
    final harness = demoHarness();
    h = (client: harness.client, db: harness.db, backend: harness.backend);
    dashboards = DashboardRepository(harness.client, harness.db, 'demo');
    analytics = AnalyticsRepository(harness.client, harness.db, 'demo');
    workItems = WorkItemRepository(harness.client, harness.db, userId: 'demo');
  });

  tearDown(() async {
    final List<String> misses = h.backend.misses;
    expect(misses.where(_mine), isEmpty, reason: 'dashboard misses: $misses');
    await h.db.close();
  });

  test('lists three team dashboards, the overview a favorite', () async {
    final list = await dashboards.list(org, project);
    expect(list.map((d) => d.name), [
      'Boardhop Overview',
      'Release readiness',
      'Relay health',
    ]);
    expect(list.every((d) => d.teamId == team), isTrue);
    expect(list.every((d) => d.scope == DashboardScope.team), isTrue);
    expect(await dashboards.favorites(org, project), {
      DemoDashboards.overviewId,
    });
    final catalog = await dashboards.catalogNames(org, project);
    expect(catalog.values, contains('Velocity'));
  });

  test('every widget on every dashboard renders natively', () async {
    for (final summary in await dashboards.list(org, project)) {
      final d = await dashboards.get(org, project, team, summary.id);
      expect(d.widgets, isNotEmpty);
      for (final w in d.widgets) {
        expect(
          DashboardRegistry.renders(w),
          isTrue,
          reason: '${d.name}: ${w.name} (${w.kind})',
        );
      }
    }
    final overview = await dashboards.get(
      org,
      project,
      team,
      DemoDashboards.overviewId,
    );
    expect(overview.orderedWidgets.take(3).map((w) => w.kind), [
      WidgetKind.sprintBurndown,
      WidgetKind.velocity,
      WidgetKind.cumulativeFlow,
    ]);
  });

  test('query tiles and lists count the world', () async {
    final bugs = DemoQueries.activeBugs;
    final count = await workItems.queryCount(org, project, bugs.id);
    final expected = DemoWorld.workItems
        .where(
          (w) => w.type == 'Bug' && (w.state == 'New' || w.state == 'Active'),
        )
        .length;
    expect(count, expected);
    expect(count, greaterThan(0));

    final review = await workItems.queryCount(
      org,
      project,
      DemoQueries.inReview.id,
    );
    expect(
      review,
      DemoWorld.workItems.where((w) => w.column == 'Review').length,
    );

    final meta = await workItems.queryMeta(
      org,
      project,
      DemoQueries.priorityOne.id,
    );
    expect(meta.isFlat, isTrue);
    expect(meta.wiql, contains('Priority'));
    for (final q in DemoQueries.all) {
      expect(
        await workItems.queryCount(org, project, q.id),
        greaterThan(0),
        reason: q.name,
      );
    }
  });

  test('the current sprint burndown ends on the world\'s states', () async {
    final sprint = DemoWorld.currentSprint;
    final days = await analytics.burndown(
      org,
      project,
      sprint.id,
      start: sprint.start,
      end: sprint.finish,
    );
    expect(days, isNotEmpty);
    expect(days.first.date, sprint.start);
    final inSprint = DemoHistory.currentSprint.items;
    final open = inSprint
        .where((h) => DemoHistory.stateCategory(h.item.state) != 'Completed')
        .length;
    expect(days.last.remaining, open);
    expect(days.last.done, inSprint.length - open);
    // A past sprint draws too.
    final last = DemoWorld.sprints[1];
    final past = await analytics.burndown(
      org,
      project,
      last.id,
      start: last.start,
      end: last.finish,
    );
    expect(past.length, 12);
    expect(past.last.remaining, lessThan(past.first.remaining));
  });

  test('velocity has six sprints of believable points', () async {
    final sk = await analytics.teamSk(org, project, team);
    expect(sk, team);
    final types = await analytics.requirementTypes(org, project, sk);
    expect(types, ['Bug', 'User Story']);
    final velocity = await analytics.velocity(org, project, sk, types);
    expect(velocity.map((v) => v.iteration.name), [
      'Sprint 14',
      'Sprint 13',
      'Sprint 12',
      'Sprint 11',
      'Sprint 10',
      'Sprint 9',
    ]);
    for (final v in velocity.skip(1)) {
      final done = v.completedPoints + v.completedLatePoints;
      expect(done, inInclusiveRange(30, 50), reason: v.iteration.name);
      expect(v.plannedPoints, greaterThanOrEqualTo(done - 3));
    }
    expect(velocity.first.planned, greaterThan(0));
  });

  test('cumulative flow grows Done over 30 days', () async {
    final board = await analytics.requirementBoardName(org, project, team);
    expect(board, 'Stories');
    final flow = await analytics.cumulativeFlow(
      org,
      project,
      team,
      board!,
      DateTime.now().toUtc().subtract(const Duration(days: 30)),
    );
    expect(flow.columns, ['New', 'Ready', 'In Progress', 'Review', 'Done']);
    expect(flow.days.length, inInclusiveRange(30, 32));
    final first = flow.days.first.counts['Done']!;
    final last = flow.days.last.counts['Done']!;
    expect(last - first, inInclusiveRange(8, 30));
    expect(
      flow.days.last.counts['Review'],
      DemoWorld.workItems.where((w) => w.column == 'Review').length,
    );
  });

  test('cycle time, work by state, burnup and pipeline outcomes', () async {
    final start = DateTime.now().toUtc().subtract(const Duration(days: 60));
    final cycle = await analytics.cycleAndLeadTime(
      org,
      project,
      team,
      start,
      types: const ['Bug', 'User Story'],
    );
    expect(cycle.items.length, greaterThan(15));
    expect(cycle.averageCycleDays, inInclusiveRange(1.5, 8));

    final states = await analytics.workByState(org, project, team);
    expect(
      states.map((s) => s.workItemType).toSet(),
      containsAll(['Bug', 'Task']),
    );

    final first = DemoHistory.sprints.first;
    final burnup = await analytics.teamBurndown(
      org,
      project,
      team,
      const ['Bug', 'User Story'],
      first.start,
      DemoHistory.sprints.last.finish,
    );
    expect(burnup.first.done, lessThan(burnup.last.done));
    expect(burnup.last.remaining, DemoHistory.openToday());

    final outcomes = await analytics.pipelineOutcomes(
      org,
      project,
      42,
      start.subtract(const Duration(days: 30)),
    );
    expect(outcomes.total, greaterThan(40));
    expect(outcomes.succeeded / outcomes.total, greaterThan(0.8));
    expect(outcomes.runs.length, 20);
  });
}

/// The real page over the demo backend, at the store screenshot's sizes.
void _page() {
  late AdoClient client;
  late AppDatabase db;
  late DemoBackend backend;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final harness = demoHarness();
    client = harness.client;
    db = harness.db;
    backend = harness.backend;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester, Size logical) async {
    tester.view.physicalSize = logical * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final auth = _AuthService();
    when(() => auth.accountById(any())).thenReturn(
      Account(
        id: 'demo',
        username: DemoWorld.me.email,
        name: DemoWorld.me.name,
      ),
    );
    when(() => auth.knownAccounts).thenReturn(const []);
    final bloc = AuthBloc(auth);
    addTearDown(bloc.close);
    final workItems = WorkItemRepository(client, db, userId: 'demo');
    final people = PeopleRepository(client, db, 'demo');
    final forms = WorkItemFormRepository(client, workItems, db, 'demo', people);
    final router = GoRouter(
      initialLocation:
          '/a/demo/orgs/$org/projects/$project/dashboards'
          '?dashboard=${DemoDashboards.overviewId}',
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/dashboards',
          builder: (context, state) => AccountScope(
            accountId: 'demo',
            child: DashboardPage(
              org: org,
              project: project,
              dashboardId: state.uri.queryParameters['dashboard'],
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DashboardRepository>.value(
            value: DashboardRepository(client, db, 'demo'),
          ),
          RepositoryProvider<SprintRepository>.value(
            value: SprintRepository(client, workItems, forms, db, 'demo'),
          ),
          RepositoryProvider<WorkItemRepository>.value(value: workItems),
          RepositoryProvider<PullRequestRepository>.value(
            value: PullRequestRepository(client, db, 'demo'),
          ),
          RepositoryProvider<PipelineRepository>.value(
            value: PipelineRepository(client, db, 'demo'),
          ),
          RepositoryProvider<PeopleRepository>.value(value: people),
          RepositoryProvider<ProjectRepository>.value(
            value: ProjectRepository(client, db),
          ),
          RepositoryProvider<AnalyticsRepository>.value(
            value: AnalyticsRepository(client, db, 'demo'),
          ),
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
    // The backend answers after a short delay per request, and the cards
    // load in waves: the dashboard, then each card's own reads.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Lets the requests still in flight finish before the tree goes, so no
  /// timer outlives the test.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  const titles = [
    'Sprint burndown',
    'Velocity',
    'Cumulative flow',
    'Active bugs',
    'Ready for review',
    'Sprint goal',
  ];

  testWidgets('draws the overview on an iPhone 17 Pro Max', (tester) async {
    await pump(tester, const Size(440, 956));

    expect(find.text('Boardhop Overview'), findsOneWidget);
    for (final t in titles.take(3)) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Every chart drew: no card is still loading or refused.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Analytics'), findsNothing);
    expect(find.textContaining('No data'), findsNothing);
    for (final t in titles) {
      final f = find.text(t);
      if (f.evaluate().isNotEmpty) {
        debugPrint('phone $t at ${tester.getRect(f.first)}');
      }
    }
    final mine = backend.misses.where(
      (m) =>
          m.contains('analytics.dev.azure.com') ||
          m.contains('/_apis/dashboard/') ||
          m.contains('/_apis/favorite/') ||
          m.contains('/_apis/wit/queries/'),
    );
    expect(mine, isEmpty, reason: '${backend.misses}');
    debugPrint('other misses: ${backend.misses}');
    await unmount(tester);
  });

  testWidgets('draws the overview on an iPad Pro 13-inch', (tester) async {
    await pump(tester, const Size(1376, 1032));

    for (final t in titles) {
      expect(find.text(t), findsWidgets, reason: t);
      debugPrint('tablet $t at ${tester.getRect(find.text(t).first)}');
    }
    expect(find.textContaining('not shown in Boardhop'), findsNothing);
    await unmount(tester);
  });
}
