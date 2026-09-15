import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes.dart';
import '../../../../core/util/format.dart';
import '../../../../data/models/dashboard.dart';
import '../../../../data/models/pipeline.dart';
import '../../../../data/repositories/pipeline_repository.dart';
import '../../../../theme/theme.dart';
import '../../../pipelines/widgets/pipeline_visuals.dart';
import '../../../shared/account_scope.dart';
import '../dashboard_card.dart';

/// Build History: one bar per run of a pipeline, newest on the right,
/// height by duration against the slowest of them and colour by outcome.
///
/// Plain `Container`s rather than a chart library: twenty bars need no axes
/// and no interaction model, and the charting phase (D-C) is what brings
/// `fl_chart` into the app.
class BuildHistoryCard extends StatefulWidget {
  const BuildHistoryCard({
    super.key,
    required this.args,
    required this.settings,
  });

  final DashboardCardArgs args;
  final BuildHistorySettings settings;

  @override
  State<BuildHistoryCard> createState() => _BuildHistoryCardState();
}

class _BuildHistoryCardState extends State<BuildHistoryCard>
    with DashboardCardMixin {
  static const _top = 20;
  static const _barHeight = 72.0;

  List<BuildRun>? _runs;

  @override
  Future<void> fetch({required bool refresh}) async {
    final runs = await context.read<PipelineRepository>().runs(
      widget.args.org,
      widget.args.project,
      definitionId: widget.settings.definitionId,
      top: _top,
      queryOrder: PipelineRepository.finishTimeDescending,
    );
    apply(() => _runs = runs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final runs = _runs;
    // The service answers newest first; the eye reads a history left to
    // right, so the oldest bar is drawn first.
    final bars = (runs ?? const <BuildRun>[]).reversed.toList();
    final slowest = bars.fold<int>(
      1,
      (m, r) => (r.duration?.inSeconds ?? 0) > m ? r.duration!.inSeconds : m,
    );
    final name = widget.args.widget.name.isNotEmpty
        ? widget.args.widget.name
        : bars.isNotEmpty
        ? bars.last.definitionName
        : 'Build history';
    return DashboardCard(
      title: name,
      icon: Icons.bar_chart_outlined,
      filled: widget.args.filled,
      maxBodyHeight: widget.args.maxBodyHeight,
      loading: loading && runs == null,
      error: error,
      onTap: () => context.go(
        Routes.pipelines(
          AccountScope.of(context),
          widget.args.org,
          widget.args.project,
        ),
      ),
      child: bars.isEmpty
          ? Text(
              'No runs yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _barHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final run in bars)
                        Expanded(
                          child: _Bar(
                            run: run,
                            slowestSeconds: slowest,
                            maxHeight: _barHeight,
                            onTap: () => context.push(
                              Routes.pipelineRun(
                                AccountScope.of(context),
                                widget.args.org,
                                widget.args.project,
                                '${run.id}',
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  '${bars.length} runs · last '
                  '${relativeTime(bars.last.finishTime ?? bars.last.queueTime)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
    required this.onTap,
  });

  final BuildRun run;
  final int slowestSeconds;
  final double maxHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (_, color) = runGlyph(context, run.status, run.result);
    final seconds = run.duration?.inSeconds ?? 0;
    // A floor of a fifth: a five-second run is still a run, and a bar too
    // short to see reads as a gap in the history.
    final factor = slowestSeconds <= 0
        ? 0.2
        : (seconds / slowestSeconds).clamp(0.2, 1.0);
    return Tooltip(
      message:
          '${run.buildNumber} · '
          '${runResultLabel(run.status, run.result)}'
          '${run.duration == null ? '' : ' · ${formatDuration(run.duration)}'}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: maxHeight * factor,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
