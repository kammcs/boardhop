import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/dashboard.dart';

/// A cached dashboard with the time it was read, for the "Updated N min ago"
/// line the page shows above a cache-first open (D12).
typedef CachedDashboard = ({Dashboard dashboard, DateTime fetchedAt});

/// The Dashboards hub's reads (research/19 §4.1). Reads only: there is no
/// dashboard write in the app (§6).
///
/// Everything about this area is preview-only, and the versions differ per
/// resource — `api-version=7.1` is a 400 on all of them
/// (`VssInvalidPreviewVersionException`, spike s57). It is the first Boardhop
/// API that cannot be pinned to a released version.
///
/// Two route facts decide the shape of [list] and [get]:
///
/// * the **project** route lists every team's dashboards in one call but
///   never carries `widgets`;
/// * the **GET by id** needs the team segment (`{project}/{team}/_apis/…`);
///   without it the service answers 404 even for a dashboard the project
///   route just listed. So [get] takes the team id the summary carries in
///   `groupId`.
///
/// Reads go through [_cached] against `JsonCache` and fall back to the stale
/// copy when the network fails, exactly like `SprintRepository`.
class DashboardRepository {
  DashboardRepository(this._client, [AppDatabase? db, String? userId])
    : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final JsonCache _cache;

  /// `{count, value}` with the modern dashboard resource.
  static const apiVersion = '7.1-preview.3';

  /// The widgets sub-resource is a version behind the dashboards it belongs
  /// to; `7.1-preview.3` on it is a 404.
  static const widgetsApiVersion = '7.1-preview.2';

  /// Widget types and the Favorites API.
  static const widgetTypesApiVersion = '7.1-preview.1';
  static const favoritesApiVersion = '7.1-preview.1';

  /// Dashboards and their layout change about as often as a team's process
  /// does; the cache is what makes a cold open instant and an offline one
  /// possible (D12).
  static const cacheTtl = Duration(hours: 24);

  /// The widget-type catalog is the same for every project in an
  /// organization and is only used to name kinds the app does not render.
  static const catalogTtl = Duration(days: 7);

  /// Dashboard favorites are the user's own and cheap to re-read.
  static const favoritesTtl = Duration(hours: 24);

  /// The artifact type the Favorites API knows dashboards by (spike s58,
  /// read off `_apis/Favorite/FavoriteProviders`).
  static const favoriteArtifactType =
      'Microsoft.TeamFoundation.Dashboards.Dashboard';

  static String listKey(String org, String project) =>
      'dashboard:list:$org:$project';

  static String dashboardKey(String org, String project, String id) =>
      'dashboard:$org:$project:$id';

  static String favoritesKey(String org, String project) =>
      'dashboard:favorites:$org:$project';

  static String catalogKey(String org, String project) =>
      'dashboard:catalog:$org:$project';

  /// The web's dashboard page, for the "open on web" actions (D10, D2).
  static Uri webUri(String org, String project, String dashboardId) => Uri.parse(
    'https://dev.azure.com/${Uri.encodeComponent(org)}'
    '/${Uri.encodeComponent(project)}/_dashboards/dashboard/$dashboardId',
  );

  // ---------------------------------------------------------------- reads

  /// Every dashboard of the project, all teams, without widgets.
  Future<List<DashboardSummary>> list(
    String org,
    String project, {
    bool refresh = false,
  }) => _cached<List<DashboardSummary>>(
    listKey(org, project),
    () => _client.getJson(
      org: org,
      project: project,
      path: '_apis/dashboard/dashboards',
      apiVersion: apiVersion,
    ),
    _parseList,
    refresh: refresh,
  );

  /// The cached dashboard list without touching the network, for a first
  /// paint while the refresh is in flight.
  Future<List<DashboardSummary>?> cachedList(String org, String project) async {
    final hit = await _cache.get(listKey(org, project));
    if (hit == null) return null;
    try {
      return _parseList(hit.json);
    } catch (_) {
      return null;
    }
  }

  /// One dashboard with its widgets. [teamId] is the summary's `teamId`
  /// (`groupId` on the wire); the route is a 404 without it.
  Future<Dashboard> get(
    String org,
    String project,
    String teamId,
    String id, {
    bool refresh = false,
  }) => _cached<Dashboard>(
    dashboardKey(org, project, id),
    () => _client.getJson(
      org: org,
      project: project,
      team: teamId,
      path: '_apis/dashboard/dashboards/$id',
      apiVersion: apiVersion,
    ),
    (json) => Dashboard.fromJson(_asMap(json)),
    refresh: refresh,
  );

  /// The cached copy of one dashboard and when it was read, so the page can
  /// draw before the network answers and say how old what it drew is (D12).
  Future<CachedDashboard?> cachedDashboard(
    String org,
    String project,
    String id,
  ) async {
    final hit = await _cache.get(dashboardKey(org, project, id));
    if (hit == null) return null;
    try {
      return (
        dashboard: Dashboard.fromJson(_asMap(hit.json)),
        fetchedAt: hit.fetchedAt,
      );
    } catch (_) {
      return null;
    }
  }

  /// The ids of the dashboards the user has favorited (D6: favorites first,
  /// the star read-only).
  ///
  /// The Favorites API is organization-scoped and takes the artifact type;
  /// entries carry an `artifactScope` naming the project they belong to, so
  /// the answer is filtered to [project] here and cached per project.
  Future<Set<String>> favorites(
    String org,
    String project, {
    bool refresh = false,
  }) => _cached<Set<String>>(
    favoritesKey(org, project),
    () => _client.getJson(
      org: org,
      path: '_apis/favorite/favorites',
      apiVersion: favoritesApiVersion,
      query: const {
        'artifactType': favoriteArtifactType,
        'artifactScopeType': 'Project',
      },
    ),
    (json) => _parseFavorites(json, project),
    refresh: refresh,
    maxAge: favoritesTtl,
  );

  /// The widget-type catalog: the name and icon of every widget kind the
  /// organization offers, used only to name the kinds Boardhop hides (D10).
  Future<List<DashboardWidgetType>> catalog(
    String org,
    String project, {
    bool refresh = false,
  }) => _cached<List<DashboardWidgetType>>(
    catalogKey(org, project),
    () => _client.getJson(
      org: org,
      project: project,
      path: '_apis/dashboard/widgettypes',
      apiVersion: widgetTypesApiVersion,
      query: const {r'$scope': 'project_Team'},
    ),
    _parseCatalog,
    refresh: refresh,
    maxAge: catalogTtl,
  );

  /// The catalog as a contributionId → display name map.
  Future<Map<String, String>> catalogNames(
    String org,
    String project, {
    bool refresh = false,
  }) async {
    final types = await catalog(org, project, refresh: refresh);
    return {
      for (final t in types)
        if (t.contributionId.isNotEmpty) t.contributionId: t.name,
    };
  }

  // -------------------------------------------------------------- parsing

  static List<DashboardSummary> _parseList(Object? json) => [
    for (final d in _values(json))
      if (d is Map) DashboardSummary.fromJson(d.cast<String, dynamic>()),
  ];

  static List<DashboardWidgetType> _parseCatalog(Object? json) {
    final map = _asMap(json);
    // The catalog answers `widgetTypes`, not `value`.
    final raw = (map['widgetTypes'] as List?) ?? (map['value'] as List?);
    return [
      for (final t in raw ?? const [])
        if (t is Map) DashboardWidgetType.fromJson(t.cast<String, dynamic>()),
    ];
  }

  static Set<String> _parseFavorites(Object? json, String project) {
    final wanted = project.toLowerCase();
    final ids = <String>{};
    for (final f in _values(json)) {
      if (f is! Map) continue;
      final scope = (f['artifactScope'] as Map?)?.cast<String, dynamic>();
      final name = (scope?['name'] as String?)?.toLowerCase();
      // An entry with no scope name cannot be attributed to a project; keep
      // it rather than lose a favorite.
      if (name != null && name.isNotEmpty && name != wanted) continue;
      final id = f['artifactId'] as String?;
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  static Map<String, dynamic> _asMap(Object? json) => switch (json) {
    Map() => json.cast<String, dynamic>(),
    _ => const <String, dynamic>{},
  };

  static List<Object?> _values(Object? json) => switch (json) {
    List() => json,
    Map() => (json['value'] as List?) ?? const [],
    _ => const [],
  };

  // --------------------------------------------------------------- shared

  Future<T> _cached<T>(
    String key,
    Future<Object> Function() fetch,
    T Function(Object? json) parse, {
    bool refresh = false,
    Duration maxAge = cacheTtl,
  }) async {
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null && DateTime.now().difference(hit.fetchedAt) < maxAge) {
        final parsed = _tryParse(hit.json, parse);
        if (parsed != null) return parsed.$1;
      }
    }
    try {
      final raw = await fetch();
      await _cache.put(key, raw);
      return parse(raw);
    } on AdoAuthException {
      // Sign-in is needed; never mask that with a stale copy.
      rethrow;
    } on AdoException {
      final stale = await _cache.get(key);
      final parsed = stale == null ? null : _tryParse(stale.json, parse);
      if (parsed != null) return parsed.$1;
      rethrow;
    }
  }

  static (T,)? _tryParse<T>(Object? json, T Function(Object? json) parse) {
    try {
      return (parse(json),);
    } catch (_) {
      return null;
    }
  }
}
