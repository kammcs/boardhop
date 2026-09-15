import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/analytics.dart';
import '../../../theme/theme.dart';
import 'chart_format.dart';

/// The pipeline's recent runs as small bars, oldest on the left: height by
/// duration against the slowest of them, colour by outcome (research/19 D9).
///
/// The same shape as the Build History card's bars, drawn from Analytics'
/// `PipelineRuns` rather than the REST run list, because the pass rate
/// beside it comes from the same call.
class RunOutcomeBars extends StatelessWidget {
  const RunOutcomeBars({
    super.key,
    required this.runs,
    required this.height,
    this.onTapRun,
  });

  /// Newest first, as Analytics answers; the bars are drawn reversed.
  final List<AnalyticsPipelineRun> runs;
  final double height;
  final void Function(AnalyticsPipelineRun run)? onTapRun;

  static Color colorFor(BuildContext context, AnalyticsPipelineRun run) {
    final colors = context.boardhopColors;
    return switch (run.outcome) {
      'Succeed' => colors.runSucceeded,
      'Failed' => colors.runFailed,
      'Canceled' => colors.runCanceled,
      _ => colors.runPartial,
    };
  }

  static String labelFor(AnalyticsPipelineRun run) => switch (run.outcome) {
    'Succeed' => 'Succeeded',
    'Failed' => 'Failed',
    'Canceled' => 'Canceled',
    final other => other ?? 'Unknown',
  };

  static List<ChartKey> keysFor(BuildContext context) {
    final colors = context.boardhopColors;
    return [
      ChartKey('Succeeded', colors.runSucceeded),
      ChartKey('Failed', colors.runFailed),
      ChartKey('Canceled', colors.runCanceled),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) return const SizedBox.shrink();
    final bars = runs.reversed.toList();
    final slowest = bars.fold<double>(
      1,
      (m, r) => (r.durationSeconds ?? 0) > m ? r.durationSeconds! : m,
    );
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final run in bars)
            Expanded(
              child: _Bar(
                run: run,
                slowestSeconds: slowest,
                maxHeight: height,
                onTap: onTapRun == null ? null : () => onTapRun!(run),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.run,
    required this.slowestSeconds,
    required this.maxHeight,
    this.onTap,
  });

  final AnalyticsPipelineRun run;
  final double slowestSeconds;
  final double maxHeight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final seconds = run.durationSeconds ?? 0;
    // A floor of a fifth, as the Build History card uses: a bar too short
    // to see reads as a gap in the history rather than a fast run.
    final factor = slowestSeconds <= 0
        ? 0.2
        : (seconds / slowestSeconds).clamp(0.2, 1.0);
    final duration = run.durationSeconds == null
        ? ''
        : ' · ${formatDuration(Duration(seconds: run.durationSeconds!.round()))}';
    final bar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: maxHeight * factor,
          decoration: BoxDecoration(
            color: RunOutcomeBars.colorFor(context, run),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
          ),
        ),
      ),
    );
    return Tooltip(
      message:
          '${run.runNumber ?? run.runId} · '
          '${RunOutcomeBars.labelFor(run)}$duration',
      child: onTap == null ? bar : InkWell(onTap: onTap, child: bar),
    );
  }
}
