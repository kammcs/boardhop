import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth/auth_bloc.dart';
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
import 'features/projects/project_list_page.dart';
import 'features/projects/project_shell.dart';
import 'features/pull_requests/pr_file_diff_page.dart';
import 'features/pull_requests/pull_request_detail_page.dart';
import 'features/pull_requests/pull_requests_page.dart';
import 'features/settings/settings_page.dart';
import 'features/work_items/work_item_detail_page.dart';
import 'features/work_items/work_item_edit_page.dart';
import 'features/work_items/work_items_page.dart';

GoRouter buildRouter(AuthBloc auth) {
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
      GoRoute(
        path: '/',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
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
      GoRoute(
        path: '/orgs',
        builder: (_, _) => const OrgPickerPage(),
        routes: [
          GoRoute(
            path: ':org/projects',
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
                    ],
                  ),
                  StatefulShellBranch(
                    routes: [
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
                        path: ':project/pull-requests',
                        builder: (_, state) => PullRequestsPage(
                          org: state.pathParameters['org']!,
                          project: state.pathParameters['project']!,
                        ),
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
            ],
          ),
          GoRoute(
            path: ':org/pull-requests',
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
            path: ':org/activity',
            builder: (_, state) =>
                ActivityPage(org: state.pathParameters['org']!),
          ),
        ],
      ),
    ],
  );
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
