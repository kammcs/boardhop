import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../theme/theme.dart';

/// Formatting and legend pieces every dashboard chart shares (research/19
/// D-C). Kept apart from the charts themselves so the focus view's data
/// list prints exactly the numbers the chart drew.

/// A whole number without a trailing `.0`, one decimal otherwise. Story
/// points come back as doubles and a "12.0 items" axis reads like a bug.
String chartNumber(num value) {
  final v = value.toDouble();
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// `3 items`, `1 item` — a count and its noun, so no chart caption reads
/// "1 items".
String countOf(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : plural ?? '${singular}s'}';

/// `d MMM` — the axis and data-list date everywhere.
final chartDayFormat = DateFormat('d MMM');

/// An axis label short enough to survive xxxL: `Sprint 12` → `12`,
/// `Iteration 4 (hardening)` → `4`, anything without a number keeps its
/// first six characters.
String shortIterationName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  final number = RegExp(r'(\d+)').allMatches(trimmed).lastOrNull;
  if (number != null) return number.group(1)!;
  return trimmed.length <= 6 ? trimmed : trimmed.substring(0, 6);
}

/// One entry of a chart's legend. Colour never carries the meaning on its
/// own (DESIGN.md §3): every series that is drawn is named here, and the
/// dashed ones say so with their dash.
@immutable
class ChartKey {
  const ChartKey(this.label, this.color, {this.dashed = false});

  final String label;
  final Color color;
  final bool dashed;
}

/// The legend under (portrait) or beside (landscape) a chart. Wraps, so it
/// keeps working at xxxL where four keys cannot share a phone's width.
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.keys, this.dense = false});

  final List<ChartKey> keys;

  /// A card's legend, which is tighter than the focus view's.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = dense
        ? theme.textTheme.labelSmall
        : theme.textTheme.labelMedium;
    return Wrap(
      spacing: dense ? Spacing.md : Spacing.lg,
      runSpacing: Spacing.xs,
      children: [
        for (final key in keys)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Swatch(color: key.color, dashed: key.dashed),
              const SizedBox(width: Spacing.xs),
              Text(key.label, style: style),
            ],
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    if (!dashed) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, borderRadius: Radii.chip),
      );
    }
    return SizedBox(
      width: 18,
      height: 3,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
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
    );
  }
}

/// One line of the focus view's data list — the series as numbers, which is
/// the part of a chart a screen reader can actually read (DESIGN.md §8).
@immutable
class ChartRow {
  const ChartRow({
    required this.label,
    required this.value,
    this.detail,
    this.color,
  });

  final String label;
  final String value;
  final String? detail;

  /// The series colour, drawn as a dot beside the label; the label already
  /// names the series, so this only supports it.
  final Color? color;
}
