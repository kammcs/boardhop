import 'package:flutter/material.dart';

import '../../../../data/models/analytics.dart';
import '../../../../data/models/dashboard.dart';
import '../../charts/chart_payload.dart';
import '../../charts/chart_sources.dart';
import '../chart_card.dart';
import '../dashboard_card.dart';

/// The Cumulative Flow Diagram: how many items sat in each board column,
/// day by day (research/19 D3, D9).
///
/// The widget names its board; the Team overview's card has no settings and
/// takes the team's requirement backlog, which is the board the web's own
/// CFD widget defaults to and the name Analytics' `BoardLocations` uses.
/// `swimlane` is read but not applied in v1 (§6): the snapshot grouping is
/// by column alone.
class CfdCard extends StatefulWidget {
  const CfdCard({super.key, required this.args, this.settings});

  final DashboardCardArgs args;

  /// Null on the Team overview's built-in card (30 days, default board).
  final CfdSettings? settings;

  static const defaultDays = 30;

  static Future<ChartPayload> load(
    BuildContext context,
    DashboardCardArgs args,
    CfdSettings? settings, {
    required bool refresh,
  }) async {
    final deps = ChartDeps.of(context);
    final teamSk = await deps.teamSk(
      args.org,
      args.project,
      teamId: settings?.team?.teamId ?? args.teamId,
      refresh: refresh,
    );
    final days = settings?.days ?? defaultDays;
    var board = settings?.board ?? '';
    if (board.isEmpty) {
      board =
          await deps.analytics.requirementBoardName(
            args.org,
            args.project,
            teamSk,
            refresh: refresh,
          ) ??
          '';
    }
    final title = args.widget.name.isNotEmpty
        ? args.widget.name
        : 'Cumulative flow';
    if (board.isEmpty) {
      // Analytics has no backlog row for this team: rather than query for a
      // board that cannot exist, the card says so where it would have drawn.
      return CumulativeFlowPayload(
        title: title,
        flow: const CumulativeFlow(),
        days: days,
        noDataNote: 'This team has no board Analytics knows about.',
      );
    }
    final flow = await deps.analytics.cumulativeFlow(
      args.org,
      args.project,
      teamSk,
      board,
      DateTime.now().toUtc().subtract(Duration(days: days)),
      refresh: refresh,
    );
    return CumulativeFlowPayload(
      title: title,
      flow: flow,
      days: days,
      boardName: board,
    );
  }

  @override
  State<CfdCard> createState() => _CfdCardState();
}

class _CfdCardState extends ChartCardState<CfdCard> {
  @override
  DashboardCardArgs get cardArgs => widget.args;

  @override
  String get fallbackTitle => 'Cumulative flow';

  @override
  IconData get icon => Icons.area_chart_outlined;

  @override
  Future<ChartPayload?> read({required bool refresh}) =>
      CfdCard.load(context, widget.args, widget.settings, refresh: refresh);
}
