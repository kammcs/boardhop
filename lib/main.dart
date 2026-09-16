import 'package:dio/dio.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'auth/auth_service.dart';
import 'core/config/app_config.dart';
import 'core/http/ado_client.dart';
import 'core/notifications/notification_service.dart';
import 'data/db/app_database.dart';
import 'demo/demo_account.dart';
import 'demo/demo_activity.dart';
import 'demo/demo_fixtures.dart';
import 'features/notifications/push_background.dart';
import 'features/notifications/push_service.dart';
import 'startup_failure.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Theme first: it must be ready before the first frame.
  final theme = await ThemeController.load();
  if (AppConfig.demoMode) await loadDemoLaunchRoute();
  final AuthService auth;
  try {
    auth = AppConfig.demoMode
        ? AuthService.demo(demoAccount())
        : await AuthService.create();
  } catch (e) {
    // A build whose MSAL redirect does not match its signing certificate
    // fails here; say so instead of sitting on the launch screen.
    runApp(StartupFailureApp(error: e));
    return;
  }
  if (AppConfig.demoMode) await prepareDemoNotifications();
  final notifications = await NotificationService.create();
  final push = await PushService.create();
  // Android's relay messages are data-only, so nothing is shown unless the app
  // shows it. This is the background and terminated half (research/14 §3.3);
  // the foreground half is PushCoordinator.
  await registerPushBackgroundHandler();
  // Demo mode keeps its invented data out of the real cache and never
  // touches the network (lib/demo).
  final db = AppConfig.demoMode
      ? AppDatabase(driftDatabase(name: 'boardhop_demo'))
      : AppDatabase();
  final client = AdoClient(
    tokenProvider: auth.accessToken,
    onUnauthorized: auth.resolveChallenge,
    dio: AppConfig.demoMode
        ? (Dio()
            ..httpClientAdapter = buildDemoBackend(
              projectPicture: (await rootBundle.load('assets/brand/logo.png'))
                  .buffer
                  .asUint8List(),
            ))
        : null,
  );

  final deps = AppDependencies(
    auth: auth,
    client: client,
    db: db,
    notifications: notifications,
    push: push,
  );
  if (AppConfig.demoMode) {
    await seedDemoActivity(deps.forAccount(demoAccount().id).activity);
  }

  runApp(BoardhopApp(deps: deps, theme: theme));
}
