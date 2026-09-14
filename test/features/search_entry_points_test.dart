import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/models/pipeline.dart';
import 'package:boardhop/data/models/git_repository.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/repo_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/features/projects/project_home_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/work_items/work_items_page.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _AuthService extends Mock implements AuthService {}

class _Projects extends Mock implements ProjectRepository {}

class _Repos extends Mock implements RepoRepository {}

class _PullRequests extends Mock implements PullRequestRepository {}

class _WorkItems extends Mock implements WorkItemRepository {}

class _Pipelines extends Mock implements PipelineRepository {}

WorkItem item(
  int id, {
  required String title,
  String type = 'Bug',
  String state = 'Active',
  String assignedTo = 'Kelly Kamm',
}) => WorkItem(
  id: id,
  rev: 1,
  fields: {
    'System.Title': title,
    'System.WorkItemType': type,
    'System.State': state,
    'System.AssignedTo': {'displayName': assignedTo, 'id': 'u-$assignedTo'},
    'System.ChangedDate': '2026-09-13T10:00:00Z',
  },
);

void main() {
  setUpAll(() => registerFallbackValue(PrListFilter.all));

  group('decision D10: the Work tab filter', () {
    test('narrows by id, title, type, state and assignee', () {
      final items = [
        item(15503, title: 'Board drag and drop'),
        item(15504, title: 'Pipelines: retry a stage', type: 'Task'),
        item(
          15505,
          title: 'Tidy the theme',
          state: 'New',
          assignedTo: 'Ada Lovelace',
        ),
      ];

      expect(filterWorkItems(items, '').length, 3);
      expect(filterWorkItems(items, '   ').length, 3);
      expect(filterWorkItems(items, 'board').single.id, 15503);
      expect(filterWorkItems(items, '15504').single.id, 15504);
      expect(filterWorkItems(items, 'task').single.id, 15504);
      expect(filterWorkItems(items, 'new').single.id, 15505);
      expect(filterWorkItems(items, 'ada').single.id, 15505);
      expect(filterWorkItems(items, 'BOARD').single.id, 15503);
      expect(filterWorkItems(items, 'nothing here'), isEmpty);
    });

    test('every word has to match something', () {
      final items = [
        item(1, title: 'Board drag and drop'),
        item(2, title: 'Board polish', type: 'Task'),
      ];
      expect(filterWorkItems(items, 'board bug').single.id, 1);
      expect(filterWorkItems(items, 'board task').single.id, 2);
      expect(filterWorkItems(items, 'board pipeline'), isEmpty);
    });

    testWidgets('the field narrows the loaded list without a call', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final workItems = _WorkItems();
      final auth = AuthBloc(_AuthService());
      addTearDown(auth.close);
      when(() => workItems.types(any(), any())).thenAnswer((_) async => []);
      when(() => workItems.refreshAssignedToMe(any(), any()))
          .thenAnswer((_) async => []);
      when(() => workItems.watchList(any(), any(), any())).thenAnswer(
        (_) => Stream.value([
          item(15503, title: 'Board drag and drop'),
          item(15504, title: 'Pipelines: retry a stage', type: 'Task'),
        ]),
      );

      final router = GoRouter(
        initialLocation: '/a/u1/orgs/o/projects/Scratch/work-items',
        routes: [
          GoRoute(
            path: '/a/:account/orgs/:org/projects/:project/work-items',
            builder: (_, state) => WorkItemsPage(
              org: state.pathParameters['org']!,
              project: state.pathParameters['project']!,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<WorkItemRepository>.value(value: workItems),
          ],
          child: BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp.router(
              theme: BoardhopTheme.light(),
              routerConfig: router,
              builder: (context, child) =>
                  AccountScope(accountId: 'u1', child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Board drag and drop'), findsOneWidget);
      expect(find.text('Pipelines: retry a stage'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'board');
      await tester.pumpAndSettle();

      expect(find.text('Board drag and drop'), findsOneWidget);
      expect(find.text('Pipelines: retry a stage'), findsNothing);
      // Nothing was fetched: the list on the device is all it looks at.
      verifyNever(() => workItems.refreshQuery(any(), any(), any()));

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.textContaining('matches "zzz"'), findsOneWidget);
    });
  });

  group('decision D3: the entry point', () {
    testWidgets('the Home app bar opens search', (tester) async {
      tester.view.physicalSize = const Size(402, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final projects = _Projects();
      final repos = _Repos();
      final prs = _PullRequests();
      final workItems = _WorkItems();
      final pipelines = _Pipelines();
      final auth = AuthBloc(_AuthService());
      addTearDown(auth.close);

      when(() => projects.watch(any()))
          .thenAnswer((_) => Stream.value(const <Project>[]));
      when(() => repos.cachedList(any(), any())).thenAnswer((_) async => null);
      when(() => repos.list(any(), any()))
          .thenAnswer((_) async => const <GitRepository>[]);
      when(
        () => prs.cachedList(
          any(),
          project: any(named: 'project'),
          filter: any(named: 'filter'),
        ),
      ).thenAnswer((_) async => null);
      when(
        () => prs.list(
          any(),
          project: any(named: 'project'),
          filter: any(named: 'filter'),
        ),
      ).thenAnswer((_) async => const <PullRequest>[]);
      when(() => workItems.watchList(any(), any(), any()))
          .thenAnswer((_) => Stream.value(const <WorkItem>[]));
      when(() => workItems.refreshAssignedToMe(any(), any()))
          .thenAnswer((_) async => const <WorkItem>[]);
      when(() => pipelines.cachedRuns(any(), any()))
          .thenAnswer((_) async => null);
      when(
        () => pipelines.runs(
          any(),
          any(),
          top: any(named: 'top'),
          cache: any(named: 'cache'),
        ),
      ).thenAnswer((_) async => const <BuildRun>[]);

      final router = GoRouter(
        initialLocation: '${Routes.project('u1', 'o', 'Scratch')}/home',
        routes: [
          GoRoute(
            path: '/a/:account/orgs/:org/projects/:project/home',
            builder: (_, state) => ProjectHomePage(
              org: state.pathParameters['org']!,
              project: state.pathParameters['project']!,
            ),
          ),
          GoRoute(
            path: '/a/:account/orgs/:org/projects/:project/search',
            builder: (_, state) => Scaffold(
              appBar: AppBar(
                title: Text('search ${state.uri.queryParameters['kind']}'),
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ProjectRepository>.value(value: projects),
            RepositoryProvider<RepoRepository>.value(value: repos),
            RepositoryProvider<PullRequestRepository>.value(value: prs),
            RepositoryProvider<WorkItemRepository>.value(value: workItems),
            RepositoryProvider<PipelineRepository>.value(value: pipelines),
          ],
          child: BlocProvider<AuthBloc>.value(
            value: auth,
            child: MaterialApp.router(
              theme: BoardhopTheme.light(),
              routerConfig: router,
              builder: (context, child) =>
                  AccountScope(accountId: 'u1', child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(find.text('search null'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      // The old "Search code" row now opens search on its code kind.
      await tester.tap(find.text('Search code'));
      await tester.pumpAndSettle();
      expect(find.text('search code'), findsOneWidget);
    });
  });
}
