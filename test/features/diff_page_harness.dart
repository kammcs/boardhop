import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/data/viewed_files_store.dart';
import 'package:boardhop/features/pull_requests/pr_file_diff_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'mention_stubs.dart';

class DiffRepo extends Mock implements PullRequestRepository {}

class DiffWorkItems extends Mock implements WorkItemRepository {}

class DiffAuthService extends Mock implements AuthService {}

/// The two files of the scratch pull request this harness serves, in the
/// order the Files tab lists them.
const kOnePath = '/src/one.dart';
const kTwoPath = '/src/two.dart';

const kOneOld = 'alpha\nbravo\ncharlie\ndelta\necho\nfoxtrot\ngolf\nhotel\n';
const kOneNew = 'alpha\nBRAVO\ncharlie\ndelta\nECHO\nfoxtrot\ngolf\nHOTEL\n';
const kTwoOld = 'one\ntwo\nthree\n';
const kTwoNew = 'one\nTWO\nthree\n';

/// Answers the reads `PrDiffSource` makes for one file of one iteration.
class DiffAdapter implements HttpClientAdapter {
  DiffAdapter({this.threads = const []});

  /// Raw thread JSON the threads route answers with.
  List<Map<String, dynamic>> threads;

  /// Every path the page asked for a blob at, for the "reload in place"
  /// assertions.
  final List<String> itemPaths = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final Map<String, dynamic> body;
    if (path.contains('/iterations') && path.endsWith('/changes')) {
      body = {
        'changeEntries': [
          {
            'changeType': 'edit',
            'changeTrackingId': 7,
            'item': {'path': kOnePath, 'objectId': 'blob-one'},
          },
          {
            'changeType': 'edit',
            'changeTrackingId': 8,
            'item': {'path': kTwoPath, 'objectId': 'blob-two'},
          },
        ],
      };
    } else if (path.endsWith('/iterations')) {
      body = {
        'value': [
          {
            'id': 1,
            'sourceRefCommit': {'commitId': 'src'},
            'commonRefCommit': {'commitId': 'base'},
          },
        ],
      };
    } else if (path.endsWith('/items')) {
      final file = options.uri.queryParameters['path'] ?? '';
      final version = options.uri.queryParameters['versionDescriptor.version'];
      itemPaths.add(file);
      final old = version == 'base';
      body = {
        'content': file == kTwoPath
            ? (old ? kTwoOld : kTwoNew)
            : (old ? kOneOld : kOneNew),
      };
    } else {
      body = {'value': threads};
    }
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

/// One file thread, in the shape the Threads API answers with.
Map<String, dynamic> threadJson({
  required int id,
  String content = 'a comment',
  String path = kOnePath,
  int? rightLine,
  int? rightLineEnd,
  int? leftLine,
  int? leftLineEnd,
  String status = 'active',
  String author = 'Kelly Kamm',
  String authorId = 'me',
  bool deleted = false,
  List<Map<String, dynamic>> likes = const [],
  String? editedAt,
}) => {
  'id': id,
  'status': status,
  'threadContext': {
    'filePath': path,
    if (rightLine != null) 'rightFileStart': {'line': rightLine, 'offset': 1},
    if (rightLine != null)
      'rightFileEnd': {'line': rightLineEnd ?? rightLine, 'offset': 1},
    if (leftLine != null) 'leftFileStart': {'line': leftLine, 'offset': 1},
    if (leftLine != null)
      'leftFileEnd': {'line': leftLineEnd ?? leftLine, 'offset': 1},
  },
  'comments': [
    {
      'id': 1,
      'commentType': 'text',
      'content': content,
      'isDeleted': deleted,
      'publishedDate': '2026-09-16T10:00:00Z',
      'lastContentUpdatedDate': ?editedAt,
      'usersLiked': likes,
      'author': {'displayName': author, 'id': authorId},
    },
  ],
};

/// A parsed thread, for the tests that build [DiffView] directly.
PrThread prThread({
  required int id,
  int? rightLine,
  int? rightLineEnd,
  int? leftLine,
  int? leftLineEnd,
  String status = 'active',
  String content = 'a comment',
  String path = kOnePath,
  String authorId = 'me',
  List<Map<String, dynamic>> likes = const [],
  bool deleted = false,
  String? editedAt,
}) => PrThread.fromJson(
  threadJson(
    id: id,
    rightLine: rightLine,
    rightLineEnd: rightLineEnd,
    leftLine: leftLine,
    leftLineEnd: leftLineEnd,
    status: status,
    content: content,
    path: path,
    authorId: authorId,
    likes: likes,
    deleted: deleted,
    editedAt: editedAt,
  ),
  includeDeleted: true,
)!;

typedef DiffHarness = ({
  DiffRepo repo,
  DiffAdapter adapter,
  ViewedFilesStore viewed,
  GoRouter router,
});

final kHarnessPr = PullRequest.fromJson({
  'pullRequestId': 8401,
  'title': 'Scratch PR',
  'status': 'active',
  'sourceRefName': 'refs/heads/spike/w39',
  'targetRefName': 'refs/heads/main',
  'createdBy': {'displayName': 'Kelly Kamm', 'id': 'me'},
  'repository': {
    'id': 'repo',
    'name': 'scratch',
    'project': {'id': 'proj', 'name': 'DevOps Mobile App'},
  },
});

/// Pumps [PrFileDiffPage] over a stubbed pull request with two files.
Future<DiffHarness> pumpDiffPage(
  WidgetTester tester, {
  List<Map<String, dynamic>> threads = const [],
  String path = kOnePath,
  int? line,
  Size size = const Size(1200, 2400),
  double devicePixelRatio = 3,
  DiffRepo? repository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(tester.view.reset);

  final repo = repository ?? DiffRepo();
  final stubs = mentionStubs();
  final forms = MentionForms();
  stubMentionProject(forms, project: 'DevOps Mobile App');
  stubMentionPullRequests(repo, org: 'o');
  when(() => repo.get('o', 8401)).thenAnswer((_) async => kHarnessPr);
  when(() => repo.meId('o')).thenAnswer((_) async => 'me');
  when(() => repo.ref('o', kHarnessPr)).thenReturn(
    const PrRef(
      org: 'o',
      id: 8401,
      projectId: 'proj',
      repositoryId: 'repo',
      title: 'Scratch PR',
      sourceBranch: 'refs/heads/spike/w39',
      targetBranch: 'refs/heads/main',
    ),
  );

  final adapter = DiffAdapter(threads: [...threads]);
  final client = AdoClient(
    tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
    dio: Dio()..httpClientAdapter = adapter,
  );
  final authService = DiffAuthService();
  when(() => authService.accessToken(accountId: any(named: 'accountId')))
      .thenAnswer((_) async => 'tok');
  final auth = AuthBloc(DiffAuthService());
  addTearDown(auth.close);
  final viewed = ViewedFilesStore(null, userId: 'u1');

  final query = ['path=$path', if (line != null) 'line=$line'].join('&');
  final router = GoRouter(
    initialLocation: '/a/u1/orgs/o/pull-requests/8401/diff?$query',
    routes: [
      GoRoute(
        path: '/a/u1/orgs/o/pull-requests/8401',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('Files tab'))),
        routes: [
          GoRoute(
            path: 'diff',
            builder: (_, state) => PrFileDiffPage(
              org: 'o',
              id: 8401,
              path: state.uri.queryParameters['path'] ?? '',
              line: int.tryParse(state.uri.queryParameters['line'] ?? ''),
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
        RepositoryProvider<WorkItemRepository>.value(value: DiffWorkItems()),
        RepositoryProvider<AdoClient>.value(value: client),
        RepositoryProvider<WorkItemFormRepository>.value(value: forms),
        RepositoryProvider<AuthService>.value(value: authService),
        RepositoryProvider<ViewedFilesStore>.value(value: viewed),
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
  return (repo: repo, adapter: adapter, viewed: viewed, router: router);
}
