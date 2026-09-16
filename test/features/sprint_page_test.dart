import 'dart:async';

import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/data/repositories/analytics_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/data/write_queue.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/sprints/sprint_page.dart';
import 'package:boardhop/features/sprints/widgets/sprint_burndown_chart.dart';
import 'package:boardhop/features/sprints/widgets/sprint_header.dart';
import 'package:boardhop/features/sprints/widgets/task_card_sheet.dart';
import 'package:boardhop/features/sprints/widgets/taskboard_grid.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'root_tab_stubs.dart';

class _Sprints extends Mock implements SprintRepository {}

class _Analytics extends Mock implements AnalyticsRepository {}

class _WorkItems extends Mock implements WorkItemRepository {}

class _Queue extends Mock implements WriteQueue {}

class _AuthService extends Mock implements AuthService {}

class _FakeWorkItem extends Fake implements WorkItem {}

/// The scratch project's sprint, shrunk to what a page test needs: a
/// customized taskboard (To Do / In Progress / Verify / Done, the shape
/// spike w34 found) and two stories with tasks, one of them Kelly's.
void main() {
  const org = 'o';
  const project = 'p';
  const team = 'team-1';
  const iterationId = 'iter-1';
  const futureId = 'iter-2';
  const me = 'kelly@kammcs.com';

  setUpAll(() {
    registerFallbackValue(_FakeWorkItem());
    registerFallbackValue(const TaskboardColumn(name: 'To Do', order: 0));
    registerFallbackValue(<Map<String, Object?>>[]);
  });

  TaskboardColumn column(
    String name,
    int order,
    String state,
    String category, {
    String? id,
  }) => TaskboardColumn(
    name: name,
    order: order,
    id: id ?? 'col-$order',
    mappings: {'Task': state},
    states: {
      'Task': [state],
    },
    stateCategory: category,
  );

  final columns = [
    column('To Do', 0, 'To Do', 'Proposed'),
    column('In Progress', 1, 'In Progress', 'InProgress'),
    // Verify shares In Progress with the column before it: this is the
    // case that needs the taskboard column call (spike w34).
    column('Verify', 2, 'In Progress', 'InProgress'),
    column('Done', 3, 'Done', 'Completed'),
  ];

  WorkItem task(
    int id, {
    String state = 'To Do',
    String title = 'A task',
    IdentityRef? who,
    double? remaining,
    int? parent,
  }) => WorkItem.fromJson({
    'id': id,
    'rev': 3,
    'fields': {
      'System.Id': id,
      'System.WorkItemType': 'Task',
      'System.Title': title,
      'System.State': state,
      'System.AssignedTo': ?who?.toJson(),
      'Microsoft.VSTS.Scheduling.RemainingWork': ?remaining,
      'System.Parent': ?parent,
    },
  });

  WorkItem story(int id, String title) => WorkItem.fromJson({
    'id': id,
    'rev': 2,
    'fields': {
      'System.Id': id,
      'System.WorkItemType': 'User Story',
      'System.Title': title,
      'System.State': 'Active',
    },
  });

  const kelly = IdentityRef(
    displayName: 'Kelly Kamm',
    uniqueName: me,
    id: 'kelly-id',
  );
  const ada = IdentityRef(
    displayName: 'Ada Example',
    uniqueName: 'ada@example.test',
    id: 'ada-id',
  );

  final current = TeamIteration(
    id: iterationId,
    name: 'Iteration 1',
    path: '$project\\Iteration 1',
    timeFrame: 'current',
    startDate: DateTime.utc(2026, 9, 8),
    finishDate: DateTime.utc(2026, 9, 21),
  );
  const next = TeamIteration(
    id: futureId,
    name: 'Iteration 2',
    path: '$project\\Iteration 2',
    timeFrame: 'future',
  );

  SprintSnapshot snapshotWith({List<SprintRow>? rows, SprintRow? unparented}) =>
      SprintSnapshot(
        iteration: current,
        columns: columns,
        rows:
            rows ??
            [
              SprintRow(
                parent: story(15503, 'The sprint view'),
                tasks: [
                  task(15550, title: 'Model the columns', who: kelly),
                  task(
                    15551,
                    state: 'In Progress',
                    title: 'Write the tests',
                    who: ada,
                    remaining: 3,
                  ),
                ],
                remaining: 3,
              ),
              SprintRow(
                parent: story(15510, 'The taskboard grid'),
                tasks: [task(15552, title: 'Drag and drop', who: kelly)],
              ),
            ],
        unparented: unparented ?? const SprintRow(),
        fetchedAt: DateTime.utc(2026, 9, 15, 9),
      );

  late _Sprints sprints;
  late _Analytics analytics;
  late _WorkItems workItems;
  late _Queue queue;
  late _AuthService auth;
  late String location;
  late List<String> visited;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    sprints = _Sprints();
    analytics = _Analytics();
    workItems = _WorkItems();
    queue = _Queue();
    auth = _AuthService();
    location = '';
    visited = <String>[];

    when(() => auth.accountById(any()))
        .thenReturn(Account(id: 'a', username: me, name: 'Kelly Kamm'));
    when(() => auth.accessToken(accountId: any(named: 'accountId')))
        .thenAnswer((_) async => 'tok');
    when(() => workItems.types(org, project)).thenAnswer(
      (_) async => const [
        WorkItemType(name: 'Task', referenceName: 'Microsoft.VSTS.Task'),
        WorkItemType(
          name: 'User Story',
          referenceName: 'Microsoft.VSTS.UserStory',
        ),
      ],
    );
    when(() => sprints.defaultTeamId(org, project))
        .thenAnswer((_) async => team);
    when(() => sprints.defaultTeamName(org, project))
        .thenAnswer((_) async => 'DevOps Mobile App Team');
    // One team is the puremedia shape, and the picker hides the switch
    // there; the team-switch test overrides this with two.
    when(() => sprints.teams(org, project, refresh: any(named: 'refresh')))
        .thenAnswer(
          (_) async => const [
            SprintTeamRef(id: team, name: 'DevOps Mobile App Team'),
          ],
        );
    when(
      () => sprints.iterations(
        org,
        project,
        team: any(named: 'team'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => SprintIterations(all: [current, next]));
    when(
      () =>
          sprints.cachedSnapshot(org, project, any(), team: any(named: 'team')),
    ).thenAnswer((_) async => null);
    when(
      () => sprints.load(
        org,
        project,
        any(),
        team: any(named: 'team'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => snapshotWith());
    when(
      () => sprints.capacities(
        org,
        project,
        any(),
        team: any(named: 'team'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => const SprintCapacity());
    when(
      () => analytics.burndown(
        org,
        project,
        any(),
        start: any(named: 'start'),
        end: any(named: 'end'),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => const <BurndownDay>[]);
  });

  Future<void> pump(
    WidgetTester tester, {
    // Wide enough for the tablet's four-column grid without a sideways
    // scroll; the phone tests ask for a phone explicitly.
    Size size = const Size(3000, 4000),
    double devicePixelRatio = 2,
    String query = '',
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    final bloc = AuthBloc(_AuthService());
    addTearDown(bloc.close);
    final router = GoRouter(
      initialLocation: '/a/u1/orgs/$org/projects/$project/sprint$query',
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/sprint',
          builder: (context, state) {
            location = state.uri.toString();
            return AccountScope(
              accountId: 'u1',
              child: SprintPage(
                org: org,
                project: project,
                iteration: state.uri.queryParameters['iteration'],
                initialTab: state.uri.queryParameters['tab'],
              ),
            );
          },
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/work-items/:id',
          builder: (context, state) {
            visited.add(state.uri.toString());
            return const Scaffold(body: Text('work item page'));
          },
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/work-items',
          builder: (context, state) {
            visited.add(state.uri.toString());
            return const Scaffold(body: Text('work items page'));
          },
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects',
          builder: (context, state) => const Scaffold(body: Text('projects')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          ...rootChromeProviders(),
          RepositoryProvider<SprintRepository>.value(value: sprints),
          RepositoryProvider<AnalyticsRepository>.value(value: analytics),
          RepositoryProvider<WorkItemRepository>.value(value: workItems),
          RepositoryProvider<WriteQueue>.value(value: queue),
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
    testWidgets('a sprint with tasks opens on the Taskboard (S2)', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Taskboard'), findsOneWidget);
      // The taskboard's columns, not the backlog's rows.
      expect(find.text('In Progress'), findsWidgets);
      expect(find.text('Model the columns'), findsOneWidget);
    });

    testWidgets('a sprint with no tasks opens on the Backlog (S2)', (
      tester,
    ) async {
      when(
        () => sprints.load(
          org,
          project,
          any(),
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => snapshotWith(
          rows: [SprintRow(parent: story(15503, 'The sprint view'))],
        ),
      );
      await pump(tester);

      expect(find.text('No tasks'), findsOneWidget);
      expect(find.text('The sprint view'), findsOneWidget);
    });

    testWidgets('the route wins over both (S1)', (tester) async {
      await pump(tester, query: '?tab=burndown');

      expect(find.textContaining('Analytics has no history'), findsOneWidget);
    });

    testWidgets('the remembered tab wins over the default (S2)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.sprint_last_tab:$org/$project': 'backlog',
      });
      await pump(tester);

      expect(find.text('The sprint view'), findsOneWidget);
      expect(find.text('Model the columns'), findsNothing);
    });

    testWidgets('choosing a tab remembers it', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Burndown'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sprint_last_tab:$org/$project'), 'burndown');
    });

    testWidgets('the default tab is not remembered as a choice', (
      tester,
    ) async {
      // Otherwise the first open writes "taskboard" into the memory and
      // into the route, and the rule in S2 never applies again.
      await pump(tester);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sprint_last_tab:$org/$project'), isNull);
      expect(location, endsWith('/sprint'));
    });
  });

  group('the cache comes first (S9)', () {
    testWidgets('a cached snapshot is drawn before the network answers', (
      tester,
    ) async {
      when(
        () => sprints.cachedSnapshot(
          org,
          project,
          any(),
          team: any(named: 'team'),
        ),
      ).thenAnswer((_) async => snapshotWith());
      // The live read never finishes, so anything on screen came from the
      // cache.
      final pending = Completer<SprintSnapshot>();
      addTearDown(() => pending.complete(snapshotWith()));
      when(
        () => sprints.load(
          org,
          project,
          any(),
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) => pending.future);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.sprint_last_iteration:$org/$project': iterationId,
      });

      await pump(tester, settle: false);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Model the columns'), findsOneWidget);
      expect(find.textContaining('showing the cached copy'), findsNothing);
    });

    testWidgets(
      'the remembered sprint draws, but never outranks the plain route',
      (tester) async {
        // The memory exists so a cold open has something to draw, not to
        // change which sprint the plain route means: reopening on
        // `/sprint` must land on whatever is current now, not on the
        // future sprint that was last looked at (iPhone check, P-C).
        SharedPreferences.setMockInitialValues(<String, Object>{
          'flutter.sprint_last_iteration:$org/$project': futureId,
        });
        when(
          () => sprints.cachedSnapshot(
            org,
            project,
            any(),
            team: any(named: 'team'),
          ),
        ).thenAnswer((_) async => snapshotWith());

        await pump(tester);

        verify(
          () => sprints.load(
            org,
            project,
            iterationId,
            team: any(named: 'team'),
            refresh: any(named: 'refresh'),
          ),
        ).called(greaterThanOrEqualTo(1));
        verifyNever(
          () => sprints.load(
            org,
            project,
            futureId,
            team: any(named: 'team'),
            refresh: any(named: 'refresh'),
          ),
        );
      },
    );

    testWidgets('offline keeps the cached copy with the age line', (
      tester,
    ) async {
      when(
        () => sprints.cachedSnapshot(
          org,
          project,
          any(),
          team: any(named: 'team'),
        ),
      ).thenAnswer((_) async => snapshotWith());
      when(
        () => sprints.load(
          org,
          project,
          any(),
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenThrow(const AdoNetworkException('no route to host'));
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.sprint_last_iteration:$org/$project': iterationId,
      });

      await pump(tester);

      expect(find.textContaining('showing the cached copy'), findsOneWidget);
      expect(find.text('Model the columns'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('filters', () {
    testWidgets('the person filter narrows the cards (S10)', (tester) async {
      await pump(tester);
      expect(find.text('Write the tests'), findsOneWidget);

      await tester.tap(find.byTooltip('Filter by person'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Me · 2'));
      await tester.pumpAndSettle();

      expect(find.text('Write the tests'), findsNothing);
      expect(find.text('Model the columns'), findsOneWidget);
      expect(find.text('Drag and drop'), findsOneWidget);
    });

    testWidgets(
      "the header keeps the whole sprint's figures while the filter is on",
      (tester) async {
        // The verdict compares against a burndown Analytics computed for
        // everyone, so a filtered "remaining" beside an unfiltered ideal
        // read "1.3 items/day ahead" the moment you filtered to yourself
        // (iPhone check, P-C). The lists are what the filter narrows.
        await pump(tester, query: '?tab=backlog');
        expect(find.text('3 h'), findsOneWidget);

        await tester.tap(find.byTooltip('Filter by person'));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('Me · 2'));
        await tester.pumpAndSettle();

        // Still the sprint's own rollup in hours, not the two tasks of
        // mine that carry no Remaining Work at all.
        expect(find.text('3 h'), findsOneWidget);
        // And the rows below did narrow: both stories drop to one task.
        expect(find.text('1 task'), findsNWidgets(2));
      },
    );

    testWidgets('the chip strip picks one story on a phone (S4)', (
      tester,
    ) async {
      await pump(tester, size: const Size(1170, 2532), devicePixelRatio: 3);

      expect(find.text('Drag and drop'), findsOneWidget);
      await tester.tap(find.textContaining('#15503'));
      await tester.pumpAndSettle();

      expect(find.text('Model the columns'), findsOneWidget);
      expect(find.text('Drag and drop'), findsNothing);
    });
  });

  group('moving a task', () {
    setUp(() {
      when(
        () => sprints.move(
          org,
          project,
          any(),
          any(),
          columns: any(named: 'columns'),
          iterationId: any(named: 'iterationId'),
          team: any(named: 'team'),
        ),
      ).thenAnswer((i) async => i.positionalArguments[2] as WorkItem);
      when(
        () => sprints.reorder(
          org,
          project,
          any(),
          previousId: any(named: 'previousId'),
          nextId: any(named: 'nextId'),
          parentId: any(named: 'parentId'),
          team: any(named: 'team'),
        ),
      ).thenAnswer((_) async => <int, double>{});
    });

    testWidgets(
      'the sheet moves through the repository, with the columns and the '
      'iteration (spike w34)',
      (tester) async {
        await pump(tester);
        await tester.tap(find.text('Model the columns'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(TaskCardSheet),
            matching: find.text('Verify'),
          ),
        );
        await tester.pumpAndSettle();

        final call = verify(
          () => sprints.move(
            org,
            project,
            captureAny(),
            captureAny(),
            columns: captureAny(named: 'columns'),
            iterationId: captureAny(named: 'iterationId'),
            team: any(named: 'team'),
          ),
        )..called(1);
        expect((call.captured[0] as WorkItem).id, 15550);
        expect((call.captured[1] as TaskboardColumn).name, 'Verify');
        // Without these two the Verify column never sticks: the state
        // patch alone lands the card in the first column mapping that
        // state.
        expect((call.captured[2] as List).length, 4);
        expect(call.captured[3], iterationId);
      },
    );

    testWidgets('a drag across columns moves through the repository', (
      tester,
    ) async {
      await pump(tester);
      final source = find.text('Model the columns');
      final target = find.text('Write the tests');
      expect(source, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final call = verify(
        () => sprints.move(
          org,
          project,
          captureAny(),
          captureAny(),
          columns: captureAny(named: 'columns'),
          iterationId: captureAny(named: 'iterationId'),
          team: any(named: 'team'),
        ),
      )..called(1);
      expect((call.captured[0] as WorkItem).id, 15550);
      expect((call.captured[1] as TaskboardColumn).name, 'In Progress');
      expect((call.captured[2] as List).length, 4);
      expect(call.captured[3], iterationId);
      // And the rank within the destination cell, under that row's parent.
      final order = verify(
        () => sprints.reorder(
          org,
          project,
          any(),
          previousId: any(named: 'previousId'),
          nextId: any(named: 'nextId'),
          parentId: captureAny(named: 'parentId'),
          team: any(named: 'team'),
        ),
      )..called(1);
      expect(order.captured.single, 15503);
    });

    testWidgets('a drag into another story is refused, not silently dropped', (
      tester,
    ) async {
      await pump(tester);
      final source = find.text('Model the columns');
      final target = find.text('Drag and drop');

      final gesture = await tester.startGesture(tester.getCenter(source));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.text('Moving a task to another story is not supported yet'),
        findsOneWidget,
      );
      verifyNever(
        () => sprints.move(
          org,
          project,
          any(),
          any(),
          columns: any(named: 'columns'),
          iterationId: any(named: 'iterationId'),
          team: any(named: 'team'),
        ),
      );
    });

    testWidgets(
      'a move into Done sends no Remaining Work with the state, and lets '
      'the process rule clear it',
      (tester) async {
        // TF401320 InvalidNotEmpty: the stock processes rule that a
        // completed task's Remaining Work is *empty*, so a zero on the
        // same patch is refused — and the rule clears the field itself,
        // which is what the returned item shows.
        when(
          () => sprints.move(
            org,
            project,
            any(),
            any(),
            columns: any(named: 'columns'),
            iterationId: any(named: 'iterationId'),
            team: any(named: 'team'),
          ),
        ).thenAnswer(
          (_) async =>
              task(15551, state: 'Done', title: 'Write the tests', who: ada),
        );
        when(() => sprints.setRemainingWork(org, project, any(), any()))
            .thenAnswer((i) async => i.positionalArguments[2] as WorkItem);

        await pump(tester);
        await tester.tap(find.text('Write the tests'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(TaskCardSheet),
            matching: find.text('Done'),
          ),
        );
        await tester.pumpAndSettle();

        verify(
          () => sprints.move(
            org,
            project,
            any(),
            any(),
            columns: any(named: 'columns'),
            iterationId: any(named: 'iterationId'),
            team: any(named: 'team'),
          ),
        ).called(1);
        // The item came back cleared (the rule ran), so nothing follows.
        verifyNever(() => sprints.setRemainingWork(org, project, any(), any()));
      },
    );

    testWidgets(
      'a process without that rule gets the zero as a patch of its own',
      (tester) async {
        // The move answers with the hours still on the item: no rule ran,
        // so the page clears them itself rather than leaving a finished
        // task claiming 3 h in every rollup.
        when(
          () => sprints.move(
            org,
            project,
            any(),
            any(),
            columns: any(named: 'columns'),
            iterationId: any(named: 'iterationId'),
            team: any(named: 'team'),
          ),
        ).thenAnswer(
          (_) async => task(
            15551,
            state: 'Done',
            title: 'Write the tests',
            who: ada,
            remaining: 3,
          ),
        );
        when(() => sprints.setRemainingWork(org, project, any(), any()))
            .thenAnswer((i) async => i.positionalArguments[2] as WorkItem);

        await pump(tester);
        await tester.tap(find.text('Write the tests'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(TaskCardSheet),
            matching: find.text('Done'),
          ),
        );
        await tester.pumpAndSettle();

        final call = verify(
          () => sprints.setRemainingWork(org, project, any(), captureAny()),
        )..called(1);
        expect(call.captured.single, 0.0);
      },
    );

    testWidgets('the sheet assigns to me', (tester) async {
      when(() => workItems.patch(org, project, any(), any()))
          .thenAnswer((i) async => i.positionalArguments[2] as WorkItem);
      await pump(tester);
      await tester.tap(find.text('Write the tests'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Assign to me'));
      await tester.pumpAndSettle();

      final call = verify(
        () => workItems.patch(org, project, any(), captureAny()),
      )..called(1);
      expect(call.captured.single, [
        {'op': 'add', 'path': '/fields/System.AssignedTo', 'value': me},
      ]);
    });

    testWidgets('the sheet writes Remaining Work once, on confirm', (
      tester,
    ) async {
      when(() => sprints.setRemainingWork(org, project, any(), any()))
          .thenAnswer((i) async => i.positionalArguments[2] as WorkItem);
      await pump(tester);
      await tester.tap(find.text('Write the tests'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Less remaining work'));
      await tester.pumpAndSettle();
      // Nothing is written until the confirm button is pressed.
      verifyNever(() => sprints.setRemainingWork(org, project, any(), any()));
      await tester.tap(find.textContaining('Set remaining work to'));
      await tester.pumpAndSettle();

      final call = verify(
        () => sprints.setRemainingWork(org, project, any(), captureAny()),
      )..called(1);
      expect(call.captured.single, 2.0);
    });

    testWidgets('offline queues the state op and says so (S9)', (tester) async {
      when(
        () => sprints.move(
          org,
          project,
          any(),
          any(),
          columns: any(named: 'columns'),
          iterationId: any(named: 'iterationId'),
          team: any(named: 'team'),
        ),
      ).thenThrow(const AdoNetworkException('no route to host'));
      when(
        () => queue.enqueuePatch(
          org: any(named: 'org'),
          project: any(named: 'project'),
          item: any(named: 'item'),
          ops: any(named: 'ops'),
          description: any(named: 'description'),
        ),
      ).thenAnswer((_) async {});
      when(() => workItems.applyLocally(org, project, any(), any()))
          .thenAnswer((i) async => i.positionalArguments[2] as WorkItem);

      await pump(tester);
      await tester.tap(find.text('Model the columns'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(TaskCardSheet),
          matching: find.text('In Progress'),
        ),
      );
      await tester.pumpAndSettle();

      final call = verify(
        () => queue.enqueuePatch(
          org: org,
          project: project,
          item: any(named: 'item'),
          ops: captureAny(named: 'ops'),
          description: any(named: 'description'),
        ),
      )..called(1);
      expect(call.captured.single, [
        {'op': 'add', 'path': '/fields/System.State', 'value': 'In Progress'},
      ]);
      expect(find.text('Offline: the move will sync later.'), findsOneWidget);
    });

    testWidgets('a refused move is reverted with the message', (tester) async {
      when(
        () => sprints.move(
          org,
          project,
          any(),
          any(),
          columns: any(named: 'columns'),
          iterationId: any(named: 'iterationId'),
          team: any(named: 'team'),
        ),
      ).thenThrow(const AdoForbiddenException('you may not do that'));

      await pump(tester);
      await tester.tap(find.text('Model the columns'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(TaskCardSheet),
          matching: find.text('Done'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not move 15550: you may not do that'),
        findsOneWidget,
      );
    });
  });

  group('the burndown tab', () {
    testWidgets(
      'a refused Analytics host explains itself, and never signs the user out',
      (tester) async {
        when(
          () => analytics.burndown(
            org,
            project,
            any(),
            start: any(named: 'start'),
            end: any(named: 'end'),
            refresh: any(named: 'refresh'),
          ),
        ).thenThrow(const AnalyticsUnavailable(statusCode: 403));

        await pump(tester, query: '?tab=burndown');

        expect(
          find.textContaining('Analytics refused this sign-in'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the chart and the day-by-day numbers draw from the series', (
      tester,
    ) async {
      when(
        () => analytics.burndown(
          org,
          project,
          any(),
          start: any(named: 'start'),
          end: any(named: 'end'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => [
          for (var i = 0; i < 4; i++)
            BurndownDay(
              date: DateTime.utc(2026, 9, 12 + i),
              remaining: 16 - i,
              done: i,
              points: 5,
            ),
        ],
      );

      await pump(tester, query: '?tab=burndown');

      expect(find.text('Remaining'), findsWidgets);
      expect(find.text('Ideal'), findsOneWidget);
      expect(find.text('4 days of history'), findsOneWidget);
      // The tab's own figures come from the series, not from the page's
      // task rollup: Analytics counts every work item in the iteration
      // (13 tasks against 125 items on CloudCover — iPhone check, P-C).
      expect(find.text('13 items'), findsOneWidget);
      await tester.tap(find.text('Day by day'));
      await tester.pumpAndSettle();
      expect(find.textContaining('13 items left'), findsOneWidget);
    });
  });

  group('the header when the rollup is in hours', () {
    testWidgets(
      'keeps the burndown sentence in items, not "No burndown data"',
      (tester) async {
        when(
          () => sprints.load(
            org,
            project,
            any(),
            team: any(named: 'team'),
            refresh: any(named: 'refresh'),
          ),
        ).thenAnswer(
          (_) async => snapshotWith(
            rows: [
              SprintRow(
                parent: story(15503, 'The sprint view'),
                tasks: [task(15550, title: 'Model the columns', remaining: 2)],
                remaining: 2,
              ),
            ],
          ),
        );
        when(
          () => analytics.burndown(
            org,
            project,
            any(),
            start: any(named: 'start'),
            end: any(named: 'end'),
            refresh: any(named: 'refresh'),
          ),
        ).thenAnswer(
          (_) async => [
            for (var i = 0; i < 4; i++)
              BurndownDay(date: DateTime.utc(2026, 9, 12 + i), remaining: 17),
          ],
        );

        await pump(tester, query: '?tab=backlog');

        expect(find.text('2 h'), findsOneWidget);
        expect(find.text('No burndown data'), findsNothing);
        expect(
          find.textContaining('items/day behind the ideal line'),
          findsOneWidget,
        );
      },
    );
  });

  group('the taskboard carries no header (S13)', () {
    // Kelly, 2026-09-15: the stat tiles, the sparkline and the verdict
    // belong to the Backlog and Burndown tabs. Over a board they only push
    // the cards down, and on a tablet the supporting pane took a third of
    // the width the grid wanted.
    Future<void> burndownLoaded() async {
      when(
        () => analytics.burndown(
          org,
          project,
          any(),
          start: any(named: 'start'),
          end: any(named: 'end'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => [
          for (var i = 0; i < 4; i++)
            BurndownDay(
              date: DateTime.utc(2026, 9, 12 + i),
              remaining: 16 - i,
              points: 5,
            ),
        ],
      );
    }

    testWidgets('on a tablet the grid has the width and height to itself', (
      tester,
    ) async {
      await burndownLoaded();

      await pump(tester, query: '?tab=taskboard');

      expect(find.byType(TaskboardGrid), findsOneWidget);
      expect(find.byType(SprintHeader), findsNothing);
      expect(find.byType(SprintBurndownChart), findsNothing);
      expect(find.text('Scope change'), findsNothing);
    });

    testWidgets('and neither does the phone board', (tester) async {
      await burndownLoaded();

      await pump(
        tester,
        query: '?tab=taskboard',
        size: const Size(1170, 2532),
        devicePixelRatio: 3,
      );

      expect(find.byType(SprintHeader), findsNothing);
      expect(find.byType(SprintBurndownChart), findsNothing);
    });

    testWidgets('the Backlog and Burndown tabs keep it', (tester) async {
      await burndownLoaded();

      await pump(tester, query: '?tab=backlog');
      expect(find.byType(SprintHeader), findsOneWidget);

      await tester.tap(find.text('Burndown'));
      await tester.pumpAndSettle();
      expect(find.byType(SprintHeader), findsOneWidget);
    });
  });

  group('a cleared Remaining Work is not " remaining"', () {
    // Clearing the hours writes a real 0 (the service refuses null), and
    // the column header then read " remaining" with no number on both the
    // phone board and the grid (iPhone check, P-D).
    setUp(() {
      when(
        () => sprints.load(
          org,
          project,
          any(),
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => snapshotWith(
          rows: [
            SprintRow(
              parent: story(15503, 'The sprint view'),
              tasks: [task(15550, title: 'Model the columns', remaining: 0)],
              remaining: 0,
            ),
          ],
        ),
      );
    });

    testWidgets('and the header counts items, not "0 h"', (tester) async {
      await pump(tester, query: '?tab=backlog');

      expect(find.text('0 h'), findsNothing);
      expect(find.text('1 items'), findsOneWidget);
    });

    testWidgets('on the phone board', (tester) async {
      await pump(
        tester,
        query: '?tab=taskboard',
        size: const Size(1170, 2532),
        devicePixelRatio: 3,
      );

      expect(find.text('Model the columns'), findsOneWidget);
      expect(find.textContaining('remaining'), findsNothing);
    });

    testWidgets('and on the tablet grid', (tester) async {
      await pump(tester, query: '?tab=taskboard');

      expect(find.byType(TaskboardGrid), findsOneWidget);
      expect(find.textContaining('remaining'), findsNothing);
    });
  });

  group('the app-bar title', () {
    testWidgets('leads with the sprint, and the phone drops the project', (
      tester,
    ) async {
      // Project-first truncated both halves on an iPhone ("DevOp…" /
      // "Iteration 1 ·…", P-C's 04); the shell has already named the
      // project twice by then. What is left for the title there is 84 dp,
      // so the second line is the dates alone — "DevOps Mobile App ·
      // 8–21 Sep" ellipsises to two letters of the project.
      await pump(tester, size: const Size(1170, 2532), devicePixelRatio: 3);

      final title = tester.widget<Text>(find.text('Iteration 1'));
      expect(title.overflow, TextOverflow.ellipsis);
      expect(find.text('8–21 Sep'), findsOneWidget);
      expect(find.text('$project · 8–21 Sep'), findsNothing);
    });

    testWidgets('a tablet has room for the project as well', (tester) async {
      await pump(tester);

      expect(find.text('Iteration 1'), findsOneWidget);
      expect(find.text('$project · 8–21 Sep'), findsOneWidget);
    });

    testWidgets('an ended sprint says so on the second line (S12)', (
      tester,
    ) async {
      final ended = TeamIteration(
        id: iterationId,
        name: 'Iteration 1',
        path: '$project\\Iteration 1',
        timeFrame: 'current',
        startDate: DateTime.now().subtract(const Duration(days: 20)),
        finishDate: DateTime.now().subtract(const Duration(days: 6)),
      );
      when(
        () => sprints.iterations(
          org,
          project,
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => SprintIterations(all: [ended]));

      await pump(tester, size: const Size(1170, 2532), devicePixelRatio: 3);

      expect(find.text('Iteration 1'), findsOneWidget);
      expect(find.text('Ended 6 days ago'), findsWidgets);
    });
  });

  group('the sprint picker', () {
    testWidgets('picking another sprint changes the route and reloads (S1)', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Choose sprint'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iteration 2'));
      await tester.pumpAndSettle();

      // A future sprint is named in the query; the current one is not.
      expect(location, endsWith('/sprint?iteration=$futureId'));
      verify(
        () => sprints.load(
          org,
          project,
          futureId,
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).called(greaterThanOrEqualTo(1));
    });

    testWidgets('two switches in a row load the sprint that was picked', (
      tester,
    ) async {
      // The picker sets the sprint and then navigates, so
      // `widget.iteration` is still the *previous* one for the rest of
      // that frame. Reading the route there showed the third sprint's
      // (empty) contents under the second one's title (iPhone check, P-C).
      const third = TeamIteration(
        id: 'iter-3',
        name: 'Iteration 3',
        path: '$project\\Iteration 3',
        timeFrame: 'future',
      );
      when(
        () => sprints.iterations(
          org,
          project,
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => SprintIterations(all: [current, next, third]));
      final loaded = <String>[];
      when(
        () => sprints.load(
          org,
          project,
          any(),
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((i) async {
        loaded.add(i.positionalArguments[2] as String);
        return snapshotWith();
      });

      await pump(tester);
      await tester.tap(find.byTooltip('Choose sprint'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iteration 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose sprint'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iteration 2'));
      await tester.pumpAndSettle();

      expect(loaded.last, futureId);
      expect(location, endsWith('/sprint?iteration=$futureId'));
    });

    testWidgets('one team hides the switch row', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Choose sprint'));
      await tester.pumpAndSettle();

      expect(find.text('DevOps Mobile App Team'), findsOneWidget);
      expect(find.text('Switch team'), findsNothing);
    });

    testWidgets('picking another team reloads the sprint with its id', (
      tester,
    ) async {
      when(() => sprints.teams(org, project, refresh: any(named: 'refresh')))
          .thenAnswer(
            (_) async => const [
              SprintTeamRef(id: team, name: 'DevOps Mobile App Team'),
              SprintTeamRef(id: 'team-2', name: 'Relay Team'),
            ],
          );
      final loadedFor = <String?>[];
      when(
        () => sprints.load(
          org,
          project,
          any(),
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((i) async {
        loadedFor.add(i.namedArguments[#team] as String?);
        return snapshotWith();
      });

      await pump(tester, query: '?iteration=$futureId');
      await tester.tap(find.byTooltip('Choose sprint'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch team'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relay Team'));
      await tester.pumpAndSettle();

      // Everything the old team resolved is asked for again with the new
      // team id — iterations, the snapshot — and the sprint in the route
      // goes, because it names an iteration this team does not have.
      expect(loadedFor.first, team);
      expect(loadedFor.last, 'team-2');
      verify(
        () => sprints.iterations(org, project, team: 'team-2', refresh: true),
      ).called(greaterThanOrEqualTo(1));
      expect(location, endsWith('/sprint'));
      expect(find.text('Relay Team'), findsNothing);
    });

    testWidgets('a deep link to one sprint opens that sprint', (tester) async {
      await pump(tester, query: '?iteration=$futureId');

      verify(
        () => sprints.load(
          org,
          project,
          futureId,
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).called(greaterThanOrEqualTo(1));
    });

    testWidgets('an ended sprint still reads as current, and says so (S12)', (
      tester,
    ) async {
      final ended = TeamIteration(
        id: iterationId,
        name: 'Iteration 106',
        path: '$project\\Iteration 106',
        timeFrame: 'current',
        startDate: DateTime.utc(2026, 8, 25),
        finishDate: DateTime.utc(2026, 9, 6),
      );
      when(
        () => sprints.iterations(
          org,
          project,
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer((_) async => SprintIterations(all: [ended]));

      await pump(tester);

      expect(find.textContaining('Ended '), findsWidgets);
    });
  });

  group('the backlog tab', () {
    testWidgets('Move to another sprint patches the iteration path (S3)', (
      tester,
    ) async {
      when(() => sprints.setIteration(org, project, any(), any()))
          .thenAnswer((i) async => i.positionalArguments[2] as WorkItem);

      await pump(tester, query: '?tab=backlog');
      await tester.tap(find.byTooltip('More for 15503'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to another sprint'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Iteration 2'));
      await tester.pumpAndSettle();

      final call = verify(
        () => sprints.setIteration(org, project, captureAny(), captureAny()),
      )..called(1);
      expect((call.captured[0] as WorkItem).id, 15503);
      expect(call.captured[1], '$project\\Iteration 2');
    });

    testWidgets('a row opens its work item', (tester) async {
      await pump(tester, query: '?tab=backlog');
      await tester.tap(find.text('The sprint view'));
      await tester.pumpAndSettle();

      expect(find.text('work item page'), findsOneWidget);
      expect(visited.single, endsWith('/work-items/15503'));
    });

    testWidgets('the unparented tasks get a row of their own, first', (
      tester,
    ) async {
      when(
        () => sprints.load(
          org,
          project,
          any(),
          team: any(named: 'team'),
          refresh: any(named: 'refresh'),
        ),
      ).thenAnswer(
        (_) async => snapshotWith(
          unparented: SprintRow(tasks: [task(15599, title: 'An orphan task')]),
        ),
      );

      await pump(tester, query: '?tab=backlog');

      expect(find.text('Unparented tasks'), findsOneWidget);
      expect(find.text('An orphan task'), findsOneWidget);
    });
  });
}
