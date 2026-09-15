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

  /// The Home tab's views (research/19 §4.3). [home] is the Summary segment,
  /// which is the tab's landing page; [dashboards] is the second segment and
  /// Wiki slots in as the third later (D8).
  static String home(String accountId, String org, String project) =>
      '${Routes.project(accountId, org, project)}/home';

  /// The Dashboards view. [dashboard] is a dashboard GUID and is **left out
  /// for the default** — the one last opened, or the default team's Overview
  /// — so the plain route is the plain view, the rule [sprint] and [search]
  /// already follow.
  static String dashboards(
    String accountId,
    String org,
    String project, {
    String? dashboard,
  }) => _withQuery('${Routes.project(accountId, org, project)}/dashboards', {
    'dashboard': dashboard,
  });

  /// The Work tab's three views, so the view switch and the pages stop
  /// concatenating route strings by hand (research/18 §4.3).
  static String workItems(String accountId, String org, String project) =>
      '${Routes.project(accountId, org, project)}/work-items';

  static String board(String accountId, String org, String project) =>
      '${Routes.project(accountId, org, project)}/boards';

  /// The Sprint view (decision S1). [iteration] is a team iteration GUID and
  /// is **left out when it is the team's current sprint**, so the plain
  /// route is the plain view — the rule [search] already follows. [tab] is
  /// `backlog`, `taskboard` or `burndown` and is left out for the default,
  /// which the page decides from the sprint's contents.
  static String sprint(
    String accountId,
    String org,
    String project, {
    String? iteration,
    String? tab,
  }) => _withQuery('${Routes.project(accountId, org, project)}/sprint', {
    'iteration': iteration,
    'tab': tab,
  });

  static String pullRequest(String accountId, String org, String id) =>
      '${Routes.org(accountId, org)}/pull-requests/${Uri.encodeComponent(id)}';

  /// [tab] is `details`, `related` or `comments`; the page opens on
  /// Details when it is left out.
  static String workItem(
    String accountId,
    String org,
    String project,
    String id, {
    String? tab,
  }) => _withQuery(
    '${Routes.project(accountId, org, project)}'
    '/work-items/${Uri.encodeComponent(id)}',
    {'tab': tab},
  );

  /// A route with the anchors that are actually set appended as a query
  /// string; a null value is simply left out.
  static String _withQuery(String base, Map<String, String?> params) {
    final query = params.entries
        .where((e) => e.value != null && e.value!.isNotEmpty)
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value!)}')
        .join('&');
    return query.isEmpty ? base : '$base?$query';
  }

  /// The same work item as a page of its own, outside the project tab
  /// shell. A push that starts from a page which is itself over the shell —
  /// the pull request detail page and its file diff — has to use this one:
  /// pushing [workItem] from there puts a second copy of the shell's page
  /// into the same navigator, and two pages with one key is an assert
  /// (`!keyReservation.contains(key)`, go_router keys a shell page by the
  /// route's identity). Everything that navigates from inside the shell —
  /// the Work tab, search, another work item — keeps using [workItem], so
  /// the dock stays under the page it opens and the pushed notifications
  /// land where they always did.
  static String workItemStandalone(
    String accountId,
    String org,
    String project,
    String id, {
    String? comment,
    String? tab,
  }) => _withQuery(
    '${Routes.project(accountId, org, project)}'
    '/work-item/${Uri.encodeComponent(id)}',
    {'comment': comment, 'tab': tab},
  );

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
