import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth/auth_bloc.dart';
import 'features/activity/activity_page.dart';
import 'features/auth/sign_in_page.dart';
import 'features/boards/boards_page.dart';
import 'features/diagnostics/diagnostics_page.dart';
import 'features/diagnostics/board_probe/board_probe_page.dart';
import 'features/diagnostics/editor_probe_page.dart';
import 'features/orgs/org_picker_page.dart';
import 'features/pipelines/pipelines_page.dart';
import 'features/projects/project_list_page.dart';
import 'features/pull_requests/pull_requests_page.dart';
import 'features/settings/settings_page.dart';
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
        path: '/orgs',
        builder: (_, _) => const OrgPickerPage(),
        routes: [
          GoRoute(
            path: ':org/projects',
            builder: (_, state) =>
                ProjectListPage(org: state.pathParameters['org']!),
            routes: [
              GoRoute(
                path: ':project/work-items',
                builder: (_, state) => WorkItemsPage(
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                ),
              ),
              GoRoute(
                path: ':project/boards',
                builder: (_, state) => BoardsPage(
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                ),
              ),
              GoRoute(
                path: ':project/pipelines',
                builder: (_, state) => PipelinesPage(
                  org: state.pathParameters['org']!,
                  project: state.pathParameters['project']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: ':org/pull-requests',
            builder: (_, state) =>
                PullRequestsPage(org: state.pathParameters['org']!),
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
