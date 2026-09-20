import 'package:flutter/material.dart';

import '../../../data/models/sprint.dart';
import '../../../data/models/work_item_form.dart';
import '../../../theme/theme.dart';
import 'sprint_format.dart';

// `SprintTeamRef` is a model (the teams read answers it), re-exported here
// so callers of the picker keep their one import.
export '../../../data/models/sprint.dart' show SprintTeamRef;

/// What the picker came back with.
sealed class SprintPickerResult {
  const SprintPickerResult();
}

final class SprintIterationPicked extends SprintPickerResult {
  const SprintIterationPicked(this.iteration);

  final TeamIteration iteration;
}

final class SprintTeamPicked extends SprintPickerResult {
  const SprintTeamPicked(this.team);

  final SprintTeamRef team;
}

/// The sprint picker: a bottom sheet on a phone, a dialog from medium up.
Future<SprintPickerResult?> showSprintPicker(
  BuildContext context, {
  required List<TeamIteration> iterations,
  required String teamName,
  String? currentIterationId,
  List<SprintTeamRef> teams = const [],
}) {
  final body = SprintPickerSheet(
    iterations: iterations,
    teamName: teamName,
    currentIterationId: currentIterationId,
    teams: teams,
  );
  if (!context.breakpoint.isCompact) {
    return showBoardhopDialog<SprintPickerResult>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<SprintPickerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => body,
  );
}

/// Grouped Current / Future / Past, as the web's sprint selector is.
///
/// `$timeframe` accepts only `current` (research/18 §1), so the whole list
/// arrives unfiltered and the grouping is done here on `attributes.timeFrame`
/// — which the service fills in even when a sprint has no dates at all.
class SprintPickerSheet extends StatelessWidget {
  const SprintPickerSheet({
    super.key,
    required this.iterations,
    required this.teamName,
    this.currentIterationId,
    this.teams = const [],
  });

  final List<TeamIteration> iterations;
  final String teamName;
  final String? currentIterationId;
  final List<SprintTeamRef> teams;

  List<TeamIteration> _group(String timeFrame) => [
    for (final i in iterations)
      if ((i.timeFrame ?? '').toLowerCase() == timeFrame) i,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = _group('current');
    final future = _group('future');
    // Newest first: a past sprint is looked up backwards from today.
    final past = _group('past').reversed.toList();
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Spacing.lg),
        children: [
          // Title, team and the switch in a Wrap, not a ListTile with a
          // trailing button: at xxxL on a phone that button takes the whole
          // tile width (DESIGN.md — an action drops below its title rather
          // than sharing the line).
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
                Text('Sprints', style: theme.textTheme.titleMedium),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      teamName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (teams.length > 1)
                      TextButton(
                        onPressed: () => _switchTeam(context),
                        child: const Text('Switch team'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._section(context, 'Current', current),
          ..._section(context, 'Future', future),
          ..._section(context, 'Past', past),
          if (iterations.isEmpty)
            Padding(
              padding: Spacing.page,
              child: Text(
                'This team has no sprints.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _switchTeam(BuildContext context) async {
    final picked = await showModalBottomSheet<SprintTeamRef>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final team in teams)
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: Text(team.name),
                selected: team.name == teamName,
                onTap: () => Navigator.of(context).pop(team),
              ),
          ],
        ),
      ),
    );
    if (picked != null && context.mounted) {
      Navigator.of(context).pop(SprintTeamPicked(picked));
    }
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    List<TeamIteration> rows,
  ) {
    if (rows.isEmpty) return const [];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.md,
          Spacing.lg,
          Spacing.xs,
        ),
        child: Text(title, style: theme.textTheme.titleSmall),
      ),
      for (final iteration in rows)
        ListTile(
          title: Text(iteration.name),
          subtitle: Text(
            sprintDateRange(iteration.startDate, iteration.finishDate),
            style: theme.textTheme.bodySmall?.copyWith(
              // "Dates not set" is a real state (S11): greyed, never hidden.
              color: iteration.startDate == null && iteration.finishDate == null
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.7)
                  : scheme.onSurfaceVariant,
            ),
          ),
          trailing: iteration.id == currentIterationId
              ? const Icon(Icons.check)
              : null,
          selected: iteration.id == currentIterationId,
          onTap: () =>
              Navigator.of(context).pop(SprintIterationPicked(iteration)),
        ),
    ];
  }
}
