import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'sprint_burndown_chart.dart';
import 'sprint_format.dart';
import '../../../data/models/sprint.dart';

/// Everything the sprint header shows, so a page can assemble it once and a
/// test can pump it without a repository.
class SprintHeaderData {
  const SprintHeaderData({
    this.remaining,
    this.done = 0,
    this.total = 0,
    this.scopeChange,
    this.days = const [],
    this.start,
    this.finish,
    this.isEnded = false,
    this.unit = 'items',
    this.seriesUnit = 'items',
    this.now,
    this.ideal,
  });

  /// Work left: hours when the team fills Remaining Work, otherwise the
  /// count of unfinished items (research/18 §1).
  final double? remaining;
  final int done;
  final int total;

  /// How much the sprint grew (or shrank) since it opened; null when there
  /// is no burndown history to measure it against.
  final double? scopeChange;
  final List<BurndownDay> days;
  final DateTime? start;
  final DateTime? finish;

  /// The service still calls an over-running sprint `current` (S12).
  final bool isEnded;

  /// What the Remaining tile counts: `h` once any task carries Remaining
  /// Work, otherwise `items`.
  final String unit;

  /// What [days] counts, which is **always** work items: Analytics answers
  /// a count and story points, never Remaining Work (research/18 §1). It is
  /// separate from [unit] because a single task with hours on it flips the
  /// tile to `h` while the burndown is still in items — reusing one unit
  /// for both made the verdict read "0.9 h/day behind" over an item series,
  /// and the page dodged that by dropping the series altogether, so a
  /// sprint with four days of history said "No burndown data" (iPhone
  /// check, P-D).
  final String seriesUnit;

  /// Injectable clock for the tests.
  final DateTime? now;

  /// The ideal line to compare against, when the page has worked one out
  /// over the sprint's own dates rather than over the days Analytics
  /// happens to hold ([burndownIdealLine] with a finish date).
  final List<double>? ideal;

  int? get percentDone => total == 0 ? null : (done * 100 / total).round();
}

/// The verdict sentence: the part of the burndown that survives xxxL text
/// and a screen reader, and the only part that ships when Analytics is not
/// available at all (research/18 S6).
///
/// [ideal] is [burndownIdealLine] over the same days. [remaining] overrides
/// the last known point when the page has a fresher figure from the
/// taskboard itself than the nightly snapshot has.
String sprintVerdict(
  List<BurndownDay> days,
  double? remaining,
  List<double> ideal, {
  bool isEnded = false,
  DateTime? finish,
  DateTime? now,
  int? daysLeft,
  String unit = 'items',
}) {
  if (isEnded) return sprintEndedLabel(finish, now: now);
  if (days.isEmpty || ideal.isEmpty) return 'No burndown data';
  // Analytics answers one row per day up to today, so the last snapshot is
  // the last day it has; [ideal] runs to the end of the sprint, which is
  // how many days are left to make the gap up in.
  final index = days.length - 1;
  final actual = remaining ?? days[index].remaining.toDouble();
  final target = index < ideal.length ? ideal[index] : 0.0;
  final delta = target - actual;
  final side = delta > 0 ? 'ahead of' : 'behind';
  final left = daysLeft ?? (ideal.length - days.length);
  if (left <= 0) {
    // On the last day there is nothing left to spread the gap over, and
    // "30 items/day behind" would be nonsense. State the gap itself.
    if (delta.abs() < 0.5) return 'On the ideal line';
    return '${_amount(delta.abs())} $unit $side the ideal line';
  }
  final rate = delta.abs() / left;
  if (rate < 0.05) return 'On the ideal line';
  return 'About ${_amount(rate)} $unit/day $side the ideal line';
}

/// `2`, `1.5`, `12`: r2's example sentence is "About 2 h/day ahead of the
/// ideal line", so a whole number never carries a decimal.
String _amount(double v) => v >= 10 || v == v.roundToDouble()
    ? v.toStringAsFixed(0)
    : v.toStringAsFixed(1);

/// The sprint header: three stat tiles, the sparkline, the verdict and the
/// dates. It scrolls away with the content, as the board's lane strip does.
class SprintHeader extends StatelessWidget {
  const SprintHeader({super.key, required this.data, this.onTileTap});

  final SprintHeaderData data;

  /// Tapping a tile is the phone's route to the sub-pages (r2 §7.1); the
  /// key is `remaining`, `done` or `scope`.
  final ValueChanged<String>? onTileTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ideal =
        data.ideal ?? burndownIdealLine(data.days, finish: data.finish);
    // Deliberately not `data.remaining`: the tile counts the sprint's
    // *tasks* (what the taskboard shows), while Analytics counts every
    // work item in the iteration — 13 against 125 on CloudCover's sprint
    // (iPhone check, P-C). Comparing one population against the other's
    // ideal line is not a verdict about anything, so the series is judged
    // against its own ideal.
    final verdict = sprintVerdict(
      data.days,
      null,
      ideal,
      isEnded: data.isEnded,
      finish: data.finish,
      now: data.now,
      daysLeft: sprintDaysLeft(data.finish, now: data.now),
      unit: data.seriesUnit,
    );
    final left = sprintDaysLeft(data.finish, now: data.now);
    // The verdict already says "Ended N days ago" when the sprint is over,
    // so the dates line does not repeat it.
    final dates = [
      sprintDateRange(data.start, data.finish),
      if (!data.isEnded && left != null && left >= 0)
        left == 1 ? '1 day left' : '$left days left',
    ].join(' · ');
    // At xxxL a 48 dp sparkline next to AX5 type is noise, so it goes
    // (r2 §6) and the sentence carries the burndown on its own.
    final showSparkline = MediaQuery.textScalerOf(context).scale(14) / 14 < 1.6;

    return Card(
      margin: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Padding(
        padding: Spacing.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Wrap, not Row: at xxxL the three tiles stack one per line.
            Wrap(
              spacing: Spacing.lg,
              runSpacing: Spacing.sm,
              children: [
                _StatTile(
                  label: 'Remaining',
                  value: data.remaining == null
                      ? '–'
                      : '${_n(data.remaining!)} ${data.unit}',
                  onTap: onTileTap == null
                      ? null
                      : () => onTileTap!('remaining'),
                ),
                _StatTile(
                  label: 'Done',
                  value: data.percentDone == null
                      ? '–'
                      : '${data.percentDone}%',
                  onTap: onTileTap == null ? null : () => onTileTap!('done'),
                ),
                _StatTile(
                  label: 'Scope change',
                  value: data.scopeChange == null
                      ? '–'
                      : '${data.scopeChange! >= 0 ? '+' : ''}'
                            '${_n(data.scopeChange!)}',
                  onTap: onTileTap == null ? null : () => onTileTap!('scope'),
                ),
              ],
            ),
            if (showSparkline && data.days.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              SprintBurndownChart(
                days: data.days,
                ideal: ideal,
                unit: data.seriesUnit,
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Text(verdict, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Spacing.xs),
            Text(
              dates,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.chip,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xs,
          vertical: Spacing.xs,
        ),
        child: content,
      ),
    );
  }
}
