import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth/auth_bloc.dart';
import 'auth/auth_service.dart';
import 'core/http/ado_client.dart';
import 'core/notifications/notification_service.dart';
import 'data/activity_sync.dart';
import 'data/avatar_store.dart';
import 'data/db/app_database.dart';
import 'data/db/json_cache.dart';
import 'data/repositories/account_repository.dart';
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

/// Repositories bound to one signed-in account: every request carries that
/// account's token, personal caches (PR inbox, my work items, the activity
/// feed, the account header) live in that account's namespace, and the
/// background sync watches that account's last-opened organization.
class AccountDeps {
  AccountDeps(AppDependencies root, this.accountId)
    : client = root.client.bound(accountId),
      db = root.db {
    avatars = AvatarStore(client);
    orgs = OrgRepository(client, db, userId: accountId);
    projects = ProjectRepository(client, db);
    workItems = WorkItemRepository(client, db, userId: accountId);
    pullRequests = PullRequestRepository(client, db, accountId);
    pipelines = PipelineRepository(client, db, accountId);
    boards = BoardRepository(client, workItems);
    queue = WriteQueue(db, workItems, userId: accountId);
    activity = ActivityRepository(
      client,
      db,
      pullRequests,
      pipelines,
      userId: accountId,
    );
    account = AccountRepository(
      root.auth,
      orgs,
      avatars,
      db: db,
      userId: accountId,
    );
    activitySync = ActivitySync(
      activity: activity,
      orgs: orgs,
      pullRequests: pullRequests,
      notifications: root.notifications,
      db: db,
      userId: accountId,
    );
  }

  final String accountId;
  final AdoClient client;
  final AppDatabase db;
  late final AvatarStore avatars;
  late final OrgRepository orgs;
  late final ProjectRepository projects;
  late final WorkItemRepository workItems;
  late final PullRequestRepository pullRequests;
  late final PipelineRepository pipelines;
  late final BoardRepository boards;
  late final WriteQueue queue;
  late final ActivityRepository activity;
  late final AccountRepository account;
  late final ActivitySync activitySync;

  /// What the pages under `/a/{account}` read from the context.
  List<RepositoryProvider<Object>> get providers => [
    RepositoryProvider<AdoClient>.value(value: client),
    RepositoryProvider<OrgRepository>.value(value: orgs),
    RepositoryProvider<ProjectRepository>.value(value: projects),
    RepositoryProvider<WorkItemRepository>.value(value: workItems),
    RepositoryProvider<BoardRepository>.value(value: boards),
    RepositoryProvider<WriteQueue>.value(value: queue),
    RepositoryProvider<PullRequestRepository>.value(value: pullRequests),
    RepositoryProvider<PipelineRepository>.value(value: pipelines),
    RepositoryProvider<ActivityRepository>.value(value: activity),
    RepositoryProvider<ActivitySync>.value(value: activitySync),
    RepositoryProvider<AvatarStore>.value(value: avatars),
    RepositoryProvider<AccountRepository>.value(value: account),
  ];
}

/// Everything built once in `main` and shared through the widget tree, plus
/// the per-account bundles created on demand.
class AppDependencies {
  AppDependencies({
    required this.auth,
    required this.client,
    required this.db,
    required this.notifications,
  });

  final AuthService auth;
  final AdoClient client;
  final AppDatabase db;
  final NotificationService notifications;

  final Map<String, AccountDeps> _accounts = {};

  Iterable<AccountDeps> get boundAccounts => _accounts.values;

  AccountDeps forAccount(String accountId) =>
      _accounts.putIfAbsent(accountId, () => AccountDeps(this, accountId));

  /// Sign-out of one account: stop its sync and drop everything cached for
  /// it. Organizations, projects and work items that another signed-in
  /// account also reaches stay; the rest go with the account.
  Future<void> removeAccount(String accountId) async {
    final deps = _accounts.remove(accountId);
    deps?.activitySync.stop();
    final others = <String>{};
    for (final row in await db.select(db.organizations).get()) {
      if (row.userId != accountId) others.add(row.name);
    }
    final mine = <String>[
      for (final row in await (db.select(
        db.organizations,
      )..where((t) => t.userId.equals(accountId))).get())
        if (!others.contains(row.name)) row.name,
    ];
    await db.transaction(() async {
      await (db.delete(
        db.organizations,
      )..where((t) => t.userId.equals(accountId))).go();
      await (db.delete(
        db.pendingWrites,
      )..where((t) => t.userId.equals(accountId))).go();
      await (db.delete(db.workItemListEntries)..where(
            (t) => t.listKey.like(
              '${WorkItemRepository.listPrefixFor(accountId)}%',
            ),
          ))
          .go();
      await JsonCache.deleteNamespace(db, accountId);
      if (mine.isNotEmpty) {
        await (db.delete(db.projects)..where((t) => t.orgName.isIn(mine))).go();
        await (db.delete(
          db.workItems,
        )..where((t) => t.orgName.isIn(mine))).go();
        await (db.delete(
          db.workItemListEntries,
        )..where((t) => t.orgName.isIn(mine))).go();
      }
    });
    if (_accounts.isEmpty) {
      await (deps?.avatars ?? AvatarStore(client)).clear();
    }
  }
}

class BoardhopApp extends StatefulWidget {
  const BoardhopApp({super.key, required this.deps, required this.theme});

  final AppDependencies deps;
  final ThemeController theme;

  @override
  State<BoardhopApp> createState() => _BoardhopAppState();
}

class _BoardhopAppState extends State<BoardhopApp> {
  late final AuthBloc _authBloc = AuthBloc(
    widget.deps.auth,
    onAccountRemoved: widget.deps.removeAccount,
  )..add(const AuthStarted());
  late final _router = buildRouter(_authBloc, widget.deps);
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
    // Background polling for every signed-in account, and only for those.
    _auth = _authBloc.stream.listen((state) {
      if (state is AuthSignedIn) {
        final ids = {for (final a in state.accounts) a.id};
        for (final bound in deps.boundAccounts.toList()) {
          if (!ids.contains(bound.accountId)) bound.activitySync.stop();
        }
        for (final id in ids) {
          deps.forAccount(id).activitySync.start();
        }
      } else if (state is AuthSignedOut) {
        for (final bound in deps.boundAccounts.toList()) {
          bound.activitySync.stop();
        }
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
    for (final bound in widget.deps.boundAccounts) {
      bound.activitySync.stop();
    }
    _authBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deps = widget.deps;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: deps),
        RepositoryProvider.value(value: deps.auth),
        RepositoryProvider.value(value: deps.client),
        RepositoryProvider.value(value: deps.db),
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
