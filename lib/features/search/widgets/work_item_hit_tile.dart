import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/search.dart';
import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'search_highlight_text.dart';

/// The rounded square the work item rows lead with: the type's glyph on a
/// tint of the type's own colour, the shape Azure DevOps uses for its own
/// tiles (`AdoTile`).
///
/// A search hit names its type but carries no `WorkItemType`, so there is
/// no process colour to prefer here the way [WorkItemVisuals] does; the
/// palette in [BoardhopColors] is all there is, and it is tuned for both
/// modes.
class WorkItemTypeTile extends StatelessWidget {
  const WorkItemTypeTile({super.key, required this.type, this.size = 36});

  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = context.boardhopColors.workItemType(type);
    return Semantics(
      label: type,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(size * 0.25),
        ),
        child: Icon(
          WorkItemType.iconFor(WorkItemVisuals.guessIcon(type)),
          size: size * 0.55,
          color: color,
        ),
      ),
    );
  }
}

/// One work item search hit (research/15 §4): the type tile, the title, the
/// matched line in bold, then `type #id`, the state, the project when the
/// search spans more than one, and when it changed. The assignee's avatar
/// trails the row.
class WorkItemHitTile extends StatelessWidget {
  const WorkItemHitTile({
    super.key,
    required this.hit,
    required this.onTap,
    this.showProject = false,
  });

  final WorkItemSearchHit hit;
  final VoidCallback onTap;

  /// True in the All-projects scope, where a row has to say where it is.
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final highlight = hit.highlight;
    // A title match is drawn in the title itself: a second line repeating
    // the title word for word (seen on the simulator) says nothing, while
    // the bold run in place says where the term was found.
    final inTitle =
        highlight != null &&
        highlight.fieldReferenceName.toLowerCase() == 'system.title';
    return ListTile(
      isThreeLine: true,
      leading: WorkItemTypeTile(type: hit.workItemType),
      title: inTitle
          ? SearchHighlightText(
              highlight: highlight,
              style: theme.textTheme.bodyLarge,
            )
          : Text(hit.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (highlight != null && !inTitle) ...[
              SearchHighlightText(highlight: highlight),
              const SizedBox(height: Spacing.xs),
            ],
            // A Wrap, not a Row: at large text scales the facts flow onto
            // another line instead of overflowing the tile (the work item
            // list learned the same lesson on the iPad).
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('${hit.workItemType} #${hit.id}', style: meta),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StateDot(
                      color: context.boardhopColors.stateCategory(
                        guessStateCategory(hit.state),
                      ),
                    ),
                    const SizedBox(width: Spacing.xs),
                    Text(hit.state, style: theme.textTheme.labelMedium),
                  ],
                ),
                if (showProject && hit.projectName.isNotEmpty)
                  Text(hit.projectName, style: meta),
                if (hit.changedDate != null)
                  Text(relativeTime(hit.changedDate), style: meta),
              ],
            ),
          ],
        ),
      ),
      trailing: hit.assignedTo == null
          ? null
          : IdentityAvatar(identity: hit.assignedTo, radius: 14),
      onTap: onTap,
    );
  }
}
