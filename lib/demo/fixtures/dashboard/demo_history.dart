import '../../demo_world.dart';

/// The Boardhop team's past, as Analytics remembers it: sprints before the
/// ones `DemoWorld` lists, what each delivered, the day-by-day history of
/// the current sprint, and every story or bug completed in the last few
/// months.
///
/// Everything is derived from `DemoWorld` where the world has an answer
/// (today's states, today's board columns, the current sprint's items), and
/// invented only where it does not (sprints 9–11, stories closed before the
/// world begins). The inventions are deterministic — a hash, not a random
/// generator — so two launches draw the same charts and a test can pin them.
abstract final class DemoHistory {
  // ------------------------------------------------------------ utilities

  /// A stable number in [0, 1) for a pair of integers.
  static double unit(int a, [int b = 0]) {
    var h = (a * 2654435761 + b * 40503 + 0x9e3779b9) & 0xffffffff;
    h ^= h >> 15;
    h = (h * 2246822519) & 0xffffffff;
    h ^= h >> 13;
    h = (h * 3266489917) & 0xffffffff;
    h ^= h >> 16;
    return h / 0x100000000;
  }

  static DateTime dayOnly(DateTime t) => DateTime.utc(t.year, t.month, t.day);

  static DateTime get today => DemoWorld.today;

  /// Whole days from [from] to [to], both taken as calendar days.
  static int daysBetween(DateTime from, DateTime to) =>
      dayOnly(to).difference(dayOnly(from)).inDays;

  static bool isWeekend(DateTime d) => d.weekday >= DateTime.saturday;

  static String day(DateTime t) {
    final d = t.toUtc();
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// How Analytics writes a date: midnight in the organization's time zone.
  static String dateValue(DateTime t) => '${day(t)}T00:00:00-07:00';

  /// A timestamp inside a day, for `CompletedDate` and pipeline runs.
  static String stamp(DateTime t) {
    final d = t.toUtc().subtract(const Duration(hours: 7));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day(d)}T${two(d.hour)}:${two(d.minute)}:${two(d.second)}'
        '.${(d.millisecond).toString().padLeft(3, '0')}-07:00';
  }

  static String stateCategory(String state) => switch (state) {
    'New' || 'To Do' => 'Proposed',
    'Active' || 'In Progress' => 'InProgress',
    'Resolved' => 'Resolved',
    'Closed' || 'Done' => 'Completed',
    'Removed' => 'Removed',
    _ => 'Proposed',
  };

  static bool isRequirement(DemoWorkItem w) =>
      w.type == 'User Story' || w.type == 'Bug';

  // ----------------------------------------------------------- iterations

  /// One sprint as Analytics lists it: the world's five plus three before
  /// them, so velocity has six iterations to draw.
  static final List<HistorySprint> sprints = () {
    final first = DemoWorld.sprints.first;
    return [
      for (var n = 9; n < first.number; n++)
        HistorySprint(
          number: n,
          id: '5b0c7d3e-1f6a-4d80-a2b4-7c9d0e1f2a${n.toString().padLeft(2, '0')}',
          start: first.start.subtract(Duration(days: 14 * (first.number - n))),
        ),
      for (final s in DemoWorld.sprints)
        HistorySprint(number: s.number, id: s.id, start: s.start),
    ];
  }();

  static HistorySprint? sprintById(String id) {
    for (final s in sprints) {
      if (s.id.toLowerCase() == id.toLowerCase()) return s;
    }
    return null;
  }

  /// What each finished sprint delivered, in story points and items of the
  /// requirement backlog (stories and bugs). A healthy team: a little over
  /// committed now and then, a straggler finished late once or twice.
  static const _delivered = <int, SprintDelivery>{
    9: SprintDelivery(
      planned: 11,
      plannedPoints: 42,
      onTime: 9,
      onTimePoints: 35,
      late: 1,
      latePoints: 3,
      incomplete: 1,
      incompletePoints: 5,
    ),
    10: SprintDelivery(
      planned: 12,
      plannedPoints: 45,
      onTime: 11,
      onTimePoints: 41,
      incomplete: 1,
      incompletePoints: 3,
    ),
    11: SprintDelivery(
      planned: 13,
      plannedPoints: 48,
      onTime: 9,
      onTimePoints: 34,
      late: 2,
      latePoints: 8,
      incomplete: 2,
      incompletePoints: 6,
    ),
    12: SprintDelivery(
      planned: 12,
      plannedPoints: 46,
      onTime: 11,
      onTimePoints: 43,
      late: 1,
      latePoints: 2,
      incomplete: 1,
      incompletePoints: 3,
    ),
    13: SprintDelivery(
      planned: 13,
      plannedPoints: 49,
      onTime: 12,
      onTimePoints: 46,
      incomplete: 1,
      incompletePoints: 5,
    ),
  };

  /// The delivery of [sprint]: the table for finished sprints, the world's
  /// items for the current one, nothing for the future.
  static SprintDelivery delivery(HistorySprint sprint, List<String> types) {
    final current = DemoWorld.currentSprint;
    if (sprint.number == current.number) return _currentDelivery(types);
    if (sprint.number > current.number) return const SprintDelivery();
    return _delivered[sprint.number] ?? const SprintDelivery();
  }

  static SprintDelivery _currentDelivery(List<String> types) {
    bool wanted(DemoWorkItem w) =>
        types.isEmpty ? isRequirement(w) : types.contains(w.type);
    final items = [
      for (final h in currentSprint.items)
        if (wanted(h.item)) h,
    ];
    num points(Iterable<SprintItemHistory> hs) =>
        hs.fold<num>(0, (sum, h) => sum + (h.item.points ?? 0));
    final planned = [
      for (final h in items)
        if (h.added == 0) h,
    ];
    final done = [
      for (final h in items)
        if (h.completed != null) h,
    ];
    final open = [
      for (final h in items)
        if (h.completed == null) h,
    ];
    return SprintDelivery(
      planned: planned.length,
      plannedPoints: points(planned),
      onTime: done.length,
      onTimePoints: points(done),
      incomplete: open.length,
      incompletePoints: points(open),
    );
  }

  // ------------------------------------------------ the current sprint

  static final CurrentSprintHistory currentSprint = CurrentSprintHistory._();

  // -------------------------------------------------------- completions

  /// How far back invented completions go. Long enough for velocity's six
  /// sprints and the Team overview's 60-day cycle time.
  static const historyDays = 84;

  /// Every story and bug completed in the last [historyDays] days, oldest
  /// first: the world's closed items where they are, invented ones around
  /// them at a pace that matches the velocity table.
  static final List<Completion> completions = () {
    final out = <Completion>[];
    final sprint = DemoWorld.currentSprint;
    final sprintAge = daysBetween(sprint.start, today);
    final worldIds = {for (final w in DemoWorld.workItems) w.id};

    // The world's own closed stories and bugs.
    for (final w in DemoWorld.workItems) {
      if (!isRequirement(w) || stateCategory(w.state) != 'Completed') continue;
      final history = currentSprint.of(w.id);
      final DateTime at;
      final double cycle;
      if (history != null && history.completed != null) {
        at = sprint.start.add(Duration(days: history.completed!));
        cycle = (history.completed! - (history.started ?? history.added))
            .clamp(1, 30)
            .toDouble();
      } else {
        final start = w.iteration.start;
        var offset = 3 + w.id % 7;
        while (isWeekend(start.add(Duration(days: offset)))) {
          offset--;
        }
        at = start.add(Duration(days: offset));
        cycle = 2.0 + (w.id % 5);
      }
      out.add(
        Completion(
          id: w.id,
          type: w.type,
          at: at,
          cycleDays: cycle + unit(w.id, 3) * 0.9,
          leadDays: cycle + 6 + unit(w.id, 4) * 14,
        ),
      );
    }

    // Invented ones before the current sprint, with ids below the world's.
    var nextId = 1052;
    for (var age = historyDays; age > sprintAge; age--) {
      final date = today.subtract(Duration(days: age));
      if (isWeekend(date)) continue;
      final r = unit(age, 7);
      final n = r < 0.44 ? 1 : (r < 0.62 ? 2 : 0);
      for (var k = 0; k < n; k++) {
        while (worldIds.contains(nextId)) {
          nextId++;
        }
        final bug = unit(age * 3 + k, 11) < 0.27;
        final cycle = bug
            ? 0.8 + unit(age, 13 + k) * 3.2
            : 1.6 + unit(age, 17 + k) * 6.8;
        out.add(
          Completion(
            id: nextId++,
            type: bug ? 'Bug' : 'User Story',
            at: date.add(Duration(hours: 16 + (unit(age, k) * 7).floor())),
            cycleDays: cycle,
            leadDays: cycle + 3 + unit(age, 19 + k) * (bug ? 9 : 24),
          ),
        );
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }();

  /// Stories and bugs completed after [day] (strictly later calendar days).
  static int completedAfter(DateTime day) =>
      completions.where((c) => dayOnly(c.at).isAfter(dayOnly(day))).length;

  static int completedBetween(DateTime from, DateTime to) => completions
      .where(
        (c) =>
            !dayOnly(c.at).isBefore(dayOnly(from)) &&
            !dayOnly(c.at).isAfter(dayOnly(to)),
      )
      .length;

  // ------------------------------------------------- cumulative flow

  /// The Stories board's columns, in order.
  static const boardColumns = ['New', 'Ready', 'In Progress', 'Review', 'Done'];
  static const boardName = 'Stories';

  /// Today's count per board column, straight from the world, with the
  /// completed stories and bugs of the history in Done.
  static Map<String, int> boardToday() {
    final counts = {for (final c in boardColumns) c: 0};
    for (final w in DemoWorld.workItems) {
      if (!isRequirement(w)) continue;
      final column = w.column;
      if (column == null || !counts.containsKey(column)) continue;
      counts[column] = counts[column]! + 1;
    }
    final invented = completions
        .where((c) => DemoWorld.workItems.every((w) => w.id != c.id))
        .length;
    counts['Done'] = counts['Done']! + invented;
    return counts;
  }

  /// The board on [date]: Done shrinks by what was completed since, the
  /// other columns wander a little around today's counts.
  static Map<String, int> boardOn(DateTime date) {
    final today = boardToday();
    final age = daysBetween(date, DemoHistory.today);
    if (age <= 0) return today;
    int wander(String column, int base, int salt) {
      final bucket = age ~/ 3;
      final r = unit(bucket, salt);
      final delta = r < 0.25 ? -1 : (r > 0.75 ? 1 : 0);
      return (base + delta).clamp(column == 'Review' ? 0 : 1, 99);
    }

    return {
      'New': wander('New', today['New']! + (age > 18 ? 1 : 0), 41),
      'Ready': wander('Ready', today['Ready']! - (age > 24 ? 1 : 0), 43),
      'In Progress': wander('In Progress', today['In Progress']!, 47),
      'Review': wander('Review', today['Review']!, 53),
      'Done': today['Done']! - completedAfter(date),
    };
  }

  // ------------------------------------------------- release burndown

  /// Open stories and bugs today, the release's remaining scope.
  static int openToday() => DemoWorld.workItems
      .where((w) => isRequirement(w) && stateCategory(w.state) != 'Completed')
      .length;

  /// Stories and bugs added to the backlog after [date].
  static int addedAfter(DateTime date) {
    var n = 0;
    for (
      var d = dayOnly(date).add(const Duration(days: 1));
      !d.isAfter(today);
      d = d.add(const Duration(days: 1))
    ) {
      if (isWeekend(d)) continue;
      if (unit(daysBetween(d, today), 31) < 0.58) n++;
    }
    return n;
  }

  /// Open requirement items on [date].
  static int openOn(DateTime date) =>
      openToday() + completedAfter(date) - addedAfter(date);
}

/// A sprint Analytics knows.
class HistorySprint {
  const HistorySprint({
    required this.number,
    required this.id,
    required this.start,
  });

  final int number;
  final String id;
  final DateTime start;

  String get name => 'Sprint $number';
  DateTime get finish => start.add(const Duration(days: 11));
  bool get isEnded => DemoHistory.today.isAfter(finish);
}

/// What one sprint planned and delivered (requirement backlog only).
class SprintDelivery {
  const SprintDelivery({
    this.planned = 0,
    this.plannedPoints = 0,
    this.onTime = 0,
    this.onTimePoints = 0,
    this.late = 0,
    this.latePoints = 0,
    this.incomplete = 0,
    this.incompletePoints = 0,
  });

  final int planned;
  final num plannedPoints;
  final int onTime;
  final num onTimePoints;
  final int late;
  final num latePoints;
  final int incomplete;
  final num incompletePoints;
}

/// One story or bug reaching Closed.
class Completion {
  const Completion({
    required this.id,
    required this.type,
    required this.at,
    required this.cycleDays,
    required this.leadDays,
  });

  final int id;
  final String type;
  final DateTime at;
  final double cycleDays;
  final double leadDays;
}

/// One item of the current sprint and the days (from the sprint's first
/// day) it was added, started, resolved and completed.
class SprintItemHistory {
  const SprintItemHistory({
    required this.item,
    required this.added,
    this.started,
    this.resolved,
    this.completed,
  });

  final DemoWorkItem item;
  final int added;
  final int? started;
  final int? resolved;
  final int? completed;

  /// The item's state category on sprint day [day], or null before it was
  /// in the sprint.
  String? categoryOn(int day) {
    if (day < added) return null;
    if (completed != null && day >= completed!) return 'Completed';
    if (resolved != null && day >= resolved!) return 'Resolved';
    if (started != null && day >= started!) return 'InProgress';
    return 'Proposed';
  }
}

/// The current sprint, day by day, ending in exactly the states the world
/// shows today.
class CurrentSprintHistory {
  CurrentSprintHistory._() {
    final sprint = DemoWorld.currentSprint;
    lastDay = DemoHistory.daysBetween(
      sprint.start,
      DemoHistory.today,
    ).clamp(0, DemoHistory.daysBetween(sprint.start, sprint.finish));
    final byId = <int, SprintItemHistory>{};
    final inSprint = <DemoWorkItem>[];
    for (final w in DemoWorld.workItems) {
      try {
        if (w.iteration.number == sprint.number) inSprint.add(w);
      } catch (_) {
        // A task whose parent is not in the world: not in any sprint.
      }
    }
    // Parents first, so a task can be added no earlier than its story.
    inSprint.sort((a, b) {
      final ta = a.type == 'Task' ? 1 : 0;
      final tb = b.type == 'Task' ? 1 : 0;
      return ta != tb ? ta.compareTo(tb) : a.id.compareTo(b.id);
    });
    for (final w in inSprint) {
      // Everything was planned on day one: a scope that grows mid-sprint
      // draws a burndown that climbs, which reads as a team in trouble.
      const added = 0;
      final category = DemoHistory.stateCategory(w.state);
      int? started;
      int? resolved;
      int? completed;
      switch (category) {
        case 'InProgress':
          started = _pick(added, lastDay, w.id, 1);
        case 'Resolved':
          started = _pick(added, lastDay - 2, w.id, 1);
          resolved = _pick(started + 1, lastDay, w.id, 2);
        case 'Completed':
          started = _pick(added, lastDay - 2, w.id, 1);
          completed = _pick(started + 1, lastDay, w.id, 3);
      }
      byId[w.id] = SprintItemHistory(
        item: w,
        added: added,
        started: started,
        resolved: resolved,
        completed: completed,
      );
    }
    items = byId.values.toList();
    _byId = byId;
  }

  /// The last day of the sprint Analytics has a snapshot for: today, or the
  /// finish day of a sprint that is over.
  late final int lastDay;
  late final List<SprintItemHistory> items;
  late final Map<int, SprintItemHistory> _byId;

  SprintItemHistory? of(int id) => _byId[id];

  /// A working day in [lo, hi], never past [lastDay].
  int _pick(int lo, int hi, int id, int salt) {
    final top = hi.clamp(0, lastDay);
    final bottom = lo.clamp(0, top);
    var day =
        bottom + (DemoHistory.unit(id, salt) * (top - bottom + 1)).floor();
    final start = DemoWorld.currentSprint.start;
    while (day > bottom &&
        DemoHistory.isWeekend(start.add(Duration(days: day)))) {
      day--;
    }
    return day.clamp(bottom, top);
  }
}
