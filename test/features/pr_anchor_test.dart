import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/features/pull_requests/pull_request_detail_page.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/features/shared/anchor_highlight.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'mention_stubs.dart';

class _Repo extends Mock implements PullRequestRepository {}

class _WorkItems extends Mock implements WorkItemRepository {}

class _AuthService extends Mock implements AuthService {}

/// Answers the two reads [PrDiffSource] makes for the Files tab.
class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.uri.path.contains('/changes')
        ? {
            'changeEntries': [
              {
                'changeType': 'edit',
                'item': {'path': '/src/app.ts'},
              },
            ],
          }
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

/// A conversation thread (no file context) or a file thread.
Map<String, dynamic> _thread(int id, String content, {String? path}) => {
  'id': id,
  'status': 'active',
  if (path != null)
    'threadContext': {
      'filePath': path,
      'rightFileStart': {'line': 6, 'offset': 1},
    },
  'comments': [
    {
      'id': 1,
      'commentType': 'text',
      'content': content,
      'publishedDate': '2026-09-12T10:00:00Z',
      'author': {'displayName': 'Kelly Kamm', 'id': 'me'},
    },
  ],
};

/// research/14 §4.2: `?tab=` picks the tab and `?thread={id}` lands on the
/// thread — a conversation thread is scrolled to and tinted, a file thread
/// opens the file diff the way tapping its header does.
void main() {
  late _Repo repo;
  late _WorkItems workItems;
  late List<Map<String, dynamic>> threads;
  late MentionStubs stubs;
  late MentionForms forms;

  final pr = PullRequest.fromJson({
    'pullRequestId': 8334,
    'title': 'Scratch PR',
    'status': 'active',
    'sourceRefName': 'refs/heads/feature/x',
    'targetRefName': 'refs/heads/main',
    'createdBy': {'displayName': 'Kelly Kamm', 'id': 'me'},
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
    threads = [
      for (var i = 1; i <= 10; i++) _thread(42500 + i, 'conversation $i'),
      _thread(42511, 'on a line', path: '/src/app.ts'),
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
    when(() => repo.rawThreads('o', pr)).thenAnswer((_) async => threads);
  });

  late GoRouter router;
  Future<void> pump(WidgetTester tester, {String? tab, int? threadId}) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = _Adapter(),
    );
    final auth = AuthBloc(_AuthService());
    addTearDown(auth.close);
    router = GoRouter(
      initialLocation: '/a/u1/orgs/o/pull-requests/8334',
      routes: [
        GoRoute(
          path: '/a/u1/orgs/o/pull-requests/8334',
          builder: (_, _) => PullRequestDetailPage(
            org: 'o',
            id: 8334,
            initialTab: tab,
            initialThreadId: threadId,
          ),
          routes: [
            // Stands in for the file diff route.
            GoRoute(
              path: 'diff',
              builder: (context, state) => Scaffold(
                appBar: AppBar(title: const Text('File diff')),
                body: Center(
                  child: Text('diff of ${state.uri.queryParameters['path']}'),
                ),
              ),
            ),
          ],
        ),
        // Stands in for the standalone work item route (the real one is
        // pinned by test/core/router_test.dart); a `#123` tapped on this
        // page has to reach *this* shape and not the in-shell one.
        GoRoute(
          path: '/a/u1/orgs/o/projects/:project/work-item/:id',
          builder: (_, s) =>
              Scaffold(body: Text('standalone ${s.pathParameters['id']}')),
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

  Finder highlighted() =>
      find.byWidgetPredicate((w) => w is AnchorHighlight && w.active);

  testWidgets('?thread={id} opens Comments and tints the conversation '
      'thread', (tester) async {
    await pump(tester, threadId: 42510);

    expect(
      find.textContaining('conversation 10', findRichText: true),
      findsOneWidget,
    );
    expect(highlighted(), findsOneWidget);
    expect(
      find.descendant(
        of: highlighted(),
        matching: find.textContaining('conversation 10', findRichText: true),
      ),
      findsOneWidget,
    );

    await tester.pump(kAnchorHighlight);
    await tester.pumpAndSettle();
    expect(highlighted(), findsNothing);
  });

  testWidgets('?thread={id} on a file thread opens the diff over the PR', (
    tester,
  ) async {
    await pump(tester, threadId: 42511);
    expect(find.text('diff of /src/app.ts'), findsOneWidget);

    // Back returns to the pull request, on the Comments tab.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('conversation 1', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('a thread that is gone leaves Comments as it is, no error', (
    tester,
  ) async {
    await pump(tester, threadId: 999999);
    expect(highlighted(), findsNothing);
    expect(
      find.textContaining('conversation 1', findRichText: true),
      findsWidgets,
    );
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('?tab=files opens the Files tab', (tester) async {
    await pump(tester, tab: 'files');
    expect(find.text('app.ts'), findsOneWidget);
    expect(highlighted(), findsNothing);
  });

  // research/16 M10 + the M-D router fix: the pull request page is itself
  // pushed over the project tab shell, so a `#123` in one of its comments
  // must open the standalone work item route. Pushing the in-shell location
  // from here puts a second copy of the shell's page in the same navigator
  // ('!keyReservation.contains(key)').
  testWidgets('#15545 in a thread opens the standalone work item route', (
    tester,
  ) async {
    threads.add(_thread(42499, 'fixes #15545'));
    await pump(tester);
    await tester.tap(find.text('Comments'));
    await tester.pumpAndSettle();

    // The comment body is selectable, so it renders through EditableText
    // and `tapOnText` has no RenderParagraph to measure; the span's own
    // recogniser is what a real tap reaches.
    expect(find.textContaining('#15545', findRichText: true), findsOneWidget);
    final recognizers = <GestureRecognizer>[];
    for (final text in tester.widgetList<SelectableText>(
      find.byType(SelectableText),
    )) {
      text.textSpan?.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) {
          recognizers.add(span.recognizer!);
        }
        return true;
      });
    }
    expect(recognizers, hasLength(1));
    (recognizers.single as TapGestureRecognizer).onTap!();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      router.state.uri.toString(),
      '/a/u1/orgs/o/projects/DevOps%20Mobile%20App/work-item/15545',
    );
    expect(find.text('standalone 15545'), findsOneWidget);
  });

  testWidgets('without an anchor the page still opens on Overview', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Scratch PR'), findsWidgets);
    expect(find.text('diff of /src/app.ts'), findsNothing);
  });
}
