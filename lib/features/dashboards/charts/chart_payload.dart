import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../../data/models/analytics.dart';
import '../../../data/models/sprint.dart';
import '../../../theme/theme.dart';
import '../../sprints/widgets/sprint_burndown_chart.dart';
import 'chart_format.dart';
import 'cumulative_flow_chart.dart';
import 'cycle_time_chart.dart';
import 'run_outcome_bars.dart';
import 'velocity_chart.dart';
import 'work_state_bars.dart';

/// What a chart card has loaded: the data, already shaped for drawing, plus
/// everything both places that draw it need — the chart, its legend, the
/// numbers as a list, and the sentence a screen reader hears (DESIGN.md §8).
///
/// The card and the focus view (D7) draw the *same* payload: the card hands
/// it to the route through `extra`, and a focus view opened cold rebuilds it
/// from the cache through the loader that made it. That is why this holds
/// data and not widgets.
sealed class ChartPayload {
  const ChartPayload();

  /// The chart's own name, which is the focus view's title when the widget
  /// on the dashboard has none.
  String get title;

  /// The one number worth reading without the chart, or null.
  String? get headline;

  /// A line under the headline: what the number is of, and over what.
  String? get summary;

  /// True when there is nothing to draw — a team with no sprints, a board
  /// with no snapshots, a pipeline that never ran.
  bool get isEmpty;

  /// What the card says instead of a chart when [isEmpty].
  String get emptyNote;

  /// One sentence naming the series and its latest values.
  String get semanticsLabel;

  /// The heading over the focus view's data list.
  String get rowsTitle;

  /// The chart itself, wrapped in [Semantics] with [semanticsLabel] and an
  /// [ExcludeSemantics] around the painting (fl_chart has no semantics of
  /// its own).
  Widget chart(
    BuildContext context, {
    required double height,
    bool compact = false,
  });

  List<ChartKey> keys(BuildContext context);

  List<ChartRow> rows();

  /// The wrapper every chart shares, so no card forgets it.
  @protected
  Widget describe(Widget child) => Semantics(
    label: semanticsLabel,
    child: ExcludeSemantics(child: child),
  );
}

/// Burndown, Burnup and both Sprint Burndown widgets (research/19 D3, D14).
///
/// One shape, because Analytics answers all four with the same
/// `WorkItemSnapshot` rows: [days] carries the value to draw in its
/// `remaining` field — the work left on a burndown, the work completed on a
/// burnup — and [ideal] is the straight line beside it.
class BurndownPayload extends ChartPayload {
  const BurndownPayload({
    required this.title,
    required this.days,
    required this.ideal,
    this.unit = 'items',
    this.burnup = false,
    this.summary,
    this.sourceDays = const [],
    this.noDataNote,
  });

  @override
  final String title;

  /// The drawn series, in `remaining`.
  final List<BurndownDay> days;
  final List<double> ideal;
  final String unit;
  final bool burnup;

  @override
  final String? summary;

  /// The rows as Analytics answered them, for the data list's second
  /// number (a burndown lists what was done that day, and the other way
  /// round).
  final List<BurndownDay> sourceDays;

  /// What the card says when there is nothing to draw and the reason is
  /// known — a team with no sprints at all, rather than a sprint with no
  /// snapshots yet.
  final String? noDataNote;

  @override
  bool get isEmpty => days.length < 2;

  @override
  String get emptyNote =>
      noDataNote ??
      (burnup
          ? 'No completed work in this period yet.'
          : 'No snapshots in this period yet.');

  @override
  String get rowsTitle => 'Day by day';

  @override
  String? get headline =>
      days.isEmpty ? null : chartNumber(days.last.remaining);

  @override
  String get semanticsLabel {
    if (days.isEmpty) return '$title. No data.';
    final last = days.length - 1;
    final verb = burnup ? 'completed' : 'remaining';
    final buffer = StringBuffer(
      '$title. ${chartNumber(days[last].remaining)} $unit $verb '
      'on ${chartDayFormat.format(days[last].date)}, '
      'day ${last + 1} of ${days.length}.',
    );
    if (last < ideal.length) {
      buffer.write(' Ideal ${chartNumber(ideal[last])} $unit.');
    }
    return buffer.toString();
  }

  @override
  Widget chart(
    BuildContext context, {
    required double height,
    bool compact = false,
  }) {
    final colors = context.boardhopColors;
    // SprintBurndownChart already wraps itself in the Semantics /
    // ExcludeSemantics pair, with the label this payload gives it.
    return SprintBurndownChart(
      days: days,
      ideal: ideal,
      mode: BurndownMode.full,
      unit: unit,
      height: height,
      semanticsLabel: semanticsLabel,
      actualColor: burnup ? colors.stateCompleted : null,
    );
  }

  @override
  List<ChartKey> keys(BuildContext context) {
    final colors = context.boardhopColors;
    return [
      ChartKey(
        burnup ? 'Completed' : 'Remaining',
        burnup ? colors.stateCompleted : colors.burndownActual,
      ),
      ChartKey('Ideal', colors.burndownIdeal, dashed: true),
    ];
  }

  @override
  List<ChartRow> rows() => [
    for (var i = 0; i < days.length; i++)
      ChartRow(
        label: chartDayFormat.format(days[i].date),
        value: '${chartNumber(days[i].remaining)} $unit',
        detail: i < ideal.length ? 'ideal ${chartNumber(ideal[i])}' : null,
      ),
  ];
}

/// Velocity over the last N iterations (D3, D9).
class VelocityPayload extends ChartPayload {
  const VelocityPayload({
    required this.title,
    required this.iterations,
    this.useStoryPoints = false,
  });

  @override
  final String title;

  /// Newest first, as Analytics answers; the chart draws them oldest left.
  final List<VelocityIteration> iterations;
  final bool useStoryPoints;

  List<VelocityIteration> get _ordered => iterations.reversed.toList();

  double _done(VelocityIteration i) => useStoryPoints
      ? i.completedPoints + i.completedLatePoints
      : i.totalCompleted.toDouble();

  String get unit => useStoryPoints ? 'points' : 'items';

  @override
  bool get isEmpty => iterations.isEmpty;

  @override
  String get emptyNote => 'This team has no dated iterations.';

  @override
  String get rowsTitle => 'Iterations';

  @override
  String? get headline {
    if (iterations.isEmpty) return null;
    final total = iterations.fold<double>(0, (sum, i) => sum + _done(i));
    return chartNumber(total / iterations.length);
  }

  @override
  String? get summary => iterations.isEmpty
      ? null
      : '$unit completed per iteration, over '
            '${countOf(iterations.length, 'iteration')}';

  @override
  String get semanticsLabel {
    if (iterations.isEmpty) return '$title. No iterations.';
    final latest = iterations.first;
    return '$title. ${latest.iteration.name}: '
        '${chartNumber(_done(latest))} $unit completed of '
        '${chartNumber(useStoryPoints ? latest.plannedPoints : latest.planned)} '
        'planned. Average $headline $unit over '
        '${countOf(iterations.length, 'iteration')}.';
  }

  @override
  Widget chart(
    BuildContext context, {
    required double height,
    bool compact = false,
  }) => describe(
    VelocityChart(
      iterations: _ordered,
      height: height,
      useStoryPoints: useStoryPoints,
    ),
  );

  @override
  List<ChartKey> keys(BuildContext context) => VelocityChart.keysFor(context);

  @override
  List<ChartRow> rows() => [
    for (final i in iterations)
      ChartRow(
        label: i.iteration.name,
        value: '${chartNumber(_done(i))} $unit',
        detail:
            '${chartNumber(useStoryPoints ? i.plannedPoints : i.planned)} '
            'planned · ${chartNumber(useStoryPoints ? i.completedLatePoints : i.completedLate)} late '
            '· ${chartNumber(useStoryPoints ? i.incompletePoints : i.incomplete)} incomplete',
      ),
  ];
}

/// The cumulative flow of one board over a window of days (D3, D9).
class CumulativeFlowPayload extends ChartPayload {
  CumulativeFlowPayload({
    required this.title,
    required CumulativeFlow flow,
    required this.days,
    this.boardName,
    this.noDataNote,
  }) : series = CumulativeFlowSeries.from(flow);

  @override
  final String title;

  final CumulativeFlowSeries series;
  final int days;
  final String? boardName;

  /// Why there is no chart, when the reason is not "no snapshots yet".
  final String? noDataNote;

  @override
  bool get isEmpty => series.isEmpty;

  @override
  String get emptyNote =>
      noDataNote ?? 'No board snapshots in the last $days days.';

  @override
  String get rowsTitle => 'Day by day';

  @override
  String? get headline =>
      series.isEmpty ? null : '${series.totalOn(series.days.length - 1)}';

  @override
  String? get summary => series.isEmpty
      ? null
      : 'items on the ${boardName ?? 'board'} today, over $days days';

  @override
  String get semanticsLabel {
    if (series.isEmpty) return '$title. No data.';
    final last = series.days.length - 1;
    final parts = [
      for (var c = 0; c < series.columns.length; c++)
        '${series.columns[c]} ${series.days[last].counts[c]}',
    ];
    return '$title. ${chartDayFormat.format(series.days[last].date)}: '
        '${parts.join(', ')}. ${series.totalOn(last)} items in total.';
  }

  @override
  Widget chart(
    BuildContext context, {
    required double height,
    bool compact = false,
  }) => describe(CumulativeFlowChart(series: series, height: height));

  @override
  List<ChartKey> keys(BuildContext context) =>
      CumulativeFlowChart.keysFor(context, series);

  @override
  List<ChartRow> rows() => [
    for (var d = series.days.length - 1; d >= 0; d--)
      ChartRow(
        label: chartDayFormat.format(series.days[d].date),
        value: '${series.totalOn(d)} items',
        detail: [
          for (var c = 0; c < series.columns.length; c++)
            '${series.columns[c]} ${series.days[d].counts[c]}',
        ].join(' · '),
      ),
  ];
}

/// Cycle time and lead time (D3, D9): a scatter of completed items with a
/// rolling average, and the averages as the headline.
class CycleTimePayload extends ChartPayload {
  const CycleTimePayload({
    required this.title,
    required this.data,
    required this.days,
    this.lead = false,
    this.showBoth = false,
  });

  @override
  final String title;

  final CycleLeadTime data;

  /// The window the widget's settings asked for, which also sets the
  /// rolling-average window.
  final int days;

  /// Draw lead time rather than cycle time.
  final bool lead;

  /// The Team overview's one card carries both averages (D9); the two
  /// dashboard widgets carry one each.
  final bool showBoth;

  double? _value(CycleLeadItem item) =>
      lead ? item.leadTimeDays : item.cycleTimeDays;

  double? get average => lead ? data.averageLeadDays : data.averageCycleDays;

  List<CycleTimePoint> get points => [
    for (final item in data.items)
      if (_value(item) case final value?)
        if (item.completedDate case final date?)
          (
            date: date,
            days: value,
            label: '#${item.workItemId} ${item.workItemType ?? ''}'.trim(),
          ),
  ];

  @override
  bool get isEmpty => points.isEmpty;

  @override
  String get emptyNote => 'Nothing was completed in the last $days days.';

  @override
  String get rowsTitle => 'Completed items';

  @override
  String? get headline {
    final value = average;
    return value == null ? null : '${chartNumber(value)} days';
  }

  @override
  String? get summary {
    final label = lead ? 'lead time' : 'cycle time';
    if (!showBoth) {
      return 'average $label over $days days, '
          '${countOf(data.count, 'item')}';
    }
    final other = lead ? data.averageCycleDays : data.averageLeadDays;
    final otherLabel = lead ? 'cycle time' : 'lead time';
    final otherText = other == null
        ? 'no $otherLabel'
        : 'average $otherLabel ${chartNumber(other)} days';
    return 'average $label over $days days · $otherText · '
        '${countOf(data.count, 'item')}';
  }

  @override
  String get semanticsLabel {
    if (isEmpty) return '$title. Nothing completed in $days days.';
    final label = lead ? 'lead time' : 'cycle time';
    return '$title. Average $label $headline over '
        '${countOf(points.length, 'item')} completed in the last $days days.';
  }

  @override
  Widget chart(
    BuildContext context, {
    required double height,
    bool compact = false,
  }) => describe(
    CycleTimeChart(
      points: points,
      height: height,
      window: rollingWindowForDays(days),
    ),
  );

  @override
  List<ChartKey> keys(BuildContext context) =>
      CycleTimeChart.keysFor(context, lead: lead);

  @override
  List<ChartRow> rows() => [
    for (final item in data.items.reversed)
      if (_value(item) case final value?)
        ChartRow(
          label: '#${item.workItemId} ${item.workItemType ?? ''}'.trim(),
          value: '${chartNumber(value)} days',
          detail: item.completedDate == null
              ? null
              : 'completed ${chartDayFormat.format(item.completedDate!)}',
        ),
  ];
}

/// The team's work by type and state — a Team overview card (D9).
class WorkByStatePayload extends ChartPayload {
  WorkByStatePayload({
    required this.title,
    required List<WorkStateCount> counts,
  }) : series = WorkByStateSeries.from(counts),
       _counts = counts;

  @override
  final String title;

  final WorkByStateSeries series;
  final List<WorkStateCount> _counts;

  @override
  bool get isEmpty => series.isEmpty;

  @override
  String get emptyNote => 'This team has no work items.';

  @override
  String get rowsTitle => 'By type and state';

  @override
  String? get headline => series.isEmpty ? null : '${series.total}';

  @override
  String? get summary => series.isEmpty
      ? null
      : 'work items across ${countOf(series.types.length, 'type')}';

  @override
  String get semanticsLabel {
    if (series.isEmpty) return '$title. No work items.';
    final parts = [
      for (var i = 0; i < WorkByStateSeries.categories.length; i++)
        () {
          final category = WorkByStateSeries.categories[i];
          final total = series.types.fold<int>(
            0,
            (sum, t) => sum + t.counts[i],
          );
          return '${WorkByStateSeries.categoryLabel(category)} $total';
        }(),
    ];
    return '$title. ${series.total} work items: ${parts.join(', ')}.';
  }

  @override
  Widget chart(
    BuildContext context, {
    required double height,
    bool compact = false,
  }) {
    // One bar is a label, a 12 dp bar and a gap; at xxxL that is half as
    // tall again, which overflowed a phone card by 18 px on the iPhone 17
    // (D-C check). So the card draws what fits, says how many types it left
    // out, and clips whatever the text scale still pushes past the edge.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final rowHeight = 20 * scale + 24;
    final fits = math.max(1, ((height - 18) / rowHeight).floor());
    return describe(
      SizedBox(
        height: height,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: double.infinity,
            fit: OverflowBoxFit.deferToChild,
            child: WorkStateBars(
              series: series,
              maxTypes: fits >= series.types.length ? null : fits,
            ),
          ),
        ),
      ),
    );
  }

  @override
  List<ChartKey> keys(BuildContext context) =>
      WorkByStateSeries.keysFor(context);

  @override
  List<ChartRow> rows() {
    final sorted = [..._counts]
      ..sort((a, b) {
        final type = a.workItemType.compareTo(b.workItemType);
        return type != 0 ? type : b.count.compareTo(a.count);
      });
    return [
      for (final c in sorted)
        ChartRow(
          label: '${c.workItemType} · ${c.state}',
          value: '${c.count}',
          detail: WorkByStateSeries.categoryLabel(c.stateCategory),
        ),
    ];
  }
}

/// One pipeline's outcomes over a window — a Team overview card (D9).
class PipelineOutcomesPayload extends ChartPayload {
  const PipelineOutcomesPayload({
    required this.title,
    required this.outcomes,
    required this.days,
    this.pipelineName,
    this.pipelineId,
  });

  @override
  final String title;

  final PipelineOutcomes outcomes;
  final int days;
  final String? pipelineName;
  final int? pipelineId;

  @override
  bool get isEmpty => outcomes.runs.isEmpty && outcomes.total == 0;

  @override
  String get emptyNote => 'No runs in the last $days days.';

  @override
  String get rowsTitle => 'Recent runs';

  @override
  String? get headline {
    final rate = outcomes.passRate;
    return rate == null ? null : '${(rate * 100).round()}%';
  }

  @override
  String? get summary =>
      '${pipelineName ?? 'Pipeline'} · '
      '${countOf(outcomes.total, 'run')} in $days days'
      '${outcomes.failed == 0 ? '' : ', ${outcomes.failed} failed'}';

  @override
  String get semanticsLabel {
    if (isEmpty) return '$title. No runs in the last $days days.';
    final rate = headline ?? 'no';
    return '$title. $rate pass rate over ${countOf(outcomes.total, 'run')} of '
        '${pipelineName ?? 'the pipeline'} in the last $days days. '
        '${outcomes.succeeded} succeeded, ${outcomes.failed} failed, '
        '${outcomes.canceled} canceled.';
  }

  @override
  Widget chart(
    BuildContext context, {
    required double height,
    bool compact = false,
  }) => describe(RunOutcomeBars(runs: outcomes.runs, height: height));

  @override
  List<ChartKey> keys(BuildContext context) => RunOutcomeBars.keysFor(context);

  @override
  List<ChartRow> rows() => [
    for (final run in outcomes.runs)
      ChartRow(
        label: 'Run ${run.runNumber ?? run.runId}',
        value: RunOutcomeBars.labelFor(run),
        detail: run.completedDate == null
            ? null
            : chartDayFormat.format(run.completedDate!.toLocal()),
      ),
  ];
}
