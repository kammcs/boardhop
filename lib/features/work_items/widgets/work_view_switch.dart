import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';

enum WorkView { items, board, sprint }

/// The Work tab holds three views of the same project: the work item list,
/// the board and the sprint (NEXT-STEPS 24, decision S1). This segmented
/// control sits in the app bar of all three, left of nothing — it is the
/// rightmost action — and switches between their routes so each keeps its
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
          ButtonSegment(
            value: WorkView.sprint,
            label: compact ? null : const Text('Sprint'),
            // The running figure, not another board or clock glyph: on a
            // phone this pill is icons only, so the three have to be
            // unmistakable at a glance.
            icon: const Icon(Icons.directions_run),
            tooltip: 'Sprint',
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
          final account = AccountScope.of(context);
          context.go(switch (view) {
            WorkView.items => Routes.workItems(account, org, project),
            WorkView.board => Routes.board(account, org, project),
            WorkView.sprint => Routes.sprint(account, org, project),
          });
        },
      ),
    );
  }
}
