import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/db/app_database.dart';
import 'package:boardhop/data/models/pr_check.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/repo_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/data/viewed_files_store.dart';
import 'package:boardhop/demo/demo_backend.dart';
import 'package:boardhop/demo/demo_world.dart';
import 'package:boardhop/demo/fixtures/pull_requests/pr_files.dart';
import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:boardhop/features/pull_requests/pr_file_diff_page.dart';
import 'package:boardhop/features/pull_requests/pull_request_detail_page.dart';
import 'package:boardhop/features/pull_requests/pull_requests_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/mention_stubs.dart';
import 'demo_harness.dart';

class _WorkItems extends Mock implements WorkItemRepository {}

class _Repos extends Mock implements RepoRepository {}

class _Sprints extends Mock implements SprintRepository {}

class _Auth extends Mock implements AuthService {}

const org = DemoWorld.org;

/// Misses that belong to this area: anything under `_apis/git`, the policy
/// routes, `connectionData` and `identities`.
List<String> prMisses(DemoBackend backend) => [
  for (final m in backend.misses)
    if (m.contains('/_apis/git/') ||
        m.contains('/_apis/policy/') ||
        m.contains('connectionData') ||
        m.contains('/_apis/identities'))
      m,
];

void main() {
  late ({AdoClient client, AppDatabase db, DemoBackend backend}) h;

  setUp(() => h = demoHarness());
  tearDown(() async {
    final others = [
      for (final m in h.backend.misses)
        if (!prMisses(h.backend).contains(m)) m,
    ];
    if (others.isNotEmpty) {
      // Other areas' routes (work items, team members); listed, not failed.
      printOnFailure('Misses outside pull requests: $others');
    }
    await h.db.close();
  });

  group('repositories', () {
    test('the inbox has active pull requests across all three repos', () async {
      final repo = PullRequestRepository(h.client, h.db, DemoWorld.me.id);

      final all = await repo.list(org, filter: PrListFilter.all);
      final toReview = await repo.list(org);
      final mine = await repo.list(org, filter: PrListFilter.mine);

      expect(all.length, inInclusiveRange(6, 8));
      expect(
        {for (final pr in all) pr.repositoryName},
        {'boardhop', 'boardhop-relay', 'boardhop-extension'},
      );
      expect({for (final pr in all) pr.createdBy.id}.length, greaterThan(4));
      expect(all.where((pr) => pr.isDraft), hasLength(2));
      expect(all.every((pr) => pr.labels.isNotEmpty || pr.isDraft), isTrue);
      expect(toReview.map((pr) => pr.id), containsAll([412, 415, 414]));
      expect(
        toReview.every((pr) => pr.reviewer(DemoWorld.me.id) != null),
        isTrue,
      );
      expect(mine.map((pr) => pr.id), [417]);
      expect(
        {for (final pr in toReview) pr.overallVote}.length,
        greaterThan(2),
        reason: 'varied reviewer states',
      );

      final relay = await repo.list(
        org,
        project: DemoWorld.project,
        filter: PrListFilter.all,
        repositoryId: DemoWorld.relayRepo.id,
      );
      expect(relay.map((pr) => pr.id), [415]);
      expect(prMisses(h.backend), isEmpty);
    });

    test('!412 has reviewers, passing checks, labels and threads', () async {
      final repo = PullRequestRepository(h.client, h.db, DemoWorld.me.id);
      final source = PrDiffSource(h.client);

      final pr = await repo.get(org, 412);
      expect(pr.title, 'Side-by-side diff on iPad');
      expect(pr.createdBy.displayName, 'Marcus Chen');
      expect(pr.sourceBranch, 'feature/side-by-side-diff');
      expect(pr.targetBranch, 'main');
      expect(pr.description, contains('#1238'));
      expect(pr.isAutoCompleteSet, isFalse);
      expect(pr.mergeStatus, 'succeeded');
      expect(pr.labels, isEmpty, reason: 'the get never carries labels');

      final priya = pr.reviewer(DemoWorld.priya.id)!;
      expect(priya.vote, PrVote.approved);
      expect(priya.isRequired, isTrue);
      expect(pr.reviewer(DemoWorld.me.id)!.vote, PrVote.none);

      expect(await repo.meId(org), DemoWorld.me.id);
      expect(await repo.workItemIds(org, pr), contains(1238));
      expect(
        (await repo.labels(org, pr)).map((l) => l.name),
        contains('tablet'),
      );

      final checks = await repo.checks(org, pr);
      final build = checks.firstWhere((c) => c.name == 'Build');
      expect(build.state, PrCheckState.succeeded);
      expect(build.detail, 'boardhop-ci');
      expect(build.isBlocking, isTrue);
      expect(
        checks
            .where((c) => c.isBlocking)
            .every((c) => c.state == PrCheckState.succeeded),
        isTrue,
      );
      expect(checks.any((c) => c.name.startsWith('coverage')), isTrue);

      final policies = await repo.policies(
        org,
        pr.projectId,
        pr.repositoryId,
        pr.targetRefName,
      );
      expect(policies.hasBlocking, isTrue);
      expect(policies.minimumApproverCount, 1);

      final raw = await repo.rawThreads(org, pr);
      final conversation = PullRequestRepository.conversation(raw);
      expect(conversation.length, greaterThanOrEqualTo(3));
      expect(conversation.any((t) => t.isResolved), isTrue);
      expect(conversation.any((t) => !t.isFileThread), isTrue);
      expect(conversation.any((t) => t.isLeftSide), isTrue);
      final activity = PullRequestRepository.conversation(
        raw,
        includeSystem: true,
      );
      expect(
        activity.where((t) => t.isSystem).map((t) => t.systemKind),
        containsAll(['VoteUpdate', 'RefUpdate']),
      );
      expect(
        activity.firstWhere((t) => t.isSystem).systemText,
        isNot(contains('{1}')),
      );

      final ref = repo.ref(org, pr);
      final iterations = await source.iterations(ref);
      expect(iterations.map((i) => i.id), [1, 2, 3]);
      final changes = await source.changes(ref, iterations.last.id);
      expect(changes, hasLength(5));
      expect(changes.first.path, kSplitDiffPath);
      expect(changes.where((c) => c.isAdd), hasLength(1));
      expect(prMisses(h.backend), isEmpty);
    });

    test('the main diff has hunks and an active thread in view', () async {
      final source = PrDiffSource(h.client);

      final ref = await source.pullRequest(org, 412);
      final it = (await source.iterations(ref)).last;
      final oldText = await source.fileAt(ref, kSplitDiffPath, it.commonCommit);
      final newText = await source.fileAt(ref, kSplitDiffPath, it.sourceCommit);
      final diff = LineDiff.compute(oldText, newText);

      final lines = newText.split('\n').length;
      expect(lines, inInclusiveRange(80, 170));
      expect(diff.added, greaterThan(5));
      expect(diff.removed, greaterThan(1));
      expect(diff.hunks, greaterThanOrEqualTo(3));
      // A change on the first screenful.
      expect(
        diff.lines.take(20).any((l) => l.kind != DiffKind.context),
        isTrue,
      );

      final threads = await source.threads(
        ref,
        iteration: it.id,
        baseIteration: 0,
      );
      final onFile = threads.where((t) => t.filePath == kSplitDiffPath).single;
      expect(onFile.isResolved, isFalse);
      expect(onFile.comments, hasLength(3));
      expect(
        onFile.comments.first.content,
        contains('@<${DemoWorld.marcus.id}>'),
      );
      expect(
        {for (final c in onFile.comments) c.author},
        {'Priya Raman', 'Marcus Chen'},
      );
      final line = onFile.rightLine!;
      expect(line, lessThan(40));
      expect(newText.split('\n')[line - 1], contains(kSplitDiffThreadLine));
      expect(prMisses(h.backend), isEmpty);
    });

    test('a vote and a reply read back', () async {
      final repo = PullRequestRepository(h.client, h.db, DemoWorld.me.id);
      final pr = await repo.get(org, 412);

      await repo.vote(org, pr, PrVote.approved);
      final raw = await repo.rawThreads(org, pr);
      final thread = PullRequestRepository.conversation(raw)
          .firstWhere((t) => t.filePath == kSplitDiffPath);
      await repo.reply(org, pr, thread.id, 'Clamped both ways now.');

      final after = await repo.get(org, 412);
      expect(after.reviewer(DemoWorld.me.id)!.vote, PrVote.approved);
      final again = PullRequestRepository.conversation(
        await repo.rawThreads(org, pr),
      ).firstWhere((t) => t.id == thread.id);
      expect(again.comments.last.content, 'Clamped both ways now.');
      expect(again.comments.last.author, DemoWorld.me.name);
      expect(prMisses(h.backend), isEmpty);
    });

    test('an unknown pull request is a 404, not a miss', () async {
      final repo = PullRequestRepository(h.client, h.db, DemoWorld.me.id);
      await expectLater(repo.get(org, 99999), throwsA(anything));
      expect(prMisses(h.backend), isEmpty);
    });
  });

  group('pages', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> pump(
      WidgetTester tester,
      String location, {
      Size size = const Size(1290, 2796),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final prs = PullRequestRepository(h.client);
      final workItems = _WorkItems();
      when(() => workItems.batch(any(), any(), any())).thenAnswer(
        (_) async => [
          WorkItem.fromJson({
            'id': 1238,
            'rev': 4,
            'fields': {
              'System.Id': 1238,
              'System.WorkItemType': 'User Story',
              'System.Title': 'Side-by-side diff on iPad',
              'System.State': 'Active',
            },
          }),
        ],
      );
      final forms = MentionForms();
      stubMentionProject(forms, org: org, project: DemoWorld.project);
      final stubs = mentionStubs();
      final auth = _Auth();
      when(() => auth.accessToken(accountId: any(named: 'accountId')))
          .thenAnswer((_) async => 'demo');
      final bloc = AuthBloc(_Auth());
      addTearDown(bloc.close);

      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(
            path: '/a/:account/orgs/:org/pull-requests',
            builder: (_, state) =>
                PullRequestsPage(org: state.pathParameters['org']!),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => PullRequestDetailPage(
                  org: state.pathParameters['org']!,
                  id: int.parse(state.pathParameters['id']!),
                ),
                routes: [
                  GoRoute(
                    path: 'diff',
                    builder: (_, state) => PrFileDiffPage(
                      org: state.pathParameters['org']!,
                      id: int.parse(state.pathParameters['id']!),
                      path: state.uri.queryParameters['path'] ?? '',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<PullRequestRepository>.value(value: prs),
            RepositoryProvider<WorkItemRepository>.value(value: workItems),
            RepositoryProvider<RepoRepository>.value(value: _Repos()),
            RepositoryProvider<SprintRepository>.value(value: _Sprints()),
            RepositoryProvider<AdoClient>.value(value: h.client),
            RepositoryProvider<WorkItemFormRepository>.value(value: forms),
            RepositoryProvider<AuthService>.value(value: auth),
            RepositoryProvider<ViewedFilesStore>.value(
              value: ViewedFilesStore(null),
            ),
            ...mentionProviders(stubs),
          ],
          child: BlocProvider<AuthBloc>.value(
            value: bloc,
            child: MaterialApp.router(
              theme: BoardhopTheme.light(),
              routerConfig: router,
              builder: (context, child) =>
                  AccountScope(accountId: DemoWorld.me.id, child: child!),
            ),
          ),
        ),
      );
      await settle(tester);
    }

    final base = '/a/${DemoWorld.me.id}/orgs/$org/pull-requests';

    testWidgets('the inbox lists pull requests to review', (tester) async {
      await pump(tester, base);

      expect(find.text('Side-by-side diff on iPad'), findsOneWidget);
      expect(
        find.text('Re-register the device when the APNs token rotates'),
        findsOneWidget,
      );
      expect(find.textContaining('boardhop-relay · !415'), findsOneWidget);
      expect(prMisses(h.backend), isEmpty);
    });

    testWidgets('!412 overview renders reviewers, checks and merge box', (
      tester,
    ) async {
      await pump(tester, '$base/412');

      expect(find.text('Side-by-side diff on iPad'), findsWidgets);
      expect(find.text('Priya Raman'), findsWidgets);
      expect(find.textContaining('boardhop-ci'), findsWidgets);
      expect(find.text('Complete'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(prMisses(h.backend), isEmpty);
    });

    testWidgets('the main file diff shows the thread on its line', (
      tester,
    ) async {
      await pump(
        tester,
        '$base/412/diff?path=${Uri.encodeQueryComponent(kSplitDiffPath)}',
      );

      expect(
        find.textContaining('ping-pong between the panes'),
        findsOneWidget,
      );
      expect(find.textContaining('returns early'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(prMisses(h.backend), isEmpty);
    });

    testWidgets('the main file diff on a 13-inch iPad', (tester) async {
      await pump(
        tester,
        '$base/412/diff?path=${Uri.encodeQueryComponent(kSplitDiffPath)}',
        size: const Size(2064, 2752),
      );

      expect(
        find.textContaining('ping-pong between the panes'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(prMisses(h.backend), isEmpty);
    });
  });
}
