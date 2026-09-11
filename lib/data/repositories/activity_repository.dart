import '../../core/http/ado_client.dart';
import '../../core/routes.dart';
import '../../core/http/ado_exceptions.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/activity.dart';
import '../models/work_item.dart';
import 'pipeline_repository.dart';
import 'pull_request_repository.dart';

/// The foreground Activity feed (research/05 §8.4, spike s09 ≈ 0.013 TSTU
/// per cycle): pull requests waiting for me and mine (org-level), work
/// items assigned to me that changed recently (one org-wide WIQL plus a
/// batch), and recent builds of the projects whose Pipelines tab has been
/// opened. Cached as one JSON list per org; a "seen" timestamp marks what is
/// new since the last visit.
class ActivityRepository {
  ActivityRepository(
    this._client,
    AppDatabase? db,
    this._pullRequests,
    this._pipelines, {
    String? userId,
  }) : _cache = JsonCache(db, namespace: userId),
       _userId = userId ?? '';

  final AdoClient _client;
  final JsonCache _cache;

  /// Account the routes on the items point back into.
  final String _userId;
  final PullRequestRepository _pullRequests;
  final PipelineRepository _pipelines;

  static const apiVersion = '7.1';
  static const workItemDays = 14;
  static const buildWindow = Duration(days: 2);
  static const maxPinnedProjects = 5;

  static String feedKey(String org) => 'activity:$org';
  static String seenKey(String org) => 'activity:seen:$org';

  static String workItemsWiql({int days = workItemDays}) =>
      'SELECT [System.Id] FROM WorkItems '
      'WHERE [System.AssignedTo] = @Me '
      'AND [System.ChangedDate] >= @Today - $days '
      'ORDER BY [System.ChangedDate] DESC';

  static const workItemFields = <String>[
    'System.Id',
    'System.Rev',
    'System.WorkItemType',
    'System.Title',
    'System.State',
    'System.ChangedDate',
    'System.ChangedBy',
    'System.TeamProject',
  ];

  /// Newest first; duplicates by key keep the first (newest) copy.
  static List<ActivityItem> merge(Iterable<ActivityItem> items) {
    final seen = <String>{};
    final out = <ActivityItem>[
      for (final i in items)
        if (seen.add(i.key)) i,
    ];
    out.sort((a, b) {
      final ta = a.time?.millisecondsSinceEpoch ?? 0;
      final tb = b.time?.millisecondsSinceEpoch ?? 0;
      return tb.compareTo(ta);
    });
    return out;
  }

  /// Projects whose Pipelines tab has been opened (their run lists are
  /// cached), capped so the poll stays cheap.
  Future<List<String>> pinnedProjects(String org) =>
      _cache.keysWithPrefix('pipelines:runs:$org:', limit: maxPinnedProjects);

  Future<List<WorkItem>> _changedWorkItems(String org) async {
    final query = await _client.send(
      method: 'POST',
      org: org,
      path: '_apis/wit/wiql',
      apiVersion: apiVersion,
      query: {r'$top': '50'},
      body: {'query': workItemsWiql()},
    );
    final ids = ((query['workItems'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => m['id'] as int)
        .toList();
    if (ids.isEmpty) return const [];
    final json = await _client.send(
      method: 'POST',
      org: org,
      path: '_apis/wit/workitemsbatch',
      apiVersion: apiVersion,
      body: {'ids': ids, 'fields': workItemFields, 'errorPolicy': 'omit'},
    );
    return ((json['value'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => WorkItem.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  /// Runs the four sources, tolerating any one failing (a project without
  /// pipelines, a denied scope) as long as something answered; auth
  /// failures always propagate.
  Future<List<ActivityItem>> refresh(String org) async {
    final items = <ActivityItem>[];
    final errors = <AdoException>[];
    Future<void> guard(Future<Iterable<ActivityItem>> Function() source) async {
      try {
        items.addAll(await source());
      } on AdoAuthException {
        rethrow;
      } on AdoException catch (e) {
        errors.add(e);
      }
    }

    final pinned = await pinnedProjects(org);
    await Future.wait([
      guard(() async {
        final prs = await _pullRequests.list(
          org,
          filter: PrListFilter.toReview,
        );
        return prs.map(
          (p) => ActivityItem.fromPullRequest(
            Routes.org(_userId, org),
            p,
            mine: false,
          ),
        );
      }),
      guard(() async {
        final prs = await _pullRequests.list(org, filter: PrListFilter.mine);
        return prs.map(
          (p) => ActivityItem.fromPullRequest(
            Routes.org(_userId, org),
            p,
            mine: true,
          ),
        );
      }),
      guard(() async {
        final wis = await _changedWorkItems(org);
        return wis.map(
          (w) => ActivityItem.fromWorkItem(Routes.org(_userId, org), w),
        );
      }),
      for (final project in pinned)
        guard(() async {
          final runs = await _pipelines.runs(org, project, top: 20);
          final cutoff = DateTime.now().subtract(buildWindow);
          return [
            for (final r in runs)
              if (r.queueTime == null || r.queueTime!.isAfter(cutoff))
                ActivityItem.fromBuild(Routes.org(_userId, org), r),
          ];
        }),
    ]);
    if (items.isEmpty && errors.isNotEmpty) throw errors.first;
    final merged = merge(items);
    await _cache.put(feedKey(org), [for (final i in merged) i.toJson()]);
    return merged;
  }

  Future<({List<ActivityItem> items, DateTime fetchedAt})?> cached(
    String org,
  ) async {
    final cached = await _cache.get(feedKey(org));
    final json = cached?.json;
    if (cached == null || json is! List) return null;
    return (
      items: [
        for (final m in json.whereType<Map>())
          ActivityItem.fromJson(m.cast<String, dynamic>()),
      ],
      fetchedAt: cached.fetchedAt,
    );
  }

  Future<DateTime?> lastSeen(String org) async {
    final cached = await _cache.get(seenKey(org));
    final json = cached?.json;
    if (json is! Map) return null;
    return DateTime.tryParse(json['at'] as String? ?? '');
  }

  Future<void> markSeen(String org, [DateTime? at]) => _cache.put(
    seenKey(org),
    {'at': (at ?? DateTime.now()).toUtc().toIso8601String()},
  );
}
