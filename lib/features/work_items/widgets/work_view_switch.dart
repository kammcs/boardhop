import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';

enum WorkView { items, board }

/// The Work tab holds two views of the same project: the work item list and
/// the board. This segmented control sits under both app bars and switches
/// between their routes, so each keeps its own state and deep links.
class WorkViewSwitch extends StatelessWidget implements PreferredSizeWidget {
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
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xs,
        Spacing.lg,
        Spacing.sm,
      ),
      child: SegmentedButton<WorkView>(
        segments: const [
          ButtonSegment(
            value: WorkView.items,
            label: Text('Items'),
            icon: Icon(Icons.assignment_outlined),
          ),
          ButtonSegment(
            value: WorkView.board,
            label: Text('Board'),
            icon: Icon(Icons.view_kanban_outlined),
          ),
        ],
        selected: {current},
        showSelectedIcon: false,
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
