import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'auth/auth_bloc.dart';
import 'auth/auth_service.dart';
import 'core/http/ado_client.dart';
import 'data/db/app_database.dart';
import 'data/repositories/org_repository.dart';
import 'data/repositories/project_repository.dart';
import 'router.dart';

/// Everything built once in `main` and shared through the widget tree.
class AppDependencies {
  AppDependencies({required this.auth, required this.client, required this.db})
    : orgs = OrgRepository(client, db),
      projects = ProjectRepository(client, db);

  final AuthService auth;
  final AdoClient client;
  final AppDatabase db;
  final OrgRepository orgs;
  final ProjectRepository projects;
}

class BoardhopApp extends StatefulWidget {
  const BoardhopApp({super.key, required this.deps});

  final AppDependencies deps;

  @override
  State<BoardhopApp> createState() => _BoardhopAppState();
}

class _BoardhopAppState extends State<BoardhopApp> {
  late final AuthBloc _authBloc = AuthBloc(widget.deps.auth)
    ..add(const AuthStarted());
  late final _router = buildRouter(_authBloc);

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
      ],
      child: BlocProvider.value(
        value: _authBloc,
        child: MaterialApp.router(
          title: 'Boardhop',
          theme: ThemeData(
            colorSchemeSeed: const Color(0xFF0078D4),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF0078D4),
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          routerConfig: _router,
        ),
      ),
    );
  }
}
