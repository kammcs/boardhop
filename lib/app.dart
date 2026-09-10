import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth/auth_bloc.dart';
import 'auth/auth_service.dart';
import 'core/http/ado_client.dart';
import 'core/notifications/notification_service.dart';
import 'data/activity_sync.dart';
import 'data/db/app_database.dart';
import 'data/repositories/activity_repository.dart';
import 'data/repositories/org_repository.dart';
import 'data/repositories/board_repository.dart';
import 'data/repositories/pipeline_repository.dart';
import 'data/repositories/project_repository.dart';
import 'data/repositories/pull_request_repository.dart';
import 'data/repositories/work_item_repository.dart';
import 'data/write_queue.dart';
import 'router.dart';
import 'theme/theme.dart';

/// Everything built once in `main` and shared through the widget tree.
class AppDependencies {
  AppDependencies({
    required this.auth,
    required this.client,
    required this.db,
    required this.notifications,
  }) : orgs = OrgRepository(client, db),
       projects = ProjectRepository(client, db),
       workItems = WorkItemRepository(client, db),
       pullRequests = PullRequestRepository(client, db),
       pipelines = PipelineRepository(client, db) {
    boards = BoardRepository(client, workItems);
    queue = WriteQueue(db, workItems);
    activity = ActivityRepository(client, db, pullRequests, pipelines);
    activitySync = ActivitySync(
      activity: activity,
      orgs: orgs,
      pullRequests: pullRequests,
      notifications: notifications,
      db: db,
    );
  }

  final AuthService auth;
  final AdoClient client;
  final AppDatabase db;
  final NotificationService notifications;
  final OrgRepository orgs;
  final ProjectRepository projects;
  final WorkItemRepository workItems;
  final PullRequestRepository pullRequests;
  final PipelineRepository pipelines;
  late final BoardRepository boards;
  late final WriteQueue queue;
  late final ActivityRepository activity;
  late final ActivitySync activitySync;
}

class BoardhopApp extends StatefulWidget {
  const BoardhopApp({super.key, required this.deps, required this.theme});

  final AppDependencies deps;
  final ThemeController theme;

  @override
  State<BoardhopApp> createState() => _BoardhopAppState();
}

class _BoardhopAppState extends State<BoardhopApp> {
  late final AuthBloc _authBloc = AuthBloc(widget.deps.auth)
    ..add(const AuthStarted());
  late final _router = buildRouter(_authBloc);
  StreamSubscription<String>? _taps;
  StreamSubscription<AuthState>? _auth;

  // Built once; the master theme is not rebuilt on mode changes, only the
  // `themeMode` switch flips between the two.
  final _light = BoardhopTheme.light();
  final _dark = BoardhopTheme.dark();

  @override
  void initState() {
    super.initState();
    final deps = widget.deps;
    // Notification taps open their item; a cold-start tap waits for the
    // first frame so the router exists.
    _taps = deps.notifications.taps.listen(_openRoute);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launch = deps.notifications.takeLaunchRoute();
      if (launch != null) _openRoute(launch);
    });
    // Background polling only while signed in.
    _auth = _authBloc.stream.listen((state) {
      if (state is AuthSignedIn) {
        deps.activitySync.start();
      } else if (state is AuthSignedOut) {
        deps.activitySync.stop();
      }
    });
  }

  void _openRoute(String route) {
    if (!mounted || route.isEmpty) return;
    _router.push(route);
  }

  @override
  void dispose() {
    _taps?.cancel();
    _auth?.cancel();
    widget.deps.activitySync.stop();
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = widget.deps;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: deps.auth),
        RepositoryProvider.value(value: deps.client),
        RepositoryProvider.value(value: deps.db),
        RepositoryProvider.value(value: deps.orgs),
        RepositoryProvider.value(value: deps.projects),
        RepositoryProvider.value(value: deps.workItems),
        RepositoryProvider.value(value: deps.boards),
        RepositoryProvider.value(value: deps.queue),
        RepositoryProvider.value(value: deps.pullRequests),
        RepositoryProvider.value(value: deps.pipelines),
        RepositoryProvider.value(value: deps.activity),
        RepositoryProvider.value(value: deps.activitySync),
        RepositoryProvider.value(value: deps.notifications),
      ],
      child: BlocProvider.value(
        value: _authBloc,
        child: ThemeScope(
          controller: widget.theme,
          child: Builder(
            builder: (context) => MaterialApp.router(
              title: 'Boardhop',
              theme: _light,
              darkTheme: _dark,
              themeMode: ThemeScope.of(context).mode,
              routerConfig: _router,
            ),
          ),
        ),
      ),
    );
  }
}
