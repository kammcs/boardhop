import '../../demo_backend.dart';
import '../../demo_world.dart';
import 'demo_history.dart';

/// `analytics.dev.azure.com`: the OData queries `AnalyticsRepository` sends
/// for the sprint burndown and every dashboard chart, answered from
/// [DemoHistory].
///
/// One route per entity set; the handler reads the `$apply` or `$filter`
/// the repository built and answers the rows that query would return. The
/// rows mirror the live shapes (research/19 §1, spike s61): `DateValue` with
/// the organization's offset, `Count`/`SP` aggregates, `Succeed` as a run
/// outcome.
void registerDemoAnalytics(DemoBackend b) {
  final org = RegExp.escape(DemoWorld.org);
  final project = '(?:${DemoWorld.project}|${DemoWorld.projectId})';
  final base = 'analytics\\.dev\\.azure\\.com/$org/$project/_odata/[^/]+';

  b.get('$base/Teams', (r) => _odata('Teams', _teams(r)));
  b.get('$base/Processes', (r) => _odata('Processes', _processes(r)));
  b.get('$base/Iterations', (r) => _odata('Iterations', _iterations(r)));
  b.get(
    '$base/WorkItemSnapshot',
    (r) => _odata('WorkItemSnapshot', _snapshot(r)),
  );
  b.get('$base/WorkItems', (r) => _odata('WorkItems', _workItems(r)));
  b.get(
    '$base/BoardLocations',
    (r) => _odata('BoardLocations', _boardLocations(r)),
  );
  b.get(
    '$base/WorkItemBoardSnapshot',
    (r) => _odata('WorkItemBoardSnapshot', _boardSnapshot(r)),
  );
  b.get('$base/PipelineRuns', (r) => _odata('PipelineRuns', _pipelineRuns(r)));
}

Map<String, dynamic> _odata(String set, List<Map<String, dynamic>> rows) => {
  '@odata.context':
      'https://analytics.dev.azure.com/${DemoWorld.org}/${DemoWorld.projectId}'
      '/_odata/v4.0-preview/\$metadata#$set',
  'value': rows,
};

/// `$apply` or `$filter`, decoded.
String _expr(DemoRequest r) => r.query[r'$apply'] ?? r.query[r'$filter'] ?? '';

String? _match(String text, String pattern) =>
    RegExp(pattern).firstMatch(text)?.group(1);

DateTime? _dateArg(String text, String op) {
  final raw = _match(text, 'DateValue $op (\\d{4}-\\d{2}-\\d{2})Z');
  return raw == null ? null : DateTime.parse('${raw}T00:00:00Z');
}

List<String> _types(String text) => [
  for (final m in RegExp("WorkItemType eq '([^']*)'").allMatches(text))
    m.group(1)!,
];

bool _teamOk(String text) {
  final sk = _match(text, r'TeamSK eq ([0-9a-fA-F-]+)');
  return sk == null || sk.toLowerCase() == DemoWorld.teamId;
}

// ------------------------------------------------------------------ lookups

List<Map<String, dynamic>> _teams(DemoRequest r) => [
  if (_teamOk(_expr(r)))
    {'TeamSK': DemoWorld.teamId, 'TeamName': DemoWorld.team},
];

List<Map<String, dynamic>> _processes(DemoRequest r) {
  if (!_teamOk(_expr(r))) return const [];
  return [
    for (final type in const ['Bug', 'User Story'])
      {
        'WorkItemType': type,
        'BacklogName': DemoHistory.boardName,
        'BacklogType': 'RequirementBacklog',
        'IsHiddenType': false,
      },
  ];
}

Map<String, dynamic> _iterationRow(HistorySprint s) => {
  'IterationSK': s.id,
  'IterationName': s.name,
  'StartDate': DemoHistory.dateValue(s.start),
  'EndDate': DemoHistory.dateValue(s.finish),
  'IsEnded': s.isEnded,
};

List<Map<String, dynamic>> _iterations(DemoRequest r) {
  final text = _expr(r);
  final id = _match(text, r'IterationId eq ([0-9a-fA-F-]+)');
  if (id != null) {
    final sprint = DemoHistory.sprintById(id);
    return [if (sprint != null) _iterationRow(sprint)];
  }
  if (!_teamOk(text)) return const [];
  final before = _match(text, r'StartDate le (\d{4}-\d{2}-\d{2})Z');
  final limit = before == null ? null : DateTime.parse('${before}T00:00:00Z');
  final top = int.tryParse(r.query[r'$top'] ?? '') ?? 1000;
  final rows = [
    for (final s in DemoHistory.sprints.reversed)
      if (limit == null || !s.start.isAfter(limit)) _iterationRow(s),
  ];
  return rows.take(top).toList();
}

// ---------------------------------------------------------------- snapshots

List<Map<String, dynamic>> _snapshot(DemoRequest r) {
  final text = _expr(r);
  final iteration = _match(text, r'IterationSK eq ([0-9a-fA-F-]+)');
  final dateSk = _match(text, r'DateSK eq (\d{8})');
  if (iteration != null && dateSk != null) {
    return _plannedOn(iteration, _types(text));
  }
  if (iteration != null) return _sprintBurndown(iteration, text);
  if (text.contains('Teams/any')) return _teamBurndown(text);
  return const [];
}

/// Velocity's "planned": what the sprint held on its first day.
List<Map<String, dynamic>> _plannedOn(String iteration, List<String> types) {
  final sprint = DemoHistory.sprintById(iteration);
  if (sprint == null) return const [];
  final d = DemoHistory.delivery(sprint, types);
  return [
    {'Planned': d.planned, 'SP': d.plannedPoints.toDouble()},
  ];
}

/// One row per day and state category of one sprint.
List<Map<String, dynamic>> _sprintBurndown(String iteration, String text) {
  final sprint = DemoHistory.sprintById(iteration);
  if (sprint == null) return const [];
  final today = DemoHistory.today;
  final from = _dateArg(text, 'ge') ?? sprint.start;
  var to = _dateArg(text, 'le') ?? sprint.finish;
  if (to.isAfter(today)) to = today;
  final rows = <Map<String, dynamic>>[];
  final current = DemoWorld.currentSprint;

  for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    final day = DemoHistory.daysBetween(sprint.start, d);
    if (day < 0) continue;
    final counts = <String, int>{};
    final points = <String, double>{};
    if (sprint.number == current.number) {
      for (final h in DemoHistory.currentSprint.items) {
        final category = h.categoryOn(day);
        if (category == null) continue;
        counts[category] = (counts[category] ?? 0) + 1;
        points[category] = (points[category] ?? 0) + (h.item.points ?? 0);
      }
    } else if (sprint.number < current.number) {
      _pastSprintDay(sprint, day, counts, points);
    }
    for (final category in const [
      'Proposed',
      'InProgress',
      'Resolved',
      'Completed',
    ]) {
      final n = counts[category];
      if (n == null || n == 0) continue;
      rows.add({
        'DateValue': DemoHistory.dateValue(d),
        'StateCategory': category,
        'Count': n,
        'SP': points[category],
      });
    }
  }
  return rows;
}

/// A finished sprint's burndown: its items and tasks, finishing about where
/// the velocity table says it did.
void _pastSprintDay(
  HistorySprint sprint,
  int day,
  Map<String, int> counts,
  Map<String, double> points,
) {
  final d = DemoHistory.delivery(sprint, const []);
  // Stories and bugs plus the tasks under them.
  final total =
      d.planned * 3 + (DemoHistory.unit(sprint.number, 5) * 4).floor();
  final remainingAtEnd = d.incomplete * 2;
  final span = 11;
  final t = (day.clamp(0, span)) / span;
  // An S-curve: slow start, most work closing in the second week.
  final progress = t * t * (3 - 2 * t);
  final wobble = (DemoHistory.unit(sprint.number * 31 + day, 9) - 0.5) * 2;
  final done = ((total - remainingAtEnd) * progress + wobble).round().clamp(
    0,
    total - remainingAtEnd,
  );
  final open = total - done;
  final inProgress = (open * 0.4).round();
  counts['Completed'] = done;
  counts['InProgress'] = inProgress;
  counts['Proposed'] = open - inProgress;
  final perItem = d.plannedPoints / (d.planned == 0 ? 1 : d.planned) / 3;
  points['Completed'] = (done * perItem).roundToDouble();
  points['InProgress'] = (inProgress * perItem).roundToDouble();
  points['Proposed'] = ((open - inProgress) * perItem).roundToDouble();
}

/// The Burndown and Burnup widgets: the team's requirement backlog over a
/// date range, scope counted from the range's first day.
List<Map<String, dynamic>> _teamBurndown(String text) {
  if (!_teamOk(text)) return const [];
  final today = DemoHistory.today;
  final from = _dateArg(text, 'ge') ?? today.subtract(const Duration(days: 30));
  var to = _dateArg(text, 'le') ?? today;
  if (to.isAfter(today)) to = today;
  final types = _types(text);
  final bugsOnly = types.length == 1 && types.single == 'Bug';
  final share = bugsOnly ? 0.25 : 1.0;
  final rows = <Map<String, dynamic>>[];
  for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
    final open = (DemoHistory.openOn(d) * share).round();
    final done = (DemoHistory.completedBetween(from, d) * share).round();
    final inProgress = (open * 0.35).round();
    final age = DemoHistory.daysBetween(d, today);
    double sp(int n, int salt) =>
        (n * 3.4 + (DemoHistory.unit(age, salt) - 0.5) * 3).roundToDouble();
    for (final (category, n, salt) in [
      ('Proposed', open - inProgress, 61),
      ('InProgress', inProgress, 67),
      ('Completed', done, 71),
    ]) {
      if (n <= 0) continue;
      rows.add({
        'DateValue': DemoHistory.dateValue(d),
        'StateCategory': category,
        'Count': n,
        'SP': sp(n, salt),
      });
    }
  }
  return rows;
}

// --------------------------------------------------------------- work items

List<Map<String, dynamic>> _workItems(DemoRequest r) {
  final text = _expr(r);
  if (!_teamOk(text)) return const [];
  if (text.contains('groupby((WorkItemType,State,StateCategory)')) {
    return _workByState();
  }
  if (text.contains('CycleTimeDays') ||
      (r.query[r'$select'] ?? '').contains('CycleTimeDays')) {
    return _cycleTime(r, text);
  }
  final list = _match(text, r'IterationSK in \(([^)]*)\)');
  if (list == null) return const [];
  final types = _types(text);
  final sprints = [
    for (final id in list.split(',')) ?DemoHistory.sprintById(id.trim()),
  ];
  if (text.contains('CompletedDate le Iteration/EndDate')) {
    return [
      for (final s in sprints)
        if (DemoHistory.delivery(s, types) case final d when d.onTime > 0)
          {
            'IterationSK': s.id,
            'Count': d.onTime,
            'SP': d.onTimePoints.toDouble(),
          },
    ];
  }
  if (text.contains('CompletedDate gt Iteration/EndDate')) {
    return [
      for (final s in sprints)
        if (DemoHistory.delivery(s, types) case final d when d.late > 0)
          {'IterationSK': s.id, 'Count': d.late, 'SP': d.latePoints.toDouble()},
    ];
  }
  if (text.contains('groupby((IterationSK,StateCategory)')) {
    return [for (final s in sprints) ..._byCategory(s, types)];
  }
  return const [];
}

List<Map<String, dynamic>> _byCategory(HistorySprint s, List<String> types) {
  final d = DemoHistory.delivery(s, types);
  final rows = <Map<String, dynamic>>[];
  if (d.onTime + d.late > 0) {
    rows.add({
      'IterationSK': s.id,
      'StateCategory': 'Completed',
      'Count': d.onTime + d.late,
      'SP': (d.onTimePoints + d.latePoints).toDouble(),
    });
  }
  if (s.number == DemoWorld.currentSprint.number) {
    final byCategory = <String, (int, num)>{};
    for (final h in DemoHistory.currentSprint.items) {
      final w = h.item;
      final wanted = types.isEmpty
          ? DemoHistory.isRequirement(w)
          : types.contains(w.type);
      if (!wanted) continue;
      final category = DemoHistory.stateCategory(w.state);
      if (category == 'Completed') continue;
      final (n, sp) = byCategory[category] ?? (0, 0);
      byCategory[category] = (n + 1, sp + (w.points ?? 0));
    }
    for (final e in byCategory.entries) {
      rows.add({
        'IterationSK': s.id,
        'StateCategory': e.key,
        'Count': e.value.$1,
        'SP': e.value.$2.toDouble(),
      });
    }
  } else if (d.incomplete > 0) {
    rows.add({
      'IterationSK': s.id,
      'StateCategory': 'InProgress',
      'Count': d.incomplete,
      'SP': d.incompletePoints.toDouble(),
    });
  }
  return rows;
}

/// Open and closed work by type and state: the world as it is, plus the
/// stories, bugs and tasks the team closed before it.
List<Map<String, dynamic>> _workByState() {
  final counts = <(String, String), int>{};
  for (final w in DemoWorld.workItems) {
    final key = (w.type, w.state);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final worldIds = {for (final w in DemoWorld.workItems) w.id};
  for (final c in DemoHistory.completions) {
    if (worldIds.contains(c.id)) continue;
    final key = (c.type, 'Closed');
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final stories = counts[('User Story', 'Closed')] ?? 0;
  counts[('Task', 'Done')] = (counts[('Task', 'Done')] ?? 0) + stories * 2;
  return [
    for (final e in counts.entries)
      {
        'WorkItemType': e.key.$1,
        'State': e.key.$2,
        'StateCategory': DemoHistory.stateCategory(e.key.$2),
        'Count': e.value,
      },
  ];
}

List<Map<String, dynamic>> _cycleTime(DemoRequest r, String text) {
  final raw = _match(text, r'CompletedDate ge (\d{4}-\d{2}-\d{2})Z');
  final from = raw == null
      ? DemoHistory.today.subtract(const Duration(days: 30))
      : DateTime.parse('${raw}T00:00:00Z');
  final types = _types(text);
  return [
    for (final c in DemoHistory.completions)
      if (!DemoHistory.dayOnly(c.at).isBefore(from) &&
          (types.isEmpty || types.contains(c.type)))
        {
          'WorkItemId': c.id,
          'WorkItemType': c.type,
          'State': 'Closed',
          'CycleTimeDays': double.parse(c.cycleDays.toStringAsFixed(4)),
          'LeadTimeDays': double.parse(c.leadDays.toStringAsFixed(4)),
          'CompletedDate': DemoHistory.stamp(c.at),
        },
  ];
}

// -------------------------------------------------------------------- board

bool _boardOk(String text) {
  final board = _match(text, "BoardName eq '([^']*)'");
  return board == null || board == DemoHistory.boardName;
}

List<Map<String, dynamic>> _boardLocations(DemoRequest r) {
  final text = _expr(r);
  if (!_teamOk(text) || !_boardOk(text)) return const [];
  return [
    for (var i = 0; i < DemoHistory.boardColumns.length; i++)
      {
        'ColumnName': DemoHistory.boardColumns[i],
        'ColumnOrder': i,
        'IsColumnSplit': DemoHistory.boardColumns[i] == 'In Progress',
      },
  ];
}

List<Map<String, dynamic>> _boardSnapshot(DemoRequest r) {
  final text = _expr(r);
  if (!_teamOk(text) || !_boardOk(text)) return const [];
  final today = DemoHistory.today;
  final from = _dateArg(text, 'ge') ?? today.subtract(const Duration(days: 30));
  final rows = <Map<String, dynamic>>[];
  for (var d = from; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
    final counts = DemoHistory.boardOn(d);
    for (final column in DemoHistory.boardColumns) {
      final n = counts[column] ?? 0;
      if (n <= 0) continue;
      rows.add({
        'DateValue': DemoHistory.dateValue(d),
        'ColumnName': column,
        'Count': n,
      });
    }
  }
  return rows;
}

// ---------------------------------------------------------------- pipelines

/// The last 90 days of runs of any pipeline: a green main branch with the
/// odd red run, which is what a pass-rate card should show.
List<Map<String, dynamic>> _runsOf(int pipelineId) {
  final now = DemoWorld.now;
  final runs = <Map<String, dynamic>>[];
  var at = now.subtract(Duration(hours: 3 + pipelineId % 5));
  var n = 0;
  while (now.difference(at).inDays < 92) {
    final r = DemoHistory.unit(pipelineId * 97 + n, 23);
    final outcome = r < 0.06
        ? 'Failed'
        : r < 0.09
        ? 'PartiallySucceeded'
        : r < 0.105
        ? 'Canceled'
        : 'Succeed';
    final seconds = 210 + (DemoHistory.unit(n, pipelineId) * 190).round();
    final completed = at;
    final started = completed.subtract(Duration(seconds: seconds));
    final queued = started.subtract(
      Duration(seconds: 4 + (DemoHistory.unit(n, 3) * 40).round()),
    );
    final local = completed.subtract(const Duration(hours: 7));
    final perDay = runs
        .where((x) => (x['_day'] as String) == DemoHistory.day(local))
        .length;
    runs.add({
      '_day': DemoHistory.day(local),
      'PipelineRunId': 9400 - n,
      'RunNumber':
          '${DemoHistory.day(local).replaceAll('-', '')}.${perDay + 1}',
      'RunOutcome': outcome,
      'RunReason': DemoHistory.unit(n, 29) < 0.7
          ? 'IndividualCI'
          : (DemoHistory.unit(n, 37) < 0.6 ? 'PullRequest' : 'Manual'),
      'QueuedDate': DemoHistory.stamp(queued),
      'StartedDate': DemoHistory.stamp(started),
      'CompletedDate': DemoHistory.stamp(completed),
      'RunDurationSeconds': seconds.toDouble(),
    });
    n++;
    at = at.subtract(
      Duration(minutes: 420 + (DemoHistory.unit(n, 41) * 1500).round()),
    );
  }
  // Run numbers count up within a day; they were built newest first.
  final byDay = <String, List<Map<String, dynamic>>>{};
  for (final run in runs) {
    byDay.putIfAbsent(run['_day'] as String, () => []).add(run);
  }
  for (final e in byDay.entries) {
    final list = e.value;
    for (var i = 0; i < list.length; i++) {
      list[i]['RunNumber'] = '${e.key.replaceAll('-', '')}.${list.length - i}';
    }
  }
  for (final run in runs) {
    run.remove('_day');
  }
  return runs;
}

List<Map<String, dynamic>> _pipelineRuns(DemoRequest r) {
  final text = _expr(r);
  final id = int.tryParse(_match(text, r'PipelineId eq (\d+)') ?? '');
  if (id == null) return const [];
  final runs = _runsOf(id);
  if (text.contains('aggregate(')) {
    final since = _match(text, r'CompletedDate ge (\d{4}-\d{2}-\d{2})Z');
    final from = since == null
        ? DateTime.utc(1970)
        : DateTime.parse('${since}T00:00:00Z');
    final window = [
      for (final run in runs)
        if (!DateTime.parse(run['CompletedDate'] as String).isBefore(from)) run,
    ];
    int count(String outcome) =>
        window.where((run) => run['RunOutcome'] == outcome).length;
    return [
      {
        'TotalCount': window.length,
        'Succeeded': count('Succeed'),
        'Failed': count('Failed'),
        'Partial': count('PartiallySucceeded'),
        'Canceled': count('Canceled'),
      },
    ];
  }
  final top = int.tryParse(r.query[r'$top'] ?? '') ?? runs.length;
  return runs.take(top).toList();
}
