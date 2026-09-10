import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/theme.dart';

/// Bottom navigation (phones) or a rail (wider) across a project's areas.
/// Each branch keeps its own navigator and scroll state.
class ProjectShell extends StatelessWidget {
  const ProjectShell({
    super.key,
    required this.shell,
    required this.org,
    required this.project,
  });

  final StatefulNavigationShell shell;
  final String org;
  final String project;

  static const _destinations = <({String label, IconData icon, IconData selected, String path})>[
    (
      label: 'Work items',
      icon: Icons.assignment_outlined,
      selected: Icons.assignment,
      path: 'work-items',
    ),
    (
      label: 'Board',
      icon: Icons.view_kanban_outlined,
      selected: Icons.view_kanban,
      path: 'boards',
    ),
    (
      label: 'Pipelines',
      icon: Icons.play_circle_outline,
      selected: Icons.play_circle,
      path: 'pipelines',
    ),
  ];

  String projectPath(String tail) =>
      '/orgs/${Uri.encodeComponent(org)}/projects/${Uri.encodeComponent(project)}/$tail';

  void _select(BuildContext context, int index) {
    if (index == shell.currentIndex) {
      shell.goBranch(index, initialLocation: true);
      return;
    }
    // Branch routes carry path parameters, so navigate to the concrete
    // location instead of relying on a branch default.
    context.go(projectPath(_destinations[index].path));
  }

  @override
  Widget build(BuildContext context) {
    if (context.breakpoint.isCompact) {
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => _select(context, i),
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: d.label,
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) => _select(context, i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ],
      ),
    );
  }
}
