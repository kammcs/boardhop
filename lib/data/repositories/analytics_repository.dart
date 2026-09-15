import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/http/ado_host.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import '../models/analytics.dart';
import '../models/sprint.dart';

/// Everything Boardhop reads from Analytics: the sprint burndown (research/18)
/// and the dashboard charts (research/19 §4.1 — team burndown, velocity,
/// cumulative flow, cycle and lead time, work by state, pipeline outcomes).
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

  // --------------------------------------------- the dashboard queries (D9)
  //
  // Everything below is research/19 §1 and spike s61, which timed each of
  // these against the scratch project and CloudCover. Three rules came out of
  // it and are obeyed here:
  //
  // * **never build an or-chain of `(IterationSK, DateSK)` pairs** — six pairs
  //   took 55 s, where six parallel one-iteration queries take 1.1 s each;
  // * `DateSK in (…)` and `DateValue in (…)` are 400, but `IterationSK in (…)`
  //   is fine, and property-to-property compares (`CompletedDate le
  //   Iteration/EndDate`) work;
  // * `DateValue` carries the organization's UTC offset, so it is compared
  //   with `ge`/`le` against a `yyyy-MM-ddZ` literal and never with `eq`.
  //
  // Analytics sends no rate-limit header at all (60 calls, s61), so these are
  // off the REST budget and on the clock instead: each is cached for an hour
  // under a key that carries the day, and each surfaces a refusal as
  // [AnalyticsUnavailable] so a card can say so (D14) instead of pushing the
  // user into sign-in.

  /// One hour, and the key carries today's date: yesterday's rows never move.
  static const dashboardTtl = Duration(hours: 1);

  static String cacheKey(
    String kind,
    String org,
    String project,
    String team,
    String args,
  ) => 'analytics:$kind:$org:$project:$team:$args:${_day(DateTime.now())}';

  /// The Analytics surrogate key of a team.
  ///
  /// In this organization `TeamSK` **is** the team GUID (s61), so the lookup
  /// is a confirmation rather than a translation — and when it answers
  /// nothing (an organization where they differ, or Analytics refusing a
  /// filter), the GUID is returned unchanged rather than failing the card.
  Future<String> teamSk(
    String org,
    String project,
    String teamId, {
    bool refresh = false,
  }) async {
    final key = cacheKey('teamsk', org, project, teamId, '-');
    return _typed<String>(
      key,
      () async {
        final rows = await _query(
          odataUri(
            org: org,
            project: project,
            entitySet: 'Teams',
            query:
                r'$filter=TeamSK eq '
                '$teamId'
                r'&$select=TeamSK,TeamName',
          ),
        );
        return rows.isEmpty
            ? teamId
            : (rows.first['TeamSK'] as String? ?? teamId);
      },
      (value) => {'sk': value},
      (json) => switch (json) {
        Map() => json['sk'] as String? ?? teamId,
        _ => throw const FormatException('not a team'),
      },
      refresh: refresh,
      // The mapping is a property of the organization, not of the day.
      maxAge: const Duration(days: 7),
    );
  }

  /// The work item types of the team's requirement backlog, for the type
  /// filter every chart needs when a widget names a backlog *category*
  /// instead of types.
  Future<List<String>> requirementTypes(
    String org,
    String project,
    String teamSk, {
    bool refresh = false,
  }) => _typed<List<String>>(
    cacheKey('types', org, project, teamSk, 'requirement'),
    () async {
      final rows = await _query(
        odataUri(
          org: org,
          project: project,
          entitySet: 'Processes',
          query:
              r'$filter=TeamSK eq '
              '$teamSk'
              " and BacklogType eq 'RequirementBacklog'"
              r'&$select=WorkItemType,BacklogName,BacklogType,IsHiddenType',
        ),
      );
      return [
        for (final r in rows)
          if ((r['IsHiddenType'] as bool? ?? false) == false)
            if (r['WorkItemType'] case final String t) t,
      ]..sort();
    },
    (value) => value,
    (json) => switch (json) {
      List() => [
        for (final t in json)
          if (t is String) t,
      ],
      _ => throw const FormatException('not a type list'),
    },
    refresh: refresh,
    maxAge: const Duration(days: 1),
  );

  /// The name of the team's requirement backlog — `Stories`, `Backlog
  /// items`, `Requirements`, depending on the process — which is also the
  /// name of its default board (research/19 §1: the backlog level's name is
  /// the board's name in every process seen).
  ///
  /// The Team overview's cumulative flow has no widget settings to name a
  /// board with, and this is the board the web's own CFD widget defaults
  /// to. Same `Processes` row as [requirementTypes], different column.
  Future<String?> requirementBoardName(
    String org,
    String project,
    String teamSk, {
    bool refresh = false,
  }) => _typed<String?>(
    cacheKey('board', org, project, teamSk, 'requirement'),
    () async {
      final rows = await _query(
        odataUri(
          org: org,
          project: project,
          entitySet: 'Processes',
          query:
              r'$filter=TeamSK eq '
              '$teamSk'
              " and BacklogType eq 'RequirementBacklog'"
              r'&$select=BacklogName,BacklogType',
        ),
      );
      for (final r in rows) {
        if (r['BacklogName'] case final String name when name.isNotEmpty) {
          return name;
        }
      }
      return null;
    },
    (value) => {'board': value},
    (json) => switch (json) {
      Map() => json['board'] as String?,
      _ => throw const FormatException('not a board name'),
    },
    refresh: refresh,
    maxAge: const Duration(days: 1),
  );

  /// The team's burndown over a date range — the Burndown and Burnup widgets,
  /// which chart a *team*, not a sprint.
  ///
  /// The same `WorkItemSnapshot` `$apply` as [burndown], with the filter
  /// swapped from `IterationSK eq` to the team, the work item types and the
  /// range; [parseBurndown] turns the rows into days either way.
  Future<List<BurndownDay>> teamBurndown(
    String org,
    String project,
    String teamSk,
    List<String> types,
    DateTime start,
    DateTime end, {
    String sumField = 'StoryPoints',
    bool refresh = false,
  }) {
    final today = DateTime.now().toUtc();
    final last = end.isAfter(today) ? today : end;
    final key = cacheKey(
      'teamburndown',
      org,
      project,
      teamSk,
      '${_day(start)}-${_day(last)}-$sumField-${types.join('|')}',
    );
    return _typed<List<BurndownDay>>(
      key,
      () async {
        final rows = await _query(
          odataUri(
            org: org,
            project: project,
            entitySet: 'WorkItemSnapshot',
            query:
                r'$apply=filter(Teams/any(t:t/TeamSK eq '
                '$teamSk)${_typeClause(types)}'
                ' and DateValue ge ${_day(start)}Z'
                ' and DateValue le ${_day(last)}Z)'
                '/groupby((DateValue,StateCategory),'
                r'aggregate($count as Count, '
                '$sumField with sum as SP))'
                r'&$orderby=DateValue asc',
          ),
        );
        return parseBurndown(rows);
      },
      (days) => [for (final d in days) d.toJson()],
      (json) => switch (json) {
        List() => [
          for (final d in json)
            if (d is Map) BurndownDay.fromJson(d.cast<String, dynamic>()),
        ],
        _ => throw const FormatException('not a burndown'),
      },
      refresh: refresh,
    );
  }

  /// The velocity of the last [iterations] dated iterations.
  ///
  /// The iteration list first (everything else needs its surrogate keys),
  /// then `3 + iterations` calls **all at once**: completed-on-time,
  /// completed-late and by-category over the whole set, plus one
  /// `WorkItemSnapshot` per iteration for what was planned on its first day.
  /// Those per-iteration snapshots are the expensive part (1.1 s each) and
  /// are the reason this is fanned out rather than chained: the same six as
  /// an or-chain of `(IterationSK, DateSK)` pairs took 55 s (s61).
  Future<List<VelocityIteration>> velocity(
    String org,
    String project,
    String teamSk,
    List<String> types, {
    int iterations = 6,
    bool refresh = false,
  }) {
    final count = iterations < 1 ? 1 : iterations;
    final key = cacheKey(
      'velocity',
      org,
      project,
      teamSk,
      '$count-${types.join('|')}',
    );
    return _typed<List<VelocityIteration>>(
      key,
      () => _fetchVelocity(org, project, teamSk, types, count),
      (value) => [for (final v in value) v.toJson()],
      (json) => switch (json) {
        List() => [
          for (final v in json)
            if (v is Map) VelocityIteration.fromJson(v.cast<String, dynamic>()),
        ],
        _ => throw const FormatException('not a velocity'),
      },
      refresh: refresh,
    );
  }

  Future<List<VelocityIteration>> _fetchVelocity(
    String org,
    String project,
    String teamSk,
    List<String> types,
    int count,
  ) async {
    final iterationRows = await _query(
      odataUri(
        org: org,
        project: project,
        entitySet: 'Iterations',
        query:
            r'$filter=Teams/any(t:t/TeamSK eq '
            '$teamSk)'
            ' and StartDate ne null'
            ' and StartDate le ${_day(DateTime.now())}Z'
            r'&$orderby=StartDate desc&$top='
            '$count'
            r'&$select=IterationSK,IterationName,StartDate,EndDate,IsEnded',
      ),
    );
    final sprints = [
      for (final r in iterationRows) AnalyticsIteration.fromRow(r),
    ];
    if (sprints.isEmpty) return const [];
    final sks = sprints.map((i) => i.sk).join(',');
    final scope =
        r'Teams/any(t:t/TeamSK eq '
        '$teamSk)${_typeClause(types)}'
        ' and IterationSK in ($sks)';

    final results = await Future.wait([
      // Completed on or before the iteration's own end date.
      _query(
        odataUri(
          org: org,
          project: project,
          entitySet: 'WorkItems',
          query:
              r'$apply=filter('
              '$scope'
              " and StateCategory eq 'Completed'"
              ' and CompletedDate le Iteration/EndDate)'
              r'/groupby((IterationSK),aggregate($count as Count,'
              ' StoryPoints with sum as SP))',
        ),
      ),
      // Completed after it.
      _query(
        odataUri(
          org: org,
          project: project,
          entitySet: 'WorkItems',
          query:
              r'$apply=filter('
              '$scope'
              " and StateCategory eq 'Completed'"
              ' and CompletedDate gt Iteration/EndDate)'
              r'/groupby((IterationSK),aggregate($count as Count,'
              ' StoryPoints with sum as SP))',
        ),
      ),
      // Everything in the iterations, by state category: what is left over
      // after the two completed buckets is the incomplete work.
      _query(
        odataUri(
          org: org,
          project: project,
          entitySet: 'WorkItems',
          query:
              r'$apply=filter('
              '$scope)'
              r'/groupby((IterationSK,StateCategory),aggregate($count as Count,'
              ' StoryPoints with sum as SP))',
        ),
      ),
      // One snapshot per iteration: planned on its first day.
      for (final sprint in sprints)
        _query(
          odataUri(
            org: org,
            project: project,
            entitySet: 'WorkItemSnapshot',
            query:
                r'$apply=filter(IterationSK eq '
                '${sprint.sk}'
                ' and DateSK eq ${_dateSk(sprint.startDate)}'
                '${_typeClause(types)})'
                r'/aggregate($count as Planned, StoryPoints with sum as SP)',
          ),
        ),
    ]);

    ({int count, double sp}) bucket(
      List<Map<String, dynamic>> rows,
      String sk,
    ) {
      var n = 0;
      var sp = 0.0;
      for (final r in rows) {
        if (r['IterationSK'] != sk) continue;
        n += (r['Count'] as num?)?.toInt() ?? 0;
        sp += (r['SP'] as num?)?.toDouble() ?? 0;
      }
      return (count: n, sp: sp);
    }

    final onTime = results[0];
    final late = results[1];
    final all = results[2];
    return [
      for (var i = 0; i < sprints.length; i++)
        () {
          final sprint = sprints[i];
          final done = bucket(onTime, sprint.sk);
          final lateDone = bucket(late, sprint.sk);
          final total = bucket(all, sprint.sk);
          final planned = results[3 + i].firstOrNull;
          return VelocityIteration(
            iteration: sprint,
            planned: (planned?['Planned'] as num?)?.toInt() ?? 0,
            plannedPoints: (planned?['SP'] as num?)?.toDouble() ?? 0,
            completed: done.count,
            completedPoints: done.sp,
            completedLate: lateDone.count,
            completedLatePoints: lateDone.sp,
            incomplete: total.count - done.count - lateDone.count,
            incompletePoints: total.sp - done.sp - lateDone.sp,
          );
        }(),
    ];
  }

  /// The cumulative flow diagram of one board over the days since [start].
  ///
  /// Two calls: the board's columns in their **current** order
  /// (`BoardLocations`, `IsCurrent eq true`) and the snapshot counts grouped
  /// by `(DateValue, ColumnName)`. The grouping is by name alone on purpose —
  /// `ColumnOrder` splits a renamed column into two series (s61) — and any
  /// column the snapshots carry that the board no longer has is appended
  /// after the current ones rather than dropped.
  Future<CumulativeFlow> cumulativeFlow(
    String org,
    String project,
    String teamSk,
    String boardName,
    DateTime start, {
    bool refresh = false,
  }) => _typed<CumulativeFlow>(
    cacheKey('cfd', org, project, teamSk, '$boardName-${_day(start)}'),
    () async {
      final board = _odataString(boardName);
      final results = await Future.wait([
        _query(
          odataUri(
            org: org,
            project: project,
            entitySet: 'BoardLocations',
            query:
                r'$apply=filter(Team/TeamSK eq '
                '$teamSk and BoardName eq $board and IsCurrent eq true)'
                '/groupby((ColumnName,ColumnOrder,IsColumnSplit))'
                r'&$orderby=ColumnOrder',
          ),
        ),
        _query(
          odataUri(
            org: org,
            project: project,
            entitySet: 'WorkItemBoardSnapshot',
            query:
                r'$apply=filter(Team/TeamSK eq '
                '$teamSk and BoardName eq $board'
                ' and DateValue ge ${_day(start)}Z)'
                r'/groupby((DateValue,ColumnName),aggregate($count as Count))'
                r'&$orderby=DateValue asc',
          ),
        ),
      ]);
      return parseCumulativeFlow(results[0], results[1]);
    },
    (value) => value.toJson(),
    (json) => switch (json) {
      Map() => CumulativeFlow.fromJson(json.cast<String, dynamic>()),
      _ => throw const FormatException('not a cumulative flow'),
    },
    refresh: refresh,
  );

  /// Cycle and lead time: every requirement completed since [start], with the
  /// two durations Analytics computes. The averages come off the list (see
  /// [CycleLeadTime.averageCycleDays]) rather than a second aggregate call.
  Future<CycleLeadTime> cycleAndLeadTime(
    String org,
    String project,
    String teamSk,
    DateTime start, {
    List<String> types = const [],
    bool refresh = false,
  }) => _typed<CycleLeadTime>(
    cacheKey(
      'cycletime',
      org,
      project,
      teamSk,
      '${_day(start)}-${types.join('|')}',
    ),
    () async {
      final rows = await _query(
        odataUri(
          org: org,
          project: project,
          entitySet: 'WorkItems',
          query:
              r'$filter=Teams/any(t:t/TeamSK eq '
              '$teamSk)${_typeClause(types)}'
              " and StateCategory eq 'Completed'"
              ' and CompletedDate ge ${_day(start)}Z'
              r'&$select=WorkItemId,WorkItemType,State,CycleTimeDays,'
              'LeadTimeDays,CompletedDate'
              r'&$orderby=CompletedDate asc',
        ),
      );
      return CycleLeadTime(
        items: [for (final r in rows) CycleLeadItem.fromRow(r)],
      );
    },
    (value) => value.toJson(),
    (json) => switch (json) {
      Map() => CycleLeadTime.fromJson(json.cast<String, dynamic>()),
      _ => throw const FormatException('not a cycle time'),
    },
    refresh: refresh,
  );

  /// The team's open and closed work by type and state, for the Team
  /// overview's "work by state" card (D9). `Removed` is filtered out server
  /// side: it is not work, and it would dwarf a real state in some projects.
  Future<List<WorkStateCount>> workByState(
    String org,
    String project,
    String teamSk, {
    bool refresh = false,
  }) => _typed<List<WorkStateCount>>(
    cacheKey('workbystate', org, project, teamSk, '-'),
    () async {
      final rows = await _query(
        odataUri(
          org: org,
          project: project,
          entitySet: 'WorkItems',
          query:
              r'$apply=filter(Teams/any(t:t/TeamSK eq '
              '$teamSk)'
              " and StateCategory ne 'Removed')"
              '/groupby((WorkItemType,State,StateCategory),'
              r'aggregate($count as Count))',
        ),
      );
      return [for (final r in rows) WorkStateCount.fromRow(r)];
    },
    (value) => [for (final w in value) w.toJson()],
    (json) => switch (json) {
      List() => [
        for (final w in json)
          if (w is Map) WorkStateCount.fromJson(w.cast<String, dynamic>()),
      ],
      _ => throw const FormatException('not a state list'),
    },
    refresh: refresh,
  );

  /// One pipeline's outcomes since [start] plus its last 20 runs, in
  /// parallel: the aggregate is the pass rate, the runs are the bars.
  ///
  /// Pipelines are project-scoped, not team-scoped, so the cache key's team
  /// slot carries the pipeline id.
  Future<PipelineOutcomes> pipelineOutcomes(
    String org,
    String project,
    int pipelineId,
    DateTime start, {
    int top = 20,
    bool refresh = false,
  }) => _typed<PipelineOutcomes>(
    cacheKey('pipeline', org, project, '$pipelineId', _day(start)),
    () async {
      final results = await Future.wait([
        _query(
          odataUri(
            org: org,
            project: project,
            entitySet: 'PipelineRuns',
            query:
                r'$apply=filter(PipelineId eq '
                '$pipelineId and CompletedDate ge ${_day(start)}Z)'
                r'/aggregate($count as TotalCount,'
                ' SucceededCount with sum as Succeeded,'
                ' FailedCount with sum as Failed,'
                ' PartiallySucceededCount with sum as Partial,'
                ' CanceledCount with sum as Canceled)',
          ),
        ),
        _query(
          odataUri(
            org: org,
            project: project,
            entitySet: 'PipelineRuns',
            query:
                r'$filter=PipelineId eq '
                '$pipelineId'
                r'&$orderby=CompletedDate desc&$top='
                '$top'
                r'&$select=PipelineRunId,RunNumber,RunOutcome,RunReason,'
                'QueuedDate,StartedDate,CompletedDate,RunDurationSeconds',
          ),
        ),
      ]);
      return PipelineOutcomes.fromAggregate(
        results[0].firstOrNull,
        runs: [for (final r in results[1]) AnalyticsPipelineRun.fromRow(r)],
      );
    },
    (value) => value.toJson(),
    (json) => switch (json) {
      Map() => PipelineOutcomes.fromJson(json.cast<String, dynamic>()),
      _ => throw const FormatException('not a pipeline outcome'),
    },
    refresh: refresh,
  );

  /// Merges the CFD's two answers: the board's current columns give the
  /// order, the snapshot rows give a count per day and column name.
  static CumulativeFlow parseCumulativeFlow(
    List<Map<String, dynamic>> columnRows,
    List<Map<String, dynamic>> snapshotRows,
  ) {
    final ordered = <String>[];
    final sorted = [...columnRows]
      ..sort(
        (a, b) => ((a['ColumnOrder'] as num?)?.toInt() ?? 0).compareTo(
          (b['ColumnOrder'] as num?)?.toInt() ?? 0,
        ),
      );
    for (final row in sorted) {
      final name = row['ColumnName'] as String?;
      if (name != null && name.isNotEmpty && !ordered.contains(name)) {
        ordered.add(name);
      }
    }
    final byDay = <String, Map<String, int>>{};
    final order = <String>[];
    for (final row in snapshotRows) {
      final raw = row['DateValue'] as String?;
      final name = row['ColumnName'] as String?;
      if (raw == null || raw.length < 10 || name == null) continue;
      final day = raw.substring(0, 10);
      final counts = byDay.putIfAbsent(day, () {
        order.add(day);
        return <String, int>{};
      });
      counts[name] =
          (counts[name] ?? 0) + ((row['Count'] as num?)?.toInt() ?? 0);
      // A column the board no longer has still has history: keep it, after
      // the current ones.
      if (!ordered.contains(name)) ordered.add(name);
    }
    order.sort();
    return CumulativeFlow(
      columns: ordered,
      days: [
        for (final day in order)
          CumulativeFlowDay(
            date: DateTime.parse('${day}T00:00:00Z'),
            counts: {
              for (final column in ordered) column: byDay[day]?[column] ?? 0,
            },
          ),
      ],
    );
  }

  /// ` and (WorkItemType eq 'A' or WorkItemType eq 'B')`, or nothing at all
  /// when the caller did not narrow the types.
  static String _typeClause(List<String> types) {
    final wanted = [
      for (final t in types)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    if (wanted.isEmpty) return '';
    final clause = wanted
        .map((t) => 'WorkItemType eq ${_odataString(t)}')
        .join(' or ');
    return ' and ($clause)';
  }

  /// An OData string literal: single-quoted, with any quote doubled.
  static String _odataString(String value) =>
      "'${value.replaceAll("'", "''")}'";

  /// `DateSK` is the day as `yyyyMMdd`, which is how the snapshot entity is
  /// keyed; `DateValue` carries an offset and cannot be compared with `eq`.
  static String _dateSk(DateTime? day) {
    final d = (day ?? DateTime.now()).toUtc();
    return '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Runs [fetch], caches the encoded result and maps every refusal the way
  /// the burndown does: [AnalyticsUnavailable] for a token the host will not
  /// take, the stale copy for anything else, and a rethrow when there is no
  /// stale copy.
  Future<T> _typed<T>(
    String key,
    Future<T> Function() fetch,
    Object Function(T value) encode,
    T Function(Object? json) decode, {
    bool refresh = false,
    Duration maxAge = dashboardTtl,
  }) async {
    if (!refresh) {
      final hit = await _cache.get(key);
      if (hit != null && DateTime.now().difference(hit.fetchedAt) < maxAge) {
        final cached = _tryDecode(hit.json, decode);
        if (cached != null) return cached.$1;
      }
    }
    try {
      final value = await fetch();
      await _cache.put(key, encode(value));
      return value;
    } on AnalyticsUnavailable {
      rethrow;
    } on AdoAuthException catch (e) {
      throw AnalyticsUnavailable(statusCode: e.statusCode, url: e.url);
    } on AdoForbiddenException catch (e) {
      throw AnalyticsUnavailable(statusCode: e.statusCode, url: e.url);
    } on AdoException {
      final stale = await _cache.get(key);
      final cached = stale == null ? null : _tryDecode(stale.json, decode);
      if (cached != null) return cached.$1;
      rethrow;
    }
  }

  static (T,)? _tryDecode<T>(Object? json, T Function(Object? json) decode) {
    try {
      return (decode(json),);
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
