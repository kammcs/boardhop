import 'package:flutter/material.dart';

import '../../../data/models/dashboard.dart';
import '../../../data/models/sprint.dart' show SprintTeamRef;
import '../../../theme/theme.dart';
import '../team_overview.dart';

/// What the dashboard picker came back with: a dashboard of the service, or
/// Boardhop's own Team overview (D6).
sealed class DashboardPicked {
  const DashboardPicked();
}

final class DashboardSummaryPicked extends DashboardPicked {
  const DashboardSummaryPicked(this.summary);

  final DashboardSummary summary;
}

final class TeamOverviewPicked extends DashboardPicked {
  const TeamOverviewPicked();
}

/// The dashboard picker: one project-wide list grouped by team, favorites
/// first with a filled star (read-only), then the Team overview entry.
///
/// A bottom sheet on a phone at 75 % of the height — a project with several
/// teams has a long list and the sheet has to be worth opening — and a
/// dialog from medium up, exactly as the sprint picker does it.
Future<DashboardPicked?> showDashboardPicker(
  BuildContext context, {
  required List<DashboardSummary> dashboards,
  required List<SprintTeamRef> teams,
  Set<String> favorites = const {},
  String? currentId,
  String? projectName,
}) {
  final body = DashboardPickerSheet(
    dashboards: dashboards,
    teams: teams,
    favorites: favorites,
    currentId: currentId,
    projectName: projectName,
  );
  if (!context.breakpoint.isCompact) {
    return showDialog<DashboardPicked>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<DashboardPicked>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.75,
    ),
    builder: (context) => body,
  );
}

class DashboardPickerSheet extends StatelessWidget {
  const DashboardPickerSheet({
    super.key,
    required this.dashboards,
    required this.teams,
    this.favorites = const {},
    this.currentId,
    this.projectName,
  });

  final List<DashboardSummary> dashboards;
  final List<SprintTeamRef> teams;
  final Set<String> favorites;
  final String? currentId;
  final String? projectName;

  /// Favorites first, then the service's own `position`, then the name —
  /// the order the web's picker shows and the one D6 asks for.
  List<DashboardSummary> _sorted(List<DashboardSummary> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      final fa = favorites.contains(a.id) ? 0 : 1;
      final fb = favorites.contains(b.id) ? 0 : 1;
      if (fa != fb) return fa.compareTo(fb);
      final byPosition = a.position.compareTo(b.position);
      if (byPosition != 0) return byPosition;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  /// Team id → display name. A dashboard whose team is not in the list
  /// (the account cannot enumerate teams, or the dashboard is
  /// project-scoped) is grouped under the project itself rather than
  /// dropped.
  String _teamName(String? teamId) {
    for (final team in teams) {
      if (team.id == teamId) return team.name;
    }
    return projectName ?? 'This project';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final byTeam = <String, List<DashboardSummary>>{};
    for (final d in dashboards) {
      byTeam.putIfAbsent(_teamName(d.teamId), () => []).add(d);
    }
    final groupNames = byTeam.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.md,
              Spacing.lg,
              Spacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dashboards', style: theme.textTheme.titleMedium),
                if (projectName != null)
                  Text(
                    projectName!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final group in groupNames) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.xs,
              ),
              child: Text(group, style: theme.textTheme.titleSmall),
            ),
            for (final d in _sorted(byTeam[group]!))
              ListTile(
                leading: Icon(
                  Icons.dashboard_outlined,
                  color: scheme.onSurfaceVariant,
                ),
                title: Text(d.name),
                subtitle: (d.description ?? '').isEmpty
                    ? null
                    : Text(
                        d.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (favorites.contains(d.id))
                      Icon(
                        Icons.star,
                        size: 18,
                        color: scheme.primary,
                        semanticLabel: 'Favorite',
                      ),
                    if (d.id == currentId)
                      const Padding(
                        padding: EdgeInsets.only(left: Spacing.sm),
                        child: Icon(Icons.check),
                      ),
                  ],
                ),
                selected: d.id == currentId,
                onTap: () =>
                    Navigator.of(context).pop(DashboardSummaryPicked(d)),
              ),
          ],
          const Divider(height: 1),
          // Boardhop's own, last: it is not a dashboard of the service and
          // says so (D1, D6).
          ListTile(
            leading: Icon(Icons.auto_awesome_outlined, color: scheme.primary),
            title: const Text(TeamOverview.name),
            subtitle: const Text('Built into Boardhop'),
            trailing: currentId == TeamOverview.id
                ? const Icon(Icons.check)
                : null,
            selected: currentId == TeamOverview.id,
            onTap: () => Navigator.of(context).pop(const TeamOverviewPicked()),
          ),
          if (dashboards.isEmpty)
            Padding(
              padding: Spacing.page,
              child: Text(
                'This project has no dashboards yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
