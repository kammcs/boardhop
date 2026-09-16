import 'dart:io';

import 'package:msal_auth/msal_auth.dart' show Account;
import 'package:path_provider/path_provider.dart';

import '../core/routes.dart';
import 'demo_world.dart';

/// The signed-in account demo mode pretends to have.
Account demoAccount() => Account(
  id: DemoWorld.me.id,
  username: DemoWorld.me.email,
  name: DemoWorld.me.name,
);

/// Where a demo launch should go once signed in, for scripted screenshots:
/// a path below the organization (`projects/Boardhop/boards`), from the
/// `BOARDHOP_DEMO_ROUTE` define, the environment variable of the same name
/// (`SIMCTL_CHILD_BOARDHOP_DEMO_ROUTE` for `simctl launch`), or the file
/// `Documents/boardhop_demo_route` in the app's container, which
/// `tool/demo-shots.sh` writes before each launch. Null for the ordinary
/// launch. Read once in `main`, before the router exists.
Future<String?> loadDemoLaunchRoute() async {
  const defined = String.fromEnvironment('BOARDHOP_DEMO_ROUTE');
  var value = defined.isNotEmpty
      ? defined
      : Platform.environment['BOARDHOP_DEMO_ROUTE'];
  if (value == null || value.isEmpty) {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/boardhop_demo_route');
      if (await file.exists()) value = (await file.readAsString()).trim();
    } on Exception {
      value = null;
    }
  }
  if (value == null || value.isEmpty) return demoLaunchRoute = null;
  final base = Routes.org(DemoWorld.me.id, DemoWorld.org);
  return demoLaunchRoute = value.startsWith('/') ? value : '$base/$value';
}

/// What [loadDemoLaunchRoute] found.
String? demoLaunchRoute;
