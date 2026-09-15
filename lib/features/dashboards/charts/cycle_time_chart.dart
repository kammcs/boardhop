import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'chart_format.dart';

/// One completed item on the cycle- or lead-time chart: the day it was
/// completed (as days since the window opened) and how long it took.
typedef CycleTimePoint = ({DateTime date, double days, String label});

/// The rolling-average window for a window of [days] (research/19 D-C):
/// a fifth of the period, rounded **down to an odd number** so the average
/// sits on a point rather than between two, and never less than 1.
int rollingWindowForDays(int days) {
  final fifth = (days * 0.2).floor();
  if (fifth <= 1) return 1;
  return fifth.isOdd ? fifth : fifth - 1;
}

/// A centred moving average over [values] with a window of [window] items.
///
/// Over items, not over calendar days: a team that completed nothing for a
/// week has no points there, and averaging the empty days would draw a line
/// through work that does not exist.
List<double> rollingAverage(List<double> values, int window) {
  if (values.isEmpty) return const [];
  final w = window < 1 ? 1 : window;
  final half = w ~/ 2;
  return [
    for (var i = 0; i < values.length; i++)
      () {
        final from = math.max(0, i - half);
        final to = math.min(values.length - 1, i + half);
        var sum = 0.0;
        for (var j = from; j <= to; j++) {
          sum += values[j];
        }
        return sum / (to - from + 1);
      }(),
  ];
}

/// Cycle time (or lead time) as a scatter of completed items with a rolling
/// average through them.
///
/// `fl_chart` has no line series on a [ScatterChart], so the average is a
/// second chart stacked over the first. Both are given the **same** axis
/// range and the same reserved title sizes — that is what makes their plot
/// areas identical — and the overlay draws its labels as empty widgets so
/// only one set of axis numbers appears.
class CycleTimeChart extends StatelessWidget {
  const CycleTimeChart({
    super.key,
    required this.points,
    required this.height,
    this.window = 1,
  });

  final List<CycleTimePoint> points;
  final double height;

  /// The rolling-average window, from [rollingWindowForDays].
  final int window;

  static List<ChartKey> keysFor(BuildContext context, {required bool lead}) {
    final colors = context.boardhopColors;
    return [
      ChartKey(lead ? 'Lead time' : 'Cycle time', colors.series(0)),
      ChartKey('Rolling average', colors.burndownIdeal, dashed: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final scale = axisTextScale(context);
    final sorted = [...points]..sort((a, b) => a.date.compareTo(b.date));
    final first = DateUtils.dateOnly(sorted.first.date);
    double x(DateTime date) =>
        DateUtils.dateOnly(date).difference(first).inDays.toDouble();

    final maxX = math.max(1.0, x(sorted.last.date));
    var maxY = 1.0;
    for (final p in sorted) {
      maxY = math.max(maxY, p.days);
    }
    // Days are a measurement, so half-days on the axis are meaningful.
    final axis = chartAxis(maxY, ticks: axisTicks(scale), strict: true);
    maxY = axis.max;

    final average = rollingAverage([for (final p in sorted) p.days], window);
    final trend = <FlSpot>[
      for (var i = 0; i < sorted.length; i++)
        FlSpot(x(sorted[i].date), average[i]),
    ];

    FlTitlesData titles({required bool visible}) => FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32 * scale,
          interval: axis.interval,
          getTitlesWidget: (value, meta) => visible && axis.showsLabel(value)
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
          interval: math.max(1, (maxX * scale / 4).ceil()).toDouble(),
          getTitlesWidget: (value, meta) {
            if (!visible) return const SizedBox.shrink();
            final step = math.max(1, (maxX * scale / 4).ceil()).toDouble();
            // Measured against the last day rather than `meta.max`, which
            // fl_chart reports for the axis and not for the labelled point.
            if (value != maxX && maxX - value < step * 0.75) {
              return const SizedBox.shrink();
            }
            final day = first.add(Duration(days: value.round()));
            return SideTitleWidget(
              meta: meta,
              child: Text(
                chartDayFormat.format(day),
                style: labelStyle,
                maxLines: 1,
                softWrap: false,
              ),
            );
          },
        ),
      ),
    );

    final grid = FlGridData(
      drawVerticalLine: false,
      horizontalInterval: axis.interval,
      getDrawingHorizontalLine: (_) => FlLine(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        strokeWidth: 1,
      ),
    );

    return SizedBox(
      height: height,
      child: Padding(
        padding: chartInsets(scale),
        child: Stack(
          children: [
            Positioned.fill(
              child: ScatterChart(
                ScatterChartData(
                  minX: 0,
                  maxX: maxX,
                  minY: 0,
                  maxY: maxY,
                  gridData: grid,
                  borderData: FlBorderData(show: false),
                  titlesData: titles(visible: true),
                  scatterTouchData: ScatterTouchData(
                    touchTooltipData: ScatterTouchTooltipData(
                      getTooltipColor: (_) => scheme.inverseSurface,
                      getTooltipItems: (spot) {
                        final i = sorted.indexWhere(
                          (p) => x(p.date) == spot.x && p.days == spot.y,
                        );
                        final item = i < 0 ? null : sorted[i];
                        return ScatterTooltipItem(
                          '${item?.label ?? ''}\n'
                          '${chartNumber(spot.y)} days',
                          textStyle: theme.textTheme.labelSmall!.copyWith(
                            color: scheme.onInverseSurface,
                          ),
                        );
                      },
                    ),
                  ),
                  scatterSpots: [
                    for (final p in sorted)
                      ScatterSpot(
                        x(p.date),
                        p.days,
                        dotPainter: FlDotCirclePainter(
                          radius: 4,
                          color: colors.series(0).withValues(alpha: 0.75),
                          strokeWidth: 0,
                          strokeColor: colors.series(0),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (trend.length > 1)
              Positioned.fill(
                child: IgnorePointer(
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxX,
                      minY: 0,
                      maxY: maxY,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      // The same reserved sizes as the scatter's, drawn
                      // empty: that is what keeps the two plot areas aligned.
                      titlesData: titles(visible: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: trend,
                          color: colors.burndownIdeal,
                          barWidth: 2,
                          dashArray: const [6, 4],
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
