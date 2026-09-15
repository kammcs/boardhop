import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/dashboard.dart';
import '../../../data/models/sprint.dart';
import '../../../data/repositories/analytics_repository.dart';
import '../../../data/repositories/sprint_repository.dart';
import '../../sprints/widgets/sprint_burndown_chart.dart';
import 'chart_payload.dart';

/// The repositories every chart card reads, taken from the tree **before**
/// the first await so nothing touches a `BuildContext` across an async gap.
class ChartDeps {
  const ChartDeps({required this.analytics, required this.sprints});

  factory ChartDeps.of(BuildContext context) => ChartDeps(
    analytics: context.read<AnalyticsRepository>(),
    sprints: context.read<SprintRepository>(),
  );

  final AnalyticsRepository analytics;
  final SprintRepository sprints;

  /// The Analytics surrogate key of the team a card charts: the widget's own
  /// team when its settings name one, else the dashboard's, else the
  /// project's default team.
  Future<String> teamSk(
    String org,
    String project, {
    String? teamId,
    bool refresh = false,
  }) async {
    final id = teamId ?? await sprints.defaultTeamId(org, project);
    return analytics.teamSk(org, project, id, refresh: refresh);
  }

  /// The work item types a chart filters on.
  ///
  /// A `WorkItemType` filter names them; a `BacklogCategory` filter (and no
  /// filter at all, which is how every Team overview card arrives) means the
  /// team's requirement backlog, with Bug added when the widget asks for it
  /// — the `includeBugsForRequirementCategory` switch the Burndown widget
  /// carries (research/19 §1).
  Future<List<String>> types(
    String org,
    String project,
    String teamSk, {
    WidgetTypeFilter? filter,
    bool includeBugs = false,
    bool refresh = false,
  }) async {
    if (filter != null && !filter.isBacklogCategory) {
      final named = filter.workItemTypes;
      if (named.isNotEmpty) return named;
    }
    final requirement = await analytics.requirementTypes(
      org,
      project,
      teamSk,
      refresh: refresh,
    );
    if (!includeBugs || requirement.contains('Bug')) return requirement;
    return [...requirement, 'Bug']..sort();
  }
}

/// Turns the Analytics snapshot days into the payload the burndown, burnup
/// and both sprint burndown cards draw (research/19 D-C).
///
/// The drawn value lives in [BurndownDay.remaining] whichever chart this is:
/// the work still open on a burndown, the work completed on a burnup, the
/// story points still open when the widget aggregates by sum. Keeping one
/// shape is what lets all four widgets share `SprintBurndownChart`.
BurndownPayload burndownPayload({
  required String title,
  required List<BurndownDay> days,
  required bool burnup,
  bool useSum = false,
  DateTime? finish,
  String? unit,
  String? summary,
  String? noDataNote,
}) {
  final drawn = [
    for (final d in days)
      BurndownDay(
        date: d.date,
        // Story points are doubles and the chart's series is a count; a
        // fractional point is rare and the data list prints the exact
        // number beside it.
        remaining: burnup
            ? d.done
            : useSum
            ? d.points.round()
            : d.remaining,
        done: d.done,
        points: d.points,
      ),
  ];
  return BurndownPayload(
    title: title,
    days: drawn,
    ideal: burnup
        ? burnupIdealLine(days, finish: finish)
        : burndownIdealLine(drawn, finish: finish),
    unit: unit ?? (useSum ? 'points' : 'items'),
    burnup: burnup,
    summary: summary,
    sourceDays: days,
    noDataNote: noDataNote,
  );
}

/// The burnup's straight line: zero on the first day, the scope the team
/// ended up with on [finish].
///
/// The mirror of [burndownIdealLine] — same anchoring, same reason. The
/// target is the last day's total scope rather than the first day's,
/// because a burnup's whole point is that scope grows.
List<double> burnupIdealLine(List<BurndownDay> days, {DateTime? finish}) {
  if (days.isEmpty) return const [];
  final target = days.last.scope.toDouble();
  final last = days.length - 1;
  if (finish != null) {
    final span = _dayGap(days.first.date, finish);
    if (span > 0) {
      return [
        for (var i = 0; i <= last; i++)
          () {
            final value =
                target * (_dayGap(days.first.date, days[i].date) / span);
            return value > target ? target : value;
          }(),
      ];
    }
  }
  if (last == 0) return [target];
  return [for (var i = 0; i <= last; i++) target * (i / last)];
}

int _dayGap(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
