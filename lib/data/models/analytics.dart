import 'package:equatable/equatable.dart';

/// The typed results of the Analytics (OData) queries behind the dashboard
/// cards (research/19 §1, spike s61). Every one round-trips through JSON
/// because `AnalyticsRepository` caches the parsed shape, not the raw rows.

/// One iteration as Analytics names it.
class AnalyticsIteration extends Equatable {
  const AnalyticsIteration({
    required this.sk,
    required this.name,
    this.startDate,
    this.endDate,
    this.isEnded = false,
  });

  factory AnalyticsIteration.fromRow(Map<String, dynamic> row) =>
      AnalyticsIteration(
        sk: row['IterationSK'] as String? ?? '',
        name: row['IterationName'] as String? ?? '',
        startDate: _date(row['StartDate']),
        endDate: _date(row['EndDate']),
        isEnded: row['IsEnded'] as bool? ?? false,
      );

  factory AnalyticsIteration.fromJson(Map<String, dynamic> json) =>
      AnalyticsIteration(
        sk: json['sk'] as String? ?? '',
        name: json['name'] as String? ?? '',
        startDate: _date(json['startDate']),
        endDate: _date(json['endDate']),
        isEnded: json['isEnded'] as bool? ?? false,
      );

  final String sk;
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isEnded;

  Map<String, dynamic> toJson() => {
    'sk': sk,
    'name': name,
    if (startDate != null) 'startDate': startDate!.toIso8601String(),
    if (endDate != null) 'endDate': endDate!.toIso8601String(),
    'isEnded': isEnded,
  };

  @override
  List<Object?> get props => [sk, name, startDate, endDate, isEnded];
}

/// One bar of the velocity chart.
///
/// Four numbers per iteration, from four separate Analytics calls (an
/// or-chain of iteration/date pairs took 55 s, spike s61): what was planned
/// on the first day, what was completed by the end date, what was completed
/// after it, and what was still in progress.
class VelocityIteration extends Equatable {
  const VelocityIteration({
    required this.iteration,
    this.planned = 0,
    this.plannedPoints = 0,
    this.completed = 0,
    this.completedPoints = 0,
    this.completedLate = 0,
    this.completedLatePoints = 0,
    this.incomplete = 0,
    this.incompletePoints = 0,
  });

  factory VelocityIteration.fromJson(Map<String, dynamic> json) =>
      VelocityIteration(
        iteration: AnalyticsIteration.fromJson(
          ((json['iteration'] as Map?) ?? const {}).cast<String, dynamic>(),
        ),
        planned: (json['planned'] as num?)?.toInt() ?? 0,
        plannedPoints: (json['plannedPoints'] as num?)?.toDouble() ?? 0,
        completed: (json['completed'] as num?)?.toInt() ?? 0,
        completedPoints: (json['completedPoints'] as num?)?.toDouble() ?? 0,
        completedLate: (json['completedLate'] as num?)?.toInt() ?? 0,
        completedLatePoints:
            (json['completedLatePoints'] as num?)?.toDouble() ?? 0,
        incomplete: (json['incomplete'] as num?)?.toInt() ?? 0,
        incompletePoints: (json['incompletePoints'] as num?)?.toDouble() ?? 0,
      );

  final AnalyticsIteration iteration;

  /// Items in the iteration on its start date (the snapshot).
  final int planned;
  final double plannedPoints;

  /// Completed on or before the iteration's end date.
  final int completed;
  final double completedPoints;

  /// Completed after it.
  final int completedLate;
  final double completedLatePoints;

  /// Still not completed.
  final int incomplete;
  final double incompletePoints;

  int get totalCompleted => completed + completedLate;

  Map<String, dynamic> toJson() => {
    'iteration': iteration.toJson(),
    'planned': planned,
    'plannedPoints': plannedPoints,
    'completed': completed,
    'completedPoints': completedPoints,
    'completedLate': completedLate,
    'completedLatePoints': completedLatePoints,
    'incomplete': incomplete,
    'incompletePoints': incompletePoints,
  };

  @override
  List<Object?> get props => [
    iteration,
    planned,
    plannedPoints,
    completed,
    completedPoints,
    completedLate,
    completedLatePoints,
    incomplete,
    incompletePoints,
  ];
}

/// One day of the cumulative flow diagram: a count per board column, in the
/// board's current column order.
class CumulativeFlowDay extends Equatable {
  const CumulativeFlowDay({required this.date, required this.counts});

  factory CumulativeFlowDay.fromJson(Map<String, dynamic> json) =>
      CumulativeFlowDay(
        date: _date(json['date']) ?? DateTime.utc(0),
        counts: {
          for (final e in ((json['counts'] as Map?) ?? const {}).entries)
            e.key.toString(): (e.value as num?)?.toInt() ?? 0,
        },
      );

  final DateTime date;
  final Map<String, int> counts;

  int countFor(String column) => counts[column] ?? 0;

  int get total => counts.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'counts': counts,
  };

  @override
  List<Object?> get props => [date, counts];
}

/// The cumulative flow diagram: the board's columns in order, and one entry
/// per day.
class CumulativeFlow extends Equatable {
  const CumulativeFlow({this.columns = const [], this.days = const []});

  factory CumulativeFlow.fromJson(Map<String, dynamic> json) => CumulativeFlow(
    columns: [
      for (final c in (json['columns'] as List?) ?? const [])
        if (c is String) c,
    ],
    days: [
      for (final d in (json['days'] as List?) ?? const [])
        if (d is Map) CumulativeFlowDay.fromJson(d.cast<String, dynamic>()),
    ],
  );

  /// In the board's **current** column order. A renamed column splits the
  /// snapshot rows, so the series are merged by name and any name the
  /// snapshots carry but the board no longer has is appended at the end.
  final List<String> columns;
  final List<CumulativeFlowDay> days;

  bool get isEmpty => days.isEmpty || columns.isEmpty;

  Map<String, dynamic> toJson() => {
    'columns': columns,
    'days': [for (final d in days) d.toJson()],
  };

  @override
  List<Object?> get props => [columns, days];
}

/// One completed work item, with the two durations Analytics computes.
class CycleLeadItem extends Equatable {
  const CycleLeadItem({
    required this.workItemId,
    this.workItemType,
    this.state,
    this.cycleTimeDays,
    this.leadTimeDays,
    this.completedDate,
  });

  factory CycleLeadItem.fromRow(Map<String, dynamic> row) => CycleLeadItem(
    workItemId: (row['WorkItemId'] as num?)?.toInt() ?? 0,
    workItemType: row['WorkItemType'] as String?,
    state: row['State'] as String?,
    cycleTimeDays: (row['CycleTimeDays'] as num?)?.toDouble(),
    leadTimeDays: (row['LeadTimeDays'] as num?)?.toDouble(),
    completedDate: _date(row['CompletedDate']),
  );

  factory CycleLeadItem.fromJson(Map<String, dynamic> json) => CycleLeadItem(
    workItemId: (json['id'] as num?)?.toInt() ?? 0,
    workItemType: json['type'] as String?,
    state: json['state'] as String?,
    cycleTimeDays: (json['cycle'] as num?)?.toDouble(),
    leadTimeDays: (json['lead'] as num?)?.toDouble(),
    completedDate: _date(json['completed']),
  );

  final int workItemId;
  final String? workItemType;
  final String? state;

  /// Days from first In Progress to Completed; null on an item that was
  /// never started (closed straight from Proposed).
  final double? cycleTimeDays;

  /// Days from created to Completed.
  final double? leadTimeDays;
  final DateTime? completedDate;

  Map<String, dynamic> toJson() => {
    'id': workItemId,
    if (workItemType != null) 'type': workItemType,
    if (state != null) 'state': state,
    if (cycleTimeDays != null) 'cycle': cycleTimeDays,
    if (leadTimeDays != null) 'lead': leadTimeDays,
    if (completedDate != null) 'completed': completedDate!.toIso8601String(),
  };

  @override
  List<Object?> get props => [
    workItemId,
    workItemType,
    state,
    cycleTimeDays,
    leadTimeDays,
    completedDate,
  ];
}

/// Cycle and lead time over a window: every completed item plus the averages.
class CycleLeadTime extends Equatable {
  const CycleLeadTime({this.items = const []});

  factory CycleLeadTime.fromJson(Map<String, dynamic> json) => CycleLeadTime(
    items: [
      for (final i in (json['items'] as List?) ?? const [])
        if (i is Map) CycleLeadItem.fromJson(i.cast<String, dynamic>()),
    ],
  );

  final List<CycleLeadItem> items;

  int get count => items.length;

  /// The mean over the items that have a value; null when none do. Computed
  /// here rather than asked for as a second `aggregate(… with average)` call,
  /// which spike s61 showed answers the same numbers for 0.4 s more.
  double? get averageCycleDays => _mean([
    for (final i in items) ?i.cycleTimeDays,
  ]);

  double? get averageLeadDays => _mean([
    for (final i in items) ?i.leadTimeDays,
  ]);

  bool get isEmpty => items.isEmpty;

  static double? _mean(List<double> values) => values.isEmpty
      ? null
      : values.reduce((a, b) => a + b) / values.length;

  Map<String, dynamic> toJson() => {
    'items': [for (final i in items) i.toJson()],
  };

  @override
  List<Object?> get props => [items];
}

/// One `(WorkItemType, State, StateCategory)` bucket.
class WorkStateCount extends Equatable {
  const WorkStateCount({
    required this.workItemType,
    required this.state,
    required this.stateCategory,
    required this.count,
  });

  factory WorkStateCount.fromRow(Map<String, dynamic> row) => WorkStateCount(
    workItemType: row['WorkItemType'] as String? ?? '',
    state: row['State'] as String? ?? '',
    stateCategory: row['StateCategory'] as String? ?? '',
    count: (row['Count'] as num?)?.toInt() ?? 0,
  );

  factory WorkStateCount.fromJson(Map<String, dynamic> json) => WorkStateCount(
    workItemType: json['type'] as String? ?? '',
    state: json['state'] as String? ?? '',
    stateCategory: json['category'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
  );

  final String workItemType;
  final String state;

  /// `Proposed`, `InProgress`, `Resolved`, `Completed` (`Removed` is filtered
  /// out by the query).
  final String stateCategory;
  final int count;

  Map<String, dynamic> toJson() => {
    'type': workItemType,
    'state': state,
    'category': stateCategory,
    'count': count,
  };

  @override
  List<Object?> get props => [workItemType, state, stateCategory, count];
}

/// One pipeline run, as Analytics reports it (the Build History card draws
/// these; the REST run list is what a tap opens).
class AnalyticsPipelineRun extends Equatable {
  const AnalyticsPipelineRun({
    required this.runId,
    this.runNumber,
    this.outcome,
    this.reason,
    this.queuedDate,
    this.startedDate,
    this.completedDate,
    this.durationSeconds,
  });

  factory AnalyticsPipelineRun.fromRow(Map<String, dynamic> row) =>
      AnalyticsPipelineRun(
        runId: (row['PipelineRunId'] as num?)?.toInt() ?? 0,
        runNumber: row['RunNumber']?.toString(),
        outcome: row['RunOutcome'] as String?,
        reason: row['RunReason'] as String?,
        queuedDate: _date(row['QueuedDate']),
        startedDate: _date(row['StartedDate']),
        completedDate: _date(row['CompletedDate']),
        durationSeconds: (row['RunDurationSeconds'] as num?)?.toDouble(),
      );

  factory AnalyticsPipelineRun.fromJson(Map<String, dynamic> json) =>
      AnalyticsPipelineRun(
        runId: (json['id'] as num?)?.toInt() ?? 0,
        runNumber: json['number'] as String?,
        outcome: json['outcome'] as String?,
        reason: json['reason'] as String?,
        queuedDate: _date(json['queued']),
        startedDate: _date(json['started']),
        completedDate: _date(json['completed']),
        durationSeconds: (json['seconds'] as num?)?.toDouble(),
      );

  final int runId;
  final String? runNumber;

  /// `Succeed`, `Failed` or `Canceled` — note `Succeed`, not `Succeeded`
  /// (spike s61).
  final String? outcome;
  final String? reason;
  final DateTime? queuedDate;
  final DateTime? startedDate;
  final DateTime? completedDate;
  final double? durationSeconds;

  bool get succeeded => outcome == 'Succeed';
  bool get failed => outcome == 'Failed';
  bool get canceled => outcome == 'Canceled';

  Map<String, dynamic> toJson() => {
    'id': runId,
    if (runNumber != null) 'number': runNumber,
    if (outcome != null) 'outcome': outcome,
    if (reason != null) 'reason': reason,
    if (queuedDate != null) 'queued': queuedDate!.toIso8601String(),
    if (startedDate != null) 'started': startedDate!.toIso8601String(),
    if (completedDate != null) 'completed': completedDate!.toIso8601String(),
    if (durationSeconds != null) 'seconds': durationSeconds,
  };

  @override
  List<Object?> get props => [
    runId,
    runNumber,
    outcome,
    reason,
    completedDate,
    durationSeconds,
  ];
}

/// A pipeline's outcomes over a window, plus its most recent runs.
class PipelineOutcomes extends Equatable {
  const PipelineOutcomes({
    this.total = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.partial = 0,
    this.canceled = 0,
    this.runs = const [],
  });

  factory PipelineOutcomes.fromAggregate(
    Map<String, dynamic>? row, {
    List<AnalyticsPipelineRun> runs = const [],
  }) => PipelineOutcomes(
    total: (row?['TotalCount'] as num?)?.toInt() ?? 0,
    succeeded: (row?['Succeeded'] as num?)?.toInt() ?? 0,
    failed: (row?['Failed'] as num?)?.toInt() ?? 0,
    partial: (row?['Partial'] as num?)?.toInt() ?? 0,
    canceled: (row?['Canceled'] as num?)?.toInt() ?? 0,
    runs: runs,
  );

  factory PipelineOutcomes.fromJson(Map<String, dynamic> json) =>
      PipelineOutcomes(
        total: (json['total'] as num?)?.toInt() ?? 0,
        succeeded: (json['succeeded'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as num?)?.toInt() ?? 0,
        partial: (json['partial'] as num?)?.toInt() ?? 0,
        canceled: (json['canceled'] as num?)?.toInt() ?? 0,
        runs: [
          for (final r in (json['runs'] as List?) ?? const [])
            if (r is Map)
              AnalyticsPipelineRun.fromJson(r.cast<String, dynamic>()),
        ],
      );

  final int total;
  final int succeeded;
  final int failed;

  /// Partially succeeded runs count as neither a pass nor a fail here; the
  /// card shows them as their own segment.
  final int partial;
  final int canceled;
  final List<AnalyticsPipelineRun> runs;

  /// Succeeded over everything that reached a verdict (canceled runs never
  /// did), or null when nothing ran.
  double? get passRate {
    final judged = succeeded + failed + partial;
    return judged == 0 ? null : succeeded / judged;
  }

  Map<String, dynamic> toJson() => {
    'total': total,
    'succeeded': succeeded,
    'failed': failed,
    'partial': partial,
    'canceled': canceled,
    'runs': [for (final r in runs) r.toJson()],
  };

  @override
  List<Object?> get props => [
    total,
    succeeded,
    failed,
    partial,
    canceled,
    runs,
  ];
}

DateTime? _date(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(
    text.length == 10 ? '${text}T00:00:00Z' : text,
  )?.toUtc();
}
