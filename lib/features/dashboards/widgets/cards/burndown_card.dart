import 'package:flutter/material.dart';

import '../../../../data/models/dashboard.dart';
import '../../charts/chart_payload.dart';
import '../../charts/chart_sources.dart';
import '../chart_card.dart';
import '../dashboard_card.dart';

/// The Burndown and Burnup widgets: a **team's** work over a date range,
/// not a sprint's (research/19 §1).
///
/// One `WorkItemSnapshot` call, filtered by the team the settings name, the
/// work item types their `workItemTypeFilter` resolves to and the period
/// their `timePeriodConfiguration` carries. The burnup draws the same rows
/// the other way up: what has been completed, climbing to the scope.
class BurndownCard extends StatefulWidget {
  const BurndownCard({
    super.key,
    required this.args,
    required this.settings,
    this.burnup = false,
  });

  final DashboardCardArgs args;
  final BurndownSettings settings;
  final bool burnup;

  /// The default window when the widget's settings carry no start date.
  static const defaultDays = 30;

  static Future<ChartPayload> load(
    BuildContext context,
    DashboardCardArgs args,
    BurndownSettings settings, {
    required bool burnup,
    required bool refresh,
  }) async {
    final deps = ChartDeps.of(context);
    final teamSk = await deps.teamSk(
      args.org,
      args.project,
      teamId: settings.team?.teamId ?? args.teamId,
      refresh: refresh,
    );
    final types = await deps.types(
      args.org,
      args.project,
      teamSk,
      filter: settings.workItemTypeFilter,
      includeBugs: settings.includeBugsForRequirementCategory,
      refresh: refresh,
    );
    final end = settings.endDate ?? DateTime.now().toUtc();
    final start =
        settings.startDate ?? end.subtract(const Duration(days: defaultDays));
    // `aggregation` 1 is a sum of the named field (Story Points on every
    // dashboard seen); 0, and an absent aggregation, count work items.
    final sum = settings.aggregation?.isSum ?? false;
    final field = settings.aggregation?.field ?? 'StoryPoints';
    final days = await deps.analytics.teamBurndown(
      args.org,
      args.project,
      teamSk,
      types,
      start,
      end,
      sumField: sum ? field : 'StoryPoints',
      refresh: refresh,
    );
    return burndownPayload(
      title: args.widget.name.isNotEmpty
          ? args.widget.name
          : burnup
          ? 'Burnup'
          : 'Burndown',
      days: days,
      burnup: burnup,
      // A burnup of story points would need the points *completed*, which
      // the snapshot grouping does not carry (it sums the open ones), so a
      // burnup always counts items.
      useSum: sum && !burnup,
      finish: end,
      unit: burnup
          ? 'items'
          : sum
          ? (field == 'StoryPoints' ? 'points' : field)
          : 'items',
      summary: types.isEmpty ? null : types.join(', '),
    );
  }

  @override
  State<BurndownCard> createState() => _BurndownCardState();
}

class _BurndownCardState extends ChartCardState<BurndownCard> {
  @override
  DashboardCardArgs get cardArgs => widget.args;

  @override
  String get fallbackTitle => widget.burnup ? 'Burnup' : 'Burndown';

  @override
  IconData get icon => widget.burnup ? Icons.trending_up : Icons.trending_down;

  @override
  Future<ChartPayload?> read({required bool refresh}) => BurndownCard.load(
    context,
    widget.args,
    widget.settings,
    burnup: widget.burnup,
    refresh: refresh,
  );
}
