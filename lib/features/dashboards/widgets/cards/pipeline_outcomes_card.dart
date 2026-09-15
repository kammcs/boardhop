import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/models/analytics.dart';
import '../../../../data/models/pipeline.dart';
import '../../../../data/repositories/analytics_repository.dart';
import '../../charts/chart_payload.dart';
import '../chart_card.dart';
import '../dashboard_card.dart';
import '../../../../data/repositories/pipeline_repository.dart';

/// Pipeline pass rate — a Team overview card (research/19 D9): how often the
/// project's busiest pipeline has passed over the last 90 days, and its
/// last runs as bars.
///
/// **One** pipeline, the most recently run: Analytics answers per pipeline
/// id and a project with twenty definitions would be twenty calls of a
/// second each for one card. The pipelines view is one tap away for the
/// rest, and the card names which one it is showing.
class PipelineOutcomesCard extends StatefulWidget {
  const PipelineOutcomesCard({super.key, required this.args});

  final DashboardCardArgs args;

  static const windowDays = 90;
  static const runs = 20;

  /// The definition that ran most recently — the completed build where
  /// there is one, else the running build. Definitions that never ran come
  /// last; a project of nothing but those answers null.
  static PipelineDefinition? mostRecentlyRun(
    List<PipelineDefinition> definitions,
  ) {
    DateTime? when(PipelineDefinition d) {
      final build = d.latestCompletedBuild ?? d.latestBuild;
      return build?.finishTime ?? build?.startTime ?? build?.queueTime;
    }

    PipelineDefinition? best;
    DateTime? bestAt;
    for (final d in definitions) {
      final at = when(d);
      if (at == null) continue;
      if (bestAt == null || at.isAfter(bestAt)) {
        best = d;
        bestAt = at;
      }
    }
    return best;
  }

  static Future<ChartPayload> load(
    BuildContext context,
    DashboardCardArgs args, {
    required bool refresh,
  }) async {
    final analytics = context.read<AnalyticsRepository>();
    final pipelines = context.read<PipelineRepository>();
    final title = args.widget.name.isNotEmpty
        ? args.widget.name
        : 'Pipeline pass rate';
    final definitions = await pipelines.definitions(args.org, args.project);
    final chosen = mostRecentlyRun(definitions);
    if (chosen == null) {
      return PipelineOutcomesPayload(
        title: title,
        outcomes: const PipelineOutcomes(),
        days: windowDays,
        pipelineName: definitions.isEmpty
            ? 'This project has no pipelines'
            : 'No pipeline has run yet',
      );
    }
    final outcomes = await analytics.pipelineOutcomes(
      args.org,
      args.project,
      chosen.id,
      DateTime.now().toUtc().subtract(const Duration(days: windowDays)),
      top: runs,
      refresh: refresh,
    );
    return PipelineOutcomesPayload(
      title: title,
      outcomes: outcomes,
      days: windowDays,
      pipelineName: chosen.name,
      pipelineId: chosen.id,
    );
  }

  @override
  State<PipelineOutcomesCard> createState() => _PipelineOutcomesCardState();
}

class _PipelineOutcomesCardState extends ChartCardState<PipelineOutcomesCard> {
  @override
  DashboardCardArgs get cardArgs => widget.args;

  @override
  String get fallbackTitle => 'Pipeline pass rate';

  @override
  IconData get icon => Icons.rocket_launch_outlined;

  @override
  Future<ChartPayload?> read({required bool refresh}) =>
      PipelineOutcomesCard.load(context, widget.args, refresh: refresh);
}
