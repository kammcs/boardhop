import 'package:flutter/material.dart';

import '../../../data/models/analytics.dart';
import '../../../theme/theme.dart';
import 'chart_format.dart';

/// The team's work by type and state (research/19 D9): one horizontal
/// stacked bar per work item type, split by state category.
///
/// Not `fl_chart`: five bars with no axis need no chart engine, and a
/// hand-laid `Row` of `Expanded`s keeps its proportions at xxxL where a
/// chart's own labels would collide.
class WorkByStateSeries {
  const WorkByStateSeries({required this.types});

  /// The state categories in the order they are stacked — the order work
  /// moves through, so the bar reads left to right like a board.
  static const categories = ['Proposed', 'InProgress', 'Resolved', 'Completed'];

  static String categoryLabel(String category) => switch (category) {
    'Proposed' => 'Not started',
    'InProgress' => 'In progress',
    'Resolved' => 'Resolved',
    'Completed' => 'Done',
    _ => category,
  };

  /// Groups the Analytics buckets by type, biggest type first, with the
  /// counts of each state category in [categories] order.
  factory WorkByStateSeries.from(List<WorkStateCount> counts) {
    final byType = <String, Map<String, int>>{};
    for (final c in counts) {
      final type = c.workItemType.isEmpty ? 'Other' : c.workItemType;
      final category = categories.contains(c.stateCategory)
          ? c.stateCategory
          : 'Proposed';
      final bucket = byType.putIfAbsent(type, () => <String, int>{});
      bucket[category] = (bucket[category] ?? 0) + c.count;
    }
    final types =
        [
          for (final e in byType.entries)
            (
              type: e.key,
              counts: [for (final c in categories) e.value[c] ?? 0],
            ),
        ]..sort((a, b) {
          int total(List<int> v) => v.fold(0, (x, y) => x + y);
          return total(b.counts).compareTo(total(a.counts));
        });
    return WorkByStateSeries(types: types);
  }

  final List<({String type, List<int> counts})> types;

  bool get isEmpty => types.isEmpty || total == 0;

  int get total =>
      types.fold(0, (sum, t) => sum + t.counts.fold(0, (a, b) => a + b));

  int totalFor(({String type, List<int> counts}) row) =>
      row.counts.fold(0, (a, b) => a + b);

  static List<ChartKey> keysFor(BuildContext context) {
    final colors = context.boardhopColors;
    return [
      for (final c in categories)
        ChartKey(categoryLabel(c), colors.stateCategory(c)),
    ];
  }
}

class WorkStateBars extends StatelessWidget {
  const WorkStateBars({super.key, required this.series, this.maxTypes});

  final WorkByStateSeries series;

  /// How many types a card has room for; null draws all of them.
  final int? maxTypes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final rows = maxTypes == null
        ? series.types
        : series.types.take(maxTypes!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in rows) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: Text(
              '${row.type} · ${series.totalFor(row)}',
              style: theme.textTheme.labelMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ClipRRect(
            borderRadius: Radii.chip,
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (var i = 0; i < WorkByStateSeries.categories.length; i++)
                    if (row.counts[i] > 0)
                      Expanded(
                        flex: row.counts[i],
                        child: ColoredBox(
                          color: colors.stateCategory(
                            WorkByStateSeries.categories[i],
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
        ],
        if (maxTypes != null && series.types.length > rows.length)
          Text(
            '+${countOf(series.types.length - rows.length, 'more type')}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
