import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/models/analytics.dart';
import '../../../theme/theme.dart';
import 'chart_format.dart';

/// Velocity: two bars per iteration — what was planned on its first day,
/// and what actually happened, stacked into completed, completed late and
/// still incomplete (research/19 §1, D-C).
///
/// Two bars rather than one stack with a planned segment: planned and
/// delivered are two measurements of the same iteration and the eye
/// compares their heights; stacking them would make the tall bar the sum of
/// things that are not additive.
class VelocityChart extends StatelessWidget {
  const VelocityChart({
    super.key,
    required this.iterations,
    required this.height,
    this.useStoryPoints = false,
  });

  final List<VelocityIteration> iterations;
  final double height;

  /// Sum story points instead of counting work items (the widget's
  /// `aggregation` is 1/sum).
  final bool useStoryPoints;

  double _planned(VelocityIteration i) =>
      useStoryPoints ? i.plannedPoints : i.planned.toDouble();
  double _completed(VelocityIteration i) =>
      useStoryPoints ? i.completedPoints : i.completed.toDouble();
  double _late(VelocityIteration i) =>
      useStoryPoints ? i.completedLatePoints : i.completedLate.toDouble();
  double _incomplete(VelocityIteration i) {
    final value = useStoryPoints ? i.incompletePoints : i.incomplete.toDouble();
    // Analytics can answer a negative leftover when an item moved out of the
    // iteration after it closed; a negative bar is not a thing.
    return value < 0 ? 0 : value;
  }

  static List<ChartKey> keysFor(BuildContext context) {
    final colors = context.boardhopColors;
    return [
      ChartKey('Planned', colors.series(0)),
      ChartKey('Completed', colors.stateCompleted),
      ChartKey('Completed late', colors.stateResolved),
      ChartKey('Incomplete', colors.stateProposed),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (iterations.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final scale = axisTextScale(context);

    var maxY = 1.0;
    for (final it in iterations) {
      final actual = _completed(it) + _late(it) + _incomplete(it);
      maxY = math.max(maxY, math.max(_planned(it), actual));
    }
    // Two bars per group, and the group has to stay readable at six
    // iterations on a phone.
    final barWidth = iterations.length > 6 ? 6.0 : 10.0;
    // Story points can be halves; a count of work items cannot.
    final axis = chartAxis(
      maxY,
      ticks: axisTicks(scale),
      integral: !useStoryPoints,
    );

    return SizedBox(
      height: height,
      child: Padding(
        padding: chartInsets(scale),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: axis.max,
            minY: 0,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: axis.interval,
              getDrawingHorizontalLine: (_) => FlLine(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32 * scale,
                  interval: axis.interval,
                  getTitlesWidget: (value, meta) => axis.showsLabel(value)
                      ? SideTitleWidget(
                          meta: meta,
                          child: Text(
                            axis.label(value),
                            style: labelStyle,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24 * scale,
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if (i < 0 || i >= iterations.length) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        shortIterationName(iterations[i].iteration.name),
                        style: labelStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final it = iterations[group.x];
                  final text = rodIndex == 0
                      ? '${it.iteration.name}\n'
                            '${chartNumber(_planned(it))} planned'
                      : '${it.iteration.name}\n'
                            '${chartNumber(_completed(it))} completed · '
                            '${chartNumber(_late(it))} late · '
                            '${chartNumber(_incomplete(it))} incomplete';
                  return BarTooltipItem(
                    text,
                    theme.textTheme.labelSmall!.copyWith(
                      color: scheme.onInverseSurface,
                    ),
                  );
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < iterations.length; i++)
                () {
                  final it = iterations[i];
                  final done = _completed(it);
                  final late = done + _late(it);
                  final all = late + _incomplete(it);
                  return BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY: _planned(it),
                        width: barWidth,
                        color: colors.series(0),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                      BarChartRodData(
                        toY: all,
                        width: barWidth,
                        // Every visible pixel comes from the stack items; the
                        // rod's own colour only shows on an all-zero bar.
                        color: scheme.surfaceContainerHighest,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                        rodStackItems: [
                          if (done > 0)
                            BarChartRodStackItem(
                              0,
                              done,
                              colors.stateCompleted,
                            ),
                          if (late > done)
                            BarChartRodStackItem(
                              done,
                              late,
                              colors.stateResolved,
                            ),
                          if (all > late)
                            BarChartRodStackItem(
                              late,
                              all,
                              colors.stateProposed,
                            ),
                        ],
                      ),
                    ],
                  );
                }(),
            ],
          ),
        ),
      ),
    );
  }
}
