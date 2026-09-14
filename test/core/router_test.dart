import 'package:boardhop/app.dart';
import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/routes.dart';
import 'package:boardhop/features/pipelines/pipeline_run_page.dart';
import 'package:boardhop/features/pipelines/pipelines_page.dart';
import 'package:boardhop/features/pull_requests/pull_request_detail_page.dart';
import 'package:boardhop/features/work_items/work_item_detail_page.dart';
import 'package:boardhop/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _AuthService extends Mock implements AuthService {}

class _Deps extends Mock implements AppDependencies {}

void main() {
  // go_router validates the route table with asserts, which profile and
  // release builds skip; a debug build (or this test) is where a bad
  // table shows up, e.g. a tab shell branch defaulting to a parameterized
  // route.
  test('route table passes go_router debug checks', () {
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = buildRouter(auth, _Deps());
    addTearDown(router.dispose);

    final project = Routes.project('u1', 'puremedia', 'DevOps Mobile App');
    for (final tail in [
      'home',
      'work-items/15503',
      'boards',
      'repos',
      'pipelines/runs/1/logs/2',
    ]) {
      final match = router.configuration.findMatch(Uri.parse('$project/$tail'));
      expect(match.isError, isFalse, reason: tail);
      expect(match.pathParameters['org'], 'puremedia', reason: tail);
    }
    final item = router.configuration.findMatch(
      Uri.parse('$project/work-items/15503'),
    );
    expect(item.pathParameters['id'], '15503');
  });

  // The standalone work item route (`Routes.workItemStandalone`) is the same
  // page outside the project tab shell, for pushes that start from a page
  // which is itself over the shell — see test/core/work_item_push_test.dart.
  // What makes it work is the absence of the shell from its match, so that
  // is what this pins.
  test('the standalone work item route is matched outside the tab shell', () {
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = buildRouter(auth, _Deps());
    addTearDown(router.dispose);

    bool hasTabShell(Iterable<RouteMatchBase> matches) => matches.any(
      (m) =>
          m is ShellRouteMatch &&
          (m.route is StatefulShellRoute || hasTabShell(m.matches)),
    );

    final project = Routes.project('u1', 'puremedia', 'DevOps Mobile App');
    final inShell = router.configuration.findMatch(
      Uri.parse('$project/work-items/15545'),
    );
    expect(inShell.isError, isFalse);
    expect(hasTabShell(inShell.matches), isTrue);

    final standalone = router.configuration.findMatch(
      Uri.parse(
        Routes.workItemStandalone(
          'u1',
          'puremedia',
          'DevOps Mobile App',
          '15545',
        ),
      ),
    );
    expect(standalone.isError, isFalse);
    expect(hasTabShell(standalone.matches), isFalse);
    expect(standalone.pathParameters['id'], '15545');
    expect(standalone.pathParameters['project'], 'DevOps Mobile App');
  });

  // research/14 §4.2: a pushed pointer's anchor rides along as a query
  // string. The pages read it from R2.5 on; until then the router has to
  // tolerate a parameter no page asks for, or every anchored tap is an error
  // page.
  test('the pushed anchors resolve to the same pages', () {
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = buildRouter(auth, _Deps());
    addTearDown(router.dispose);

    final org = Routes.org('u1', 'contoso');
    final project = Routes.project('u1', 'contoso', 'DevOps Mobile App');
    final anchored = {
      '$project/work-items/15545?comment=1998234': '$project/work-items/15545',
      '$org/pull-requests/8336?thread=4821': '$org/pull-requests/8336',
      '$org/pull-requests/8336?tab=files': '$org/pull-requests/8336',
      '$project/pipelines?tab=approvals&approval=18': '$project/pipelines',
    };
    anchored.forEach((withAnchor, plain) {
      final match = router.configuration.findMatch(Uri.parse(withAnchor));
      expect(match.isError, isFalse, reason: withAnchor);
      final bare = router.configuration.findMatch(Uri.parse(plain));
      expect(
        match.matches.last.route,
        same(bare.matches.last.route),
        reason: withAnchor,
      );
    });

    final approval = router.configuration.findMatch(
      Uri.parse('$project/pipelines?tab=approvals&approval=18'),
    );
    expect(approval.uri.queryParameters['tab'], 'approvals');
    expect(approval.uri.queryParameters['approval'], '18');
  });

  // research/14 §4.2, R2.5: the anchors have to reach the pages, including
  // on a cold start, where the deep link opens a branch of the project tab
  // shell for the first time. Building each match's page is what a cold
  // start does; the parameters the page is handed are what the anchor is.
  testWidgets('the anchored routes hand their parameters to the pages', (
    tester,
  ) async {
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = buildRouter(auth, _Deps());
    addTearDown(router.dispose);

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    Widget page(String location) {
      final match = router.configuration.findMatch(Uri.parse(location));
      expect(match.isError, isFalse, reason: location);
      final leaf = match.last;
      final state = leaf.buildState(
        router.configuration,
        match,
        metadata: const {},
      );
      return leaf.route.builder!(context, state);
    }

    final org = Routes.org('u1', 'contoso');
    final project = Routes.project('u1', 'contoso', 'DevOps Mobile App');

    final comment =
        page('$project/work-items/15545?comment=1998234') as WorkItemDetailPage;
    expect(comment.id, 15545);
    expect(comment.initialCommentId, 1998234);
    // Nothing changes for a route without the anchor.
    expect(
      (page(
        '$project/work-items/15545',
      ) as WorkItemDetailPage).initialCommentId,
      isNull,
    );

    // The standalone route hands over the same three, `?comment=` and all.
    final standalone = page(
      Routes.workItemStandalone(
        'u1',
        'contoso',
        'DevOps Mobile App',
        '15545',
        comment: '6068143',
      ),
    ) as WorkItemDetailPage;
    expect(standalone.id, 15545);
    expect(standalone.project, 'DevOps Mobile App');
    expect(standalone.initialCommentId, 6068143);

    final thread =
        page('$org/pull-requests/8334?thread=42511') as PullRequestDetailPage;
    expect(thread.id, 8334);
    expect(thread.initialThreadId, 42511);
    expect(thread.initialTab, isNull);

    final files =
        page('$org/pull-requests/8334?tab=files') as PullRequestDetailPage;
    expect(files.initialTab, 'files');
    expect(files.initialThreadId, isNull);

    final pipelines = page(
      '$project/pipelines?tab=approvals&approval=18&run=20163',
    ) as PipelinesPage;
    expect(pipelines.initialTab, 'approvals');
    expect(pipelines.initialApprovalId, '18');
    expect(pipelines.initialRunId, '20163');

    // Builds need no anchor (research/14 §4.2): the pushed run route opens
    // the run page as it is.
    final run = page(
      Routes.pipelineRun('u1', 'contoso', 'DevOps Mobile App', '20163'),
    ) as PipelineRunPage;
    expect(run.id, 20163);
    expect(run.project, 'DevOps Mobile App');
  });
}
