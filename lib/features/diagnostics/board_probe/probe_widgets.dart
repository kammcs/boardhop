import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'board_probe_data.dart';

/// Callbacks every board implementation reports through so the page can
/// measure drags and count moves the same way for each candidate.
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

/// Column width: most of a phone screen so the next column peeks in, capped
/// so tablets show several columns.
double probeColumnWidth(double viewportWidth) =>
    (viewportWidth * 0.82).clamp(240.0, 320.0);

/// DESIGN.md §3: API colors are rendered as given in light mode and pulled
/// toward the surface in dark mode instead of being used raw.
Color tintApiColor(BuildContext context, Color api) {
  final scheme = Theme.of(context).colorScheme;
  return switch (Theme.of(context).brightness) {
    Brightness.light => api,
    Brightness.dark => Color.lerp(api, scheme.surface, 0.3)!,
  };
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

class ProbeColumnHeader extends StatelessWidget {
  const ProbeColumnHeader({super.key, required this.column});

  final ProbeColumn column;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.md,
        Spacing.md,
        Spacing.md,
        Spacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: tintApiColor(context, column.apiColor),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              column.name,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: Radii.chip,
            ),
            child: Text(
              '${column.cards.length}',
              style: theme.textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The column surface shared by implementations that let us own the chrome.
class ProbeColumnFrame extends StatelessWidget {
  const ProbeColumnFrame({
    super.key,
    required this.column,
    required this.child,
  });

  final ProbeColumn column;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: Radii.card,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProbeColumnHeader(column: column),
          Expanded(child: child),
        ],
      ),
    );
  }
}
