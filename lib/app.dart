import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth/auth_bloc.dart';
import 'auth/auth_service.dart';
import 'core/http/ado_client.dart';
import 'data/db/app_database.dart';
import 'data/repositories/org_repository.dart';
import 'data/repositories/board_repository.dart';
import 'data/repositories/project_repository.dart';
import 'data/repositories/work_item_repository.dart';
import 'router.dart';
import 'theme/theme.dart';

/// Everything built once in `main` and shared through the widget tree.
class AppDependencies {
  AppDependencies({required this.auth, required this.client, required this.db})
    : orgs = OrgRepository(client, db),
      projects = ProjectRepository(client, db),
      workItems = WorkItemRepository(client, db) {
    boards = BoardRepository(client, workItems);
  }

  final AuthService auth;
  final AdoClient client;
  final AppDatabase db;
  final OrgRepository orgs;
  final ProjectRepository projects;
  final WorkItemRepository workItems;
  late final BoardRepository boards;
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

  // Built once; the master theme is not rebuilt on mode changes, only the
  // `themeMode` switch flips between the two.
  final _light = BoardhopTheme.light();
  final _dark = BoardhopTheme.dark();

  @override
  void dispose() {
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
