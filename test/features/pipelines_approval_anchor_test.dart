import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/data/models/pipeline.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pipeline_repository.dart';
import 'package:boardhop/features/pipelines/pipelines_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/shared/anchor_highlight.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Repo extends Mock implements PipelineRepository {}

class _AuthService extends Mock implements AuthService {}

PipelineApproval _approval(String id, {String status = 'pending'}) =>
    PipelineApproval(
      id: id,
      status: status,
      pipelineName: 'boardhop-scratch',
      runName: '20260913.$id',
      runId: 20163,
      instructions: 'Ship it',
      createdOn: DateTime.utc(2026, 9, 13, 15),
      steps: const [
        ApprovalStep(
          assignedApprover: IdentityRef(displayName: 'Kelly Kamm', id: 'me'),
          status: 'pending',
        ),
      ],
    );

/// research/14 §4.2 and §2.4: `?tab=approvals&approval={id}` opens the
/// Approvals tab on that approval; an approval that is no longer pending
/// gets the "Already decided" snackbar, with "Open run" when the pointer
/// carried `?run={id}`.
void main() {
  late _Repo repo;
  late List<PipelineApproval> approvals;

  setUp(() {
    repo = _Repo();
    approvals = [for (var i = 1; i <= 8; i++) _approval('a$i')];
    when(() => repo.cachedDefinitions('o', 'p')).thenAnswer((_) async => null);
    when(() => repo.cachedRuns('o', 'p')).thenAnswer((_) async => null);
    when(() => repo.definitions('o', 'p')).thenAnswer((_) async => const []);
    when(() => repo.runs('o', 'p', definitionId: any(named: 'definitionId')))
        .thenAnswer((_) async => const []);
    when(() => repo.approvals('o', 'p')).thenAnswer((_) async => approvals);
  });

  Future<void> pump(
    WidgetTester tester, {
    String? tab,
    String? approvalId,
    String? runId,
  }) async {
    // 533 x 800 dp: still the compact breakpoint, but wide enough that the
    // test font (every glyph a square) does not overflow the card's button
    // row the way a real font never would.
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    final router = GoRouter(
      initialLocation: '/a/u1/orgs/o/projects/p/pipelines',
      routes: [
        GoRoute(
          path: '/a/u1/orgs/o/projects/p/pipelines',
          builder: (_, _) => PipelinesPage(
            org: 'o',
            project: 'p',
            initialTab: tab,
            initialApprovalId: approvalId,
            initialRunId: runId,
          ),
          routes: [
            GoRoute(
              path: 'runs/:id',
              builder: (_, state) => Scaffold(
                appBar: AppBar(title: const Text('Run')),
                body: Center(child: Text('run ${state.pathParameters['id']}')),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [RepositoryProvider<PipelineRepository>.value(value: repo)],
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
  }

  Finder highlighted() =>
      find.byWidgetPredicate((w) => w is AnchorHighlight && w.active);

  testWidgets('?tab=approvals&approval={id} opens the tab on that approval', (
    tester,
  ) async {
    await pump(tester, tab: 'approvals', approvalId: 'a7');

    expect(find.text('Already decided'), findsNothing);
    expect(highlighted(), findsOneWidget);
    expect(
      find.descendant(
        of: highlighted(),
        matching: find.textContaining('20260913.a7'),
      ),
      findsOneWidget,
    );
    // Its Approve and Reject buttons came with it, which is the action the
    // notification is asking for.
    expect(
      find.descendant(of: highlighted(), matching: find.text('Approve')),
      findsOneWidget,
    );

    await tester.pump(kAnchorHighlight);
    await tester.pumpAndSettle();
    expect(highlighted(), findsNothing);
  });

  testWidgets('an approval that is no longer pending says "Already decided" '
      'and offers the run', (tester) async {
    await pump(tester, tab: 'approvals', approvalId: 'gone', runId: '20163');

    expect(find.text('Already decided'), findsOneWidget);
    expect(highlighted(), findsNothing);

    await tester.tap(find.text('Open run'));
    await tester.pumpAndSettle();
    expect(find.text('run 20163'), findsOneWidget);
  });

  testWidgets('with no run in the pointer the snackbar has no action', (
    tester,
  ) async {
    await pump(tester, tab: 'approvals', approvalId: 'gone');
    expect(find.text('Already decided'), findsOneWidget);
    expect(find.text('Open run'), findsNothing);
  });

  testWidgets('without an anchor the page opens on Runs as before', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Already decided'), findsNothing);
    expect(highlighted(), findsNothing);
    expect(find.text('All pipelines'), findsOneWidget);
  });
}
