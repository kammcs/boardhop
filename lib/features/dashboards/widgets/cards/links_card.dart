import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes.dart';
import '../../../../data/models/dashboard.dart';
import '../../../shared/account_scope.dart';
import '../dashboard_card.dart';

/// The link widgets — Work Links, Other Links, Welcome, VS Shortcuts and
/// New Work Item — all draw the same thing: a short list of shortcuts.
///
/// Every one of them stores `null` settings (§1), so there is nothing to
/// read and nothing that names a target. What the web puts behind them is
/// mostly desktop (Visual Studio protocol handlers, the web's own backlog
/// pages), so Boardhop shows **the app's own routes** instead: the places
/// the same person would be going. Nothing here leaves the app.
class LinksCard extends StatelessWidget {
  const LinksCard({super.key, required this.args});

  final DashboardCardArgs args;

  static IconData iconFor(WidgetKind kind) => switch (kind) {
    WidgetKind.newWorkItem => Icons.add_circle_outline,
    WidgetKind.welcome => Icons.waving_hand_outlined,
    WidgetKind.vsShortcuts => Icons.developer_mode_outlined,
    _ => Icons.link_outlined,
  };

  @override
  Widget build(BuildContext context) {
    // The diagnostics probe draws this card outside the account shell, so
    // there is no account to build a route from: the rows are shown and
    // inert rather than asserting.
    final account = AccountScope.maybeOf(context);
    final org = args.org;
    final project = args.project;
    final base = account == null ? null : Routes.project(account, org, project);
    final links = <(IconData, String, VoidCallback?)>[
      if (account != null && base != null) ...[
        (
          Icons.add_circle_outline,
          'New work item',
          () => context.push('$base/work-items/new'),
        ),
        (
          Icons.assignment_outlined,
          'Work items',
          () => context.go(Routes.workItems(account, org, project)),
        ),
        (
          Icons.view_kanban_outlined,
          'Board',
          () => context.go(Routes.board(account, org, project)),
        ),
        (
          Icons.directions_run,
          'Sprint',
          () => context.go(Routes.sprint(account, org, project)),
        ),
        (Icons.source_outlined, 'Repos', () => context.go('$base/repos')),
        (
          Icons.play_circle_outline,
          'Pipelines',
          () => context.go(Routes.pipelines(account, org, project)),
        ),
      ] else ...[
        (Icons.add_circle_outline, 'New work item', null),
        (Icons.assignment_outlined, 'Work items', null),
        (Icons.view_kanban_outlined, 'Board', null),
        (Icons.directions_run, 'Sprint', null),
        (Icons.source_outlined, 'Repos', null),
        (Icons.play_circle_outline, 'Pipelines', null),
      ],
    ];
    // New Work Item is a single-purpose widget on the web; keep it that way.
    final rows = args.widget.kind == WidgetKind.newWorkItem
        ? links.take(1).toList()
        : links;
    return DashboardCard(
      title: args.widget.name.isNotEmpty ? args.widget.name : 'Links',
      icon: iconFor(args.widget.kind),
      filled: args.filled,
      maxBodyHeight: args.maxBodyHeight,
      padBody: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (icon, label, go) in rows)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(icon, size: 20),
              title: Text(label),
              onTap: go,
            ),
        ],
      ),
    );
  }
}
