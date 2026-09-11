import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'app.dart';
import 'auth/auth_bloc.dart';
import 'data/models/git_repository.dart';
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
import 'features/repos/code_browser_page.dart';
import 'features/repos/code_search_page.dart';
import 'features/repos/commit_page.dart';
import 'features/repos/commits_page.dart';
import 'features/repos/compare_page.dart';
import 'features/repos/file_diff_page.dart';
import 'features/repos/file_page.dart';
import 'features/repos/repo_page.dart';
import 'features/repos/repos_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shared/account_scope.dart';
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
                        path: ':project/code-search',
                        builder: (_, state) => CodeSearchPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                          initialQuery: state.uri.queryParameters['q'],
                        ),
                      ),
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
                                builder: (_, state) => _RepoRoute(
                                  state: state,
                                  builder: (repo) => BranchPickerPage(
                                    org: state.pathParameters['org']!,
                                    project: state.pathParameters['project']!,
                                    repoId: repo.id,
                                    repoName: repo.name,
                                    current:
                                        state.uri.queryParameters['current'],
                                    defaultBranch: repo.defaultBranchName,
                                  ),
                                ),
                              ),
                              GoRoute(
                                path: 'code',
                                builder: (_, state) => _RepoRoute(
                                  state: state,
                                  builder: (repo) => CodeBrowserPage(
                                    org: state.pathParameters['org']!,
                                    project: state.pathParameters['project']!,
                                    repo: repo,
                                    ref: _refOf(state, repo),
                                    path:
                                        state.uri.queryParameters['path'] ??
                                        '/',
                                  ),
                                ),
                              ),
                              GoRoute(
                                path: 'file',
                                builder: (_, state) => _RepoRoute(
                                  state: state,
                                  builder: (repo) => FilePage(
                                    org: state.pathParameters['org']!,
                                    project: state.pathParameters['project']!,
                                    repo: repo,
                                    ref: _refOf(state, repo),
                                    path:
                                        state.uri.queryParameters['path'] ??
                                        '/',
                                    line: int.tryParse(
                                      state.uri.queryParameters['line'] ?? '',
                                    ),
                                    find: state.uri.queryParameters['find'],
                                  ),
                                ),
                              ),
                              GoRoute(
                                path: 'commits',
                                builder: (_, state) => _RepoRoute(
                                  state: state,
                                  builder: (repo) => CommitsPage(
                                    org: state.pathParameters['org']!,
                                    project: state.pathParameters['project']!,
                                    repo: repo,
                                    ref: _refOf(state, repo),
                                    path: state.uri.queryParameters['path'],
                                  ),
                                ),
                                routes: [
                                  GoRoute(
                                    path: ':id',
                                    builder: (_, state) => _RepoRoute(
                                      state: state,
                                      builder: (repo) => CommitPage(
                                        org: state.pathParameters['org']!,
                                        project:
                                            state.pathParameters['project']!,
                                        repo: repo,
                                        commitId: state.pathParameters['id']!,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              GoRoute(
                                path: 'diff',
                                builder: (_, state) => _RepoRoute(
                                  state: state,
                                  builder: (repo) => FileDiffPage(
                                    org: state.pathParameters['org']!,
                                    project: state.pathParameters['project']!,
                                    repo: repo,
                                    path:
                                        state.uri.queryParameters['path'] ??
                                        '/',
                                    oldRef:
                                        state.uri.queryParameters['old'] ?? '',
                                    newRef:
                                        state.uri.queryParameters['new'] ?? '',
                                    changeType:
                                        state.uri.queryParameters['change'] ??
                                        'edit',
                                    originalPath:
                                        state.uri.queryParameters['original'],
                                  ),
                                ),
                              ),
                              GoRoute(
                                path: 'compare',
                                builder: (_, state) => _RepoRoute(
                                  state: state,
                                  builder: (repo) => ComparePage(
                                    org: state.pathParameters['org']!,
                                    project: state.pathParameters['project']!,
                                    repo: repo,
                                    base:
                                        state.uri.queryParameters['base'] ??
                                        repo.defaultBranchName ??
                                        '',
                                    target: _refOf(state, repo),
                                  ),
                                ),
                              ),
                              GoRoute(
                                path: 'search',
                                builder: (_, state) => CodeSearchPage(
                                  org: state.pathParameters['org']!,
                                  project: state.pathParameters['project']!,
                                  repoName: state.pathParameters['repo']!,
                                  initialQuery: state.uri.queryParameters['q'],
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

/// Branch the query names, else the repository's default branch.
String _refOf(GoRouterState state, GitRepository repo) {
  final ref = state.uri.queryParameters['ref'];
  return ref == null || ref.isEmpty ? repo.defaultBranchName ?? '' : ref;
}

/// Pages under `repos/:repo` need the repository object (id, default
/// branch, web URL), which the route only names; resolve it from the cached
/// list, or the network on a cold deep link.
class _RepoRoute extends StatefulWidget {
  const _RepoRoute({required this.state, required this.builder});

  final GoRouterState state;
  final Widget Function(GitRepository repo) builder;

  @override
  State<_RepoRoute> createState() => _RepoRouteState();
}

class _RepoRouteState extends State<_RepoRoute> {
  late final Future<GitRepository?> _repo = _resolve();

  Future<GitRepository?> _resolve() async {
    final repos = context.read<RepoRepository>();
    final org = widget.state.pathParameters['org']!;
    final project = widget.state.pathParameters['project']!;
    final name = widget.state.pathParameters['repo']!;
    final cached = await repos.cachedList(org, project);
    for (final r in cached?.items ?? const <GitRepository>[]) {
      if (r.name == name) return r;
    }
    for (final r in await repos.list(org, project)) {
      if (r.name == name) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GitRepository?>(
      future: _repo,
      builder: (context, snapshot) {
        final repo = snapshot.data;
        if (repo != null) return widget.builder(repo);
        final name = widget.state.pathParameters['repo']!;
        return Scaffold(
          appBar: AppBar(title: Text(name)),
          body: Center(
            child: snapshot.hasError
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  )
                : snapshot.connectionState == ConnectionState.done
                ? Text('Repository "$name" not found.')
                : const CircularProgressIndicator(),
          ),
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
