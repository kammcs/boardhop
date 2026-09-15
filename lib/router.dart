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
import 'features/dashboards/chart_focus_page.dart';
import 'features/dashboards/dashboard_page.dart';
import 'features/dashboards/widgets/chart_card.dart';
import 'features/diagnostics/dashboard_probe/dashboard_probe_page.dart';
import 'features/diagnostics/diagnostics_page.dart';
import 'features/diagnostics/diff_probe/diff_probe_page.dart';
import 'features/diagnostics/board_probe/board_probe_page.dart';
import 'features/diagnostics/editor_probe_page.dart';
import 'features/diagnostics/mention_probe_page.dart';
import 'features/diagnostics/sprint_probe/sprint_probe_page.dart';
import 'features/diagnostics/wiki_probe/wiki_probe_page.dart';
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
import 'features/repos/file_edit_page.dart';
import 'features/repos/file_page.dart';
import 'features/repos/repo_page.dart';
import 'features/repos/repos_page.dart';
import 'features/search/search_page.dart';
import 'features/sprints/sprint_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shared/account_scope.dart';
import 'features/shared/splash_page.dart';
import 'features/wiki/wiki_page_page.dart';
import 'features/wiki/wiki_tree_page.dart';
import 'features/work_items/form/work_item_form_page.dart';
import 'features/work_items/work_item_detail_page.dart';
import 'features/work_items/work_items_page.dart';
import 'core/config/app_config.dart';

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
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      // Local testing only: no route at all in a store build, so nothing
      // (a stale deep link, a typed URL) can open the probes there.
      if (AppConfig.diagnosticsEnabled) ...[
        GoRoute(
          path: '/diagnostics',
          builder: (_, _) => const DiagnosticsPage(),
        ),
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
        GoRoute(
          path: '/diagnostics/mention',
          builder: (_, _) => const MentionProbePage(),
        ),
        GoRoute(
          path: '/diagnostics/sprint',
          builder: (_, _) => const SprintProbePage(),
        ),
        GoRoute(
          path: '/diagnostics/dashboard',
          builder: (_, _) => const DashboardProbePage(),
        ),
        GoRoute(
          path: '/diagnostics/wiki',
          builder: (_, _) => const WikiProbePage(),
        ),
      ],
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
              // Every branch route carries :account/:org/:project, which
              // go_router's debug checks reject as a branch default. The
              // placeholder initialLocations satisfy the checks and are
              // never navigated to: ProjectShell always goes to concrete
              // paths (also when re-tapping the current tab).
              StatefulShellRoute.indexedStack(
                builder: (context, state, shell) => ProjectShell(
                  shell: shell,
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                  location: state.uri.path,
                ),
                branches: [
                  StatefulShellBranch(
                    initialLocation: '$_branchPlaceholder/home',
                    routes: [
                      GoRoute(
                        path: ':project/home',
                        builder: (_, state) => ProjectHomePage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                        ),
                      ),
                      // The Dashboards view is the Home tab's second
                      // segment (research/19 D5/D8), so it lives in the
                      // Home branch beside Summary and search and keeps
                      // the shell's dock. `dashboard` unset means the one
                      // last opened, or the default team's Overview.
                      GoRoute(
                        path: ':project/dashboards',
                        builder: (_, state) => DashboardPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                          dashboardId: state.uri.queryParameters['dashboard'],
                        ),
                      ),
                      // The Wiki view is the Home tab's third segment
                      // (research/20 §4.3), so it lives in the Home branch
                      // beside Summary and Dashboards and keeps the shell's
                      // dock. `wiki` unset means the one last opened, or
                      // the project wiki; `path` is the tree's expansion
                      // and, on a tablet, the pane's page (K6).
                      GoRoute(
                        path: ':project/wiki',
                        builder: (_, state) => WikiTreePage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                          wikiIdOrName: state.uri.queryParameters['wiki'],
                          path: state.uri.queryParameters['path'],
                        ),
                      ),
                      // Search lives in the Home branch, which is where it
                      // is opened from, so it keeps the shell's dock and
                      // its paddings (research/15 §4). `kind` unset is the
                      // grouped view; set, the See-all list of that kind.
                      GoRoute(
                        path: ':project/search',
                        builder: (_, state) => SearchPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                          initialQuery: state.uri.queryParameters['q'],
                          scope: SearchScope.fromWire(
                            state.uri.queryParameters['scope'],
                          ),
                          kind: SearchKind.fromWire(
                            state.uri.queryParameters['kind'],
                          ),
                        ),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    initialLocation: '$_branchPlaceholder/work-items',
                    routes: [
                      GoRoute(
                        path: ':project/work-items',
                        builder: (_, state) => WorkItemsPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                          // A dashboard's query card opens its query here
                          // (research/19 D7).
                          initialQueryId: state.uri.queryParameters['query'],
                          initialQueryName:
                              state.uri.queryParameters['queryName'],
                        ),
                        routes: [
                          // Before ':id': go_router matches in order and
                          // "new" is not an id.
                          GoRoute(
                            path: 'new',
                            builder: (_, state) {
                              final query = state.uri.queryParameters;
                              return WorkItemFormPage(
                                org: state.pathParameters['org']!,
                                project: state.pathParameters['project']!,
                                typeName: query['type'] ?? 'Task',
                                teamId: query['team'],
                                stateName: query['state'],
                                lane: query['lane'],
                                laneField: query['laneField'],
                                parentId: int.tryParse(query['parent'] ?? ''),
                                relation: query['rel'],
                                templateId: query['template'],
                                resumeDraft: query['draft'] == '1',
                              );
                            },
                          ),
                          GoRoute(
                            path: ':id',
                            // `?comment={id}` from a pushed comment
                            // notification (research/14 §4.2), and
                            // `?tab=details|related|comments` to open one
                            // of the three tabs straight away.
                            builder: (_, state) => WorkItemDetailPage(
                              org: state.pathParameters['org']!,
                              project: state.pathParameters['project']!,
                              id: int.parse(state.pathParameters['id']!),
                              initialTab: state.uri.queryParameters['tab'],
                              initialCommentId: int.tryParse(
                                state.uri.queryParameters['comment'] ?? '',
                              ),
                            ),
                            routes: [
                              // The full form in edit mode; the detail
                              // page shows the same box as a dialog from
                              // medium up, so this route is the phone push
                              // and the deep link.
                              GoRoute(
                                path: 'edit',
                                builder: (_, state) => WorkItemFormPage.edit(
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
                      // The third Work view (decision S1), a sibling of
                      // the board so the pill's three views share the
                      // branch navigator and its back stack. `iteration`
                      // is a team iteration GUID and is absent for the
                      // current sprint; `tab` is backlog | taskboard |
                      // burndown.
                      GoRoute(
                        path: ':project/sprint',
                        builder: (_, state) => SprintPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                          iteration: state.uri.queryParameters['iteration'],
                          initialTab: state.uri.queryParameters['tab'],
                        ),
                      ),
                    ],
                  ),
                  StatefulShellBranch(
                    initialLocation: '$_branchPlaceholder/repos',
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
                                path: 'edit',
                                builder: (_, state) => _RepoRoute(
                                  state: state,
                                  builder: (repo) => FileEditPage(
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
                    initialLocation: '$_branchPlaceholder/pipelines',
                    routes: [
                      GoRoute(
                        path: ':project/pipelines',
                        // `?tab=approvals&approval={id}&run={runId}` from a
                        // pushed approval notification (research/14 §4.2).
                        builder: (_, state) => PipelinesPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                          initialTab: state.uri.queryParameters['tab'],
                          initialApprovalId:
                              state.uri.queryParameters['approval'],
                          initialRunId: state.uri.queryParameters['run'],
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
              // Outside the tab shell on purpose: a push that starts from
              // a page which is already over the shell (the pull request
              // detail page, its file diff) cannot add a second copy of
              // the shell's page to the same navigator. `Routes
              // .workItemStandalone` is the only thing that builds this
              // location; everything inside the shell keeps using the
              // branch route below, dock and all.
              // The dashboard's chart focus view (research/19 D7), over
              // the shell for the same reason: the card that pushes it is
              // inside the shell's Home branch. The chart it drew rides
              // along in `extra`; a cold open finds the widget on the
              // cached dashboard instead.
              GoRoute(
                path: ':project/chart/:widget',
                builder: (_, state) => ChartFocusPage(
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                  widgetId: state.pathParameters['widget']!,
                  dashboardId: state.uri.queryParameters['dashboard'],
                  initial: state.extra is ChartFocusArgs
                      ? state.extra! as ChartFocusArgs
                      : null,
                ),
              ),
              // One wiki page, over the shell like the chart focus view and
              // for the same reason: the reader pushes another reader on a
              // wiki link, and two pages with one shell key is an assert.
              GoRoute(
                path: ':project/wiki-page/:wiki',
                builder: (_, state) => WikiPagePage(
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                  wikiIdOrName: state.pathParameters['wiki']!,
                  path: state.uri.queryParameters['path'],
                  id: int.tryParse(state.uri.queryParameters['id'] ?? ''),
                  version: state.uri.queryParameters['version'],
                  anchor: state.uri.queryParameters['anchor'],
                ),
              ),
              GoRoute(
                path: ':project/work-item/:id',
                builder: (_, state) => WorkItemDetailPage(
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                  id: int.parse(state.pathParameters['id']!),
                  initialTab: state.uri.queryParameters['tab'],
                  initialCommentId: int.tryParse(
                    state.uri.queryParameters['comment'] ?? '',
                  ),
                ),
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
                // `?tab=comments|files` and `?thread={id}` from a pushed
                // pull request notification (research/14 §4.2).
                builder: (_, state) => PullRequestDetailPage(
                  org: state.pathParameters['org']!,
                  id: int.parse(state.pathParameters['id']!),
                  initialTab: state.uri.queryParameters['tab'],
                  initialThreadId: int.tryParse(
                    state.uri.queryParameters['thread'] ?? '',
                  ),
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

/// Placeholder project path for the tab shell's `initialLocation`s; see the
/// comment on the `StatefulShellRoute` in `buildRouter`.
const _branchPlaceholder = '/a/-/orgs/-/projects/-';

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
