import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/data/write_queue.dart';
import 'package:boardhop/features/boards/move_choreography.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:msal_auth/msal_auth.dart';

class _WorkItems extends Mock implements WorkItemRepository {}

class _Queue extends Mock implements WriteQueue {}

class _AuthService extends Mock implements AuthService {}

class _FakeWorkItem extends Fake implements WorkItem {}

/// The dispatch the Kanban board and the sprint taskboard share
/// (`BoardsPage._move` was the original). Each of the four endings is a
/// different promise to the user, so each gets a test.
void main() {
  const org = 'o';
  const project = 'p';

  final card = WorkItem.fromJson({
    'id': 15550,
    'rev': 3,
    'fields': {
      'System.Id': 15550,
      'System.WorkItemType': 'Task',
      'System.Title': 'Model the columns',
      'System.State': 'To Do',
    },
  });

  const ops = [
    {'op': 'add', 'path': '/fields/System.State', 'value': 'In Progress'},
  ];

  setUpAll(() {
    registerFallbackValue(_FakeWorkItem());
    registerFallbackValue(<Map<String, Object?>>[]);
    registerFallbackValue(<String, dynamic>{});
  });

  late _WorkItems workItems;
  late _Queue queue;
  late AuthBloc bloc;
  late _AuthService authService;

  setUp(() {
    workItems = _WorkItems();
    queue = _Queue();
    authService = _AuthService();
    // An account the service does not recognise: the bloc then reports the
    // reason and keeps the others signed in, without trying to sign in
    // interactively inside a widget test.
    when(() => authService.knownAccounts).thenReturn([
      Account(id: 'other', username: 'other@example.test', name: 'Other'),
    ]);
    when(() => authService.accountById(any())).thenReturn(null);
    bloc = AuthBloc(authService);
  });

  tearDown(() => bloc.close());

  /// Runs the choreography inside a real widget tree — it reads the auth
  /// bloc, the queue and the messenger from the context.
  Future<
    ({
      MoveOutcome outcome,
      List<String> failures,
      List<WorkItem> queued,
      BuildContext context,
    })
  >
  run(
    WidgetTester tester, {
    required Future<void> Function() write,
    List<Map<String, Object?>> offline = ops,
  }) async {
    late MoveOutcome outcome;
    final failures = <String>[];
    final queued = <WorkItem>[];
    late BuildContext captured;
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<WorkItemRepository>.value(value: workItems),
          RepositoryProvider<WriteQueue>.value(value: queue),
        ],
        child: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: MaterialApp(
            theme: BoardhopTheme.light(),
            home: AccountScope(
              accountId: 'u1',
              child: Builder(
                builder: (context) {
                  captured = context;
                  return const Scaffold(body: SizedBox.shrink());
                },
              ),
            ),
          ),
        ),
      ),
    );
    final sub = bloc.stream.listen(null);
    addTearDown(sub.cancel);
    outcome = await runMoveChoreography(
      captured,
      org: org,
      project: project,
      card: card,
      write: write,
      offlineOps: () => offline,
      offlineDescription: 'Move 15550 to In Progress',
      onQueued: queued.add,
      onFailed: failures.add,
    );
    await tester.pumpAndSettle();
    return (
      outcome: outcome,
      failures: failures,
      queued: queued,
      context: captured,
    );
  }

  testWidgets('a clean write is simply done', (tester) async {
    final result = await run(tester, write: () async {});

    expect(result.outcome, MoveOutcome.done);
    expect(result.failures, isEmpty);
    verifyNever(
      () => queue.enqueuePatch(
        org: any(named: 'org'),
        project: any(named: 'project'),
        item: any(named: 'item'),
        ops: any(named: 'ops'),
        description: any(named: 'description'),
      ),
    );
  });

  testWidgets('an expired token asks for an interactive sign-in and leaves '
      'the move on screen', (tester) async {
    final result = await run(
      tester,
      write: () async => throw const AdoAuthException('token expired'),
    );

    expect(result.outcome, MoveOutcome.signedOut);
    // The reason travelled to the auth bloc rather than being swallowed:
    // its handler looked the account up.
    verify(() => authService.accountById('u1')).called(1);
    // The optimistic move is not reverted: the sign-in flow replaces the
    // page anyway, and putting the card back would flash.
    expect(result.failures, isEmpty);
  });

  testWidgets('offline queues the patch, applies it locally and says so', (
    tester,
  ) async {
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

    final result = await run(
      tester,
      write: () async => throw const AdoNetworkException('no route to host'),
    );

    expect(result.outcome, MoveOutcome.queued);
    expect(result.queued.single.id, 15550);
    expect(find.text(kOfflineMoveMessage), findsOneWidget);
    final call = verify(
      () => queue.enqueuePatch(
        org: org,
        project: project,
        item: any(named: 'item'),
        ops: captureAny(named: 'ops'),
        description: 'Move 15550 to In Progress',
      ),
    )..called(1);
    expect(call.captured.single, ops);
  });

  testWidgets('offline with nothing worth queueing queues nothing', (
    tester,
  ) async {
    // An in-slot reorder: the rank is recomputed on the next refresh
    // (decision S9), and a sprint move that only changes a taskboard
    // column has no patch at all.
    final result = await run(
      tester,
      write: () async => throw const AdoNetworkException('no route to host'),
      offline: const [],
    );

    expect(result.outcome, MoveOutcome.queued);
    expect(result.queued, isEmpty);
    verifyNever(
      () => queue.enqueuePatch(
        org: any(named: 'org'),
        project: any(named: 'project'),
        item: any(named: 'item'),
        ops: any(named: 'ops'),
        description: any(named: 'description'),
      ),
    );
    expect(find.text(kOfflineMoveMessage), findsNothing);
  });

  testWidgets('a refused move hands back the service\'s own words', (
    tester,
  ) async {
    final result = await run(
      tester,
      write: () async => throw const AdoForbiddenException('you may not'),
    );

    expect(result.outcome, MoveOutcome.failed);
    expect(result.failures.single, 'Could not move 15550: you may not');
  });

  testWidgets('a stale revision asks for a reload in its own words', (
    tester,
  ) async {
    final result = await run(
      tester,
      write: () async => throw const AdoStaleRevisionException('412'),
    );

    expect(result.outcome, MoveOutcome.stale);
    expect(
      result.failures.single,
      'Work item 15550 changed elsewhere; the board was reloaded, try again.',
    );
  });

  test('the sprint names itself in the stale message', () {
    expect(
      moveFailureMessage(
        15550,
        const AdoStaleRevisionException('412'),
        label: 'sprint',
      ),
      'Work item 15550 changed elsewhere; the sprint was reloaded, try again.',
    );
  });
}
