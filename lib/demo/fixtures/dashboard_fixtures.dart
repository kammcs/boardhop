import '../demo_backend.dart';
import '../demo_world.dart';
import 'dashboard/demo_analytics.dart';
import 'dashboard/demo_dashboards.dart';

/// The Dashboards view: the team's three dashboards and their widgets, the
/// favorites and widget catalog the picker reads, the saved queries behind
/// the query tiles and lists, and every Analytics query the charts send —
/// the sprint page's burndown included, which is the same
/// `AnalyticsRepository.burndown` call.
///
/// Open it with `BOARDHOP_DEMO_ROUTE=projects/Boardhop/dashboards`
/// (`?dashboard=<id>` for one of the others).
void registerDashboardFixtures(DemoBackend b) {
  final org = RegExp.escape(DemoWorld.org);
  final project = '(?:${DemoWorld.project}|${DemoWorld.projectId})';
  final team = '(?:${DemoWorld.teamId}|Boardhop%20Team|Boardhop Team)';
  const guid = '([0-9a-fA-F-]{36})';
  final core = 'dev\\.azure\\.com/$org';

  // ---------------------------------------------------------- dashboards

  b.get('$core/$project/_apis/dashboard/dashboards', (_) {
    final all = DemoDashboards.all;
    return {
      'count': all.length,
      'value': [for (final d in all) DemoDashboards.summary(d)],
    };
  });

  // By id needs the team segment, as on the service; without it a 404.
  b.get(
    '$core/$project/$team/_apis/dashboard/dashboards/$guid',
    (r) => DemoDashboards.byId(r.group(1)),
  );
  b.get('$core/$project/$team/_apis/dashboard/dashboards/$guid/widgets', (r) {
    final widgets = DemoDashboards.byId(r.group(1))?['widgets'] as List?;
    if (widgets == null) return null;
    return {'count': widgets.length, 'value': widgets};
  });
  b.get('$core/$project/$team/_apis/dashboard/dashboards/$guid/widgets/$guid', (
    r,
  ) {
    final widgets = DemoDashboards.byId(r.group(1))?['widgets'] as List?;
    for (final w in widgets ?? const []) {
      if ((w as Map)['id'] == r.group(2)) return w;
    }
    return null;
  });

  b.get(
    '$core/$project/_apis/dashboard/widgettypes',
    (_) => DemoDashboards.catalog(),
  );
  b.get('$core/_apis/favorite/favorites', (_) => DemoDashboards.favorites());

  // ------------------------------------------------------- saved queries
  //
  // Only this area's query ids match, so these routes never shadow the work
  // fixtures' saved queries (or are shadowed by theirs, as long as their
  // patterns name their own ids too): the backend stops at the first route
  // that matches, even when its handler answers null.
  final queryId =
      '(${[for (final q in DemoQueries.all) RegExp.escape(q.id)].join('|')})';

  b.get('$core/$project/_apis/wit/queries/$queryId', (r) {
    final q = DemoQueries.byId(r.group(1));
    return q == null ? null : DemoQueries.definition(q);
  });
  b.get('$core/$project/_apis/wit/wiql/$queryId', (r) {
    final q = DemoQueries.byId(r.group(1));
    if (q == null) return null;
    return DemoQueries.result(q, top: int.tryParse(r.query[r'$top'] ?? ''));
  });
  // The tile's count: the service answers `X-Total-Count` on a HEAD. The
  // demo backend cannot set headers, so this answers an empty 200 and the
  // repository falls back to the GET above, as it does for a service that
  // refuses HEAD.
  b.on('HEAD', '$core/$project/_apis/wit/wiql/$queryId', (r) {
    final q = DemoQueries.byId(r.group(1));
    return q == null ? null : const DemoResponse(200);
  });

  // ------------------------------------------------------------ analytics

  registerDemoAnalytics(b);
}
