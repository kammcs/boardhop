import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'app.dart';
import 'auth/auth_bloc.dart';
import 'data/models/git_repository.dart';
import 'data/repositories/pipeline_repository.dart' show CachedList;
import 'data/repositories/repo_repository.dart';
import 'features/activity/activity_page.dart';
import 'features/auth/sign_in_page.dart';
import 'features/boards/boards_page.dart';
import 'features/diagnostics/diagnostics_page.dart';
import 'features/diagnostics/diff_probe/diff_probe_page.dart';
import 'features/diagnostics/board_probe/board_probe_page.dart';
import 'features/diagnostics/editor_probe_page.dart';
import 'features/orgs/org_picker_page.dart';
import 'features/pipelines/pipeline_log_page.dart';
import 'features/pipelines/pipeline_run_page.dart';
import 'features/pipelines/pipelines_page.dart';
import 'features/projects/project_home_page.dart';
import 'features/projects/project_list_page.dart';
import 'features/projects/project_shell.dart';
import 'features/pull_requests/pr_file_diff_page.dart';
import 'features/pull_requests/pull_request_detail_page.dart';
import 'features/pull_requests/pull_requests_page.dart';
import 'features/repos/branch_picker_page.dart';
import 'features/repos/repo_page.dart';
import 'features/repos/repos_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shared/account_scope.dart';
import 'features/shared/feature_placeholder_page.dart';
import 'features/shared/splash_page.dart';
import 'features/work_items/work_item_detail_page.dart';
import 'features/work_items/work_item_edit_page.dart';
import 'features/work_items/work_items_page.dart';

/// `/orgs` lists every signed-in account with its organizations; everything
/// below an organization lives under `/a/{account}/orgs/{org}` so the pages
/// act as that account (see `Routes`).
GoRouter buildRouter(AuthBloc auth, AppDependencies deps) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _StreamListenable(auth.stream),
    redirect: (context, state) {
      final s = auth.state;
      final atSignIn = state.matchedLocation == '/sign-in';
      final atSplash = state.matchedLocation == '/';
      return switch (s) {
        AuthUnknown() => atSplash ? null : '/',
        AuthBusy() => null,
        AuthSignedOut() => atSignIn ? null : '/sign-in',
        AuthSignedIn() => (atSignIn || atSplash) ? '/orgs' : null,
      };
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashPage()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInPage()),
      GoRoute(path: '/diagnostics', builder: (_, _) => const DiagnosticsPage()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(
        path: '/diagnostics/editor',
        builder: (_, _) => const EditorProbePage(),
      ),
      GoRoute(
        path: '/diagnostics/board',
        builder: (_, _) => const BoardProbePage(),
      ),
      GoRoute(
        path: '/diagnostics/diff',
        builder: (_, _) => const DiffProbePage(),
      ),
      GoRoute(path: '/orgs', builder: (_, _) => const OrgPickerPage()),
      ShellRoute(
        builder: (context, state, child) {
          final accountId = state.pathParameters['account']!;
          return MultiRepositoryProvider(
            providers: deps.forAccount(accountId).providers,
            child: AccountScope(accountId: accountId, child: child),
          );
        },
        routes: [
          GoRoute(
            path: '/a/:account/orgs/:org/projects',
            builder: (_, state) =>
                ProjectListPage(org: state.pathParameters['org']!),
            routes: [
              StatefulShellRoute.indexedStack(
                builder: (context, state, shell) => ProjectShell(
                  shell: shell,
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                ),
                branches: [
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: ':project/home',
                        builder: (_, state) => ProjectHomePage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                        ),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: ':project/work-items',
                        builder: (_, state) => WorkItemsPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                        ),
                        routes: [
                          GoRoute(
                            path: ':id',
                            builder: (_, state) => WorkItemDetailPage(
                              org: state.pathParameters['org']!,
                              project: state.pathParameters['project']!,
                              id: int.parse(state.pathParameters['id']!),
                            ),
                            routes: [
                              GoRoute(
                                path: 'edit',
                                builder: (_, state) => WorkItemEditPage(
                                  org: state.pathParameters['org']!,
                                  project: state.pathParameters['project']!,
                                  id: int.parse(state.pathParameters['id']!),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      GoRoute(
                        path: ':project/boards',
                        builder: (_, state) => BoardsPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                        ),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: ':project/repos',
                        builder: (_, state) => ReposPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                        ),
                        routes: [
                          GoRoute(
                            path: ':repo',
                            builder: (_, state) => RepoPage(
                              org: state.pathParameters['org']!,
                              project: state.pathParameters['project']!,
                              repoName: state.pathParameters['repo']!,
                            ),
                            routes: [
                              GoRoute(
                                path: 'branches',
                                builder: (_, state) => _BranchPickerRoute(
                                  org: state.pathParameters['org']!,
                                  project: state.pathParameters['project']!,
                                  repoName: state.pathParameters['repo']!,
                                  current: state.uri.queryParameters['current'],
                                ),
                              ),
                              GoRoute(
                                path: 'code',
                                builder: (_, state) =>
                                    const FeaturePlaceholderPage(
                                      title: 'Code',
                                      plannedIn: 'phase 2 of the repos plan',
                                    ),
                              ),
                              GoRoute(
                                path: 'commits',
                                builder: (_, state) =>
                                    const FeaturePlaceholderPage(
                                      title: 'Commits',
                                      plannedIn: 'phase 3 of the repos plan',
                                    ),
                              ),
                              GoRoute(
                                path: 'search',
                                builder: (_, state) =>
                                    const FeaturePlaceholderPage(
                                      title: 'Code search',
                                      plannedIn: 'phase 4 of the repos plan',
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: ':project/pipelines',
                        builder: (_, state) => PipelinesPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'runs/:id',
                            builder: (_, state) => PipelineRunPage(
                              org: state.pathParameters['org']!,
                              project: state.pathParameters['project']!,
                              id: int.parse(state.pathParameters['id']!),
                            ),
                            routes: [
                              GoRoute(
                                path: 'logs/:logId',
                                builder: (_, state) => PipelineLogPage(
                                  org: state.pathParameters['org']!,
                                  project: state.pathParameters['project']!,
                                  buildId: int.parse(
                                    state.pathParameters['id']!,
                                  ),
                                  logId: int.parse(
                                    state.pathParameters['logId']!,
                                  ),
                                  title: state.uri.queryParameters['name'],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              GoRoute(
                path: ':project/pull-requests',
                builder: (_, state) => PullRequestsPage(
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                  repositoryId: state.uri.queryParameters['repoId'],
                  repositoryName: state.uri.queryParameters['repo'],
                ),
              ),
            ],
          ),
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
                      iteration: int.tryParse(
                        state.uri.queryParameters['iteration'] ?? '',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/a/:account/orgs/:org/activity',
            builder: (_, state) =>
                ActivityPage(org: state.pathParameters['org']!),
          ),
        ],
      ),
    ],
  );
}

/// The branch picker needs the repository id, which only the cached list
/// knows; resolve the name first.
class _BranchPickerRoute extends StatelessWidget {
  const _BranchPickerRoute({
    required this.org,
    required this.project,
    required this.repoName,
    this.current,
  });

  final String org;
  final String project;
  final String repoName;
  final String? current;

  @override
  Widget build(BuildContext context) {
    final repos = context.read<RepoRepository>();
    return FutureBuilder<CachedList<GitRepository>?>(
      future: repos.cachedList(org, project),
      builder: (context, snapshot) {
        GitRepository? repo;
        for (final r in snapshot.data?.items ?? const <GitRepository>[]) {
          if (r.name == repoName) repo = r;
        }
        if (repo == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return BranchPickerPage(
          org: org,
          project: project,
          repoId: repo.id,
          repoName: repo.name,
          current: current,
          defaultBranch: repo.defaultBranchName,
        );
      },
    );
  }
}

/// Lets go_router re-evaluate redirects whenever the auth bloc emits.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
