import 'package:flutter/material.dart';

import '../../../../data/models/dashboard.dart';
import '../../../../data/models/work_item_form.dart' show TeamIteration;
import '../../charts/chart_payload.dart';
import '../../charts/chart_sources.dart';
import '../chart_card.dart';
import '../dashboard_card.dart';

/// Sprint Burndown — the Analytics widget, the legacy one, and the Team
/// overview's own card.
///
/// All three draw the same chart from the same Analytics rows (D14): the
/// legacy widget's server-rendered PNG is not used, and its settings point
/// at an iteration just as the Analytics widget's do. The Team overview
/// arrives with no settings at all and charts the team's **current** sprint
/// through `SprintRepository`.
class SprintBurndownCard extends StatefulWidget {
  const SprintBurndownCard({super.key, required this.args, this.settings});

  final DashboardCardArgs args;

  /// Null on the Team overview's built-in card (D9).
  final SprintBurndownSettings? settings;

  static Future<ChartPayload> load(
    BuildContext context,
    DashboardCardArgs args,
    SprintBurndownSettings? settings, {
    required bool refresh,
  }) async {
    final deps = ChartDeps.of(context);
    final title = args.widget.name.isNotEmpty
        ? args.widget.name
        : 'Sprint burndown';
    var iterationId = settings?.iterationId;
    var start = settings?.startDate;
    var end = settings?.endDate;
    String? sprintName;

    if (iterationId == null || start == null || end == null) {
      final teamId =
          settings?.team?.teamId ??
          args.teamId ??
          await deps.sprints.defaultTeamId(args.org, args.project);
      final iterations = await deps.sprints.iterations(
        args.org,
        args.project,
        team: teamId,
        refresh: refresh,
      );
      final TeamIteration? sprint = iterationId == null
          ? iterations.defaultIteration
          : iterations.byId(iterationId) ?? iterations.defaultIteration;
      if (sprint == null && iterationId == null) {
        // A team with no iterations at all: nothing to chart, and the card
        // says so rather than asking Analytics about nothing.
        return burndownPayload(
          title: title,
          days: const [],
          burnup: false,
          noDataNote: 'This team has no sprints.',
        );
      }
      iterationId ??= sprint!.id;
      start ??= sprint?.startDate;
      end ??= sprint?.finishDate;
      sprintName = sprint?.name;
    }

    final today = DateTime.now().toUtc();
    final from = start ?? today.subtract(const Duration(days: 30));
    final to = end ?? today;
    final days = await deps.analytics.burndown(
      args.org,
      args.project,
      iterationId,
      start: from,
      end: to,
      refresh: refresh,
    );
    return burndownPayload(
      title: title,
      days: days,
      burnup: false,
      finish: to,
      summary: sprintName ?? settings?.iterationPath,
    );
  }

  @override
  State<SprintBurndownCard> createState() => _SprintBurndownCardState();
}

class _SprintBurndownCardState extends ChartCardState<SprintBurndownCard> {
  @override
  DashboardCardArgs get cardArgs => widget.args;

  @override
  String get fallbackTitle => 'Sprint burndown';

  @override
  IconData get icon => Icons.trending_down;

  @override
  Future<ChartPayload?> read({required bool refresh}) =>
      SprintBurndownCard.load(
        context,
        widget.args,
        widget.settings,
        refresh: refresh,
      );
}
