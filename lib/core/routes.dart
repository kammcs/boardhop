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

  /// Search inside one project (research/15 §4). The query carries what the
  /// page is showing so a deep link, a restart or a See-all push reopens the
  /// same answer: `q` the term, `scope` `project` (the default, omitted) or
  /// `org`, `kind` one of `wi`, `code`, `pr` for a See-all view and unset for
  /// the grouped one.
  static String search(
    String accountId,
    String org,
    String project, {
    String? q,
    String? scope,
    String? kind,
  }) {
    final term = q?.trim() ?? '';
    final params = <String, String>{};
    if (term.isNotEmpty) params['q'] = term;
    // The default scope is left out, so the plain route is the plain view.
    if (scope != null && scope != 'project') params['scope'] = scope;
    if (kind != null) params['kind'] = kind;
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final base = '${Routes.project(accountId, org, project)}/search';
    return query.isEmpty ? base : '$base?$query';
  }

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
