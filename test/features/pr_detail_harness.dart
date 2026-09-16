import 'dart:convert';
import 'dart:typed_data';

import 'package:boardhop/auth/auth_bloc.dart';
import 'package:boardhop/auth/auth_service.dart';
import 'package:boardhop/core/http/ado_client.dart';
import 'package:boardhop/data/models/git_repository.dart';
import 'package:boardhop/data/models/pr_check.dart';
import 'package:boardhop/data/models/pull_request.dart';
import 'package:boardhop/data/models/sprint.dart';
import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/data/repositories/pr_diff_source.dart';
import 'package:boardhop/data/repositories/pull_request_repository.dart';
import 'package:boardhop/data/repositories/repo_repository.dart';
import 'package:boardhop/data/repositories/sprint_repository.dart';
import 'package:boardhop/data/repositories/work_item_form_repository.dart';
import 'package:boardhop/data/repositories/work_item_repository.dart';
import 'package:boardhop/data/viewed_files_store.dart';
import 'package:boardhop/features/pull_requests/pull_request_detail_page.dart';
import 'package:boardhop/features/shared/account_scope.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'mention_stubs.dart';

class PrRepo extends Mock implements PullRequestRepository {}

class PrWorkItems extends Mock implements WorkItemRepository {}

class PrRepos extends Mock implements RepoRepository {}

class PrSprints extends Mock implements SprintRepository {}

class PrAuth extends Mock implements AuthService {}

/// The pull request every P-B test starts from: scratch PR 8401 against
/// `scratch/policy-target`, which is the branch that carries the blocking
/// policies 192 and 193 (research/22 §1).
PullRequest samplePr({
  int id = 8401,
  String status = 'active',
  bool isDraft = false,
  String? mergeStatus = 'succeeded',
  List<Map<String, dynamic>> reviewers = const [],
  Map<String, dynamic>? autoCompleteSetBy,
  Map<String, dynamic>? completionOptions,
  List<String> labels = const [],
  String createdById = 'author',
  String targetRef = 'refs/heads/scratch/policy-target',
  String? mergeFailureMessage,
}) => PullRequest.fromJson({
  'pullRequestId': id,
  'title': 'Scratch policy PR',
  'description': 'A description.',
  'status': status,
  'isDraft': isDraft,
  'sourceRefName': 'refs/heads/spike/w39',
  'targetRefName': targetRef,
  'createdBy': {'displayName': 'Ada Example', 'id': createdById},
  'mergeStatus': ?mergeStatus,
  'mergeFailureMessage': ?mergeFailureMessage,
  'lastMergeSourceCommit': {'commitId': 'src'},
  'reviewers': reviewers,
  'autoCompleteSetBy': ?autoCompleteSetBy,
  'completionOptions': ?completionOptions,
  'labels': [
    for (final l in labels) {'name': l, 'active': true},
  ],
  'repository': {
    'id': 'repo',
    'name': 'scratch',
    'project': {'id': 'proj', 'name': 'DevOps Mobile App'},
  },
});

Map<String, dynamic> reviewerJson(
  String id,
  String name, {
  int vote = 0,
  bool isRequired = false,
  bool isFlagged = false,
  bool hasDeclined = false,
  bool isContainer = false,
}) => {
  'id': id,
  'displayName': name,
  'vote': vote,
  'isRequired': isRequired,
  'isFlagged': isFlagged,
  'hasDeclined': hasDeclined,
  'isContainer': isContainer,
};

/// The two blocking policies on `scratch/policy-target`: minimum reviewers
/// 1 (192) and merge strategy squash + no-fast-forward (193).
PrPolicySet policyTargetSet({
  List<String> requiredReviewerIds = const [],
  bool withOptional = false,
}) => PrPolicySet.fromJson({
  'value': [
    {
      'id': 192,
      'isBlocking': true,
      'isEnabled': true,
      'type': {
        'id': PrPolicy.minimumReviewersType,
        'displayName': 'Minimum number of reviewers',
      },
      'settings': {'minimumApproverCount': 1},
    },
    {
      'id': 193,
      'isBlocking': true,
      'isEnabled': true,
      'type': {
        'id': PrPolicy.mergeStrategyType,
        'displayName': 'Require a merge strategy',
      },
      'settings': {'allowSquash': true, 'allowNoFastForward': true},
    },
    if (requiredReviewerIds.isNotEmpty)
      {
        'id': 194,
        'isBlocking': true,
        'isEnabled': true,
        'type': {
          'id': PrPolicy.requiredReviewersType,
          'displayName': 'Required reviewers',
        },
        'settings': {'requiredReviewerIds': requiredReviewerIds},
      },
    if (withOptional)
      {
        'id': 195,
        'isBlocking': false,
        'isEnabled': true,
        'type': {'id': 'build-type', 'displayName': 'Build'},
        'settings': <String, dynamic>{},
      },
  ],
}, 'refs/heads/scratch/policy-target');

/// Answers the two reads [PrDiffSource] makes for the Files tab.
class PrAdapter implements HttpClientAdapter {
  PrAdapter({this.changeEntries = const []});

  final List<Map<String, dynamic>> changeEntries;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.uri.path.contains('/changes')
        ? {'changeEntries': changeEntries}
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

/// Everything the detail page reads, mocked, plus a `pump` that puts it on
/// screen inside the router it expects.
class PrHarness {
  PrHarness({
    required this.pr,
    this.meId = 'me',
    this.policies,
    this.checks = const [],
    this.conflicts = const [],
    this.threads = const [],
    this.changeEntries = const [],
    this.workItemsLinked = const [],
  });

  PullRequest pr;
  final String meId;
  PrPolicySet? policies;
  List<PrCheck> checks;
  List<PrConflict> conflicts;
  List<Map<String, dynamic>> threads;
  List<Map<String, dynamic>> changeEntries;
  List<WorkItem> workItemsLinked;

  late final PrRepo repo = PrRepo();
  late final PrWorkItems workItems = PrWorkItems();
  late final PrRepos repos = PrRepos();
  late final PrSprints sprints = PrSprints();
  late final MentionForms forms = MentionForms();
  late final MentionStubs stubs = mentionStubs();
  final viewed = ViewedFilesStore(null);

  static void registerFallbacks() {
    registerMentionFallbacks();
    registerFallbackValue(samplePr());
    registerFallbackValue(const PrCompletionOptions());
  }

  void stub() {
    registerFallbacks();
    stubMentionProject(forms, project: 'DevOps Mobile App');
    stubMentionPullRequests(repo);
    when(() => forms.tags('o', 'DevOps Mobile App'))
        .thenAnswer((_) async => const ['boardhop-spike', 'boardhop-spike-2']);
    when(() => repo.get('o', pr.id)).thenAnswer((_) async => pr);
    when(() => repo.meId('o')).thenAnswer((_) async => meId);
    when(() => repo.ref('o', any())).thenReturn(
      PrRef(
        org: 'o',
        id: pr.id,
        projectId: 'proj',
        repositoryId: 'repo',
        title: pr.title,
        sourceBranch: pr.sourceRefName,
        targetBranch: pr.targetRefName,
      ),
    );
    when(() => repo.workItemIds('o', any()))
        .thenAnswer((_) async => [for (final w in workItemsLinked) w.id]);
    when(() => workItems.batch('o', 'proj', any()))
        .thenAnswer((_) async => workItemsLinked);
    when(() => repo.checks('o', any())).thenAnswer((_) async => checks);
    when(() => repo.labels('o', any())).thenAnswer((_) async => pr.labels);
    when(
      () => repo.policies(
        any(),
        any(),
        any(),
        any(),
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer((_) async => policies ?? const PrPolicySet([]));
    when(
      () => repo.conflicts(
        'o',
        any(),
        excludeResolved: any(named: 'excludeResolved'),
        top: any(named: 'top'),
      ),
    ).thenAnswer((_) async => conflicts);
    when(() => repo.rawThreads('o', any())).thenAnswer((_) async => threads);
    when(
      () => repos.branches(
        'o',
        'proj',
        'repo',
        defaultBranch: any(named: 'defaultBranch'),
      ),
    ).thenAnswer(
      (_) async => [
        GitBranch.fromJson(const {
          'name': 'main',
          'aheadCount': 0,
          'behindCount': 0,
        }),
        GitBranch.fromJson(const {
          'name': 'scratch/policy-target',
          'aheadCount': 1,
          'behindCount': 0,
        }),
      ],
    );
    when(() => repos.cachedList('o', 'DevOps Mobile App'))
        .thenAnswer((_) async => null);
    when(() => repos.branches('o', 'proj', 'repo')).thenAnswer(
      (_) async => [
        GitBranch.fromJson(const {
          'name': 'main',
          'aheadCount': 0,
          'behindCount': 0,
        }),
        GitBranch.fromJson(const {
          'name': 'scratch/policy-target',
          'aheadCount': 1,
          'behindCount': 0,
        }),
      ],
    );
    when(
      () => sprints.teams(
        'o',
        'DevOps Mobile App',
        refresh: any(named: 'refresh'),
      ),
    ).thenAnswer(
      (_) async => const [
        SprintTeamRef(id: 'team-guid', name: 'Boardhop Team'),
      ],
    );
    when(() => sprints.teams('o', 'DevOps Mobile App')).thenAnswer(
      (_) async => const [
        SprintTeamRef(id: 'team-guid', name: 'Boardhop Team'),
      ],
    );
  }

  /// The page answers a write by reloading; `becomes` swaps the pull
  /// request the next `get` answers with.
  void becomes(PullRequest next) {
    pr = next;
    when(() => repo.get('o', next.id)).thenAnswer((_) async => next);
    when(() => repo.labels('o', any())).thenAnswer((_) async => next.labels);
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1200, 4800),
    double devicePixelRatio = 3,
    String? initialTab,
  }) async {
    stub();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    final client = AdoClient(
      tokenProvider: ({String? tenantId, String? accountId}) async => 'tok',
      dio: Dio()..httpClientAdapter = PrAdapter(changeEntries: changeEntries),
    );
    final auth = AuthBloc(PrAuth());
    addTearDown(auth.close);
    final authService = PrAuth();
    when(() => authService.accessToken(accountId: any(named: 'accountId')))
        .thenAnswer((_) async => 'tok');
    final router = GoRouter(
      initialLocation: '/a/u1/orgs/o/pull-requests/${pr.id}',
      routes: [
        GoRoute(
          path: '/a/u1/orgs/o/pull-requests/${pr.id}',
          builder: (_, _) => PullRequestDetailPage(
            org: 'o',
            id: pr.id,
            initialTab: initialTab,
          ),
          routes: [
            GoRoute(
              path: 'diff',
              builder: (context, _) => const Scaffold(body: Text('the diff')),
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
          RepositoryProvider<RepoRepository>.value(value: repos),
          RepositoryProvider<SprintRepository>.value(value: sprints),
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
  }
}
