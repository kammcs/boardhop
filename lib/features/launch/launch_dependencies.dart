import '../../app.dart';
import 'launch_resolver.dart';

/// The launch resolver as the running app builds it: per-account
/// repositories out of [AppDependencies.forAccount], which needs no
/// `BuildContext`.
///
/// Kept out of `launch_resolver.dart` on purpose. The resolver itself knows
/// only two repositories, so its tests compile two repositories; wiring it
/// to `AppDependencies` pulls in the router and with it every page, which
/// only `app.dart` and `router.dart` — both already there — should pay for.
LaunchResolver launchResolverFor(AppDependencies deps) => LaunchResolver(
  repositoriesFor: (accountId) {
    final account = deps.forAccount(accountId);
    return (orgs: account.orgs, projects: account.projects);
  },
);
