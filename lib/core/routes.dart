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

  static String activity(String accountId, String org) =>
      '${Routes.org(accountId, org)}/activity';

  static String pullRequest(String accountId, String org, String id) =>
      '${Routes.org(accountId, org)}/pull-requests/${Uri.encodeComponent(id)}';

  static String workItem(
    String accountId,
    String org,
    String project,
    String id,
  ) =>
      '${Routes.project(accountId, org, project)}'
      '/work-items/${Uri.encodeComponent(id)}';

  static String pipelines(String accountId, String org, String project) =>
      '${Routes.project(accountId, org, project)}/pipelines';

  static String pipelineRun(
    String accountId,
    String org,
    String project,
    String id,
  ) =>
      '${Routes.pipelines(accountId, org, project)}'
      '/runs/${Uri.encodeComponent(id)}';
}
