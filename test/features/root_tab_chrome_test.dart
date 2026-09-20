import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/data/models/git_repository.dart';
import 'package:boardhop/data/models/pipeline.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/repo_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/features/activity/activity_bell.dart';
import 'package:boardhop/features/pipelines/pipelines_page.dart';
import 'package:boardhop/features/projects/project_home_page.dart';
import 'package:boardhop/features/projects/widgets/project_picker_button.dart';
import 'package:boardhop/features/repos/repos_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/work_items/work_items_page.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures/duo_display.dart';
import 'root_tab_stubs.dart';

class _AuthService extends Mock implements AuthService {}

class _Repos extends Mock implements RepoRepository {}

class _PullRequests extends Mock implements PullRequestRepository {}

class _WorkItems extends Mock implements WorkItemRepository {}

class _Pipelines extends Mock implements PipelineRepository {}

const _org = 'contoso';
const _project = 'Scratch';

/// The four root tabs lost their back arrow to the project picker
/// (research/21 L4) and gained the Activity bell (L5).
void main() {
  setUpAll(() {
    registerFallbackValue(PrListFilter.all);
  });

  RepoRepository stubRepos() {
    final repos = _Repos();
    when(() => repos.cachedList(any(), any())).thenAnswer((_) async => null);
    when(() => repos.cachedLanguages(any(), any()))
        .thenAnswer((_) async => null);
    when(() => repos.cachedFavorites(any(), any()))
        .thenAnswer((_) async => null);
    when(() => repos.recents(any(), any())).thenAnswer((_) async => const []);
    when(() => repos.list(any(), any()))
        .thenAnswer((_) async => const <GitRepository>[]);
    when(() => repos.languages(any(), any()))
        .thenAnswer((_) async => const <String, List<RepoLanguage>>{});
    when(() => repos.favorites(any(), any()))
        .thenAnswer((_) async => const <String, String>{});
    return repos;
  }

  PullRequestRepository stubPrs() {
    final prs = _PullRequests();
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
    return prs;
  }

  WorkItemRepository stubWorkItems() {
    final workItems = _WorkItems();
    when(() => workItems.watchList(any(), any(), any()))
        .thenAnswer((_) => Stream.value(const <WorkItem>[]));
    when(() => workItems.refreshAssignedToMe(any(), any()))
        .thenAnswer((_) async => const <WorkItem>[]);
    when(() => workItems.types(any(), any())).thenAnswer((_) async => const []);
    return workItems;
  }

  PipelineRepository stubPipelines() {
    final pipelines = _Pipelines();
    when(() => pipelines.cachedRuns(any(), any()))
        .thenAnswer((_) async => null);
    when(() => pipelines.cachedDefinitions(any(), any()))
        .thenAnswer((_) async => null);
    when(() => pipelines.definitions(any(), any()))
        .thenAnswer((_) async => const <PipelineDefinition>[]);
    when(
      () => pipelines.runs(
        any(),
        any(),
        definitionId: any(named: 'definitionId'),
        top: any(named: 'top'),
        cache: any(named: 'cache'),
      ),
    ).thenAnswer((_) async => const <BuildRun>[]);
    when(() => pipelines.approvals(any(), any()))
        .thenAnswer((_) async => const <PipelineApproval>[]);
    return pipelines;
  }

  Future<void> pumpTab(
    WidgetTester tester, {
    required String path,
    required Widget Function() page,
    required List<RepositoryProvider<Object>> repositories,
    Size size = const Size(402, 1600),
    DisplayRegions? regions,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = GoRouter(
      initialLocation: path,
      routes: [GoRoute(path: path, builder: (_, _) => page())],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      Duo.scope(
        window: size,
        regions: regions,
        child: MultiRepositoryProvider(
          providers: [
            ...rootChromeProviders(
              projects: stubProjects([const Project(id: 'p1', name: _project)]),
            ),
            ...repositories,
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
      ),
    );
    await tester.pumpAndSettle();
    // creaseInBox reads the transform the last layout left, so a folded
    // display needs one more frame before the panes move onto it.
    await tester.pump();
  }

  void expectChrome() {
    expect(find.byType(ProjectPickerButton), findsOneWidget);
    expect(find.byTooltip('Switch project'), findsOneWidget);
    expect(find.byType(ActivityBell), findsOneWidget);
    // The back arrow to the project list is gone from the root tabs.
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byTooltip('Projects'), findsNothing);
  }

  testWidgets('Home carries the picker and the bell, and no back arrow', (
    tester,
  ) async {
    await pumpTab(
      tester,
      path: '${Routes.project('u1', _org, _project)}/home',
      page: () => const ProjectHomePage(org: _org, project: _project),
      repositories: [
        RepositoryProvider<RepoRepository>.value(value: stubRepos()),
        RepositoryProvider<PullRequestRepository>.value(value: stubPrs()),
        RepositoryProvider<WorkItemRepository>.value(value: stubWorkItems()),
        RepositoryProvider<PipelineRepository>.value(value: stubPipelines()),
      ],
    );

    expectChrome();
    // The search action and the view pill are untouched.
    expect(find.byTooltip('Search'), findsOneWidget);
  });

  testWidgets('Work carries the picker and the bell, and no back arrow', (
    tester,
  ) async {
    await pumpTab(
      tester,
      path: Routes.workItems('u1', _org, _project),
      page: () => const WorkItemsPage(org: _org, project: _project),
      repositories: [
        RepositoryProvider<WorkItemRepository>.value(value: stubWorkItems()),
      ],
    );

    expectChrome();
  });

  testWidgets('Repos carries the picker and the bell, and no back arrow', (
    tester,
  ) async {
    await pumpTab(
      tester,
      path: '${Routes.project('u1', _org, _project)}/repos',
      page: () => const ReposPage(org: _org, project: _project),
      repositories: [
        RepositoryProvider<RepoRepository>.value(value: stubRepos()),
      ],
    );

    expectChrome();
    expect(find.byTooltip('Search code'), findsOneWidget);
  });

  testWidgets('Pipelines carries the picker and the bell, and no back arrow', (
    tester,
  ) async {
    await pumpTab(
      tester,
      path: Routes.pipelines('u1', _org, _project),
      page: () => const PipelinesPage(org: _org, project: _project),
      repositories: [
        RepositoryProvider<PipelineRepository>.value(value: stubPipelines()),
      ],
    );

    expectChrome();
  });

  group('the project-name title (Kelly, 2026-09-16)', () {
    Finder titleName() =>
        find.descendant(of: find.byType(AppBar), matching: find.text(_project));

    testWidgets('is dropped on a phone in portrait', (tester) async {
      await pumpTab(
        tester,
        path: Routes.workItems('u1', _org, _project),
        page: () => const WorkItemsPage(org: _org, project: _project),
        repositories: [
          RepositoryProvider<WorkItemRepository>.value(value: stubWorkItems()),
        ],
      );
      expect(titleName(), findsNothing);
      // The tile still names the project.
      expect(find.byType(ProjectPickerButton), findsOneWidget);
    });

    testWidgets('stays on a phone in landscape', (tester) async {
      await pumpTab(
        tester,
        path: Routes.workItems('u1', _org, _project),
        page: () => const WorkItemsPage(org: _org, project: _project),
        repositories: [
          RepositoryProvider<WorkItemRepository>.value(value: stubWorkItems()),
        ],
        size: const Size(874, 402),
      );
      expect(titleName(), findsOneWidget);
    });

    testWidgets('stays on a tablet', (tester) async {
      await pumpTab(
        tester,
        path: '${Routes.project('u1', _org, _project)}/home',
        page: () => const ProjectHomePage(org: _org, project: _project),
        repositories: [
          RepositoryProvider<RepoRepository>.value(value: stubRepos()),
          RepositoryProvider<PullRequestRepository>.value(value: stubPrs()),
          RepositoryProvider<WorkItemRepository>.value(value: stubWorkItems()),
          RepositoryProvider<PipelineRepository>.value(value: stubPipelines()),
        ],
        size: const Size(1024, 1366),
      );
      expect(titleName(), findsOneWidget);
    });
  });

  group('the master/detail pane on a fold (research/23 D3)', () {
    Future<void> pumpWork(WidgetTester tester, {DisplayRegions? regions}) =>
        pumpTab(
          tester,
          path: Routes.workItems('u1', _org, _project),
          page: () => const WorkItemsPage(org: _org, project: _project),
          repositories: [
            RepositoryProvider<WorkItemRepository>.value(
              value: stubWorkItems(),
            ),
          ],
          size: Duo.wide,
          regions: regions,
        );

    testWidgets('the list pane ends on the crease and the divider fills '
        'the band', (tester) async {
      await pumpWork(tester, regions: Duo.folded(Duo.wideBand));
      final divider = tester.widget<VerticalDivider>(
        find.byType(VerticalDivider),
      );
      expect(divider.width, Duo.wideBand.width);
      expect(
        tester.getTopLeft(find.byType(VerticalDivider)).dx,
        closeTo(Duo.wideBand.left, 0.5),
      );
    });

    testWidgets('flat, the pane keeps its fraction', (tester) async {
      await pumpWork(tester, regions: Duo.flat(Duo.wideBand));
      final divider = tester.widget<VerticalDivider>(
        find.byType(VerticalDivider),
      );
      expect(divider.width, 1);
      // 42 % of the window, clamped to 480.
      expect(
        tester.getTopLeft(find.byType(VerticalDivider)).dx,
        closeTo(399.42, 1),
      );
    });
  });
}
