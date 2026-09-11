import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/pipeline.dart';
import '../../data/repositories/pipeline_repository.dart';
import '../../theme/theme.dart';
import '../work_items/widgets/work_item_visuals.dart';
import 'widgets/pipeline_visuals.dart';

/// One run: header, then the timeline as stages → jobs → tasks with issues
/// inline. Polls while the run is active. Cancel, rerun and retry stage
/// from the app bar; tasks open their log.
class PipelineRunPage extends StatefulWidget {
  const PipelineRunPage({
    super.key,
    required this.org,
    required this.project,
    required this.id,
  });

  final String org;
  final String project;
  final int id;

  @override
  State<PipelineRunPage> createState() => _PipelineRunPageState();
}

class _PipelineRunPageState extends State<PipelineRunPage> {
  static const _pollEvery = Duration(seconds: 8);

  BuildRun? _run;
  Timeline? _timeline;
  String? _error;
  bool _loading = false;
  bool _acting = false;
  Timer? _poll;

  PipelineRepository get _repo => context.read<PipelineRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<Object>([
        _repo.run(widget.org, widget.project, widget.id),
        _repo.timeline(widget.org, widget.project, widget.id),
      ]);
      if (!mounted) return;
      final run = results[0] as BuildRun;
      setState(() {
        _run = run;
        _timeline = results[1] as Timeline;
      });
      _schedulePoll(run);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted && !quiet) setState(() => _error = e.message);
    } finally {
      if (mounted && !quiet) setState(() => _loading = false);
    }
  }

  void _schedulePoll(BuildRun run) {
    _poll?.cancel();
    if (!run.isActive) return;
    _poll = Timer(_pollEvery, () {
      if (mounted) _load(quiet: true);
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      await action();
      await _load();
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _cancel() async {
    final run = _run;
    if (run == null) return;
    if (!await _confirm(
      'Cancel ${run.buildNumber}?',
      'The run stops after the current step.',
      'Cancel run',
    )) {
      return;
    }
    await _act(() => _repo.cancel(widget.org, widget.project, run.id));
  }

  Future<void> _rerun() async {
    final run = _run;
    if (run == null) return;
    if (!await _confirm(
      'Run ${run.definitionName} again?',
      'Queues a new run on ${run.branch}.',
      'Run',
    )) {
      return;
    }
    BuildRun? queued;
    await _act(() async {
      queued = await _repo.queue(
        widget.org,
        widget.project,
        run.definitionId,
        branch: run.sourceBranch,
      );
    });
    if (queued != null && mounted) {
      context.pushReplacement(
        '/orgs/${Uri.encodeComponent(widget.org)}/projects/'
        '${Uri.encodeComponent(widget.project)}/pipelines/runs/${queued!.id}',
      );
    }
  }

  Future<void> _retryStage(TimelineRecord stage) async {
    final run = _run;
    if (run == null) return;
    if (!await _confirm(
      'Retry stage ${stage.name}?',
      'Failed and canceled jobs of this stage run again.',
      'Retry',
    )) {
      return;
    }
    await _act(
      () => _repo.retryStage(
        widget.org,
        widget.project,
        run.id,
        stage.identifier,
      ),
    );
  }

  void _openLog(TimelineRecord record) {
    final logId = record.logId;
    if (logId == null) return;
    context.push(
      Uri(
        path:
            '/orgs/${Uri.encodeComponent(widget.org)}/projects/'
            '${Uri.encodeComponent(widget.project)}/pipelines/runs/${widget.id}/logs/$logId',
        queryParameters: {'name': record.name},
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final run = _run;
    final timeline = _timeline;
    final retryable = run != null && run.isCompleted && timeline != null
        ? timeline.stages
              .where((s) => s.isStage && (s.failed || s.result == 'canceled'))
              .toList()
        : const <TimelineRecord>[];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(run?.buildNumber ?? '#${widget.id}'),
            if (run != null)
              Text(
                run.definitionName,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (run != null && run.isActive)
            IconButton(
              tooltip: 'Cancel run',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _acting ? null : _cancel,
            ),
          if (run != null && run.isCompleted)
            PopupMenuButton<Object>(
              tooltip: 'More',
              enabled: !_acting,
              onSelected: (v) =>
                  v is TimelineRecord ? _retryStage(v) : _rerun(),
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'rerun', child: Text('Run again')),
                for (final s in retryable)
                  PopupMenuItem(value: s, child: Text('Retry stage ${s.name}')),
              ],
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading || _acting) const LinearProgressIndicator(),
          if (_error != null)
            ListTile(
              leading: Icon(Icons.error_outline, color: scheme.error),
              title: Text(_error!),
            ),
          Expanded(
            child: run == null || timeline == null
                ? (_loading
                      ? const Center(
                          child: CircularProgressIndicator.adaptive(),
                        )
                      : const SizedBox.shrink())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ContentColumn(
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: Spacing.xxl),
                        children: [
                          _RunHeader(run: run),
                          for (final stage in timeline.stages) ...[
                            _StageHeader(stage: stage),
                            if (timeline.isLeafSection(stage))
                              for (final t in timeline.tasksOf(stage))
                                _TaskRow(
                                  key: ValueKey(t.identifier),
                                  task: t,
                                  onTap: t.logId == null
                                      ? null
                                      : () => _openLog(t),
                                )
                            else
                              for (final job in timeline.jobsOf(stage))
                                _JobTile(
                                  key: ValueKey(
                                    '${job.identifier}#${job.attempt}',
                                  ),
                                  job: job,
                                  tasks: timeline.tasksOf(job),
                                  onOpenLog: _openLog,
                                  checkpointReason: timeline.checkpointReason(
                                    job,
                                  ),
                                ),
                          ],
                          if (timeline.stages.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(Spacing.xl),
                              child: Text(
                                run.isActive
                                    ? 'Waiting for an agent…'
                                    : 'No timeline for this run.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({required this.run});

  final BuildRun run;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = runGlyph(context, run.status, run.result);
    final facts = <(IconData, String)>[
      (Icons.call_split, run.branch),
      if (run.shortCommit.isNotEmpty) (Icons.commit, run.shortCommit),
      if (reasonLabel(run.reason).isNotEmpty)
        (Icons.bolt, reasonLabel(run.reason)),
      if (run.duration != null)
        (Icons.timer_outlined, formatDuration(run.duration)),
      if (run.queueTime != null)
        (Icons.schedule, 'queued ${relativeTime(run.queueTime)}'),
    ];
    return Padding(
      padding: Spacing.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  runResultLabel(run.status, run.result),
                  style: theme.textTheme.titleLarge?.copyWith(color: color),
                ),
              ),
              if (run.requestedFor != null)
                Chip(
                  avatar: IdentityAvatar(
                    identity: run.requestedFor,
                    radius: 10,
                  ),
                  label: Text(run.requestedFor!.displayName),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if ((run.triggerMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              run.triggerMessage!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          for (final m in run.validationMessages) ...[
            const SizedBox(height: Spacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 18, color: scheme.error),
                const SizedBox(width: Spacing.xs),
                Expanded(
                  child: SelectableText(
                    m,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.md,
            runSpacing: Spacing.xs,
            children: [
              for (final (i, text) in facts)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(i, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: Spacing.xs),
                    Text(
                      text,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({required this.stage});

  final TimelineRecord stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = recordGlyph(context, stage);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              stage.name,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            stage.isSkipped
                ? 'skipped'
                : [
                    if (stage.attempt > 1) 'attempt ${stage.attempt}',
                    if (stage.duration != null) formatDuration(stage.duration),
                  ].join(' · '),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({
    super.key,
    required this.job,
    required this.tasks,
    required this.onOpenLog,
    this.checkpointReason,
  });

  final TimelineRecord job;
  final List<TimelineRecord> tasks;
  final ValueChanged<TimelineRecord> onOpenLog;

  /// For checkpoint jobs: what they wait on.
  final String? checkpointReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = recordGlyph(context, job);
    final subtitle = [
      if (job.isInProgress && (job.currentOperation ?? '').isNotEmpty)
        job.currentOperation!,
      ?checkpointReason,
      if (job.errorCount > 0) '${job.errorCount} errors',
      if (job.warningCount > 0) '${job.warningCount} warnings',
      if ((job.workerName ?? '').isNotEmpty && job.isCompleted) job.workerName!,
    ].join(' · ');
    if (tasks.isEmpty) {
      return ListTile(
        leading: Icon(icon, color: color),
        title: Text(job.name),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: Text(
          job.isSkipped ? 'skipped' : formatDuration(job.duration),
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        onTap: job.logId == null ? null : () => onOpenLog(job),
      );
    }
    return ExpansionTile(
      key: PageStorageKey('job-${job.identifier}'),
      leading: Icon(icon, color: color),
      title: Text(job.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Text(
        job.isSkipped ? 'skipped' : formatDuration(job.duration),
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      initiallyExpanded: job.needsAttention,
      children: [
        for (final t in tasks)
          _TaskRow(
            key: ValueKey(t.identifier),
            task: t,
            onTap: t.logId == null ? null : () => onOpenLog(t),
          ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({super.key, required this.task, required this.onTap});

  final TimelineRecord task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final (icon, color) = recordGlyph(context, task);
    final issues = task.issues.take(3).toList();
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 40, right: Spacing.lg),
      leading: Icon(icon, size: 18, color: color),
      title: Text(task.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: issues.isEmpty
          ? (task.isInProgress && (task.currentOperation ?? '').isNotEmpty
                ? Text(task.currentOperation!)
                : null)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in issues)
                  Text(
                    i.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: i.isError ? colors.runFailed : colors.runPartial,
                    ),
                  ),
                if (task.issues.length > issues.length)
                  Text(
                    '+${task.issues.length - issues.length} more',
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
      trailing: Text(
        task.isSkipped ? 'skipped' : formatDuration(task.duration),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}
