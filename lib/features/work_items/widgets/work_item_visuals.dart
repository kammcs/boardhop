import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../boards/widgets/kanban_board.dart' show tintApiColor;

/// Colors and glyphs for a work item, preferring what the project's process
/// says (type color, state color) and falling back to [BoardhopColors].
class WorkItemVisuals {
  const WorkItemVisuals(this.types);

  final Map<String, WorkItemType> types;

  WorkItemType? typeOf(WorkItem item) => types[item.type];

  Color typeColor(BuildContext context, WorkItem item) {
    final api = parseHexColor(typeOf(item)?.color);
    return api == null
        ? context.boardhopColors.workItemType(item.type)
        : tintApiColor(context, api);
  }

  IconData typeIcon(WorkItem item) =>
      typeOf(item)?.icon ?? WorkItemType.iconFor(_guessIcon(item.type));

  Color stateColor(BuildContext context, WorkItem item) {
    final state = typeOf(item)?.stateNamed(item.state);
    final api = parseHexColor(state?.color);
    if (api != null) return tintApiColor(context, api);
    return context.boardhopColors.stateCategory(state?.category ?? '');
  }

  static String _guessIcon(String type) => switch (type.toLowerCase()) {
    'bug' => 'icon_bug',
    'task' => 'icon_task',
    'user story' || 'product backlog item' || 'requirement' => 'icon_book',
    'feature' => 'icon_crown',
    'epic' => 'icon_trophy',
    'issue' || 'impediment' => 'icon_traffic_cone',
    'test case' => 'icon_test_case',
    _ => '',
  };
}

class StateDot extends StatelessWidget {
  const StateDot({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class IdentityAvatar extends StatelessWidget {
  const IdentityAvatar({super.key, required this.identity, this.radius = 12});

  final IdentityRef? identity;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = identity?.initialsLabel ?? '–';
    return Tooltip(
      message: identity?.displayName ?? 'Unassigned',
      child: CircleAvatar(
        radius: radius,
        backgroundColor: identity == null
            ? scheme.surfaceContainerHighest
            : scheme.secondaryContainer,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: identity == null
                ? scheme.onSurfaceVariant
                : scheme.onSecondaryContainer,
            fontSize: radius * 0.85,
          ),
        ),
      ),
    );
  }
}

/// Board card: type stripe and glyph, id, title, assignee, state.
class WorkItemCard extends StatelessWidget {
  const WorkItemCard({
    super.key,
    required this.item,
    required this.visuals,
    this.dragging = false,
  });

  final WorkItem item;
  final WorkItemVisuals visuals;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeColor = visuals.typeColor(context, item);
    final background = theme.brightness == Brightness.dark
        ? scheme.surfaceContainerHigh
        : scheme.surfaceContainerLowest;
    return Material(
      color: background,
      elevation: dragging ? 6 : 0,
      shadowColor: scheme.shadow,
      borderRadius: Radii.card,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: typeColor, width: 4)),
        ),
        child: Padding(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(visuals.typeIcon(item), size: 16, color: typeColor),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      '${item.type} ${item.id}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IdentityAvatar(identity: item.assignedTo),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  StateDot(color: visuals.stateColor(context, item)),
                  const SizedBox(width: Spacing.xs),
                  Text(item.state, style: theme.textTheme.labelMedium),
                  if (item.boardColumnDone) ...[
                    const SizedBox(width: Spacing.sm),
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: context.boardhopColors.stateCompleted,
                    ),
                    const SizedBox(width: 2),
                    Text('Done', style: theme.textTheme.labelSmall),
                  ],
                  const Spacer(),
                  if (item.tags.isNotEmpty)
                    Flexible(
                      child: Text(
                        item.tags.take(2).join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
