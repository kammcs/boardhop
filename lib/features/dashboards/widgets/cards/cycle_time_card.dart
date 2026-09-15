import 'package:flutter/material.dart';

import '../../../../data/models/dashboard.dart';
import '../../charts/chart_payload.dart';
import '../../charts/chart_sources.dart';
import '../chart_card.dart';
import '../dashboard_card.dart';

/// Cycle Time and Lead Time — one card class for both widgets, and for the
/// Team overview's card that carries both averages (research/19 D3, D9).
///
/// Cycle time is the days from first In Progress to Completed; lead time is
/// the days from created to Completed. Analytics computes both per item, so
/// one read answers either chart and the overview's card shows the average
/// of the other beside it.
class CycleTimeCard extends StatefulWidget {
  const CycleTimeCard({
    super.key,
    required this.args,
    this.settings,
    this.lead = false,
    this.showBoth = false,
  });

  final DashboardCardArgs args;

  /// Null on the Team overview's built-in card (60 days, both averages).
  final CycleTimeSettings? settings;

  /// Draw lead time rather than cycle time.
  final bool lead;

  /// Name both averages, which is what the Team overview's one card does.
  final bool showBoth;

  /// The Team overview's window (D9); the widgets carry their own
  /// `timePeriodInDays`.
  static const overviewDays = 60;

  static Future<ChartPayload> load(
    BuildContext context,
    DashboardCardArgs args,
    CycleTimeSettings? settings, {
    required bool lead,
    required bool showBoth,
    required bool refresh,
  }) async {
    final deps = ChartDeps.of(context);
    final teamSk = await deps.teamSk(
      args.org,
      args.project,
      teamId: settings?.team?.teamId ?? args.teamId,
      refresh: refresh,
    );
    final types = await deps.types(
      args.org,
      args.project,
      teamSk,
      filter: settings?.workItemTypeFilter,
      refresh: refresh,
    );
    final days = settings?.days ?? overviewDays;
    final data = await deps.analytics.cycleAndLeadTime(
      args.org,
      args.project,
      teamSk,
      DateTime.now().toUtc().subtract(Duration(days: days)),
      types: types,
      refresh: refresh,
    );
    return CycleTimePayload(
      title: args.widget.name.isNotEmpty
          ? args.widget.name
          : showBoth
          ? 'Cycle and lead time'
          : lead
          ? 'Lead time'
          : 'Cycle time',
      data: data,
      days: days,
      lead: lead,
      showBoth: showBoth,
    );
  }

  @override
  State<CycleTimeCard> createState() => _CycleTimeCardState();
}

class _CycleTimeCardState extends ChartCardState<CycleTimeCard> {
  @override
  DashboardCardArgs get cardArgs => widget.args;

  @override
  String get fallbackTitle => widget.showBoth
      ? 'Cycle and lead time'
      : widget.lead
      ? 'Lead time'
      : 'Cycle time';

  @override
  IconData get icon => Icons.scatter_plot_outlined;

  @override
  Future<ChartPayload?> read({required bool refresh}) => CycleTimeCard.load(
    context,
    widget.args,
    widget.settings,
    lead: widget.lead,
    showBoth: widget.showBoth,
    refresh: refresh,
  );
}
