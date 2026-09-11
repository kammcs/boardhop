import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';

enum WorkView { items, board }

/// The Work tab holds two views of the same project: the work item list and
/// the board. This segmented control sits in the app bar of both, left of
/// the action icons, and switches between their routes so each keeps its
/// own state and deep links. Icons only on phones, icon and label wider.
class WorkViewSwitch extends StatelessWidget {
  const WorkViewSwitch({
    super.key,
    required this.org,
    required this.project,
    required this.current,
  });

  final String org;
  final String project;
  final WorkView current;

  @override
  Widget build(BuildContext context) {
    final compact = context.breakpoint.isCompact;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
      child: SegmentedButton<WorkView>(
        segments: [
          ButtonSegment(
            value: WorkView.items,
            label: compact ? null : const Text('Items'),
            icon: const Icon(Icons.assignment_outlined),
            tooltip: 'Work items',
          ),
          ButtonSegment(
            value: WorkView.board,
            label: compact ? null : const Text('Board'),
            icon: const Icon(Icons.view_kanban_outlined),
            tooltip: 'Board',
          ),
        ],
        selected: {current},
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onSelectionChanged: (selection) {
          final view = selection.first;
          if (view == current) return;
          final base = projectRoute(context, org, project);
          context.go(
            view == WorkView.items ? '$base/work-items' : '$base/boards',
          );
        },
      ),
    );
  }
}
