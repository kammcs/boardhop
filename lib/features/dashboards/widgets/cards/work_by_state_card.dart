import 'package:flutter/material.dart';

import '../../charts/chart_payload.dart';
import '../../charts/chart_sources.dart';
import '../chart_card.dart';
import '../dashboard_card.dart';

/// Work by state — a Team overview card (research/19 D9).
///
/// One Analytics call grouped by `(WorkItemType, State, StateCategory)`,
/// drawn as a stacked bar per work item type. There is no dashboard widget
/// behind it: the web's nearest equivalent is the Chart for Work Items,
/// which Boardhop hides because its settings carry no query (D2).
class WorkByStateCard extends StatefulWidget {
  const WorkByStateCard({super.key, required this.args});

  final DashboardCardArgs args;

  static Future<ChartPayload> load(
    BuildContext context,
    DashboardCardArgs args, {
    required bool refresh,
  }) async {
    final deps = ChartDeps.of(context);
    final teamSk = await deps.teamSk(
      args.org,
      args.project,
      teamId: args.teamId,
      refresh: refresh,
    );
    final counts = await deps.analytics.workByState(
      args.org,
      args.project,
      teamSk,
      refresh: refresh,
    );
    return WorkByStatePayload(
      title: args.widget.name.isNotEmpty ? args.widget.name : 'Work by state',
      counts: counts,
    );
  }

  @override
  State<WorkByStateCard> createState() => _WorkByStateCardState();
}

class _WorkByStateCardState extends ChartCardState<WorkByStateCard> {
  @override
  DashboardCardArgs get cardArgs => widget.args;

  @override
  String get fallbackTitle => 'Work by state';

  @override
  IconData get icon => Icons.donut_small_outlined;

  @override
  Future<ChartPayload?> read({required bool refresh}) =>
      WorkByStateCard.load(context, widget.args, refresh: refresh);
}
