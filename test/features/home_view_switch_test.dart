import 'package:boardhop/features/projects/widgets/home_view_switch.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The Home tab's pill (research/19 D5, D8, D13; research/20 §4.2): three
/// segments, icons only on a phone, and it navigates rather than calling
/// back.
void main() {
  const org = 'o';
  const project = 'p';

  late String location;

  Future<void> pump(
    WidgetTester tester, {
    HomeView current = HomeView.summary,
    Size size = const Size(1170, 2532),
    double devicePixelRatio = 3,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    location = '';
    final router = GoRouter(
      initialLocation: '/a/u1/orgs/$org/projects/$project/home',
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/home',
          builder: (context, state) {
            location = state.uri.toString();
            return AccountScope(
              accountId: 'u1',
              child: Scaffold(
                appBar: AppBar(
                  actions: [
                    HomeViewSwitch(
                      org: org,
                      project: project,
                      current: current,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/dashboards',
          builder: (context, state) {
            location = state.uri.toString();
            return const Scaffold(body: Text('dashboards page'));
          },
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/projects/:project/wiki',
          builder: (context, state) {
            location = state.uri.toString();
            return const Scaffold(body: Text('wiki page'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: BoardhopTheme.light(), routerConfig: router),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('all three segments are there, icons only on a phone', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byIcon(Icons.summarize_outlined), findsOneWidget);
    expect(find.byIcon(Icons.dashboard_outlined), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.text('Summary'), findsNothing);
    expect(find.text('Dashboards'), findsNothing);
    expect(find.text('Wiki'), findsNothing);
  });

  testWidgets('a tablet gets the labels too', (tester) async {
    await pump(tester, size: const Size(2048, 1536), devicePixelRatio: 2);

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Dashboards'), findsOneWidget);
    expect(find.text('Wiki'), findsOneWidget);
  });

  testWidgets('picking Dashboards goes to the plain dashboards route', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.dashboard_outlined));
    await tester.pumpAndSettle();

    // No `?dashboard=`: the plain route is the plain view, and the page
    // opens the one last remembered (D6).
    expect(location, '/a/u1/orgs/$org/projects/$project/dashboards');
    expect(find.text('dashboards page'), findsOneWidget);
  });

  testWidgets('picking the segment already selected navigates nowhere', (
    tester,
  ) async {
    await pump(tester, current: HomeView.summary);

    await tester.tap(find.byIcon(Icons.summarize_outlined));
    await tester.pumpAndSettle();

    expect(location, '/a/u1/orgs/$org/projects/$project/home');
  });

  testWidgets('from Dashboards the other segment goes back to Summary', (
    tester,
  ) async {
    await pump(tester, current: HomeView.dashboards);

    await tester.tap(find.byIcon(Icons.summarize_outlined));
    await tester.pumpAndSettle();

    expect(location, '/a/u1/orgs/$org/projects/$project/home');
  });

  testWidgets('picking Wiki goes to the plain wiki route', (tester) async {
    await pump(tester);

    await tester.tap(find.byIcon(Icons.menu_book_outlined));
    await tester.pumpAndSettle();

    // No `?wiki=` and no `?path=`: the plain route is the plain view, and
    // the tree page opens the wiki last remembered (K1).
    expect(location, '/a/u1/orgs/$org/projects/$project/wiki');
    expect(find.text('wiki page'), findsOneWidget);
  });

  testWidgets('from Wiki the other segments still navigate', (tester) async {
    await pump(tester, current: HomeView.wiki);

    await tester.tap(find.byIcon(Icons.dashboard_outlined));
    await tester.pumpAndSettle();

    expect(location, '/a/u1/orgs/$org/projects/$project/dashboards');
  });
}
