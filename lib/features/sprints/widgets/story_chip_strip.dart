import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../boards/widgets/kanban_board.dart' show boardTextScale;
import '../../work_items/widgets/work_item_visuals.dart';
import 'sprint_format.dart';
import '../../../data/models/sprint.dart';

/// The phone's row axis (S4): the story chip strip, built exactly like the
/// board's swimlane chips so the Sprint view feels like the Board view.
///
/// No mainstream mobile app renders a two-dimensional board on a phone
/// (r2 §2), so the second axis becomes this: `All` · `Unparented` (first,
/// and only when it has tasks) · one chip per story, with a trailing
/// `Stories…` chip for when the ids mean nothing.
///
/// [selected] is null for All, [kUnparentedRowKey] for Unparented, otherwise
/// the parent's id as a string ([sprintRowKey]).
class StoryChipStrip extends StatelessWidget {
  const StoryChipStrip({
    super.key,
    required this.rows,
    required this.visuals,
    required this.selected,
    required this.onSelected,
  });

  /// Every row of the sprint, Unparented included, in the order the grid
  /// shows them.
  final List<SprintRow> rows;
  final WorkItemVisuals visuals;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final row in rows)
        if (row.parent != null || row.tasks.isNotEmpty) row,
    ];
    // At xxxL a chip carrying id and title is wider than the screen, so the
    // title goes and the sheet becomes the way to read it (r2 §6).
    final idOnly = boardTextScale(context) >= 1.6;
    final inset = MediaQuery.paddingOf(context);
    final height = (48 * boardTextScale(context)).clamp(48.0, 96.0);
    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: Spacing.lg)
            .add(EdgeInsets.only(left: inset.left, right: inset.right)),
        children: [
          _chip(context, key: null, label: 'All', selected: selected == null),
          for (final row in visible) ...[
            const SizedBox(width: Spacing.sm),
            _chip(
              context,
              key: sprintRowKey(row),
              label: _labelFor(row, idOnly: idOnly),
              selected: selected == sprintRowKey(row),
            ),
          ],
          const SizedBox(width: Spacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: ActionChip(
              avatar: const Icon(Icons.list, size: 18),
              label: const Text('Stories…'),
              onPressed: () => _openSheet(context, visible),
            ),
          ),
        ],
      ),
    );
  }

  static String _labelFor(SprintRow row, {required bool idOnly}) {
    final parent = row.parent;
    if (parent == null) return 'Unparented';
    if (idOnly) return '#${parent.id}';
    final title = parent.title.length > 22
        ? '${parent.title.substring(0, 21)}…'
        : parent.title;
    return '#${parent.id} $title';
  }

  Widget _chip(
    BuildContext context, {
    required String? key,
    required String label,
    required bool selected,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(key),
    ),
  );

  Future<void> _openSheet(BuildContext context, List<SprintRow> rows) async {
    final picked = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _StorySheet(rows: rows, visuals: visuals),
    );
    if (picked != null) onSelected(picked == '' ? null : picked);
  }
}

/// The full list behind the `Stories…` chip: title, state, task count and
/// the remaining rollup, for when an id says nothing.
class _StorySheet extends StatelessWidget {
  const _StorySheet({required this.rows, required this.visuals});

  final List<SprintRow> rows;
  final WorkItemVisuals visuals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        children: [
          ListTile(
            title: Text('Stories', style: theme.textTheme.titleMedium),
            // The empty string is All: a null pop means "dismissed".
            trailing: TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('All'),
            ),
          ),
          const Divider(height: 1),
          for (final row in rows)
            ListTile(
              leading: row.parent == null
                  ? const Icon(Icons.inbox_outlined)
                  : Icon(
                      visuals.typeIcon(row.parent!),
                      color: visuals.typeColor(context, row.parent!),
                    ),
              title: Text(row.parent?.title ?? 'Unparented'),
              subtitle: Text(
                [
                  if (row.parent != null) row.parent!.state,
                  formatTaskCount(row.tasks.length),
                  if (formatRemaining(row.remaining).isNotEmpty)
                    '${formatRemaining(row.remaining)} remaining',
                ].join(' · '),
              ),
              onTap: () => Navigator.of(context).pop(sprintRowKey(row)),
            ),
        ],
      ),
    );
  }
}
