import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/pull_request.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/pr_diff_source.dart';
import '../../data/repositories/pull_request_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../theme/theme.dart';
import '../work_items/widgets/work_item_actions.dart' show CommentComposer;
import '../work_items/widgets/work_item_visuals.dart';
import 'widgets/pr_visuals.dart';

/// One pull request: overview (description, reviewers, linked work items),
/// changed files of the latest iteration, and the conversation. Vote,
/// complete and abandon from the app bar; new conversation comments from
/// the composer.
class PullRequestDetailPage extends StatefulWidget {
  const PullRequestDetailPage({super.key, required this.org, required this.id});

  final String org;
  final int id;

  @override
  State<PullRequestDetailPage> createState() => _PullRequestDetailPageState();
}

class _PullRequestDetailPageState extends State<PullRequestDetailPage> {
  PullRequest? _pr;
  String? _me;
  List<WorkItem> _workItems = const [];
  List<PrFileChange> _changes = const [];
  int? _iteration;
  List<PrThread> _conversation = const [];
  String? _error;
  bool _loading = false;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = context.read<PullRequestRepository>();
    final workItems = context.read<WorkItemRepository>();
    final source = PrDiffSource(context.read<AdoClient>());
    try {
      final pr = await repo.get(widget.org, widget.id);
      _me = await repo.meId(widget.org);
      final ref = repo.ref(widget.org, pr);
      final results = await Future.wait<Object>([
        repo.workItemIds(widget.org, pr),
        source.iterations(ref),
        repo.rawThreads(widget.org, pr),
      ]);
      final ids = results[0] as List<int>;
      final iterations = results[1] as List<PrIteration>;
      final raw = results[2] as List<Map<String, dynamic>>;
      final last = iterations.isEmpty ? null : iterations.last.id;
      final changes = last == null
          ? const <PrFileChange>[]
          : await source.changes(ref, last);
      final linked = ids.isEmpty
          ? const <WorkItem>[]
          : await workItems.batch(widget.org, pr.projectId, ids);
      if (!mounted) return;
      setState(() {
        _pr = pr;
        _iteration = last;
        _changes = changes;
        _workItems = linked;
        _conversation = PullRequestRepository.conversation(raw);
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
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
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      debugPrint('PR action failed: $e');
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _vote(PrVote vote) async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() => repo.vote(widget.org, pr, vote));
  }

  Future<void> _complete() async {
    final pr = _pr;
    if (pr == null) return;
    var deleteSource = true;
    var squash = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Complete !${pr.id}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Merge ${pr.sourceBranch} into ${pr.targetBranch}.'),
              const SizedBox(height: Spacing.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Delete source branch'),
                value: deleteSource,
                onChanged: (v) => setState(() => deleteSource = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Squash commits'),
                value: squash,
                onChanged: (v) => setState(() => squash = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Complete'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<PullRequestRepository>();
    await _act(
      () => repo.complete(
        widget.org,
        pr,
        deleteSourceBranch: deleteSource,
        squash: squash,
      ),
    );
  }

  Future<void> _abandon() async {
    final pr = _pr;
    if (pr == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Abandon !${pr.id}?'),
        content: const Text('The pull request can be reactivated later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abandon'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = context.read<PullRequestRepository>();
    await _act(() => repo.setStatus(widget.org, pr, 'abandoned'));
  }

  Future<bool> _comment(String text) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    var ok = false;
    await _act(() async {
      await repo.addThread(widget.org, pr, content: text);
      ok = true;
    });
    return ok;
  }

  void _openFile(PrFileChange change) {
    final it = _iteration;
    if (it == null) return;
    context.push(
      Uri(
        path:
            '/orgs/${Uri.encodeComponent(widget.org)}/pull-requests/${widget.id}/diff',
        queryParameters: {'path': change.path, 'iteration': '$it'},
      ).toString(),
    );
  }

  void _openWorkItem(WorkItem item) {
    final pr = _pr;
    if (pr == null) return;
    context.push(
      '/orgs/${Uri.encodeComponent(widget.org)}/projects/'
      '${Uri.encodeComponent(pr.projectName)}/work-items/${item.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pr = _pr;
    final myVote = pr?.reviewer(_me)?.vote ?? PrVote.none;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('!${widget.id}'),
              if (pr != null)
                Text(
                  '${pr.projectName} / ${pr.repositoryName}',
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
            if (pr != null && pr.isActive)
              PopupMenuButton<PrVote>(
                tooltip: 'Vote',
                enabled: !_acting,
                icon: Icon(voteIcon(myVote), color: voteColor(context, myVote)),
                onSelected: _vote,
                itemBuilder: (context) => [
                  for (final v in PrVote.values)
                    PopupMenuItem(
                      value: v,
                      child: Row(
                        children: [
                          Icon(voteIcon(v), color: voteColor(context, v)),
                          const SizedBox(width: Spacing.md),
                          Expanded(child: Text(v.label)),
                          if (v == myVote) const Icon(Icons.check, size: 18),
                        ],
                      ),
                    ),
                ],
              ),
            if (pr != null && pr.isActive)
              PopupMenuButton<String>(
                tooltip: 'More',
                enabled: !_acting,
                onSelected: (v) => v == 'complete' ? _complete() : _abandon(),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'complete', child: Text('Complete…')),
                  PopupMenuItem(value: 'abandon', child: Text('Abandon…')),
                ],
              ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
          ],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Overview'),
              Tab(
                text: 'Files${_changes.isEmpty ? '' : ' (${_changes.length})'}',
              ),
              Tab(
                text:
                    'Conversation${_conversation.isEmpty ? '' : ' (${_conversation.length})'}',
              ),
            ],
          ),
        ),
        bottomNavigationBar: pr == null || !pr.isActive
            ? null
            : CommentComposer(onSubmit: _comment, busy: _acting),
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
              child: pr == null
                  ? (_loading
                        ? const Center(
                            child: CircularProgressIndicator.adaptive(),
                          )
                        : const SizedBox.shrink())
                  : TabBarView(
                      children: [
                        _Overview(
                          pr: pr,
                          workItems: _workItems,
                          onWorkItemTap: _openWorkItem,
                        ),
                        _Files(changes: _changes, onTap: _openFile),
                        _Conversation(threads: _conversation),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.pr,
    required this.workItems,
    required this.onWorkItemTap,
  });

  final PullRequest pr;
  final List<WorkItem> workItems;
  final ValueChanged<WorkItem> onWorkItemTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ContentColumn(
      child: ListView(
        padding: const EdgeInsets.only(bottom: Spacing.xxl),
        children: [
          Padding(
            padding: Spacing.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(pr.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: Spacing.md),
                Wrap(
                  spacing: Spacing.sm,
                  runSpacing: Spacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: StateDot(
                        color: prStatusColor(context, pr.status),
                      ),
                      label: Text(pr.status),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (pr.isDraft) const DraftChip(),
                    Chip(
                      avatar: IdentityAvatar(
                        identity: pr.createdBy,
                        radius: 10,
                      ),
                      label: Text(pr.createdBy.displayName),
                      visualDensity: VisualDensity.compact,
                    ),
                    Chip(
                      avatar: const Icon(Icons.schedule, size: 16),
                      label: Text(relativeTime(pr.creationDate)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.md),
                Row(
                  children: [
                    Icon(
                      Icons.call_merge,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Spacing.xs),
                    Expanded(
                      child: Text(
                        '${pr.sourceBranch} → ${pr.targetBranch}',
                        style: BoardhopTheme.codeStyle(context),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _SectionTitle('Description'),
          Padding(
            padding: Spacing.pageHorizontal,
            child: (pr.description ?? '').trim().isEmpty
                ? Text(
                    'No description.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : MarkdownBody(data: pr.description!, selectable: true),
          ),
          _SectionTitle('Reviewers (${pr.reviewers.length})'),
          if (pr.reviewers.isEmpty)
            Padding(
              padding: Spacing.pageHorizontal,
              child: Text(
                'No reviewers yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final r in pr.reviewers)
            ListTile(
              dense: true,
              leading: IdentityAvatar(identity: r.identity, radius: 14),
              title: Text(r.displayName),
              subtitle: Text(
                '${r.vote.label}${r.isRequired ? ' · required' : ''}'
                '${r.isContainer ? ' · group' : ''}',
              ),
              trailing: Icon(
                voteIcon(r.vote),
                color: voteColor(context, r.vote),
              ),
            ),
          _SectionTitle('Linked work items (${workItems.length})'),
          if (workItems.isEmpty)
            Padding(
              padding: Spacing.pageHorizontal,
              child: Text(
                'None.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final w in workItems)
            ListTile(
              dense: true,
              leading: const Icon(Icons.link),
              title: Text(
                w.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('${w.type} ${w.id} · ${w.state}'),
              onTap: () => onWorkItemTap(w),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.lg,
      Spacing.lg,
      Spacing.sm,
    ),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Files extends StatelessWidget {
  const _Files({required this.changes, required this.onTap});

  final List<PrFileChange> changes;
  final ValueChanged<PrFileChange> onTap;

  static IconData _icon(String changeType) => switch (changeType) {
    'add' => Icons.add_circle_outline,
    'delete' => Icons.remove_circle_outline,
    'rename' || 'rename, edit' => Icons.drive_file_rename_outline,
    _ => Icons.edit_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (changes.isEmpty) {
      return Center(
        child: Text(
          'No changed files.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ContentColumn(
      child: ListView(
        padding: const EdgeInsets.only(bottom: Spacing.xxl),
        children: [
          for (final c in changes)
            ListTile(
              leading: Icon(_icon(c.changeType)),
              title: Text(
                c.path.substring(c.path.lastIndexOf('/') + 1),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                c.path,
                style: BoardhopTheme.codeStyle(context).copyWith(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                c.changeType,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              onTap: () => onTap(c),
            ),
        ],
      ),
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.threads});

  final List<PrThread> threads;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (threads.isEmpty) {
      return Center(
        child: Text(
          'No comments yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ContentColumn(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          Spacing.xxl,
        ),
        children: [
          for (final t in threads)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.md),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: Radii.card,
                child: Padding(
                  padding: Spacing.card,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final c in t.comments) ...[
                        Text(c.author, style: theme.textTheme.labelLarge),
                        const SizedBox(height: Spacing.xs),
                        MarkdownBody(data: c.content, selectable: true),
                        const SizedBox(height: Spacing.sm),
                      ],
                      Text(
                        t.status,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
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
