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
import '../shared/account_scope.dart';
import 'widgets/pipeline_visuals.dart';

/// Milestone 3: recent runs (optionally one pipeline), the pipeline list
/// with a Run action, and pending environment approvals.
class PipelinesPage extends StatefulWidget {
  const PipelinesPage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  State<PipelinesPage> createState() => _PipelinesPageState();
}

class _PipelinesPageState extends State<PipelinesPage> {
  List<PipelineDefinition> _definitions = const [];
  List<BuildRun> _runs = const [];
  List<PipelineApproval> _approvals = const [];
  PipelineDefinition? _filter;
  DateTime? _shownAt;
  String? _error;
  String? _approvalsError;
  bool _loading = false;
  bool _acting = false;
  bool _loadedOnce = false;

  PipelineRepository get _repo => context.read<PipelineRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _approvalsError = null;
    });
    final repo = _repo;
    if (!_loadedOnce) {
      final results = await Future.wait([
        repo.cachedDefinitions(widget.org, widget.project),
        repo.cachedRuns(widget.org, widget.project),
      ]);
      if (!mounted) return;
      final defs = results[0] as CachedList<PipelineDefinition>?;
      final runs = results[1] as CachedList<BuildRun>?;
      if (defs != null || runs != null) {
        setState(() {
          _definitions = defs?.items ?? _definitions;
          _runs = _filter == null ? runs?.items ?? _runs : _runs;
          _shownAt = runs?.fetchedAt ?? defs?.fetchedAt;
        });
      }
    }
    try {
      final filter = _filter;
      final results = await Future.wait<Object>([
        repo.definitions(widget.org, widget.project),
        repo.runs(widget.org, widget.project, definitionId: filter?.id),
      ]);
      if (!mounted || filter != _filter) return;
      setState(() {
        _definitions = results[0] as List<PipelineDefinition>;
        _runs = results[1] as List<BuildRun>;
        _shownAt = DateTime.now();
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
      return;
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
    // Approvals need vso.build_execute-level access on some tenants; a
    // failure here only empties the tab.
    try {
      final approvals = await repo.approvals(widget.org, widget.project);
      if (mounted) setState(() => _approvals = approvals);
    } on AdoAuthException {
      rethrow;
    } on AdoException catch (e) {
      if (mounted) setState(() => _approvalsError = e.message);
    } catch (e) {
      // A payload the parser does not expect must not take the page down.
      if (mounted) {
        setState(() => _approvalsError = 'Could not read approvals: $e');
      }
    }
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
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _setFilter(PipelineDefinition? d) {
    if (d?.id == _filter?.id) return;
    setState(() {
      _filter = d;
      _runs = const [];
    });
    _load();
  }

  Future<void> _pickPipeline() async {
    final picked = await showModalBottomSheet<PipelineDefinition?>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive),
              title: const Text('All pipelines'),
              selected: _filter == null,
              onTap: () => Navigator.of(context).pop(null),
            ),
            for (final d in _definitions)
              ListTile(
                leading: _LatestGlyph(d.latestBuild),
                title: Text(d.name),
                subtitle: d.isRootFolder ? null : Text(d.folder),
                selected: d.id == _filter?.id,
                onTap: () => Navigator.of(context).pop(d),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    _setFilter(picked);
  }

  String _runPath(BuildRun run) =>
      '${orgRoute(context, widget.org)}/projects/'
      '${Uri.encodeComponent(widget.project)}/pipelines/runs/${run.id}';

  Future<void> _queue(PipelineDefinition d) async {
    final controller = TextEditingController(
      text: d.latestBuild?.sourceBranch ?? 'refs/heads/main',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Run ${d.name}?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Branch',
            helperText: 'refs/heads/… or a branch name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Run'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var branch = controller.text.trim();
    if (!branch.startsWith('refs/')) branch = 'refs/heads/$branch';
    BuildRun? queued;
    await _act(() async {
      queued = await _repo.queue(
        widget.org,
        widget.project,
        d.id,
        branch: branch,
      );
    });
    if (queued != null && mounted) context.push(_runPath(queued!));
  }

  Future<void> _resolve(PipelineApproval a, {required bool approve}) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          '${approve ? 'Approve' : 'Reject'} ${a.pipelineName ?? 'run'} '
          '${a.runName ?? ''}?',
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Comment (optional)'),
          minLines: 1,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final comment = controller.text.trim();
    await _act(
      () => _repo.resolveApproval(
        widget.org,
        widget.project,
        a.id,
        approve: approve,
        comment: comment.isEmpty ? null : comment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.project, overflow: TextOverflow.ellipsis),
              Text(
                'Pipelines',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          leading: IconButton(
            tooltip: 'Projects',
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                context.go('${orgRoute(context, widget.org)}/projects'),
          ),
          actions: [],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Runs'),
              Tab(
                text:
                    'Pipelines${_definitions.isEmpty ? '' : ' (${_definitions.length})'}',
              ),
              Tab(
                text:
                    'Approvals${_approvals.isEmpty ? '' : ' (${_approvals.length})'}',
              ),
            ],
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading || _acting) const LinearProgressIndicator(),
            if (_error != null)
              ListTile(
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: Text(_error!),
                subtitle: _shownAt == null || _runs.isEmpty
                    ? null
                    : Text('Showing runs from ${relativeTime(_shownAt)}.'),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _RunsTab(
                    runs: _runs,
                    filter: _filter,
                    loaded: _loadedOnce && !_loading,
                    onPickPipeline: _pickPipeline,
                    onClearFilter: () => _setFilter(null),
                    onRefresh: _load,
                    onTap: (run) => context.push(_runPath(run)),
                  ),
                  _DefinitionsTab(
                    definitions: _definitions,
                    loaded: _loadedOnce && !_loading,
                    busy: _acting,
                    onRefresh: _load,
                    onTap: (d) {
                      _setFilter(d);
                      DefaultTabController.of(context).animateTo(0);
                    },
                    onRun: _queue,
                    onOpenRun: (run) => context.push(_runPath(run)),
                  ),
                  _ApprovalsTab(
                    approvals: _approvals,
                    error: _approvalsError,
                    loaded: _loadedOnce && !_loading,
                    busy: _acting,
                    onRefresh: _load,
                    onApprove: (a) => _resolve(a, approve: true),
                    onReject: (a) => _resolve(a, approve: false),
                    onOpenRun: (a) => a.runId == null
                        ? null
                        : context.push(
                            '${orgRoute(context, widget.org)}/projects/'
                            '${Uri.encodeComponent(widget.project)}/pipelines/runs/${a.runId}',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestGlyph extends StatelessWidget {
  const _LatestGlyph(this.run);

  final BuildRun? run;

  @override
  Widget build(BuildContext context) {
    final r = run;
    if (r == null) {
      return Icon(
        Icons.radio_button_unchecked,
        color: Theme.of(context).colorScheme.outline,
      );
    }
    final (icon, color) = runGlyph(context, r.status, r.result);
    return Icon(icon, color: color);
  }
}

class _RunsTab extends StatelessWidget {
  const _RunsTab({
    required this.runs,
    required this.filter,
    required this.loaded,
    required this.onPickPipeline,
    required this.onClearFilter,
    required this.onRefresh,
    required this.onTap,
  });

  final List<BuildRun> runs;
  final PipelineDefinition? filter;
  final bool loaded;
  final VoidCallback onPickPipeline;
  final VoidCallback onClearFilter;
  final Future<void> Function() onRefresh;
  final ValueChanged<BuildRun> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ContentColumn(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: scrollEndPadding(context),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.xs,
              ),
              child: Wrap(
                spacing: Spacing.sm,
                children: [
                  InputChip(
                    avatar: const Icon(Icons.filter_list, size: 18),
                    label: Text(filter?.name ?? 'All pipelines'),
                    onPressed: onPickPipeline,
                    onDeleted: filter == null ? null : onClearFilter,
                  ),
                ],
              ),
            ),
            if (runs.isEmpty && loaded)
              Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      size: 40,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: Spacing.sm),
                    const Text('No runs yet.', textAlign: TextAlign.center),
                  ],
                ),
              ),
            for (final run in runs)
              RunTile(
                key: ValueKey(run.id),
                run: run,
                showPipeline: filter == null,
                onTap: () => onTap(run),
              ),
          ],
        ),
      ),
    );
  }
}

/// One run in a list: glyph, pipeline and number, branch, who and why,
/// age and duration.
class RunTile extends StatelessWidget {
  const RunTile({
    super.key,
    required this.run,
    required this.onTap,
    this.showPipeline = true,
  });

  final BuildRun run;
  final VoidCallback onTap;
  final bool showPipeline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = runGlyph(context, run.status, run.result);
    final who = run.requestedFor?.displayName ?? '';
    final why = reasonLabel(run.reason);
    final detail = [
      if (who.isNotEmpty) who,
      if (why.isNotEmpty) why,
      if (run.duration != null) formatDuration(run.duration),
    ].join(' · ');
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        showPipeline
            ? '${run.definitionName} · ${run.buildNumber}'
            : run.buildNumber,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((run.triggerMessage ?? '').isNotEmpty)
            Text(
              run.triggerMessage!.split('\n').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            '${run.branch}${detail.isEmpty ? '' : ' · $detail'}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: Text(
        relativeTime(run.queueTime),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: (run.triggerMessage ?? '').isNotEmpty,
      onTap: onTap,
    );
  }
}

class _DefinitionsTab extends StatelessWidget {
  const _DefinitionsTab({
    required this.definitions,
    required this.loaded,
    required this.busy,
    required this.onRefresh,
    required this.onTap,
    required this.onRun,
    required this.onOpenRun,
  });

  final List<PipelineDefinition> definitions;
  final bool loaded;
  final bool busy;
  final Future<void> Function() onRefresh;
  final ValueChanged<PipelineDefinition> onTap;
  final ValueChanged<PipelineDefinition> onRun;
  final ValueChanged<BuildRun> onOpenRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ContentColumn(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: scrollEndPadding(context),
          children: [
            if (definitions.isEmpty && loaded)
              Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Text(
                  'No pipelines in this project.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final d in definitions)
              ListTile(
                key: ValueKey(d.id),
                leading: _LatestGlyph(d.latestBuild),
                title: Text(
                  d.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  d.latestBuild == null
                      ? (d.isRootFolder ? 'No runs yet' : d.folder)
                      : '${d.latestBuild!.buildNumber} · ${runResultLabel(d.latestBuild!.status, d.latestBuild!.result)}'
                            ' · ${relativeTime(d.latestBuild!.queueTime)}'
                            '${d.queueStatus == 'enabled' || d.queueStatus == null ? '' : ' · ${d.queueStatus}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  tooltip: 'Run pipeline',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: busy || d.queueStatus == 'disabled'
                      ? null
                      : () => onRun(d),
                ),
                onTap: () => onTap(d),
              ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalsTab extends StatelessWidget {
  const _ApprovalsTab({
    required this.approvals,
    required this.error,
    required this.loaded,
    required this.busy,
    required this.onRefresh,
    required this.onApprove,
    required this.onReject,
    required this.onOpenRun,
  });

  final List<PipelineApproval> approvals;
  final String? error;
  final bool loaded;
  final bool busy;
  final Future<void> Function() onRefresh;
  final ValueChanged<PipelineApproval> onApprove;
  final ValueChanged<PipelineApproval> onReject;
  final void Function(PipelineApproval) onOpenRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ContentColumn(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.sm,
            Spacing.lg,
            Spacing.xxl,
          ),
          children: [
            if (error != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: Text(error!),
              ),
            if (approvals.isEmpty && loaded && error == null)
              Padding(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  children: [
                    Icon(
                      Icons.how_to_reg_outlined,
                      size: 40,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: Spacing.sm),
                    const Text(
                      'No pending approvals.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            for (final a in approvals)
              Padding(
                key: ValueKey(a.id),
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: Radii.card,
                  child: InkWell(
                    borderRadius: Radii.card,
                    onTap: a.runId == null ? null : () => onOpenRun(a),
                    child: Padding(
                      padding: Spacing.card,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${a.pipelineName ?? 'Pipeline'} · ${a.runName ?? ''}',
                            style: theme.textTheme.titleSmall,
                          ),
                          if ((a.instructions ?? '').isNotEmpty) ...[
                            const SizedBox(height: Spacing.xs),
                            Text(a.instructions!),
                          ],
                          const SizedBox(height: Spacing.sm),
                          Wrap(
                            spacing: Spacing.sm,
                            runSpacing: Spacing.xs,
                            children: [
                              for (final s in a.steps)
                                Chip(
                                  avatar: IdentityAvatar(
                                    identity: s.assignedApprover,
                                    radius: 10,
                                  ),
                                  label: Text(
                                    '${s.assignedApprover?.displayName ?? '?'}'
                                    '${s.status == 'pending' ? '' : ' · ${s.status}'}',
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                            ],
                          ),
                          const SizedBox(height: Spacing.sm),
                          Row(
                            children: [
                              Text(
                                'waiting ${relativeTime(a.createdOn)}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: busy ? null : () => onReject(a),
                                child: const Text('Reject'),
                              ),
                              const SizedBox(width: Spacing.xs),
                              FilledButton(
                                onPressed: busy ? null : () => onApprove(a),
                                child: const Text('Approve'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
