import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../theme/theme.dart';

/// The three pieces of page furniture the Dashboards view draws around its
/// cards. They live here rather than inside the page so the diagnostics
/// probe draws the same widgets the page does, on canned data.

/// "Updated 3m ago", or the offline form, over content that did not come
/// from this minute's network read (D12).
class DashboardCacheLine extends StatelessWidget {
  const DashboardCacheLine({super.key, this.shownAt, this.offline = false});

  final DateTime? shownAt;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final at = shownAt;
    if (at == null && !offline) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final age = at == null ? '' : ' · ${relativeTime(at)}';
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg + MediaQuery.paddingOf(context).left,
        Spacing.xs,
        Spacing.lg + MediaQuery.paddingOf(context).right,
        0,
      ),
      child: Row(
        children: [
          Icon(
            offline ? Icons.cloud_off_outlined : Icons.history_toggle_off,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              offline
                  ? 'offline · showing the cached copy$age'
                  : at == null
                  ? 'Updated'
                  : 'Updated ${relativeTime(at)} ago',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// D1: an empty dashboard is the common case — three of the four puremedia
/// projects' Overviews have no widgets at all — so it is not an empty state
/// but an offer of Boardhop's own Team overview.
class DashboardEmptyOffer extends StatelessWidget {
  const DashboardEmptyOffer({
    super.key,
    required this.onShowTeamOverview,
    this.isTeamOverview = false,
  });

  final VoidCallback onShowTeamOverview;

  /// True when the empty dashboard **is** the Team overview, which has
  /// nothing to offer beyond itself.
  final bool isTeamOverview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.dashboard_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            isTeamOverview
                ? 'Nothing to show yet.'
                : 'This dashboard has no widgets.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            isTeamOverview
                ? 'The Team overview draws itself from this team’s data.'
                : 'Every team gets an empty Overview when it is created, and '
                      'widgets are added on the web. Boardhop can show its '
                      'own overview of this team in the meantime.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!isTeamOverview) ...[
            const SizedBox(height: Spacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onShowTeamOverview,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Show the Team overview'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// D10: the widgets Boardhop cannot draw are counted, not faked, and the
/// line opens the dashboard on the web, where they do draw.
class DashboardHiddenLine extends StatelessWidget {
  const DashboardHiddenLine({
    super.key,
    required this.hidden,
    required this.onOpenWeb,
  });

  final int hidden;
  final VoidCallback? onOpenWeb;

  @override
  Widget build(BuildContext context) {
    if (hidden <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onOpenWeb,
          icon: Icon(
            Icons.open_in_new,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          label: Text(
            hidden == 1
                ? '1 widget not shown in Boardhop'
                : '$hidden widgets not shown in Boardhop',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
