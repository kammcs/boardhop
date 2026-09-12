import 'package:boardhop/data/write_queue.dart';
import 'package:boardhop/features/projects/project_shell.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/shared/unsaved_work.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:boardhop/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _Queue extends Mock implements WriteQueue {}

/// The tablet form: a dialog over the branch rather than a route of its
/// own, holding changes it would rather not lose.
class _DirtyDialog extends StatefulWidget {
  const _DirtyDialog();

  @override
  State<_DirtyDialog> createState() => _DirtyDialogState();
}

class _DirtyDialogState extends State<_DirtyDialog> {
  late final UnsavedWorkGuard _guard = UnsavedWorkGuard(
    isDirty: () => true,
    confirmLeave: _confirm,
  );

  @override
  void initState() {
    super.initState();
    UnsavedWork.register(_guard);
  }

  @override
  void dispose() {
    UnsavedWork.unregister(_guard);
    super.dispose();
  }

  Future<bool> _confirm() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard your changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) =>
      const Dialog(child: SizedBox(height: 200, child: Text('the form')));
}

class _WorkPage extends StatelessWidget {
  const _WorkPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          // As the real form does: the account's repositories are
          // provided above the branch navigator, not above the root one.
          useRootNavigator: false,
          builder: (_) => const _DirtyDialog(),
        ),
        child: const Text('open the form'),
      ),
    ),
  );
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
    UnsavedWork.clear();
  });

  tearDown(UnsavedWork.clear);

  const base = '/a/u1/orgs/o/projects/p';

  GoRouter router() => GoRouter(
    initialLocation: '$base/work-items',
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
                  builder: (_, _) => tail == 'work-items'
                      ? const _WorkPage()
                      : Scaffold(body: Center(child: Text('$tail page'))),
                ),
              ],
            ),
        ],
      ),
    ],
  );

  Future<void> pump(WidgetTester tester) async {
    // A tablet in landscape, so the shell shows the Apple glass rail.
    tester.view.physicalSize = const Size(2048, 1536);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final config = router();
    addTearDown(config.dispose);
    await tester.pumpWidget(
      RepositoryProvider<WriteQueue>.value(
        value: queue,
        child: MaterialApp.router(
          theme: BoardhopTheme.light().copyWith(platform: TargetPlatform.iOS),
          routerConfig: config,
          builder: (context, child) => ThemeScope(
            controller: ThemeController.inMemory(),
            child: AccountScope(accountId: 'u1', child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the rail asks before dropping a dirty dialog on the tab it is '
      'already on', (tester) async {
    await pump(tester);
    await tester.tap(find.text('open the form'));
    await tester.pumpAndSettle();
    expect(find.text('the form'), findsOneWidget);

    // Re-tapping the current tab: the location is already the branch root
    // (the form is a dialog, not a route), which used to swallow the tap.
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('the form'), findsOneWidget);

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('the form'), findsNothing);
    expect(find.text('open the form'), findsOneWidget);
  });

  testWidgets('with nothing unsaved the current tab is still a no-op', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsNothing);
    expect(find.text('open the form'), findsOneWidget);
  });

  testWidgets('another tab still switches without a question', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget);
  });
}
