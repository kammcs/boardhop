import 'package:flutter/material.dart';

import '../../../../data/models/dashboard.dart';
import '../../charts/chart_payload.dart';
import '../../charts/chart_sources.dart';
import '../chart_card.dart';
import '../dashboard_card.dart';

/// Velocity: planned against delivered for the team's last N iterations
/// (research/19 D3, D9).
///
/// The widget stores `null` settings on every dashboard seen, which means
/// "this team, six iterations, count" — [VelocitySettings.defaults] — so
/// the Team overview's card and a configured widget take the same path.
class VelocityCard extends StatefulWidget {
  const VelocityCard({super.key, required this.args, required this.settings});

  final DashboardCardArgs args;
  final VelocitySettings settings;

  static Future<ChartPayload> load(
    BuildContext context,
    DashboardCardArgs args,
    VelocitySettings settings, {
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
      refresh: refresh,
    );
    final iterations = await deps.analytics.velocity(
      args.org,
      args.project,
      teamSk,
      types,
      iterations: settings.iterations,
      refresh: refresh,
    );
    return VelocityPayload(
      title: args.widget.name.isNotEmpty ? args.widget.name : 'Velocity',
      iterations: iterations,
      useStoryPoints: settings.aggregation?.isSum ?? false,
    );
  }

  @override
  State<VelocityCard> createState() => _VelocityCardState();
}

class _VelocityCardState extends ChartCardState<VelocityCard> {
  @override
  DashboardCardArgs get cardArgs => widget.args;

  @override
  String get fallbackTitle => 'Velocity';

  @override
  IconData get icon => Icons.bar_chart_outlined;

  @override
  Future<ChartPayload?> read({required bool refresh}) => VelocityCard.load(
    context,
    widget.args,
    widget.settings,
    refresh: refresh,
  );
}
