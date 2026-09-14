import 'package:boardhop/core/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The project tab shell is a `StatefulShellRoute`, and go_router keys a
/// shell's page by the route's own identity — every match of that route
/// yields the same `ValueKey`. So pushing a location that lives *inside* the
/// shell from a page that is itself *over* the shell (the pull request
/// detail page and its file diff, both siblings of the shell in the same
/// navigator) asks that navigator to hold two pages with one key, which is
/// `'!keyReservation.contains(key)'`.
///
/// `Routes.workItemStandalone` is the way out: the same page on a route
/// outside the shell, so the push adds one ordinary page. These tests use
/// stub pages on the real route *shape* — `test/core/router_test.dart` pins
/// the real table's paths, parameters and the absence of the shell, and
/// `pr_anchor_test.dart` pins the pull request page pushing this location.
///
/// The failing case is deliberately not a test of its own: once the
/// navigator asserts, the element tree is corrupt and every later pump
/// throws again, so the reproduction lives in the phase report instead.
Widget _page(String label) => Scaffold(
  appBar: AppBar(title: Text(label)),
  body: const SizedBox.shrink(),
);

GoRouter _router() => GoRouter(
  initialLocation: '${Routes.project('u1', 'o', 'P')}/work-items',
  routes: [
    ShellRoute(
      builder: (context, state, child) => child,
      routes: [
        GoRoute(
          path: '/a/:account/orgs/:org/projects',
          builder: (_, _) => _page('projects'),
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, shell) => shell,
              branches: [
                StatefulShellBranch(
                  initialLocation: '/a/-/orgs/-/projects/-/work-items',
                  routes: [
                    GoRoute(
                      path: ':project/work-items',
                      builder: (_, _) => _page('work items'),
                      routes: [
                        GoRoute(
                          path: ':id',
                          builder: (_, s) =>
                              _page('in shell ${s.pathParameters['id']}'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            GoRoute(
              path: ':project/work-item/:id',
              builder: (_, s) => _page('standalone ${s.pathParameters['id']}'),
            ),
          ],
        ),
        GoRoute(
          path: '/a/:account/orgs/:org/pull-requests',
          builder: (_, _) => _page('pull requests'),
          routes: [
            GoRoute(
              path: ':id',
              builder: (_, s) => _page('pr ${s.pathParameters['id']}'),
            ),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  /// Reaches the pull request detail page the way the app does: the project
  /// shell is open, and the pull request is pushed over it.
  Future<GoRouter> overTheShell(WidgetTester tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('work items'), findsOneWidget);
    router.push(Routes.pullRequest('u1', 'o', '8334'));
    await tester.pumpAndSettle();
    expect(find.text('pr 8334'), findsOneWidget);
    return router;
  }

  testWidgets('the standalone location opens over the shell and Back returns '
      'to the pull request', (tester) async {
    final router = await overTheShell(tester);

    router.push(Routes.workItemStandalone('u1', 'o', 'P', '15545'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('standalone 15545'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('pr 8334'), findsOneWidget);
  });

  testWidgets('inside the shell the branch route is still the one used', (
    tester,
  ) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.push(Routes.workItem('u1', 'o', 'P', '15545'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('in shell 15545'), findsOneWidget);

    // And a second work item pushed from the first (a `#123` in a comment)
    // still works, which is why that path was never the broken one.
    router.push(Routes.workItem('u1', 'o', 'P', '15546'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('in shell 15546'), findsOneWidget);
  });

  test('the standalone path differs from the branch path by one segment', () {
    expect(
      Routes.workItemStandalone('u1', 'o', 'DevOps Mobile App', '15545'),
      '/a/u1/orgs/o/projects/DevOps%20Mobile%20App/work-item/15545',
    );
    expect(
      Routes.workItemStandalone('u1', 'o', 'P', '15545', comment: '6068143'),
      '/a/u1/orgs/o/projects/P/work-item/15545?comment=6068143',
    );
  });
}
