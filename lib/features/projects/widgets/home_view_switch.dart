import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';

/// The Home tab's views (research/19 D8). Two segments ship now; Wiki is
/// the third and slots in here, in [HomeViewSwitch] and in [Routes]
/// without touching any caller.
enum HomeView { summary, dashboards }

/// The Home tab holds the project's own views: the Summary landing page and
/// the team's Azure DevOps dashboards (research/19 D5, D8, D13). Cloned from
/// `WorkViewSwitch`: it is the **rightmost** app-bar item on every page of
/// the tab, so it never moves when an action appears next to it, and it is
/// icons only on a phone.
class HomeViewSwitch extends StatelessWidget {
  const HomeViewSwitch({
    super.key,
    required this.org,
    required this.project,
    required this.current,
  });

  final String org;
  final String project;
  final HomeView current;

  @override
  Widget build(BuildContext context) {
    final compact = context.breakpoint.isCompact;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
      child: SegmentedButton<HomeView>(
        segments: [
          ButtonSegment(
            value: HomeView.summary,
            label: compact ? null : const Text('Summary'),
            icon: const Icon(Icons.summarize_outlined),
            tooltip: 'Summary',
          ),
          ButtonSegment(
            value: HomeView.dashboards,
            label: compact ? null : const Text('Dashboards'),
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: 'Dashboards',
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
            HomeView.summary => Routes.home(account, org, project),
            // No `dashboard`: the plain route is the plain view, and the
            // page opens the one last remembered (D6).
            HomeView.dashboards => Routes.dashboards(account, org, project),
          });
        },
      ),
    );
  }
}
