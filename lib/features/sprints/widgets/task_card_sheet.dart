import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'sprint_format.dart';
import '../../../data/models/sprint.dart';

/// `Microsoft.VSTS.Scheduling.RemainingWork`, the one schedule field the
/// taskboard writes (research/18 S3).
const String kRemainingWorkField = 'Microsoft.VSTS.Scheduling.RemainingWork';

/// What the user asked for on a task card. The caller performs it: this
/// sheet never writes.
sealed class TaskCardAction {
  const TaskCardAction();
}

/// Move the task to [column] (index [columnIndex] in the list the sheet was
/// given). WCAG 2.2 2.5.7 requires this single-pointer path next to the
/// drag (r2 §5.2), and it is also the only move `tool/shot-ios.sh` can
/// drive, since idb has no long-press drag.
final class MoveTaskAction extends TaskCardAction {
  const MoveTaskAction(this.columnIndex, this.column);

  final int columnIndex;
  final TaskboardColumn column;
}

/// Write Remaining Work. `0` clears it — the field refuses null (research/18
/// §1), so "Set to 0" is a zero and never a delete.
final class SetRemainingWorkAction extends TaskCardAction {
  const SetRemainingWorkAction(this.hours);

  final double hours;
}

final class AssignToMeAction extends TaskCardAction {
  const AssignToMeAction();
}

final class OpenTaskAction extends TaskCardAction {
  const OpenTaskAction();
}

/// Whether an item of [type] can reach [column] at all.
///
/// A customized taskboard maps one state per work item type per column, so
/// a column that never mentions the type has no state to move the item to
/// and the row is disabled rather than hidden — a hidden row would read as
/// "this board has three columns" on a board that has four.
bool columnAcceptsType(TaskboardColumn column, String type) =>
    column.mappings.isEmpty || column.mappings.containsKey(type);

/// Does landing in [column] mean the task is finished? Used for the note
/// the web does not show: the process's own rule empties Remaining Work
/// when a task reaches its completed state, and writing a zero there is
/// refused (TF401320 InvalidNotEmpty — see `SprintRepository.moveOps`).
bool _isDoneColumn(TaskboardColumn column) =>
    (column.stateCategory ?? '').toLowerCase() == 'completed' ||
    column.name.toLowerCase() == 'done';

/// Per-column screen-reader actions for a task card, so the move is
/// reachable without opening anything (r2 §5.2). The sheet and the grid
/// build them from the same place so the labels never drift apart.
Map<CustomSemanticsAction, VoidCallback> taskMoveSemanticsActions({
  required List<TaskboardColumn> columns,
  required String type,
  required int? currentColumn,
  required void Function(int columnIndex) onMoveTo,
}) {
  final actions = <CustomSemanticsAction, VoidCallback>{};
  for (var i = 0; i < columns.length; i++) {
    if (i == currentColumn) continue;
    if (!columnAcceptsType(columns[i], type)) continue;
    actions[CustomSemanticsAction(label: 'Move to ${columns[i].name}')] = () =>
        onMoveTo(i);
  }
  return actions;
}

/// The tap-to-move sheet: a bottom sheet on a phone, the same content in a
/// centered dialog from the medium breakpoint (the pattern
/// `pickClassificationPath` set for the tree picker).
Future<TaskCardAction?> showTaskCardSheet(
  BuildContext context, {
  required WorkItem task,
  required List<TaskboardColumn> columns,
  required WorkItemVisuals visuals,
  int? currentColumn,
  double? remainingWork,
  bool canAssignToMe = true,
}) {
  final body = TaskCardSheet(
    task: task,
    columns: columns,
    visuals: visuals,
    currentColumn: currentColumn,
    remainingWork: remainingWork ?? _remainingOf(task),
    canAssignToMe: canAssignToMe,
  );
  if (!context.breakpoint.isCompact) {
    return showDialog<TaskCardAction>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<TaskCardAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => body,
  );
}

double? _remainingOf(WorkItem task) =>
    task.field<num>(kRemainingWorkField)?.toDouble();

/// The sheet's body, public so a probe (and a test) can pump it directly.
class TaskCardSheet extends StatefulWidget {
  const TaskCardSheet({
    super.key,
    required this.task,
    required this.columns,
    required this.visuals,
    this.currentColumn,
    this.remainingWork,
    this.canAssignToMe = true,
  });

  final WorkItem task;
  final List<TaskboardColumn> columns;
  final WorkItemVisuals visuals;

  /// Index of the column the task is in now, checked and not tappable.
  final int? currentColumn;
  final double? remainingWork;
  final bool canAssignToMe;

  @override
  State<TaskCardSheet> createState() => _TaskCardSheetState();
}

class _TaskCardSheetState extends State<TaskCardSheet> {
  late double _remaining = widget.remainingWork ?? 0;

  bool get _changed => _remaining != (widget.remainingWork ?? 0);

  void _step(double by) =>
      setState(() => _remaining = (_remaining + by).clamp(0, 999));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final task = widget.task;
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.only(bottom: Spacing.lg),
        children: [
          ListTile(
            leading: Icon(
              widget.visuals.typeIcon(task),
              color: widget.visuals.typeColor(context, task),
            ),
            title: Text(task.title, maxLines: 3, overflow: TextOverflow.fade),
            subtitle: Text('${task.type} ${task.id} · ${task.state}'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.xs,
            ),
            child: Text('Move to', style: theme.textTheme.titleSmall),
          ),
          for (var i = 0; i < widget.columns.length; i++)
            _columnRow(context, i, widget.columns[i]),
          const Divider(height: 1),
          _remainingRow(context),
          const Divider(height: 1),
          if (widget.canAssignToMe)
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Assign to me'),
              onTap: () => Navigator.of(context).pop(const AssignToMeAction()),
            ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('Open task'),
            onTap: () => Navigator.of(context).pop(const OpenTaskAction()),
          ),
          if (_changed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                0,
              ),
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context)
                        .pop(SetRemainingWorkAction(_remaining)),
                child: Text(
                  _remaining == 0
                      ? 'Clear remaining work'
                      : 'Set remaining work to ${formatRemaining(_remaining)}',
                ),
              ),
            ),
          if (_changed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.xs,
                Spacing.lg,
                0,
              ),
              child: Text(
                'Nothing is written until you confirm.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _columnRow(BuildContext context, int index, TaskboardColumn column) {
    final theme = Theme.of(context);
    final current = index == widget.currentColumn;
    final reachable = columnAcceptsType(column, widget.task.type);
    final enabled = reachable && !current;
    final note = _isDoneColumn(column) && enabled
        ? 'Moving to ${column.name} clears remaining work'
        : !reachable
        ? 'Not available for a ${widget.task.type}'
        : null;
    return ListTile(
      enabled: enabled,
      leading: Icon(
        current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: current ? theme.colorScheme.primary : null,
      ),
      title: Text(column.name),
      subtitle: note == null ? null : Text(note),
      trailing: current ? const Icon(Icons.check) : null,
      onTap: enabled
          ? () => Navigator.of(context).pop(MoveTaskAction(index, column))
          : null,
    );
  }

  Widget _remainingRow(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Remaining work', style: theme.textTheme.titleSmall),
          const SizedBox(height: Spacing.sm),
          // A Wrap, not a Row: at xxxL the stepper and "Set to 0" cannot
          // share a line on a phone.
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: 'Less remaining work',
                onPressed: _remaining <= 0 ? null : () => _step(-1),
                icon: const Icon(Icons.remove),
              ),
              Text(
                _remaining == 0 ? '0 h' : formatRemaining(_remaining),
                style: theme.textTheme.titleMedium,
              ),
              IconButton.outlined(
                tooltip: 'More remaining work',
                onPressed: () => _step(1),
                icon: const Icon(Icons.add),
              ),
              TextButton(
                onPressed: _remaining == 0
                    ? null
                    : () => setState(() => _remaining = 0),
                child: const Text('Set to 0'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
