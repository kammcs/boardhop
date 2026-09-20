import 'package:boardhop/core/display_environment.dart';
import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/repositories/org_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:boardhop/data/write_queue.dart';
import 'package:boardhop/features/launch/launch_hooks.dart';
import 'package:boardhop/features/launch/launch_resolver.dart';
import 'package:boardhop/features/projects/project_shell.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:boardhop/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Queue extends Mock implements WriteQueue {}

class _Orgs extends Fake implements OrgRepository {}

/// The shell reaches the pending notice through the resolver, which is what
/// the app root provides (a `RepositoryProvider` will not hold a
/// `Listenable`).
LaunchResolver _resolver(LaunchNotice notice) => LaunchResolver(
  repositoriesFor: (_) => (orgs: _Orgs(), projects: _Projects(const [])),
  notice: notice,
);

class _Projects extends Fake implements ProjectRepository {
  _Projects(this.names);

  final List<String> names;

  @override
  Stream<List<Project>> watch(String org) => Stream.value([
    for (final name in names) Project(id: 'id-$name', name: name),
  ]);
}

void main() {
  late _Queue queue;

  setUp(() {
    queue = _Queue();
    when(queue.watch).thenAnswer((_) => Stream.value(const <PendingWrite>[]));
    when(queue.drain).thenAnswer(
      (_) async =>
          const DrainResult(synced: 0, conflicts: 0, stoppedOffline: false),
    );
  });

  tearDown(() => LaunchHooks.onChooseAnotherProject = null);

  const base = '/a/u1/orgs/o/projects/p';

  Future<void> pump(
    WidgetTester tester, {
    LaunchNotice? notice,
    _Projects? projects,
  }) async {
    final config = GoRouter(
      initialLocation: '$base/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => ProjectShell(
            shell: shell,
            org: 'o',
            project: 'p',
            location: state.uri.path,
          ),
          branches: [
            for (final tail in ['home', 'work-items', 'repos', 'pipelines'])
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '$base/$tail',
                    builder: (_, _) =>
                        Scaffold(body: Center(child: Text('$tail page'))),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
    addTearDown(config.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WriteQueue>.value(value: queue),
          if (notice != null)
            RepositoryProvider<LaunchResolver>.value(value: _resolver(notice)),
          if (projects != null)
            RepositoryProvider<ProjectRepository>.value(value: projects),
        ],
        child: MaterialApp.router(
          theme: BoardhopTheme.light(),
          routerConfig: config,
          builder: (context, child) => ThemeScope(
            controller: ThemeController.inMemory(),
            // The shell reads the display's shape from here now; a test
            // has no Runner to ask (research/23 §4.2).
            child: DisplayScope.override(
              child: AccountScope(accountId: 'u1', child: child!),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // research/21 L7: the launch settled for another project, and says so on
  // the shell it lands in.
  testWidgets('a launch fallback shows its snackbar once', (tester) async {
    final notice = LaunchNotice()
      ..value = const LaunchFallback.accountGone('Atlas');
    addTearDown(notice.dispose);

    await pump(tester, notice: notice);
    expect(
      find.text("Your last project isn't available any more; opened Atlas."),
      findsOneWidget,
    );
    // Taken, not read: a rebuild does not say it again.
    expect(notice.value, isNull);
  });

  testWidgets('no fallback, no snackbar', (tester) async {
    final notice = LaunchNotice();
    addTearDown(notice.dispose);
    await pump(tester, notice: notice);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the shell works without the launch providers', (tester) async {
    await pump(tester);
    expect(find.text('home page'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  // The remembered project is opened without verifying it (L8); a project
  // the organization's cached list does not name is gone.
  testWidgets('a project that is gone offers the picker', (tester) async {
    var opened = 0;
    LaunchHooks.onChooseAnotherProject = (_) => opened++;

    await pump(tester, projects: _Projects(const ['Atlas', 'Beacon']));
    expect(find.text('"p" is not available any more.'), findsOneWidget);

    await tester.tap(find.text('Choose another project'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('a project that is there says nothing', (tester) async {
    await pump(tester, projects: _Projects(const ['Atlas', 'p']));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a cold, empty project cache is not an answer', (tester) async {
    await pump(tester, projects: _Projects(const []));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('without the picker registered the line still shows', (
    tester,
  ) async {
    await pump(tester, projects: _Projects(const ['Atlas']));
    expect(find.text('"p" is not available any more.'), findsOneWidget);
    expect(find.text('Choose another project'), findsNothing);
  });
}
