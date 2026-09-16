import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/write_queue.dart';
import 'package:boardhop/features/sprints/sprint_page.dart';
import 'package:boardhop/features/sprints/widgets/sprint_burndown_chart.dart';
import 'package:boardhop/features/work_items/work_item_detail_page.dart';
import 'package:boardhop/features/work_items/work_items_page.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/analytics_repository.dart';
import 'package:boardhop/data/repositories/board_repository.dart';
import 'package:boardhop/data/repositories/people_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/demo/demo_backend.dart';
import 'package:boardhop/demo/demo_world.dart';
import 'package:boardhop/demo/fixtures/work/wiql.dart';
import 'package:boardhop/features/boards/boards_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/mention_stubs.dart';
import '../features/root_tab_stubs.dart';
import 'demo_harness.dart';

const org = DemoWorld.org;
const project = DemoWorld.project;
const account = 'kelly@kammcs.com-demo';

void main() {
  late DemoBackend backend;
  late AppDatabase db;
  late WorkItemRepository workItems;
  late PeopleRepository people;
  late WorkItemFormRepository forms;
  late BoardRepository boards;
  late SprintRepository sprints;
  late AnalyticsRepository analytics;

  setUp(() {
    final harness = demoHarness();
    backend = harness.backend;
    db = harness.db;
    workItems = WorkItemRepository(harness.client, harness.db, userId: account);
    people = PeopleRepository(harness.client, harness.db, account);
    forms = WorkItemFormRepository(
      harness.client,
      workItems,
      harness.db,
      account,
      people,
    );
    boards = BoardRepository(harness.client, workItems, harness.db, account);
    sprints = SprintRepository(
      harness.client,
      workItems,
      forms,
      harness.db,
      account,
    );
    analytics = AnalyticsRepository(harness.client, harness.db, account);
  });

  tearDown(() async {
    expect(backend.misses, isEmpty, reason: 'every request answered');
    await db.close();
  });

  group('WIQL evaluator', () {
    List<int> ids(String wiql) => [
      for (final f in DemoWiql(wiql).run([
        for (final w in DemoWorld.workItems)
          {
            'System.Id': w.id,
            'System.TeamProject': 'Boardhop',
            'System.WorkItemType': w.type,
            'System.State': w.state,
            'System.AssignedTo': ?w.assignee?.identity(),
            'System.IterationPath': w.iterationPath,
            'System.ChangedDate': DemoWorld.iso(w.changedDate),
            'System.Title': w.title,
          },
      ]))
        f['System.Id'] as int,
    ];

    test('@Me, state exclusions and ORDER BY', () {
      final mine = ids(WorkItemRepository.assignedToMeWiql());
      expect(mine, containsAll([1234, 1262, 1264, 1257, 1275]));
      expect(mine, isNot(contains(1231)));
      expect(mine.first, anyOf(1234, 1262));
    });

    test('IN, @CurrentIteration and parentheses', () {
      final bugs = ids(
        "SELECT [System.Id] FROM WorkItems WHERE ([System.WorkItemType] IN "
        "('Bug') OR [System.Title] CONTAINS 'glass') AND "
        '[System.IterationPath] = @CurrentIteration',
      );
      // Bugs, and anything with glass in its title (1276 is a task).
      expect(bugs.toSet(), {1252, 1255, 1286, 1257, 1275, 1276});
    });

    test('@Today - n', () {
      final recent = ids(WorkItemRepository.recentlyUpdatedWiql(days: 1));
      expect(recent, contains(1234));
      expect(recent, isNot(contains(1210)));
    });
  });

  test('assigned to me (Work items list and project Home)', () async {
    final items = await workItems.refreshAssignedToMe(org, project);
    expect(items.map((w) => w.id), containsAll([1234, 1262, 1264]));
    expect(items.every((w) => w.assignedTo?.displayName == 'Kelly Kamm'), true);
    expect(items.first.changedDate, isNotNull);
    final types = await workItems.types(org, project);
    expect(types.map((t) => t.name), contains('User Story'));
    expect(types.firstWhere((t) => t.name == 'Bug').color, 'CC293D');
    final recent = await workItems.refreshRecentlyUpdated(org, project);
    expect(recent, isNotEmpty);
    final queries = await workItems.queries(org, project);
    final leaves = [for (final q in queries) ...q.leaves];
    expect(leaves, hasLength(4));
    final bugs = await workItems.refreshQuery(
      org,
      project,
      leaves.firstWhere((q) => q.name == 'Active bugs').id,
    );
    expect(bugs.map((w) => w.type).toSet(), {'Bug'});
    final meta = await workItems.queryMeta(org, project, leaves.first.id);
    expect(meta.isFlat, isTrue);
    expect(
      await workItems.queryCount(org, project, leaves.first.id),
      items.length,
    );
  });

  test('Stories board: cards in every column and both halves', () async {
    final list = await boards.boards(org, project);
    expect(list.first.name, 'Stories');
    final snapshot = await boards.load(org, project, list.first.id);
    final board = snapshot.board;
    expect(
      [for (final s in board.slots) s.title],
      ['New', 'Ready', 'In Progress', 'In Progress', 'Review', 'Done'],
    );
    final counts = [for (final slot in snapshot.cardsBySlot) slot.length];
    expect(counts.where((c) => c > 0).length, 6, reason: '$counts');
    expect(counts.where((c) => c >= 3).length, greaterThanOrEqualTo(4));
    expect(snapshot.rankField, BoardRepository.stackRank);
    final doneHalf = snapshot.cardsBySlot[3];
    expect(doneHalf.single.id, 1236);
    final story = snapshot.cardsBySlot[2].firstWhere((w) => w.id == 1234);
    expect(story.tags, ['sprints']);
    expect(story.assignedTo?.displayName, 'Kelly Kamm');
    // Features board too.
    final features = await boards.load(org, project, list[1].id);
    expect(features.cardCount, 5);
  });

  test('a board move writes and sticks', () async {
    final list = await boards.boards(org, project);
    final snapshot = await boards.load(org, project, list.first.id);
    final card = snapshot.cardsBySlot[1].first;
    final moved = await boards.move(
      org,
      project,
      snapshot.board,
      card,
      snapshot.board.slots[2],
    );
    expect(moved.state, 'Active');
    expect(moved.rev, card.rev + 1);
    final again = await boards.load(org, project, list.first.id);
    expect(again.cardsBySlot[2].map((w) => w.id), contains(card.id));
  });

  test('sprint: taskboard, capacity and burndown', () async {
    final iterations = await sprints.iterations(org, project);
    expect(iterations.current.single.name, 'Sprint 14');
    expect(iterations.past, hasLength(2));
    expect(iterations.future, hasLength(2));
    final current = iterations.defaultIteration!;
    final snapshot = await sprints.load(org, project, current.id);

    expect(
      [for (final c in snapshot.columns) c.name],
      ['To Do', 'In Progress', 'Done'],
    );
    expect(snapshot.rows.first.parent!.id, 1234);
    expect(snapshot.unparented.tasks, isEmpty);
    final hero = snapshot.rows.first;
    expect(hero.tasks.map((t) => t.id), [1262, 1263, 1264]);
    expect(hero.remaining, 9);
    final cells = SprintRepository.distribute(snapshot.columns, snapshot.tasks);
    expect(cells.every((c) => c.length >= 4), isTrue, reason: '$cells');
    expect(snapshot.parents.map((w) => w.type).toSet(), {'User Story', 'Bug'});
    expect(snapshot.tasks.every((t) => t.assignedTo != null), isTrue);

    final capacity = await sprints.capacities(org, project, current.id);
    expect(capacity.members, hasLength(6));
    expect(capacity.totalPerDay, 35);
    expect(capacity.workingDays, hasLength(5));

    final days = await analytics.burndown(
      org,
      project,
      current.id,
      start: current.startDate!,
      end: current.finishDate!,
    );
    // Served by the dashboard fixtures' Analytics routes.
    expect(days, isNotEmpty);
    expect(days.first.remaining, greaterThan(days.last.remaining));
    expect(days.last.done, greaterThan(0));

    final teams = await sprints.teams(org, project);
    expect(teams.single.name, DemoWorld.team);
  });

  test('sprint writes: move a task, set remaining work', () async {
    final iterations = await sprints.iterations(org, project);
    final snapshot = await sprints.load(
      org,
      project,
      iterations.defaultIteration!.id,
    );
    final task = snapshot.rows.first.tasks.firstWhere((t) => t.id == 1264);
    final moved = await sprints.move(
      org,
      project,
      task,
      snapshot.columns[1],
      columns: snapshot.columns,
      iterationId: iterations.defaultIteration!.id,
    );
    expect(moved.state, 'In Progress');
    final hours = await sprints.setRemainingWork(org, project, moved, 3);
    expect(hours.field<num>(SprintRepository.remainingWorkField), 3);
  });

  test('work item detail: 1234 with form, links and comments', () async {
    final item = await workItems.refreshItem(org, project, 1234);
    expect(item.title, 'Sprint taskboard with capacity bars');
    expect(item.description, contains('capacity'));
    expect(
      item.field<String>('Microsoft.VSTS.Common.AcceptanceCriteria'),
      contains('amber'),
    );
    expect(item.parentRelation?.targetId, 1184);
    expect(
      item.childRelations.map((r) => r.targetId),
      containsAll([1262, 1263, 1264]),
    );
    expect(item.linkRelations.length, greaterThanOrEqualTo(5));

    final linked = await workItems.batch(org, project, [
      for (final r in item.linkRelations)
        if (r.targetId != null) r.targetId!,
    ]);
    expect(linked.map((w) => w.id), contains(1184));

    final spec = await forms.formSpec(org, project, item.type);
    expect(spec.source, FormSource.xmlForm);
    expect(spec.layout.header.map((c) => c.fieldReferenceName), [
      'System.Title',
      'System.Id',
      'System.AssignedTo',
      'System.State',
      'System.Reason',
      'System.AreaPath',
      'System.IterationPath',
      'System.ChangedDate',
    ]);
    final details = spec.layout.detailsPage!;
    final groups = [
      for (final s in details.sections)
        for (final g in s.groups) g.label,
    ];
    expect(
      groups,
      containsAll(['Description', 'Acceptance Criteria', 'Planning']),
    );
    expect(spec.fields['System.State']!.allowedValues, contains('Active'));
    expect(
      spec.fields['Microsoft.VSTS.Scheduling.StoryPoints']!.type.isNumeric,
      true,
    );
    expect(spec.type.transitionsFrom('Active'), contains('Resolved'));

    final comments = await workItems.comments(org, project, 1234);
    expect(comments, hasLength(4));
    expect(comments.first.createdBy.displayName, 'Sofia Alvarez');
    expect(
      comments.any((c) => c.mentions.contains(DemoWorld.kelly.id)),
      isTrue,
    );
    expect(comments[1].displayHtml, contains('data-vss-mention="version:2.0,'));

    final backlog = await forms.backlogTypes(org, project);
    expect(backlog.childTypeNames('User Story'), contains('Task'));

    final members = await forms.teamMembers(
      org,
      DemoWorld.projectId,
      DemoWorld.teamId,
    );
    expect(members, hasLength(6));
    final names = await people.identitiesByIds(org, [DemoWorld.aiko.id]);
    expect(names.values.single.displayName, 'Aiko Tanaka');
    expect(
      await forms.searchPeople(org, DemoWorld.projectId, 'pri'),
      hasLength(1),
    );
  });

  test('work item detail: 1231, the form pickers and a new comment', () async {
    final item = await workItems.refreshItem(org, project, 1231);
    expect(item.state, 'Resolved');
    final comments = await workItems.comments(org, project, 1231);
    expect(comments.any((c) => c.mentions.contains(DemoWorld.aiko.id)), isTrue);
    final added = await workItems.addComment(
      org,
      project,
      1231,
      'Thanks @<${DemoWorld.aiko.id}>, merging.',
    );
    expect(added.renderedText, contains('@Aiko Tanaka'));
    expect(added.mentions, [DemoWorld.aiko.id]);
    expect(await workItems.comments(org, project, 1231), hasLength(5));

    final bug = await forms.formSpec(org, project, 'Bug');
    expect(bug.fields.keys, contains('Microsoft.VSTS.TCM.ReproSteps'));
    final areas = await forms.classificationNodes(org, project);
    expect(areas!.children, hasLength(3));
    final nodes = await forms.classificationNodes(org, project, areas: false);
    expect(nodes!.children.map((n) => n.path), contains(r'Boardhop\Sprint 14'));
    final defaults = await forms.teamDefaults(org, project);
    expect(defaults.currentIterationPath, r'Boardhop\Sprint 14');
    expect(defaults.defaultArea, 'Boardhop');
    expect(await forms.tags(org, project), contains('tablet'));
    final templates = await forms.templates(org, project, DemoWorld.teamId);
    expect(templates.single.workItemTypeName, 'Bug');

    // An edit through the form's own patch.
    final ops = WorkItemFormRepository.buildEditOps(item, {
      'Microsoft.VSTS.Common.Priority': 2,
    });
    await forms.validatePatch(org, project, item, ops.skip(1).toList());
    final saved = await workItems.patch(org, project, item, ops);
    expect(saved.priority, 2);

    // A new task under the story.
    final created = await forms.create(
      org,
      project,
      'Task',
      WorkItemFormRepository.buildCreateOps(
        {'System.Title': 'Write the release note'},
        parentUrl:
            'https://dev.azure.com/kammcs/${DemoWorld.projectId}/_apis/wit/workItems/1231',
      ),
    );
    expect(created.id, greaterThan(1289));
    expect(created.state, 'To Do');
  });

  group('pages', () {
    late MentionStubs stubs;
    late MentionPullRequests prs;
    late _AuthService auth;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      stubs = mentionStubs();
      prs = MentionPullRequests();
      stubMentionPullRequests(prs, org: org);
      auth = _AuthService();
      when(() => auth.accountById(any())).thenReturn(
        Account(id: account, username: DemoWorld.me.email, name: 'Kelly Kamm'),
      );
      when(() => auth.accessToken(accountId: any(named: 'accountId')))
          .thenAnswer((_) async => 'demo');
    });

    /// Pumps [location] through the app's own route shapes and lets the demo
    /// backend answer in real time until [ready] appears.
    Future<void> pumpRoute(
      WidgetTester tester,
      String location,
      Finder ready, {
      Size size = const Size(2732, 2048),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final bloc = AuthBloc(auth);
      addTearDown(bloc.close);
      final queue = WriteQueue(db, workItems, userId: account);
      Widget scoped(Widget child) =>
          AccountScope(accountId: account, child: child);
      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(
            path: '/a/:account/orgs/:org/projects/:project/boards',
            builder: (context, state) =>
                scoped(const BoardsPage(org: org, project: project)),
          ),
          GoRoute(
            path: '/a/:account/orgs/:org/projects/:project/sprint',
            builder: (context, state) => scoped(
              SprintPage(
                org: org,
                project: project,
                iteration: state.uri.queryParameters['iteration'],
                initialTab: state.uri.queryParameters['tab'],
              ),
            ),
          ),
          GoRoute(
            path: '/a/:account/orgs/:org/projects/:project/work-items',
            builder: (context, state) =>
                scoped(const WorkItemsPage(org: org, project: project)),
          ),
          GoRoute(
            path: '/a/:account/orgs/:org/projects/:project/work-items/:id',
            builder: (context, state) => scoped(
              WorkItemDetailPage(
                org: org,
                project: project,
                id: int.parse(state.pathParameters['id']!),
                initialTab: state.uri.queryParameters['tab'],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MultiRepositoryProvider(
            providers: [
              ...rootChromeProviders(),
              ...mentionProviders((
                people: stubs.people,
                recents: stubs.recents,
                search: stubs.search,
              )),
              RepositoryProvider<AuthService>.value(value: auth),
              RepositoryProvider<WriteQueue>.value(value: queue),
              RepositoryProvider<PullRequestRepository>.value(value: prs),
              RepositoryProvider<BoardRepository>.value(value: boards),
              RepositoryProvider<WorkItemRepository>.value(value: workItems),
              RepositoryProvider<WorkItemFormRepository>.value(value: forms),
              RepositoryProvider<SprintRepository>.value(value: sprints),
              RepositoryProvider<AnalyticsRepository>.value(value: analytics),
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
        for (var i = 0; i < 60 && ready.evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
        // Let the lazy reads behind the first frame (capacity, burndown,
        // mentions) land too.
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }
      });
      await tester.pump();
    }

    /// Unmounts the page so drift's stream cleanup timers run inside the
    /// test rather than failing it as pending.
    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 1));
    }

    String route(String rest) =>
        '${Routes.project(account, org, project)}/$rest';

    testWidgets('Boards: the Stories board', (tester) async {
      await pumpRoute(
        tester,
        route('boards'),
        find.text('Sprint taskboard with capacity bars'),
      );
      expect(find.text('Stories'), findsWidgets);
      expect(find.text('Sprint taskboard with capacity bars'), findsOneWidget);
      expect(find.text('Wiki pages with Mermaid diagrams'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('Sprint: the taskboard', (tester) async {
      await pumpRoute(
        tester,
        route('sprint?tab=taskboard'),
        find.text('Capacity bar per person'),
      );
      expect(find.text('Capacity bar per person'), findsOneWidget);
      expect(find.text('To Do'), findsWidgets);
      expect(find.text('Done'), findsWidgets);
      expect(find.textContaining('Sprint 14'), findsWidgets);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('Sprint: the burndown', (tester) async {
      await pumpRoute(
        tester,
        route('sprint?tab=burndown'),
        find.byType(SprintBurndownChart),
      );
      expect(find.byType(SprintBurndownChart), findsWidgets);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('Work items: assigned to me', (tester) async {
      await pumpRoute(
        tester,
        route('work-items'),
        find.text('Remaining work rollup on story rows'),
      );
      expect(find.text('Remaining work rollup on story rows'), findsWidgets);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('Work item 1234: details and discussion', (tester) async {
      await pumpRoute(
        tester,
        route('work-items/1234?tab=comments'),
        find.textContaining('Checked on the iPad Pro', findRichText: true),
      );
      expect(
        find.textContaining('Checked on the iPad Pro', findRichText: true),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}

class _AuthService extends Mock implements AuthService {}
