import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/models/analytics.dart';
import '../../../theme/theme.dart';
import 'chart_format.dart';

/// The cumulative flow's series after the board's columns have been capped
/// (research/19 D-C): at most [maxColumns] of them, everything past that
/// merged into one "Other", in the board's current order.
///
/// Pure, and separate from the chart, because both the chart and the focus
/// view's data list have to agree on which column a number belongs to.
class CumulativeFlowSeries {
  const CumulativeFlowSeries({required this.columns, required this.days});

  static const maxColumns = 6;
  static const otherLabel = 'Other';

  factory CumulativeFlowSeries.from(
    CumulativeFlow flow, {
    int maxColumns = CumulativeFlowSeries.maxColumns,
  }) {
    if (flow.columns.length <= maxColumns) {
      return CumulativeFlowSeries(
        columns: flow.columns,
        days: [
          for (final day in flow.days)
            (
              date: day.date,
              counts: [for (final c in flow.columns) day.countFor(c)],
            ),
        ],
      );
    }
    final kept = flow.columns.take(maxColumns).toList();
    final merged = flow.columns.skip(maxColumns).toList();
    return CumulativeFlowSeries(
      columns: [...kept, otherLabel],
      days: [
        for (final day in flow.days)
          (
            date: day.date,
            counts: [
              for (final c in kept) day.countFor(c),
              merged.fold(0, (sum, c) => sum + day.countFor(c)),
            ],
          ),
      ],
    );
  }

  /// The column names, in the board's current order, with the overflow
  /// column last when there was one.
  final List<String> columns;

  /// One entry per day: the count in each of [columns], in that order.
  final List<({DateTime date, List<int> counts})> days;

  bool get isEmpty => days.length < 2 || columns.isEmpty;

  int totalOn(int dayIndex) => days[dayIndex].counts.fold(0, (a, b) => a + b);

  /// The running total up to and including [column] on [dayIndex] — what
  /// the stacked area actually draws.
  double cumulative(int dayIndex, int column) {
    var sum = 0;
    for (var i = 0; i <= column; i++) {
      sum += days[dayIndex].counts[i];
    }
    return sum.toDouble();
  }
}

/// The cumulative flow diagram: one filled band per board column, stacked,
/// oldest day on the left.
///
/// `fl_chart` has no stacked area, so the bands are cumulative lines with
/// `belowBarData` and are drawn from the topmost (every column) down to the
/// first, each painting over the one behind it — which is what leaves each
/// band showing only its own column's thickness.
class CumulativeFlowChart extends StatelessWidget {
  const CumulativeFlowChart({
    super.key,
    required this.series,
    required this.height,
  });

  final CumulativeFlowSeries series;
  final double height;

  static List<ChartKey> keysFor(
    BuildContext context,
    CumulativeFlowSeries series,
  ) {
    final colors = context.boardhopColors;
    return [
      for (var i = 0; i < series.columns.length; i++)
        ChartKey(series.columns[i], colors.series(i)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // One day is a point, not an area, and fl_chart divides by the x range.
    if (series.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final scale = axisTextScale(context);
    final last = series.days.length - 1;

    var maxY = 1.0;
    for (var d = 0; d <= last; d++) {
      maxY = math.max(maxY, series.totalOn(d).toDouble());
    }
    final step = math
        .max(1, (series.days.length * scale / 4).ceil())
        .toDouble();

    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(top: Spacing.sm, right: Spacing.sm),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: last.toDouble(),
            minY: 0,
            maxY: maxY * 1.1,
            gridData: FlGridData(
              drawVerticalLine: false,
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
                  getTitlesWidget: (value, meta) => value >= meta.max
                      ? const SizedBox.shrink()
                      : SideTitleWidget(
                          meta: meta,
                          child: Text(
                            chartNumber(value),
                            style: labelStyle,
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 24 * scale,
                  interval: step,
                  getTitlesWidget: (value, meta) {
                    final i = value.round();
                    if (i < 0 || i > last) return const SizedBox.shrink();
                    // The final date is always drawn; an interval label
                    // too close to it would overprint.
                    if (value != meta.max && meta.max - value < step * 0.75) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        chartDayFormat.format(series.days[i].date),
                        style: labelStyle,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                // Six bands would give six tooltips on one touch; the first
                // bar is the topmost line, which is the day's total.
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    if (spot.barIndex != 0)
                      null
                    else
                      () {
                        final day = spot.x.round().clamp(0, last);
                        return LineTooltipItem(
                          '${chartDayFormat.format(series.days[day].date)}\n'
                          '${chartNumber(series.totalOn(day))} items',
                          theme.textTheme.labelSmall!.copyWith(
                            color: scheme.onInverseSurface,
                          ),
                        );
                      }(),
                ],
              ),
            ),
            lineBarsData: [
              // Topmost band first: each later line paints its area over the
              // one behind it, leaving the column's own thickness visible.
              for (var c = series.columns.length - 1; c >= 0; c--)
                LineChartBarData(
                  spots: [
                    for (var d = 0; d <= last; d++)
                      FlSpot(d.toDouble(), series.cumulative(d, c)),
                  ],
                  color: colors.series(c),
                  barWidth: 1.5,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: colors.series(c).withValues(alpha: 0.75),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
