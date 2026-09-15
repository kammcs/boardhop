import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/theme.dart';
import '../../../data/models/sprint.dart';

/// How much chart there is room for.
enum BurndownMode {
  /// ~48 dp, no axes, no touch: the line in the sprint header (r2 §3.1).
  sparkline,

  /// The Burndown tab: dated axis, labelled ideal line, per-day tooltip.
  full,
}

/// The straight line the sprint would follow if it burned down evenly:
/// from the first day's remaining work to zero on [finish].
///
/// **[finish] matters.** Analytics answers one row per day *up to today*,
/// not to the end of the sprint (P-A §8.4), so burning to zero over the
/// rows in hand puts the ideal at zero on the day the data stops — four
/// days into a fortnight the scratch sprint read "Ideal today: 0 items"
/// and the header called a sprint on schedule "2 items/day behind"
/// (iPhone check, P-C). With the sprint's finish date the line has the
/// slope it really has, and simply does not reach zero inside the window
/// the chart draws.
///
/// Without [finish] — an undated sprint, which three of the four puremedia
/// projects run — it falls back to the old shape, because there is nothing
/// else to anchor on.
///
/// Pure and separate from the widget because the header's verdict sentence
/// compares against the same numbers, and because a chart no one can read
/// is not an accessible answer on its own (DESIGN.md §8).
List<double> burndownIdealLine(List<BurndownDay> days, {DateTime? finish}) {
  if (days.isEmpty) return const [];
  final start = days.first.remaining.toDouble();
  final last = days.length - 1;
  if (finish != null) {
    final span = _dayGap(days.first.date, finish);
    if (span > 0) {
      return [
        for (var i = 0; i <= last; i++)
          () {
            final value =
                start * (1 - _dayGap(days.first.date, days[i].date) / span);
            return value < 0 ? 0.0 : value;
          }(),
      ];
    }
  }
  if (last == 0) return [start];
  return [for (var i = 0; i <= last; i++) start * (1 - i / last)];
}

/// Whole days from [from] to [to], compared as calendar dates: Azure
/// DevOps dates are date-only and a local-time shift moves them by a day.
int _dayGap(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// One sentence describing the chart for a screen reader: fl_chart has no
/// semantics of its own (r2 §3.3, fl_chart #1746/#2082), so this is ours.
String burndownSemanticsLabel(
  List<BurndownDay> days, {
  List<double> ideal = const [],
  String unit = 'items',
}) {
  if (days.isEmpty) return 'Sprint burndown. No data.';
  final index = days.length - 1;
  final actual = days[index].remaining.toDouble();
  final buffer = StringBuffer(
    'Sprint burndown. ${_number(actual)} $unit remaining '
    'on day ${index + 1} of ${days.length}.',
  );
  if (index < ideal.length) {
    buffer.write(' Ideal ${_number(ideal[index])} $unit.');
  }
  return buffer.toString();
}

String _number(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// The sprint burndown, and the only place `fl_chart` is used.
///
/// Everything the library draws takes plain colors from
/// `Theme.of(context)` and `context.boardhopColors`, so light and dark keep
/// coming from the theme (DESIGN.md §3), and a future breaking change in
/// the package touches this file alone (r2 §3.3).
///
/// Degenerate input draws nothing rather than throwing: fl_chart's
/// [issue #2115](https://github.com/imaNNeo/fl_chart/issues/2115) is a
/// late-init error on all-null spot data, and an empty sprint is normal on
/// a project that has never run one.
class SprintBurndownChart extends StatelessWidget {
  const SprintBurndownChart({
    super.key,
    required this.days,
    this.mode = BurndownMode.sparkline,
    this.ideal,
    this.showPoints = false,
    this.unit = 'items',
    this.height,
    this.isNonWorkingDay,
    this.semanticsLabel,
    this.actualColor,
  });

  final List<BurndownDay> days;
  final BurndownMode mode;

  /// Defaults to [burndownIdealLine] over [days].
  final List<double>? ideal;

  /// Draw story points as a second series (research/18 S6). Off by default:
  /// most teams leave the field empty.
  final bool showPoints;

  /// What the y axis counts. Hours are not available in practice
  /// (research/18 §1), so the default is items.
  final String unit;
  final double? height;

  /// Faint vertical bands. Defaults to Saturday and Sunday, which is every
  /// probed team's `workingDays` (`monday`…`friday`).
  final bool Function(DateTime day)? isNonWorkingDay;

  /// What a screen reader is told, when the caller knows better than
  /// [burndownSemanticsLabel] does: a dashboard's Burnup widget draws the
  /// same shape reading the other way, and a team burndown is not a
  /// sprint's (research/19 D-C).
  final String? semanticsLabel;

  /// The colour of the drawn series, for the burnup that is climbing rather
  /// than burning down. Defaults to `BoardhopColors.burndownActual`.
  final Color? actualColor;

  bool get _sparkline => mode == BurndownMode.sparkline;

  @override
  Widget build(BuildContext context) {
    final points = <FlSpot>[
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), days[i].remaining.toDouble()),
    ];
    // Nothing to draw: no days at all, or a single point (a line chart of
    // one spot has no x range, and fl_chart divides by it — issue #2115).
    if (points.length < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final line = ideal ?? burndownIdealLine(days);
    final idealSpots = <FlSpot>[
      for (var i = 0; i < line.length; i++) FlSpot(i.toDouble(), line[i]),
    ];
    final pointSpots = <FlSpot>[
      if (showPoints && days.any((d) => d.points > 0))
        for (var i = 0; i < days.length; i++)
          FlSpot(i.toDouble(), days[i].points),
    ];

    final maxY = math.max(
      points.map((s) => s.y).reduce(math.max),
      idealSpots.isEmpty ? 0.0 : idealSpots.map((s) => s.y).reduce(math.max),
    );

    // A flat zero sprint would give a zero-height axis; `chartAxis` answers
    // 0…1 for that. Story points can be halves, so the axis is only forced
    // to whole numbers when the chart is counting items.
    final axis = chartAxis(
      maxY,
      ticks: axisTicks(axisTextScale(context)),
      integral: !showPoints && unit == 'items',
    );

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: (days.length - 1).toDouble(),
        minY: 0,
        maxY: axis.max,
        gridData: FlGridData(
          show: !_sparkline,
          drawVerticalLine: false,
          horizontalInterval: axis.interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _titles(context, axis),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: _nonWorkingBands(scheme),
        ),
        lineTouchData: _sparkline
            ? const LineTouchData(enabled: false)
            : _touch(context),
        lineBarsData: [
          // Ideal first so the actual line draws over it.
          if (idealSpots.length > 1)
            LineChartBarData(
              spots: idealSpots,
              color: colors.burndownIdeal,
              barWidth: _sparkline ? 1.5 : 2,
              // DESIGN.md §3: never color alone. The ideal line is the
              // dashed one, and the full chart labels it as well.
              dashArray: const [6, 4],
              dotData: const FlDotData(show: false),
            ),
          if (pointSpots.length > 1)
            LineChartBarData(
              spots: pointSpots,
              color: scheme.tertiary,
              barWidth: _sparkline ? 1.5 : 2,
              dashArray: const [2, 3],
              dotData: const FlDotData(show: false),
            ),
          LineChartBarData(
            spots: points,
            color: actualColor ?? colors.burndownActual,
            barWidth: _sparkline ? 2 : 3,
            isStrokeCapRound: true,
            dotData: FlDotData(show: !_sparkline && points.length <= 20),
          ),
        ],
      ),
    );

    return Semantics(
      label:
          semanticsLabel ??
          burndownSemanticsLabel(days, ideal: line, unit: unit),
      child: ExcludeSemantics(
        child: SizedBox(
          height: height ?? (_sparkline ? 48 : 220),
          child: Padding(
            padding: _sparkline
                ? EdgeInsets.zero
                : chartInsets(axisTextScale(context)),
            child: chart,
          ),
        ),
      ),
    );
  }

  List<VerticalRangeAnnotation> _nonWorkingBands(ColorScheme scheme) {
    final off = isNonWorkingDay ?? _weekend;
    // The sparkline is 48 dp tall and often only a handful of days wide, so
    // two banded days out of four read as a grey slab rather than a hint
    // (P-C §6.5). Half the alpha there; the full chart's band is already
    // small against a fortnight and stays as it is.
    final color = scheme.onSurface.withValues(alpha: _sparkline ? 0.03 : 0.06);
    return [
      for (var i = 0; i < days.length; i++)
        if (off(days[i].date))
          VerticalRangeAnnotation(x1: i - 0.5, x2: i + 0.5, color: color),
    ];
  }

  static bool _weekend(DateTime day) =>
      day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

  FlTitlesData _titles(BuildContext context, ChartAxis axis) {
    if (_sparkline) return const FlTitlesData(show: false);
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final format = DateFormat('d MMM');
    final scale = axisTextScale(context);
    // Roughly five dates across, whatever the sprint's length — and fewer
    // of them as the text grows, or they run into each other.
    final step = math.max(1, (days.length * scale / 5).ceil()).toDouble();
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 36 * scale,
          interval: axis.interval,
          getTitlesWidget: (value, meta) => axis.showsLabel(value)
              ? SideTitleWidget(
                  meta: meta,
                  child: Text(
                    axis.label(value),
                    style: style,
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
          reservedSize: 28 * scale,
          interval: step,
          getTitlesWidget: (value, meta) {
            final i = value.round();
            if (i < 0 || i >= days.length) return const SizedBox.shrink();
            // The chart always labels its last day; an interval label too
            // close to it would overprint. Measured against the last index
            // rather than `meta.max`, which fl_chart reports for the axis
            // and not for the point being labelled.
            final last = days.length - 1;
            if (i != last && last - i < step * 0.75) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
              meta: meta,
              child: Text(
                format.format(days[i].date),
                style: style,
                maxLines: 1,
                softWrap: false,
              ),
            );
          },
        ),
      ),
    );
  }

  LineTouchData _touch(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final format = DateFormat('d MMM');
    return LineTouchData(
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => scheme.inverseSurface,
        getTooltipItems: (spots) => [
          for (final spot in spots)
            LineTooltipItem(
              '${format.format(days[spot.x.round().clamp(0, days.length - 1)].date)}\n'
              '${_number(spot.y)} $unit',
              theme.textTheme.labelMedium!.copyWith(
                color: scheme.onInverseSurface,
              ),
            ),
        ],
      ),
    );
  }
}

/// The legend the full chart needs so the dashed line is named and not just
/// differently coloured (DESIGN.md §3).
class BurndownLegend extends StatelessWidget {
  const BurndownLegend({
    super.key,
    this.showPoints = false,
    this.actualLabel = 'Remaining',
    this.idealLabel = 'Ideal',
    this.actualColor,
  });

  final bool showPoints;

  /// "Remaining" on a burndown, "Completed" on the dashboard's burnup.
  final String actualLabel;
  final String idealLabel;
  final Color? actualColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.boardhopColors;
    return Wrap(
      spacing: Spacing.lg,
      runSpacing: Spacing.xs,
      children: [
        _Key(color: actualColor ?? colors.burndownActual, label: actualLabel),
        _Key(color: colors.burndownIdeal, label: idealLabel, dashed: true),
        if (showPoints)
          _Key(
            color: theme.colorScheme.tertiary,
            label: 'Story points',
            dashed: true,
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 18,
          height: 3,
          child: Row(
            children: [
              for (var i = 0; i < (dashed ? 3 : 1); i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: Spacing.xs),
        Text(label, style: theme.textTheme.labelMedium),
      ],
    );
  }
}
