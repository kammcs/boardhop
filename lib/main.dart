import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/auth_service.dart';
import 'core/http/ado_client.dart';
import 'core/notifications/notification_service.dart';
import 'data/db/app_database.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Theme first: it must be ready before the first frame.
  final theme = await ThemeController.load();
  final auth = await AuthService.create();
  final notifications = await NotificationService.create();
  final db = AppDatabase();
  final client = AdoClient(
    tokenProvider: auth.accessToken,
    onUnauthorized: auth.resolveChallenge,
  );

  runApp(
    BoardhopApp(
      deps: AppDependencies(
        auth: auth,
        client: client,
        db: db,
        notifications: notifications,
      ),
      theme: theme,
    ),
  );
}
