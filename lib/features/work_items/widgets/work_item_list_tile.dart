import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import 'work_item_visuals.dart';

/// One work item as the Work items list draws it: type glyph, title, then
/// `Type id`, the state with its dot and the iteration leaf, with the
/// changed date trailing.
///
/// Lifted out of `WorkItemsPage` unchanged (research/19 §4.2) so a
/// dashboard's Query Results and Assigned to Me cards show a row exactly as
/// the list does; the list is still its other caller.
class WorkItemListTile extends StatelessWidget {
  const WorkItemListTile({
    super.key,
    required this.item,
    required this.visuals,
    required this.onTap,
    this.selected = false,
    this.dense = false,
  });

  final WorkItem item;
  final WorkItemVisuals visuals;
  final VoidCallback onTap;
  final bool selected;

  /// Tightens the row for a dashboard card, where several rows share a
  /// card of a fixed height. Nothing else changes.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iteration = pathLeaf(item.iterationPath);
    return ListTile(
      dense: dense,
      visualDensity: dense ? VisualDensity.compact : null,
      contentPadding: dense
          ? const EdgeInsets.symmetric(horizontal: Spacing.md)
          : null,
      selected: selected,
      selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.4),
      leading: Icon(
        visuals.typeIcon(item),
        color: visuals.typeColor(context, item),
      ),
      title: Text(
        item.title,
        maxLines: dense ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        // A Wrap rather than a Row: at large text scales (or with a long
        // state name) the segments flow onto a second line instead of
        // overflowing the tile.
        child: Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${item.type} ${item.id}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StateDot(color: visuals.stateColor(context, item)),
                const SizedBox(width: Spacing.xs),
                Text(item.state, style: theme.textTheme.labelMedium),
              ],
            ),
            if (iteration.isNotEmpty && !dense)
              Text(
                iteration,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
      trailing: dense
          ? null
          : Text(
              relativeTime(item.changedDate),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
      onTap: onTap,
    );
  }
}
