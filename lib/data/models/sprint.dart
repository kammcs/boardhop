import 'package:equatable/equatable.dart';

import 'work_item.dart';
import 'work_item_form.dart';

/// One taskboard column.
///
/// Two sources, and the app must handle the second first because it is the
/// majority case (research/18 §1, spike s54: three of four projects):
///
/// * the team customized its taskboard, so `work/taskboardcolumns` answers
///   real columns with an [id] and explicit [mappings];
/// * it did not, and the columns are **derived** from the state categories
///   of the task-backlog types (Proposed → To Do, InProgress and Resolved →
///   In Progress, Completed → Done). Those carry no [id] — and the
///   `taskboardworkitems` reads and writes are 400 on such a project.
///
/// [mappings] is the state a card *takes* when it is dropped here, one per
/// work item type. [states] is every state that *lands* here, which is a
/// longer list on a derived column (a Scrum Task's Active and Resolved both
/// sit under In Progress) and is what places a card.
class TaskboardColumn extends Equatable {
  const TaskboardColumn({
    required this.name,
    required this.order,
    this.id,
    this.mappings = const {},
    this.states = const {},
    this.stateCategory,
  });

  factory TaskboardColumn.fromJson(Map<String, dynamic> json) =>
      TaskboardColumn(
        name: json['name'] as String? ?? '',
        order: (json['order'] as num?)?.toInt() ?? 0,
        id: json['id'] as String?,
        mappings: _stringMap(json['mappings']),
        states: {
          for (final e in ((json['states'] as Map?) ?? const {}).entries)
            e.key.toString(): [
              for (final s in (e.value as List?) ?? const []) '$s',
            ],
        },
        stateCategory: json['stateCategory'] as String?,
      );

  /// `taskboardcolumns` answers `mappings: [{workItemType, state}]`; the
  /// column then accepts exactly that one state per type.
  factory TaskboardColumn.fromWire(Map<String, dynamic> json) {
    final mappings = <String, String>{};
    for (final m in (json['mappings'] as List?) ?? const []) {
      if (m is! Map) continue;
      final type = m['workItemType'] as String?;
      final state = m['state'] as String?;
      if (type != null && state != null) mappings[type] = state;
    }
    return TaskboardColumn(
      name: json['name'] as String? ?? '',
      order: (json['order'] as num?)?.toInt() ?? 0,
      id: json['id'] as String?,
      mappings: mappings,
      states: {
        for (final e in mappings.entries) e.key: [e.value],
      },
    );
  }

  /// Null on a derived column; the service's column id when customized,
  /// which is also what makes `taskboardworkitems` legal.
  final String? id;
  final String name;
  final int order;

  /// Work item type → the state a card takes when it lands here.
  final Map<String, String> mappings;

  /// Work item type → every state that belongs in this column.
  final Map<String, List<String>> states;

  /// `Proposed`, `InProgress` or `Completed` when known.
  final String? stateCategory;

  bool get isCustomized => id != null;

  /// The last column of the board in category terms: a card here counts as
  /// finished for a rollup.
  bool get isDone => (stateCategory ?? '').toLowerCase() == 'completed';

  bool accepts(String type, String state) =>
      (states[type] ?? const []).contains(state) || mappings[type] == state;

  TaskboardColumn copyWith({String? stateCategory}) => TaskboardColumn(
    name: name,
    order: order,
    id: id,
    mappings: mappings,
    states: states,
    stateCategory: stateCategory ?? this.stateCategory,
  );

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'name': name,
    'order': order,
    'mappings': mappings,
    'states': states,
    if (stateCategory != null) 'stateCategory': stateCategory,
  };

  static Map<String, String> _stringMap(Object? raw) => {
    for (final e in ((raw as Map?) ?? const {}).entries)
      e.key.toString(): '${e.value}',
  };

  @override
  List<Object?> get props => [id, name, order, mappings, states, stateCategory];
}

/// One row of the sprint: a requirement and the tasks under it, or — when
/// [parent] is null — the unparented tasks the web shows in a row of their
/// own at the top (research/18 §1).
class SprintRow extends Equatable {
  const SprintRow({
    this.parent,
    this.tasks = const [],
    this.remaining,
    this.done = 0,
  });

  factory SprintRow.fromJson(Map<String, dynamic> json) => SprintRow(
    parent: json['parent'] is Map
        ? WorkItem.fromJson((json['parent'] as Map).cast<String, dynamic>())
        : null,
    tasks: [
      for (final t in (json['tasks'] as List?) ?? const [])
        if (t is Map) WorkItem.fromJson(t.cast<String, dynamic>()),
    ],
    remaining: (json['remaining'] as num?)?.toDouble(),
    done: (json['done'] as num?)?.toInt() ?? 0,
  );

  /// The requirement; null for the unparented row.
  final WorkItem? parent;
  final List<WorkItem> tasks;

  /// Remaining Work summed over the tasks that are not done, or null when
  /// no task carries the field — which is every project in puremedia
  /// (spike s54), so the UI must treat null as "do not show a rollup".
  final double? remaining;

  /// How many of [tasks] sit in a Done column.
  final int done;

  bool get isUnparented => parent == null;
  bool get isEmpty => tasks.isEmpty && parent == null;
  int get taskCount => tasks.length;

  Map<String, dynamic> toJson() => {
    if (parent != null) 'parent': parent!.toJson(),
    'tasks': [for (final t in tasks) t.toJson()],
    if (remaining != null) 'remaining': remaining,
    'done': done,
  };

  @override
  List<Object?> get props => [parent?.id, tasks, remaining, done];
}

/// Everything one sprint view draws, from one `iterations/{id}/workitems`
/// call plus a `workitemsbatch`. Cached whole (JsonCache) so the page opens
/// offline, so it round trips through JSON.
class SprintSnapshot extends Equatable {
  const SprintSnapshot({
    required this.iteration,
    required this.columns,
    required this.rows,
    required this.fetchedAt,
    this.unparented = const SprintRow(),
    this.explicitColumns = const {},
  });

  factory SprintSnapshot.fromJson(Map<String, dynamic> json) => SprintSnapshot(
    iteration: TeamIteration.fromJson(
      ((json['iteration'] as Map?) ?? const {}).cast<String, dynamic>(),
    ),
    columns: [
      for (final c in (json['columns'] as List?) ?? const [])
        if (c is Map) TaskboardColumn.fromJson(c.cast<String, dynamic>()),
    ],
    rows: [
      for (final r in (json['rows'] as List?) ?? const [])
        if (r is Map) SprintRow.fromJson(r.cast<String, dynamic>()),
    ],
    unparented: json['unparented'] is Map
        ? SprintRow.fromJson(
            (json['unparented'] as Map).cast<String, dynamic>(),
          )
        : const SprintRow(),
    explicitColumns: {
      for (final e in ((json['explicitColumns'] as Map?) ?? const {}).entries)
        int.tryParse(e.key.toString()) ?? 0: '${e.value}',
    },
    fetchedAt:
        DateTime.tryParse(json['fetchedAt'] as String? ?? '') ?? DateTime.now(),
  );

  final TeamIteration iteration;
  final List<TaskboardColumn> columns;

  /// Requirement rows in wire order, which is ascending StackRank: the
  /// service has already done the ordering (spike s54).
  final List<SprintRow> rows;

  /// Tasks whose parent is not in this sprint. Shown first, like the web.
  final SprintRow unparented;

  /// Work item id → column name, read from `taskboardworkitems` and only
  /// populated on a customized board. It matters solely where one state
  /// maps to several columns; everywhere else the state places the card.
  final Map<int, String> explicitColumns;

  final DateTime fetchedAt;

  bool get isCustomized => columns.any((c) => c.isCustomized);

  /// Every row, unparented first when it has tasks — the order the phone's
  /// chip strip and the tablet's grid both use.
  List<SprintRow> get allRows => [
    if (unparented.tasks.isNotEmpty) unparented,
    ...rows,
  ];

  List<WorkItem> get tasks => [
    ...unparented.tasks,
    for (final r in rows) ...r.tasks,
  ];

  int get taskCount => tasks.length;

  /// The requirements, in rank order (the Backlog tab's list).
  List<WorkItem> get parents => [
    for (final r in rows)
      if (r.parent != null) r.parent!,
  ];

  SprintSnapshot copyWith({
    List<SprintRow>? rows,
    SprintRow? unparented,
    Map<int, String>? explicitColumns,
  }) => SprintSnapshot(
    iteration: iteration,
    columns: columns,
    rows: rows ?? this.rows,
    unparented: unparented ?? this.unparented,
    explicitColumns: explicitColumns ?? this.explicitColumns,
    fetchedAt: fetchedAt,
  );

  Map<String, dynamic> toJson() => {
    'iteration': iteration.toJson(),
    'columns': [for (final c in columns) c.toJson()],
    'rows': [for (final r in rows) r.toJson()],
    'unparented': unparented.toJson(),
    'explicitColumns': {
      for (final e in explicitColumns.entries) '${e.key}': e.value,
    },
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  @override
  List<Object?> get props => [
    iteration,
    columns,
    rows,
    unparented,
    explicitColumns,
    fetchedAt,
  ];
}

/// A half-open day range (`daysOff` on a capacity row, team days off).
class DateRange extends Equatable {
  const DateRange({required this.start, required this.end});

  factory DateRange.fromJson(Map<String, dynamic> json) => DateRange(
    start: DateTime.tryParse(json['start'] as String? ?? '') ?? DateTime(0),
    end: DateTime.tryParse(json['end'] as String? ?? '') ?? DateTime(0),
  );

  final DateTime start;
  final DateTime end;

  /// Inclusive on both ends, as Azure DevOps means it: a single day off is
  /// `start == end`.
  int get days => end.difference(start).inDays + 1;

  /// Inclusive, compared as calendar dates: Azure DevOps stores days off as
  /// date-only values at UTC midnight, and converting them to local time
  /// moves the boundary by a day.
  bool contains(DateTime day) =>
      _dayNumber(day) >= _dayNumber(start) &&
      _dayNumber(day) <= _dayNumber(end);

  static int _dayNumber(DateTime t) => t.year * 10000 + t.month * 100 + t.day;

  Map<String, dynamic> toJson() => {
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
  };

  @override
  List<Object?> get props => [start, end];
}

/// One member's capacity in a sprint.
class CapacityMember extends Equatable {
  const CapacityMember({
    required this.member,
    this.capacityPerDay = 0,
    this.activities = const [],
    this.daysOff = const [],
  });

  factory CapacityMember.fromJson(Map<String, dynamic> json) {
    final activities = [
      for (final a in (json['activities'] as List?) ?? const [])
        if (a is Map)
          (
            name: a['name'] as String? ?? '',
            capacityPerDay: (a['capacityPerDay'] as num?)?.toDouble() ?? 0,
          ),
    ];
    return CapacityMember(
      member: IdentityRef.fromJson(
        ((json['teamMember'] ?? json['member']) as Map?)
                ?.cast<String, dynamic>() ??
            const {},
      ),
      capacityPerDay: activities.fold(0, (n, a) => n + a.capacityPerDay),
      activities: activities,
      daysOff: [
        for (final d in (json['daysOff'] as List?) ?? const [])
          if (d is Map) DateRange.fromJson(d.cast<String, dynamic>()),
      ],
    );
  }

  final IdentityRef member;

  /// The sum over [activities]; Azure DevOps stores capacity per activity,
  /// not per person.
  final double capacityPerDay;
  final List<({String name, double capacityPerDay})> activities;
  final List<DateRange> daysOff;

  int get daysOffCount => daysOff.fold(0, (n, r) => n + r.days);

  Map<String, dynamic> toJson() => {
    'member': member.toJson(),
    'activities': [
      for (final a in activities)
        {'name': a.name, 'capacityPerDay': a.capacityPerDay},
    ],
    'daysOff': [for (final d in daysOff) d.toJson()],
  };

  @override
  List<Object?> get props => [member, capacityPerDay, activities, daysOff];
}

/// `iterations/{id}/capacities` + `teamdaysoff` + the team's working days.
///
/// Read-only and shown only when the team filled it in (decision S7). No
/// project in puremedia does (spike s54), so [isEmpty] is the normal case.
class SprintCapacity extends Equatable {
  const SprintCapacity({
    this.members = const [],
    this.teamDaysOff = const [],
    this.workingDays = const [],
  });

  factory SprintCapacity.fromJson(Map<String, dynamic> json) => SprintCapacity(
    members: [
      // The collection is `teamMembers`, not `value` (spike s54): reading
      // `value` here is an easy and silent bug.
      for (final m
          in (json['teamMembers'] ?? json['members']) as List? ?? const [])
        if (m is Map) CapacityMember.fromJson(m.cast<String, dynamic>()),
    ],
    teamDaysOff: [
      for (final d in (json['teamDaysOff'] as List?) ?? const [])
        if (d is Map) DateRange.fromJson(d.cast<String, dynamic>()),
    ],
    workingDays: [
      for (final d in (json['workingDays'] as List?) ?? const []) '$d',
    ],
  );

  final List<CapacityMember> members;
  final List<DateRange> teamDaysOff;

  /// `monday` … `sunday`, lower case, as `teamsettings` answers.
  final List<String> workingDays;

  bool get isEmpty => members.isEmpty;
  double get totalPerDay => members.fold(0, (n, m) => n + m.capacityPerDay);

  /// Whether [day] is a working day for the team: in [workingDays] and not
  /// a team day off. With no `workingDays` read, Monday to Friday.
  bool isWorkingDay(DateTime day) {
    const names = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final name = names[day.weekday - 1];
    final working = workingDays.isEmpty
        ? day.weekday <= DateTime.friday
        : workingDays.map((d) => d.toLowerCase()).contains(name);
    if (!working) return false;
    return !teamDaysOff.any((r) => r.contains(day));
  }

  Map<String, dynamic> toJson() => {
    'teamMembers': [for (final m in members) m.toJson()],
    'teamDaysOff': [for (final d in teamDaysOff) d.toJson()],
    'workingDays': workingDays,
  };

  @override
  List<Object?> get props => [members, teamDaysOff, workingDays];
}

/// One day of the burndown, from the Analytics `WorkItemSnapshot` grouped by
/// day and state category (research/18 §1).
class BurndownDay extends Equatable {
  const BurndownDay({
    required this.date,
    this.remaining = 0,
    this.done = 0,
    this.points = 0,
  });

  factory BurndownDay.fromJson(Map<String, dynamic> json) => BurndownDay(
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime(0),
    remaining: (json['remaining'] as num?)?.toInt() ?? 0,
    done: (json['done'] as num?)?.toInt() ?? 0,
    points: (json['points'] as num?)?.toDouble() ?? 0,
  );

  /// Midnight UTC of the snapshot day. Dates from Azure DevOps are
  /// date-only; a local-time shift moves sprint boundaries by a day, so
  /// these are kept in UTC and formatted, never converted.
  final DateTime date;

  /// Work items not yet Completed on that day (Proposed + InProgress +
  /// Resolved).
  final int remaining;

  /// Work items Completed on that day.
  final int done;

  /// Story points still open on that day, the optional second series.
  /// Hours are not an option: Remaining Work is empty everywhere (s54).
  final double points;

  int get scope => remaining + done;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'remaining': remaining,
    'done': done,
    'points': points,
  };

  @override
  List<Object?> get props => [date, remaining, done, points];
}

/// The team's iterations split the way the picker shows them (decision S11:
/// current, then future, then past, newest first).
class SprintIterations extends Equatable {
  const SprintIterations({this.all = const []});

  final List<TeamIteration> all;

  List<TeamIteration> get current => _timeFrame('current');
  List<TeamIteration> get future => _timeFrame('future');

  /// Past sprints newest first; the wire order is oldest first.
  List<TeamIteration> get past => _timeFrame('past').reversed.toList();

  List<TeamIteration> _timeFrame(String frame) => [
    for (final i in all)
      if ((i.timeFrame ?? '').toLowerCase() == frame) i,
  ];

  /// What the Sprint view opens on: the current sprint, else the next
  /// future one, else the most recent past one.
  TeamIteration? get defaultIteration =>
      current.firstOrNull ?? future.firstOrNull ?? past.firstOrNull;

  TeamIteration? byId(String id) {
    for (final i in all) {
      if (i.id == id) return i;
    }
    return null;
  }

  bool get isEmpty => all.isEmpty;

  @override
  List<Object?> get props => [all];
}

/// Dates on a sprint header. Every one of these copes with null dates:
/// three of the four puremedia projects run the stock undated Iteration 1,
/// and the service still calls the first of them `current` (spike s54).
extension SprintDates on TeamIteration {
  /// Decision S12: a sprint whose finish date has passed is still labelled
  /// `current` by the service when the team has no later one, and the
  /// header then says "Ended N days ago".
  bool isEnded({DateTime? now}) {
    final finish = finishDate;
    if (finish == null) return false;
    return _day(now ?? DateTime.now()).isAfter(_day(finish));
  }

  /// Whole days since the sprint's finish date, null when undated or not
  /// yet over.
  int? daysSinceEnd({DateTime? now}) {
    final finish = finishDate;
    if (finish == null) return null;
    final days = _day(now ?? DateTime.now()).difference(_day(finish)).inDays;
    return days > 0 ? days : null;
  }

  /// Days from today to the finish date inclusive, null when undated or
  /// already over. "6 days left" counts today.
  int? daysRemaining({DateTime? now}) {
    final finish = finishDate;
    if (finish == null) return null;
    final days =
        _day(finish).difference(_day(now ?? DateTime.now())).inDays + 1;
    return days > 0 ? days : null;
  }

  /// Calendar length of the sprint, null when either date is missing.
  int? get lengthInDays {
    final start = startDate;
    final finish = finishDate;
    if (start == null || finish == null) return null;
    return _day(finish).difference(_day(start)).inDays + 1;
  }

  bool get hasDates => startDate != null && finishDate != null;

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);
}
