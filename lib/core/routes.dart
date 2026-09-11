/// Route paths are account-scoped: the same organization can be reached by
/// two signed-in identities with different permissions, so every org route
/// names the account first. Pure functions, shared by the router, the
/// pages and the activity items that carry a route into a notification.
abstract final class Routes {
  static const orgs = '/orgs';

  static String account(String accountId) =>
      '/a/${Uri.encodeComponent(accountId)}';

  static String org(String accountId, String org) =>
      '${account(accountId)}/orgs/${Uri.encodeComponent(org)}';

  static String project(String accountId, String org, String project) =>
      '${Routes.org(accountId, org)}/projects/${Uri.encodeComponent(project)}';
}
