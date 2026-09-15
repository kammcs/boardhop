import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/sprint.dart';

/// The burndown, and the only thing Boardhop reads from Analytics.
///
/// Analytics is OData on its own host (`analytics.dev.azure.com`) with the
/// version in the path rather than an `api-version` query, so the URI is
/// built here and sent through [AdoClient.sendRaw] — which still attaches
/// the bearer token, records the rate-limit headers and retries a 401 once.
///
/// What the spikes settled (research/18 §1, r1 §6):
///
/// * one `WorkItemSnapshot` call grouped by day and state category is the
///   whole burndown: ~1.3 s, no `X-RateLimit-Cost` at all, so it is off the
///   REST budget but far slower than any REST call — load it lazily, never
///   in front of the taskboard;
/// * `IterationSK` equalled the team iteration GUID in this organization,
///   but that is not guaranteed, so an empty answer retries through the
///   `Iterations` lookup;
/// * **hours are not available**: Remaining Work is empty on every item in
///   every project, so the series are item count and story points;
/// * the org-level route with no project segment is 403.
///
/// The app's Entra token against this host was unverified until the
/// diagnostics probe (decision S6); a refusal surfaces as
/// [AnalyticsUnavailable] so the Burndown tab can say so instead of
/// pushing the user into sign-in.
class AnalyticsRepository {
  AnalyticsRepository(this._client, [AppDatabase? db, String? userId])
    : _cache = JsonCache(db, namespace: userId);

  final AdoClient _client;
  final JsonCache _cache;

  /// `v3.0-preview`, `v4.0-preview` and `v1.0` all answer; the entity sets
  /// this needs (`WorkItemSnapshot`, `Iterations`) are declared in v4.
  static const odataVersion = 'v4.0-preview';

  /// Snapshots of past days never change, so the key carries the last day
  /// the window covers; only today's key is ever refetched.
  static String burndownKey(
    String org,
    String project,
    String iterationId,
    DateTime lastDay,
  ) => 'analytics:burndown:$org:$project:$iterationId:${_day(lastDay)}';

  /// An hour: everything before today is immutable, and today's line moves
  /// as the team works.
  static const cacheTtl = Duration(hours: 1);

  /// `https://analytics.dev.azure.com/{org}/{project}/_odata/{version}/{set}`
  /// with a raw query, because OData's `$apply` must keep its parentheses
  /// and commas readable and `Uri(queryParameters:)` percent-encodes the
  /// `$` and the slashes of the transformation pipeline.
  static Uri odataUri({
    required String org,
    required String project,
    required String entitySet,
    required String query,
  }) => Uri(
    scheme: 'https',
    host: AdoHost.analytics.hostname,
    pathSegments: [org, project, '_odata', odataVersion, entitySet],
    query: query,
  );

  /// One row per day and state category: the count of work items and the
  /// sum of their story points.
  static Uri snapshotUri({
    required String org,
    required String project,
    required String iterationSk,
    required DateTime start,
    required DateTime end,
  }) => odataUri(
    org: org,
    project: project,
    entitySet: 'WorkItemSnapshot',
    query:
        r'$apply=filter(IterationSK eq '
        '$iterationSk and DateValue ge ${_day(start)}Z '
        'and DateValue le ${_day(end)}Z)'
        '/groupby((DateValue,StateCategory),'
        r'aggregate($count as Count, StoryPoints with sum as SP))'
        r'&$orderby=DateValue asc',
  );

  /// The fallback when `IterationSK` is not the team iteration's GUID.
  static Uri iterationUri({
    required String org,
    required String project,
    required String iterationId,
  }) => odataUri(
    org: org,
    project: project,
    entitySet: 'Iterations',
    query:
        r'$filter=IterationId eq '
        '$iterationId'
        r'&$select=IterationSK,IterationName,StartDate,EndDate',
  );

  /// The burndown of one sprint, one row per day between [start] and [end].
  ///
  /// Throws [AnalyticsUnavailable] when the host refuses the token or the
  /// organization has no Analytics; any other failure falls back to the
  /// cached copy the way the other repositories do.
  Future<List<BurndownDay>> burndown(
    String org,
    String project,
    String iterationId, {
    required DateTime start,
    required DateTime end,
    bool refresh = false,
  }) async {
    final today = DateTime.now().toUtc();
    final lastDay = end.isAfter(today) ? today : end;
    final key = burndownKey(org, project, iterationId, lastDay);
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null && DateTime.now().difference(hit.fetchedAt) < cacheTtl) {
        final cached = _tryParse(hit.json);
        if (cached != null) return cached;
      }
    }
    try {
      var rows = await _query(
        snapshotUri(
          org: org,
          project: project,
          iterationSk: iterationId,
          start: start,
          end: end,
        ),
      );
      if (rows.isEmpty) {
        final sk = await _iterationSk(org, project, iterationId);
        if (sk != null && sk != iterationId) {
          rows = await _query(
            snapshotUri(
              org: org,
              project: project,
              iterationSk: sk,
              start: start,
              end: end,
            ),
          );
        }
      }
      final days = parseBurndown(rows);
      await _cache.put(key, [for (final d in days) d.toJson()]);
      return days;
    } on AnalyticsUnavailable {
      rethrow;
    } on AdoAuthException catch (e) {
      // The token reached the host and the host said no: that is the S6
      // failure, not a sign-out.
      throw AnalyticsUnavailable(statusCode: e.statusCode, url: e.url);
    } on AdoForbiddenException catch (e) {
      throw AnalyticsUnavailable(statusCode: e.statusCode, url: e.url);
    } on AdoException {
      final stale = await _cache.get(key);
      final cached = stale == null ? null : _tryParse(stale.json);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _query(Uri uri) async {
    final response = await _client.sendRaw(method: 'GET', uri: uri);
    final data = response.data;
    final json = switch (data) {
      Map() => data.cast<String, dynamic>(),
      _ => const <String, dynamic>{},
    };
    return [
      for (final r in (json['value'] as List?) ?? const [])
        if (r is Map) r.cast<String, dynamic>(),
    ];
  }

  Future<String?> _iterationSk(
    String org,
    String project,
    String iterationId,
  ) async {
    final rows = await _query(
      iterationUri(org: org, project: project, iterationId: iterationId),
    );
    return rows.isEmpty ? null : rows.first['IterationSK'] as String?;
  }

  /// Groups the OData rows into one [BurndownDay] per day: everything that
  /// is not Completed is remaining (Removed is neither), and the points are
  /// the story points still open.
  static List<BurndownDay> parseBurndown(List<Map<String, dynamic>> rows) {
    final remaining = <String, int>{};
    final done = <String, int>{};
    final points = <String, double>{};
    final order = <String>[];
    for (final row in rows) {
      final raw = row['DateValue'] as String?;
      if (raw == null || raw.length < 10) continue;
      final day = raw.substring(0, 10);
      if (!remaining.containsKey(day)) {
        order.add(day);
        remaining[day] = 0;
        done[day] = 0;
        points[day] = 0;
      }
      final count = (row['Count'] as num?)?.toInt() ?? 0;
      final sp = (row['SP'] as num?)?.toDouble() ?? 0;
      switch (row['StateCategory'] as String?) {
        case 'Completed':
          done[day] = done[day]! + count;
        case 'Removed':
          break;
        default:
          remaining[day] = remaining[day]! + count;
          points[day] = points[day]! + sp;
      }
    }
    order.sort();
    return [
      for (final day in order)
        BurndownDay(
          // Date-only, kept in UTC: a local shift moves a sprint boundary
          // by a day.
          date: DateTime.parse('${day}T00:00:00Z'),
          remaining: remaining[day]!,
          done: done[day]!,
          points: points[day]!,
        ),
    ];
  }

  List<BurndownDay>? _tryParse(Object? json) {
    if (json is! List) return null;
    try {
      return [
        for (final d in json)
          if (d is Map) BurndownDay.fromJson(d.cast<String, dynamic>()),
      ];
    } catch (_) {
      return null;
    }
  }

  static String _day(DateTime t) {
    final d = t.toUtc();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
