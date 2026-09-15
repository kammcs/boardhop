import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/sprint.dart';
import '../../../data/models/work_item_form.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_field_groups.dart';
import 'sprint_burndown_chart.dart';
import 'sprint_format.dart';

/// The Burndown tab (decision S6): the full chart with its legend, the
/// seven facts a burndown actually answers, and the day-by-day numbers as a
/// list — because a chart nobody can read is not an accessible answer on
/// its own (DESIGN.md §8, r2 §3.3).
///
/// The text ships whatever Analytics says. When the host refuses the app's
/// token the tab says exactly that, and when the sprint simply has no
/// history yet it says that instead; neither is an error strip, because
/// neither is something the user did wrong.
class SprintBurndownTab extends StatelessWidget {
  const SprintBurndownTab({
    super.key,
    required this.days,
    this.header,
    this.capacity,
    this.loading = false,
    this.unavailable = false,
    this.error,
    this.iteration,
    this.remaining,
    this.unit = 'items',
    this.now,
  });

  final List<BurndownDay> days;
  final Widget? header;
  final SprintCapacity? capacity;
  final bool loading;

  /// Analytics refused this sign-in (`AnalyticsUnavailable`).
  final bool unavailable;

  /// Anything else that went wrong reading it.
  final String? error;
  final TeamIteration? iteration;

  /// An override for the series' own last value. Left unset by the page:
  /// its rollup counts the sprint's tasks while Analytics counts every
  /// work item in the iteration, so the two are not interchangeable
  /// (13 against 125 on CloudCover's sprint — iPhone check, P-C).
  final double? remaining;
  final String unit;
  final DateTime? now;

  bool get _hasChart => days.length >= 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inset = MediaQuery.paddingOf(context);
    final ideal = burndownIdealLine(days, finish: iteration?.finishDate);
    final showPoints = days.any((d) => d.points > 0);
    final cap = capacity;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        inset.left,
        0,
        inset.right,
        Spacing.xl + inset.bottom,
      ),
      children: [
        ?header,
        if (loading)
          const Padding(
            padding: Spacing.page,
            child: LinearProgressIndicator(),
          ),
        if (_hasChart)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SprintBurndownChart(
                  days: days,
                  mode: BurndownMode.full,
                  ideal: ideal,
                  showPoints: showPoints,
                  unit: unit,
                  isNonWorkingDay: cap == null
                      ? null
                      : (day) => !cap.isWorkingDay(day),
                ),
                const SizedBox(height: Spacing.sm),
                BurndownLegend(showPoints: showPoints),
              ],
            ),
          ),
        if (!loading && !_hasChart)
          Padding(
            padding: Spacing.page,
            child: Text(
              _explanation(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: unavailable || error != null
                    ? scheme.onSurfaceVariant
                    : null,
              ),
            ),
          ),
        const SizedBox(height: Spacing.md),
        ..._facts(context, ideal),
        if (days.isNotEmpty) _DayList(days: days, unit: unit),
      ],
    );
  }

  /// One sentence for every reason the chart is not on screen. Analytics
  /// refusing the token is its own case: it is an administrator's setting,
  /// not a missing sprint, and telling the user "no data" would send them
  /// looking in the wrong place (decision S6).
  String _explanation() {
    if (unavailable) {
      return 'Analytics refused this sign-in, so there is no burndown '
          'chart. The numbers below come from the sprint itself. An '
          'organization administrator controls access to the Analytics '
          'service.';
    }
    final message = error;
    if (message != null) return 'The burndown could not be read: $message';
    final sprint = iteration;
    if (sprint != null && !sprint.hasDates) {
      return 'This sprint has no start and finish dates, so there is '
          'nothing to burn down against. Dates are set in the web.';
    }
    if (days.length == 1) {
      return 'Analytics has one day of history for this sprint so far; a '
          'line needs two.';
    }
    return 'Analytics has no history for this sprint yet. It records one '
        'snapshot a day, so a chart appears a day or two after the sprint '
        'starts.';
  }

  /// The facts a burndown answers, as [DetailFactRow]s — the part that
  /// survives a screen reader and AX XXXL type. Only the ones the data
  /// actually supports are shown.
  List<Widget> _facts(BuildContext context, List<double> ideal) {
    final theme = Theme.of(context);
    final last = days.isEmpty ? null : days.last;
    final actual = remaining ?? last?.remaining.toDouble();
    final daysLeft = sprintDaysLeft(iteration?.finishDate, now: now);
    final idealToday = days.isEmpty || ideal.isEmpty
        ? null
        : ideal[days.length - 1];
    final scope = days.length < 2
        ? null
        : (days.last.scope - days.first.scope).toDouble();
    final perDay = days.length < 2
        ? null
        : (days.first.remaining - days.last.remaining) / (days.length - 1);
    final rows = <Widget>[
      if (actual != null)
        DetailFactRow(label: 'Remaining', value: '${_n(actual)} $unit'),
      if (last != null) DetailFactRow(label: 'Done', value: '${last.done}'),
      if (scope != null)
        DetailFactRow(
          label: 'Scope change',
          value: '${scope >= 0 ? '+' : ''}${_n(scope)} $unit',
        ),
      if (daysLeft != null)
        DetailFactRow(
          label: 'Days left',
          value: daysLeft < 0
              ? sprintEndedLabel(iteration?.finishDate, now: now)
              : daysLeft == 1
              ? '1 day'
              : '$daysLeft days',
        ),
      if (idealToday != null)
        DetailFactRow(label: 'Ideal today', value: '${_n(idealToday)} $unit'),
      if (perDay != null)
        DetailFactRow(label: 'Average burn', value: '${_n(perDay)} $unit/day'),
      if (days.isNotEmpty)
        DetailFactRow(
          label: 'History',
          value: days.length == 1
              ? '1 day'
              : '${days.length} days, '
                    '${DateFormat('d MMM').format(days.first.date)} – '
                    '${DateFormat('d MMM').format(days.last.date)}',
        ),
    ];
    if (rows.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          Spacing.xs,
        ),
        child: Text('The numbers', style: theme.textTheme.titleSmall),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    ];
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Every day of the series as text, folded away by default: this is the
/// chart's accessible equivalent, not an extra feature (r2 §3.3).
class _DayList extends StatelessWidget {
  const _DayList({required this.days, required this.unit});

  final List<BurndownDay> days;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = DateFormat('EEE d MMM');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('Day by day', style: theme.textTheme.titleSmall),
        subtitle: Text(
          '${days.length} ${days.length == 1 ? 'day' : 'days'} of history',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        children: [
          for (final day in days)
            DetailFactRow(
              // Dates from Analytics are date-only at UTC midnight; a
              // local-time shift would move them a day (P-A §4).
              label: format.format(day.date),
              value: [
                '${day.remaining} $unit left',
                '${day.done} done',
                if (day.points > 0) '${_n(day.points)} pts',
              ].join(' · '),
            ),
        ],
      ),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}
