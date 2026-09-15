import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes.dart';
import '../../../../data/models/sprint.dart';
import '../../../../data/repositories/sprint_repository.dart';
import '../../../../theme/theme.dart';
import '../../../shared/account_scope.dart';
import '../../../work_items/widgets/work_item_visuals.dart';
import '../dashboard_card.dart';

/// Working days (Mon–Fri) from today to the sprint's finish date,
/// inclusive. Team days off live on the capacity read and are not worth a
/// second call for one line of text.
///
/// Top level so the calendar edges can be checked without a widget.
int workingDaysLeft(DateTime? finish, {DateTime? now}) {
  if (finish == null) return 0;
  var day = DateUtils.dateOnly(now ?? DateTime.now());
  final end = DateUtils.dateOnly(finish.toLocal());
  var days = 0;
  while (!day.isAfter(end)) {
    if (day.weekday <= DateTime.friday) days++;
    day = day.add(const Duration(days: 1));
  }
  return days;
}

/// Sprint Overview: the team's current sprint as one stacked bar — not
/// started, in progress, done — plus the working days left.
///
/// Everything here is a call `SprintRepository` already makes for the
/// Sprint view, so opening a dashboard with this card on it costs nothing
/// extra once the sprint has been looked at.
class SprintOverviewCard extends StatefulWidget {
  const SprintOverviewCard({super.key, required this.args});

  final DashboardCardArgs args;

  @override
  State<SprintOverviewCard> createState() => _SprintOverviewCardState();
}

class _SprintOverviewCardState extends State<SprintOverviewCard>
    with DashboardCardMixin {
  SprintSnapshot? _snapshot;

  @override
  Future<void> fetch({required bool refresh}) async {
    final repo = context.read<SprintRepository>();
    final org = widget.args.org;
    final project = widget.args.project;
    final team = widget.args.teamId ?? await repo.defaultTeamId(org, project);
    if (!mounted) return;
    final iterations = await repo.iterations(org, project, team: team);
    if (!mounted) return;
    final current = iterations.defaultIteration;
    if (current == null) {
      apply(() => _snapshot = null);
      return;
    }
    final cached = await repo.cachedSnapshot(
      org,
      project,
      current.id,
      team: team,
    );
    if (cached != null) apply(() => _snapshot = cached);
    final snapshot = await repo.load(
      org,
      project,
      current.id,
      team: team,
      refresh: refresh,
    );
    apply(() => _snapshot = snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final snapshot = _snapshot;
    final items = snapshot == null
        ? const []
        : [...snapshot.parents, ...snapshot.tasks];
    var proposed = 0;
    var inProgress = 0;
    var done = 0;
    for (final item in items) {
      switch (guessStateCategory(item.state)) {
        case 'Completed' || 'Resolved':
          done++;
        case 'InProgress':
          inProgress++;
        case 'Removed':
          break;
        default:
          proposed++;
      }
    }
    final total = proposed + inProgress + done;
    final left = workingDaysLeft(snapshot?.iteration.finishDate);
    return DashboardCard(
      title: widget.args.widget.name.isNotEmpty
          ? widget.args.widget.name
          : 'Sprint overview',
      icon: Icons.timelapse,
      filled: widget.args.filled,
      maxBodyHeight: widget.args.maxBodyHeight,
      loading: loading && snapshot == null,
      error: error,
      onTap: () => context.go(
        Routes.sprint(
          AccountScope.of(context),
          widget.args.org,
          widget.args.project,
        ),
      ),
      child: snapshot == null
          ? Text(
              'This team has no sprints.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.iteration.name,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Spacing.sm),
                if (total == 0)
                  Text(
                    'Nothing in this sprint yet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  ClipRRect(
                    borderRadius: Radii.chip,
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        children: [
                          if (proposed > 0)
                            Expanded(
                              flex: proposed,
                              child: ColoredBox(
                                color: colors.stateCategory('Proposed'),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          if (inProgress > 0)
                            Expanded(
                              flex: inProgress,
                              child: ColoredBox(
                                color: colors.stateCategory('InProgress'),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          if (done > 0)
                            Expanded(
                              flex: done,
                              child: ColoredBox(
                                color: colors.stateCategory('Completed'),
                                child: const SizedBox.expand(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: Spacing.sm),
                // Never colour alone (DESIGN §3): every segment is named.
                Text(
                  '$proposed not started · $inProgress in progress · $done done',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  left == 1 ? '1 working day left' : '$left working days left',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}
