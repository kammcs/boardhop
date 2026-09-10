import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/auth_service.dart';
import 'core/http/ado_client.dart';
import 'data/db/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final auth = await AuthService.create();
  final db = AppDatabase();
  final client = AdoClient(tokenProvider: auth.accessToken);

  runApp(
    BoardhopApp(
      deps: AppDependencies(auth: auth, client: client, db: db),
    ),
  );
}
