import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'board_probe_data.dart';

/// Callbacks the probe page uses to measure drags and count moves.
class BoardProbeHooks {
  const BoardProbeHooks({
    required this.onDragStart,
    required this.onDragEnd,
    required this.onMove,
  });

  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<CardMove> onMove;
}

class ProbeCardView extends StatelessWidget {
  const ProbeCardView({
    super.key,
    required this.card,
    required this.column,
    this.dragging = false,
  });

  final ProbeCard card;
  final ProbeColumn column;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final typeColor = colors.workItemType(card.type);
    final stateColor = colors.stateCategory(column.stateCategory);
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
                  Icon(_typeIcon(card.type), size: 16, color: typeColor),
                  const SizedBox(width: Spacing.xs),
                  Text(
                    '${card.type} ${card.id}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: scheme.secondaryContainer,
                    child: Text(
                      card.assignee,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: Spacing.sm),
              Row(
                children: [
                  Icon(Icons.circle, size: 10, color: stateColor),
                  const SizedBox(width: Spacing.xs),
                  Text(column.stateName, style: theme.textTheme.labelMedium),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _typeIcon(String type) => switch (type) {
    'Bug' => Icons.bug_report_outlined,
    'Task' => Icons.check_box_outlined,
    'User Story' => Icons.auto_stories_outlined,
    'Feature' => Icons.emoji_events_outlined,
    'Epic' => Icons.workspace_premium_outlined,
    _ => Icons.circle_outlined,
  };
}
