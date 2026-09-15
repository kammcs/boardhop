import 'package:flutter/material.dart';

import '../../../data/models/sprint.dart';
import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'sprint_format.dart';

/// What the overflow menu on a backlog row offers (decision S3).
enum SprintRowAction { moveToSprint, addTask }

/// The Backlog tab: the sprint's requirement rows in rank order — the
/// service has already ranked them (spike s54) — each with its rollup, plus
/// the unparented tasks as rows of their own and the capacity strip when
/// the team filled one in (S7).
///
/// This is the tab that has to work on CloudCover 2.0, where the sprint
/// holds 143 rows and 5 task-type items: it is a plain list, not a board.
class SprintBacklogTab extends StatelessWidget {
  const SprintBacklogTab({
    super.key,
    required this.rows,
    required this.visuals,
    required this.onOpen,
    required this.onRowAction,
    this.header,
    this.capacity,
    this.unit = 'items',
  });

  /// Unparented first, as [SprintSnapshot.allRows] orders them.
  final List<SprintRow> rows;
  final WorkItemVisuals visuals;
  final ValueChanged<WorkItem> onOpen;
  final void Function(SprintRowAction action, SprintRow row, WorkItem item)
  onRowAction;

  /// The sprint header, which scrolls away with this tab's content.
  final Widget? header;
  final SprintCapacity? capacity;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inset = MediaQuery.paddingOf(context);
    final capacityStrip = capacity;
    final items = <Widget>[
      ?header,
      if (capacityStrip != null && !capacityStrip.isEmpty)
        SprintCapacityStrip(capacity: capacityStrip),
      for (final row in rows) ...[
        if (row.parent != null)
          _RequirementTile(
            row: row,
            visuals: visuals,
            onOpen: onOpen,
            onAction: onRowAction,
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Text(
              'Unparented tasks',
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final task in row.tasks)
            _TaskTile(
              row: row,
              task: task,
              visuals: visuals,
              onOpen: onOpen,
              onAction: onRowAction,
            ),
        ],
      ],
      if (rows.isEmpty)
        Padding(
          padding: Spacing.page,
          child: Text(
            'Nothing is in this sprint yet.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
    return ListView(
      // The floating glass rail on Apple tablets sits outside the page, so
      // the list keeps clear of it on both sides.
      padding: EdgeInsets.fromLTRB(
        inset.left,
        0,
        inset.right,
        Spacing.xl + inset.bottom,
      ),
      children: items,
    );
  }
}

/// One requirement: type glyph, id, title, state, the rollup and the
/// assignee, with the overflow the sprint's two row writes live behind.
class _RequirementTile extends StatelessWidget {
  const _RequirementTile({
    required this.row,
    required this.visuals,
    required this.onOpen,
    required this.onAction,
  });

  final SprintRow row;
  final WorkItemVisuals visuals;
  final ValueChanged<WorkItem> onOpen;
  final void Function(SprintRowAction action, SprintRow row, WorkItem item)
  onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final parent = row.parent!;
    final rollup = formatRemaining(row.remaining);
    return ListTile(
      leading: Icon(
        visuals.typeIcon(parent),
        color: visuals.typeColor(context, parent),
      ),
      title: Text(parent.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      isThreeLine: true,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: Spacing.xs),
          // A Wrap so the metadata drops to a second line at accessibility
          // text sizes rather than overflowing.
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StateDot(color: visuals.stateColor(context, parent)),
                  const SizedBox(width: Spacing.xs),
                  Text(parent.state, style: theme.textTheme.labelMedium),
                ],
              ),
              Text(
                '${parent.type} ${parent.id}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Text(
                row.done > 0
                    ? '${formatTaskCount(row.tasks.length)} · ${row.done} done'
                    : formatTaskCount(row.tasks.length),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (rollup.isNotEmpty)
                Text(
                  '$rollup remaining',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IdentityAvatar(identity: parent.assignedTo),
          _RowMenu(
            row: row,
            item: parent,
            onAction: onAction,
            canAddTask: true,
          ),
        ],
      ),
      onTap: () => onOpen(parent),
    );
  }
}

/// A task in the unparented row: the same line, without a rollup.
class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.row,
    required this.task,
    required this.visuals,
    required this.onOpen,
    required this.onAction,
  });

  final SprintRow row;
  final WorkItem task;
  final WorkItemVisuals visuals;
  final ValueChanged<WorkItem> onOpen;
  final void Function(SprintRowAction action, SprintRow row, WorkItem item)
  onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final remaining = formatRemaining(
      task.field<num>('Microsoft.VSTS.Scheduling.RemainingWork')?.toDouble(),
    );
    return ListTile(
      leading: Icon(
        visuals.typeIcon(task),
        color: visuals.typeColor(context, task),
      ),
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              StateDot(color: visuals.stateColor(context, task)),
              const SizedBox(width: Spacing.xs),
              Text(task.state, style: theme.textTheme.labelMedium),
            ],
          ),
          Text(
            '${task.type} ${task.id}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (remaining.isNotEmpty)
            Text(
              '$remaining remaining',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IdentityAvatar(identity: task.assignedTo),
          _RowMenu(row: row, item: task, onAction: onAction, canAddTask: false),
        ],
      ),
      onTap: () => onOpen(task),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({
    required this.row,
    required this.item,
    required this.onAction,
    required this.canAddTask,
  });

  final SprintRow row;
  final WorkItem item;
  final void Function(SprintRowAction action, SprintRow row, WorkItem item)
  onAction;
  final bool canAddTask;

  @override
  Widget build(BuildContext context) => PopupMenuButton<SprintRowAction>(
    tooltip: 'More for ${item.id}',
    // Apple tablets float the glass rail just outside the page's trailing
    // edge, and a menu aligned to its own button opens hard against it.
    offset: kTrailingMenuOffset,
    onSelected: (action) => onAction(action, row, item),
    itemBuilder: (context) => [
      const PopupMenuItem(
        value: SprintRowAction.moveToSprint,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.swap_horiz),
          title: Text('Move to another sprint'),
        ),
      ),
      if (canAddTask)
        const PopupMenuItem(
          value: SprintRowAction.addTask,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.add_task),
            title: Text('Add task'),
          ),
        ),
    ],
  );
}

/// Capacity, read-only and shown only when the team filled it in for this
/// sprint (decision S7): no team in puremedia does, so the normal answer is
/// that this strip is not on screen at all.
class SprintCapacityStrip extends StatelessWidget {
  const SprintCapacityStrip({super.key, required this.capacity});

  final SprintCapacity capacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
            Text('Capacity', style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.xs),
            Text(
              '${formatRemaining(capacity.totalPerDay)} a day '
              'across ${capacity.members.length} '
              '${capacity.members.length == 1 ? 'person' : 'people'}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.sm),
            for (final member in capacity.members)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: Row(
                  children: [
                    IdentityAvatar(identity: member.member),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        member.member.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      [
                        '${formatRemaining(member.capacityPerDay)}/day',
                        if (member.daysOffCount > 0)
                          '${member.daysOffCount} '
                              '${member.daysOffCount == 1 ? 'day' : 'days'} off',
                      ].join(' · '),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
