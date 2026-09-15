import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routes.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';

/// The Home tab's views (research/19 D8, research/20 §4.2). Three segments:
/// the project's Summary, the team's dashboards and the project wiki.
enum HomeView { summary, dashboards, wiki }

/// The Home tab holds the project's own views: the Summary landing page, the
/// team's Azure DevOps dashboards and the wiki (research/19 D5, D8, D13;
/// research/20 §4.2). Cloned from `WorkViewSwitch`: it is the **rightmost**
/// app-bar item on every page of the tab, so it never moves when an action
/// appears next to it, and it is icons only on a phone — which is why the
/// third segment's icon has to be unmistakable on its own (item 24).
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
          ButtonSegment(
            value: HomeView.wiki,
            label: compact ? null : const Text('Wiki'),
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Wiki',
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
            // No `wiki` and no `path`: the plain route is the plain view,
            // and the tree page opens the wiki last remembered, expanded
            // along the page last read (K1).
            HomeView.wiki => Routes.wiki(account, org, project),
          });
        },
      ),
    );
  }
}
