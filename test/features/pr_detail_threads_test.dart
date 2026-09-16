import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/data/viewed_files_store.dart';
import 'package:boardhop/features/pull_requests/pull_request_detail_page.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'mention_stubs.dart';

class _Repo extends Mock implements PullRequestRepository {}

class _WorkItems extends Mock implements WorkItemRepository {}

class _AuthService extends Mock implements AuthService {}

/// Answers the two reads [PrDiffSource] makes for the Files tab; the
/// threads themselves come from the mocked repository.
class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.uri.path.contains('/changes')
        ? {'changeEntries': <Object>[]}
        : {
            'value': [
              {
                'id': 1,
                'sourceRefCommit': {'commitId': 'src'},
                'commonRefCommit': {'commitId': 'base'},
              },
            ],
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _thread(int id, String content) => {
  'id': id,
  'status': 'active',
  'threadContext': {
    'filePath': '/src/app.ts',
    'rightFileStart': {'line': 6, 'offset': 1},
  },
  'comments': [
    {
      'id': 1,
      'commentType': 'text',
      'content': content,
      'publishedDate': '2026-09-12T10:00:00Z',
      'author': {'displayName': 'Ada Example', 'id': 'me'},
    },
  ],
};

/// The person the mention test picks, with the identity GUID a mention
/// needs (research/16 §1).
const kellyGuid = '11111111-2222-3333-4444-555555555555';
const kelly = IdentityRef(
  displayName: 'Kelly Kamm',
  uniqueName: 'kelly@kammcs.com',
  id: kellyGuid,
);

void main() {
  late _Repo repo;
  late _WorkItems workItems;
  late List<List<Map<String, dynamic>>> threadReads;
  late MentionStubs stubs;
  late MentionForms forms;

  final pr = PullRequest.fromJson({
    'pullRequestId': 8334,
    'title': 'Scratch PR',
    'status': 'active',
    'sourceRefName': 'refs/heads/feature/x',
    'targetRefName': 'refs/heads/main',
    // Not [kelly]: the mention list would then hold two rows reading the
    // same name, one from the pull request and one from the team.
    'createdBy': {'displayName': 'Ada Example', 'id': 'me'},
    'repository': {
      'id': 'repo',
      'name': 'scratch',
      'project': {'id': 'proj', 'name': 'DevOps Mobile App'},
    },
  });

  setUp(() {
    repo = _Repo();
    workItems = _WorkItems();
    // The page builds its mention picker in the background; these answer
    // its reads with nothing (research/16 §4.5).
    stubs = mentionStubs();
    forms = MentionForms();
    stubMentionProject(forms, project: 'DevOps Mobile App');
    stubMentionPullRequests(repo);
    when(() => stubs.people.teamMembers('o', 'proj', 'team'))
        .thenAnswer((_) async => const [kelly]);
    // The first read has one thread; every later read has two, standing
    // for the reply posted on the file diff.
    threadReads = [
      [_thread(1, 'first')],
      [_thread(1, 'first'), _thread(2, 'posted on the diff')],
    ];
    when(() => repo.get('o', 8334)).thenAnswer((_) async => pr);
    when(() => repo.meId('o')).thenAnswer((_) async => 'me');
    when(() => repo.ref('o', pr)).thenReturn(
      const PrRef(
        org: 'o',
        id: 8334,
        projectId: 'proj',
        repositoryId: 'repo',
        title: 'Scratch PR',
        sourceBranch: 'refs/heads/feature/x',
        targetBranch: 'refs/heads/main',
      ),
    );
    when(() => repo.workItemIds('o', pr)).thenAnswer((_) async => const []);
    when(() => repo.checks('o', pr)).thenAnswer((_) async => const []);
    // P-B: the overview's merge box and label chips read these on open.
    when(() => repo.labels('o', pr)).thenAnswer((_) async => const []);
    when(
      () => repo.policies(
        'o',
        'proj',
        'repo',
        'refs/heads/main',
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => const PrPolicySet([]));
    when(() => repo.rawThreads('o', pr)).thenAnswer(
      (_) async =>
          threadReads.length == 1 ? threadReads.first : threadReads.removeAt(0),
    );
  });

  late GoRouter router;
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = _Adapter(),
    );
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    // The page reads a bearer token of its own for the attachment images
    // inside the description and the comments (research/17 §4).
    final authService = _AuthService();
    when(() => authService.accessToken(accountId: any(named: 'accountId')))
        .thenAnswer((_) async => 'tok');
    router = GoRouter(
      initialLocation: '/a/u1/orgs/o/pull-requests/8334',
      routes: [
        GoRoute(
          path: '/a/u1/orgs/o/pull-requests/8334',
          builder: (_, _) => const PullRequestDetailPage(org: 'o', id: 8334),
          routes: [
            // Stands in for the file diff, which is a route pushed over
            // the detail page and can write threads of its own.
            GoRoute(
              path: 'diff',
              builder: (context, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('leave the diff'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<PullRequestRepository>.value(value: repo),
          RepositoryProvider<WorkItemRepository>.value(value: workItems),
          RepositoryProvider<AdoClient>.value(value: client),
          RepositoryProvider<WorkItemFormRepository>.value(value: forms),
          RepositoryProvider<AuthService>.value(value: authService),
          // Viewed marks are local; a null database makes the store a
          // no-op, which is all this test needs (R8).
          RepositoryProvider<ViewedFilesStore>.value(
            value: ViewedFilesStore(null),
          ),
          ...mentionProviders(stubs),
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
  }

  testWidgets('the Comments tab re-reads its threads when the diff comes '
      'back', (tester) async {
    await pump(tester);
    await tester.tap(find.textContaining('Comments'));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('posted on the diff'), findsNothing);

    // Opening the thread pushes the diff; a reply written there used to
    // leave this tab showing what it read before (iPad walkthrough).
    await tester.tap(find.text('app.ts:6').first);
    await tester.pumpAndSettle();
    expect(find.text('leave the diff'), findsOneWidget);

    await tester.tap(find.text('leave the diff'));
    await tester.pumpAndSettle();
    expect(find.text('posted on the diff'), findsOneWidget);
    verify(() => repo.rawThreads('o', pr)).called(2);
  });

  // M-D finding 1: the names map is built from the threads the page has
  // read, so a comment naming somebody none of the earlier ones did drew as
  // "@someone" until the page was reopened. Reloading the threads has to
  // re-run the lookup.
  testWidgets('a mention that arrives with a thread reload is named, not '
      '"@someone"', (tester) async {
    threadReads = [
      [_thread(1, 'first')],
      [_thread(1, 'first'), _thread(2, 'ping @<$kellyGuid>')],
    ];
    when(() => stubs.people.identitiesByIds('o', any()))
        .thenAnswer((_) async => const {kellyGuid: kelly});

    await pump(tester);
    await tester.tap(find.textContaining('Comments'));
    await tester.pumpAndSettle();
    // Nothing on screen names anybody yet, so the map starts empty.
    expect(find.textContaining('@someone', findRichText: true), findsNothing);

    await tester.tap(find.text('app.ts:6').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('leave the diff'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('ping @Kelly Kamm', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('@someone', findRichText: true), findsNothing);
  });

  testWidgets('the Comments composer posts a picked mention as @<guid>', (
    tester,
  ) async {
    when(() => repo.addThread('o', pr, content: any(named: 'content')))
        .thenAnswer((_) async => 99);
    await pump(tester);
    await tester.tap(find.textContaining('Comments'));
    await tester.pumpAndSettle();

    final composer = find.byType(TextField).last;
    await tester.tap(composer);
    await tester.pumpAndSettle();
    await tester.enterText(composer, 'over to you @kel');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('mentionOptions')),
        matching: find.text('Kelly Kamm'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Post comment'));
    await tester.pumpAndSettle();
    verify(() => repo.addThread('o', pr, content: 'over to you @<$kellyGuid>'))
        .called(1);
  });
}
