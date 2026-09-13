import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/pr_check.dart';
import '../../data/models/pull_request.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/pr_diff_source.dart';
import '../../data/repositories/pull_request_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../theme/theme.dart';
import '../work_items/widgets/work_item_actions.dart' show CommentComposer;
import '../work_items/widgets/work_item_visuals.dart';
import '../shared/account_scope.dart';
import '../shared/anchor_highlight.dart';
import 'widgets/pr_visuals.dart';
import 'widgets/thread_card.dart';

/// One pull request: overview (description, checks, reviewers, linked work
/// items), changed files of a chosen iteration, and the conversation with
/// replies and thread status. Vote, complete and abandon from the app bar;
/// new conversation comments from the composer.
class PullRequestDetailPage extends StatefulWidget {
  const PullRequestDetailPage({
    super.key,
    required this.org,
    required this.id,
    this.initialTab,
    this.initialThreadId,
  });

  final String org;
  final int id;

  /// Which tab a pushed notification wants (`?tab=comments|files`,
  /// research/14 §4.2). Anything else, and the page opens on Overview
  /// as it always has.
  final String? initialTab;

  /// The thread a pushed comment notification names (`?thread={id}`). It
  /// selects Comments; a conversation thread is scrolled to and tinted, a
  /// file thread opens the diff at that file the way tapping its header
  /// does, so Back returns to this page.
  final int? initialThreadId;

  @override
  State<PullRequestDetailPage> createState() => _PullRequestDetailPageState();
}

class _PullRequestDetailPageState extends State<PullRequestDetailPage>
    with SingleTickerProviderStateMixin {
  /// Overview, Files, Comments. Owned here rather than through a
  /// `DefaultTabController` so the scaffold rebuilds when the tab changes
  /// and can take its composer away; see [_commentsTab].
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: _initialIndex)
        ..addListener(() {
          if (!mounted) return;
          setState(() {});
        });

  /// The tab a deep link asks for (research/14 §4.2); a thread anchor
  /// implies Comments, because that is where the thread lives.
  int get _initialIndex => switch (widget.initialTab) {
    'files' => _filesTab,
    'comments' => _commentsTab,
    _ => widget.initialThreadId != null ? _commentsTab : 0,
  };

  /// The Comments tab's index. The composer posts a conversation comment,
  /// which means nothing under Overview and is the wrong gesture under
  /// Files, where a comment belongs to a line and is written from the
  /// diff's gutter (iPhone walkthrough, finding j).
  static const int _commentsTab = 2;
  static const int _filesTab = 1;

  /// One key per thread card, and the tint the anchored one wears for two
  /// seconds (research/14 §4.2).
  final Map<int, GlobalKey> _threadKeys = {};
  final _threadScroll = ScrollController();
  int? _highlighted;
  Timer? _highlightTimer;

  /// The anchor is honoured once: a pull to refresh, or coming back from
  /// the file diff, must not scroll the reader away again.
  int? _anchoredFor;

  PullRequest? _pr;
  String? _me;
  List<WorkItem> _workItems = const [];
  List<PrCheck> _checks = const [];
  List<PrIteration> _iterations = const [];
  List<PrFileChange> _changes = const [];
  int? _iteration;
  List<PrThread> _conversation = const [];
  PrConversationFilter _threadFilter = PrConversationFilter.all;
  String? _error;
  bool _loading = false;
  bool _changesLoading = false;
  bool _acting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(PullRequestDetailPage old) {
    super.didUpdateWidget(old);
    if (old.initialThreadId != widget.initialThreadId) {
      _anchoredFor = null;
      _anchorThread();
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _threadScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// Lands a pushed comment notification on its thread (research/14 §4.2).
  ///
  /// A conversation thread is scrolled to and tinted. A file thread opens
  /// the file diff exactly as tapping the thread's header does, but only
  /// after the Comments tab has been shown, so Back comes back here. A
  /// thread that is no longer in the list leaves the tab as it is, with no
  /// error.
  void _anchorThread() {
    final id = widget.initialThreadId;
    if (id == null || _anchoredFor == id) return;
    final thread = _conversation.where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    _anchoredFor = id;
    // A filter hiding the thread would make the anchor land on nothing.
    if (PullRequestRepository.filterConversation([
      thread,
    ], _threadFilter).isEmpty) {
      setState(() => _threadFilter = PrConversationFilter.all);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (thread.isFileThread) {
        await _openThread(thread);
        return;
      }
      final key = _threadKeys.putIfAbsent(id, GlobalKey.new);
      final found = await revealAnchor(target: key, scroller: _threadScroll);
      if (!found || !mounted) return;
      setState(() => _highlighted = id);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(kAnchorHighlight, () {
        if (mounted) setState(() => _highlighted = null);
      });
    });
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
        repo.checks(widget.org, pr),
      ]);
      final ids = results[0] as List<int>;
      final iterations = results[1] as List<PrIteration>;
      final raw = results[2] as List<Map<String, dynamic>>;
      final checks = results[3] as List<PrCheck>;
      // Keep the chosen iteration across reloads when it still exists.
      final selected = iterations.any((i) => i.id == _iteration)
          ? _iteration
          : (iterations.isEmpty ? null : iterations.last.id);
      final changes = selected == null
          ? const <PrFileChange>[]
          : await source.changes(ref, selected);
      final linked = ids.isEmpty
          ? const <WorkItem>[]
          : await workItems.batch(widget.org, pr.projectId, ids);
      if (!mounted) return;
      setState(() {
        _pr = pr;
        _iterations = iterations;
        _iteration = selected;
        _changes = changes;
        _checks = checks;
        _workItems = linked;
        _conversation = PullRequestRepository.conversation(raw);
      });
      _anchorThread();
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectIteration(int id) async {
    final pr = _pr;
    if (pr == null || id == _iteration) return;
    setState(() {
      _iteration = id;
      _changesLoading = true;
    });
    final source = PrDiffSource(context.read<AdoClient>());
    final ref = context.read<PullRequestRepository>().ref(widget.org, pr);
    try {
      final changes = await source.changes(ref, id);
      if (mounted) setState(() => _changes = changes);
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
      if (mounted) setState(() => _changesLoading = false);
    }
  }

  /// Runs a write, then reloads. Completing a pull request is asynchronous
  /// on the service (the merge is queued), so [settle] keeps reloading for
  /// a few seconds until the status leaves `active`.
  /// Runs a write, reloads, and reports whether the write itself went
  /// through, so a caller chaining two writes can stop after the first.
  Future<bool> _act(
    Future<void> Function() action, {
    bool settle = false,
  }) async {
    setState(() {
      _acting = true;
      _error = null;
    });
    var ok = false;
    try {
      await action();
      ok = true;
      await _load();
      for (var i = 0; settle && i < 6 && _pr?.isActive == true; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return ok;
        await _load();
      }
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
    return ok;
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
      settle: true,
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
    await _act(() => repo.setStatus(widget.org, pr, 'abandoned'), settle: true);
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

  Future<bool> _reply(PrThread thread, String text) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _act(() => repo.reply(widget.org, pr, thread.id, text));
  }

  Future<bool> _setThreadStatus(PrThread thread, String status) async {
    final pr = _pr;
    if (pr == null) return false;
    final repo = context.read<PullRequestRepository>();
    return _act(() => repo.setThreadStatus(widget.org, pr, thread.id, status));
  }

  Future<void> _openFile(PrFileChange change) => _openDiff(change.path);

  /// Opens the file a thread is anchored to, at the iteration being
  /// viewed, so the comment can be read in context.
  Future<void> _openThread(PrThread thread) async {
    final path = thread.filePath;
    if (path == null) return;
    await _openDiff(path);
  }

  /// The diff is a route pushed over this page, and threads are written
  /// there too (a reply, a resolve, a new anchored thread). This page kept
  /// the threads it read before that, so the Comments tab showed the state
  /// from before the write until someone pulled (iPad walkthrough, defect
  /// 6). Re-read them when the diff comes back.
  Future<void> _openDiff(String path) async {
    final it = _iteration;
    if (it == null) return;
    await context.push(
      Uri(
        path:
            '${orgRoute(context, widget.org)}/pull-requests/${widget.id}/diff',
        queryParameters: {'path': path, 'iteration': '$it'},
      ).toString(),
    );
    if (!mounted) return;
    await _reloadThreads();
  }

  /// Just the conversation, without the file list and the checks: what a
  /// write on another page can have changed.
  Future<void> _reloadThreads() async {
    final pr = _pr;
    if (pr == null) return;
    final repo = context.read<PullRequestRepository>();
    setState(() => _loading = true);
    try {
      final raw = await repo.rawThreads(widget.org, pr);
      if (!mounted) return;
      setState(() => _conversation = PullRequestRepository.conversation(raw));
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
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openWorkItem(WorkItem item) {
    final pr = _pr;
    if (pr == null) return;
    context.push(
      '${orgRoute(context, widget.org)}/projects/'
      '${Uri.encodeComponent(pr.projectName)}/work-items/${item.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pr = _pr;
    final myVote = pr?.reviewer(_me)?.vote ?? PrVote.none;
    final scrollingTabs = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    return Scaffold(
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
                offset: kTrailingMenuOffset,
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
                offset: kTrailingMenuOffset,
                enabled: !_acting,
                onSelected: (v) => v == 'complete' ? _complete() : _abandon(),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'complete', child: Text('Complete…')),
                  PopupMenuItem(value: 'abandon', child: Text('Abandon…')),
                ],
              ),
          ],
          bottom: TabBar(
            controller: _tabs,
            // Three filled thirds clip "Comments (3)" at accessibility
            // text sizes (iPhone walkthrough, defect 10); let the strip
            // scroll instead so every label stays whole and reachable.
            isScrollable: scrollingTabs,
            tabAlignment: scrollingTabs ? TabAlignment.start : null,
            tabs: [
              const Tab(text: 'Overview'),
              Tab(
                text: 'Files${_changes.isEmpty ? '' : ' (${_changes.length})'}',
              ),
              Tab(
                text:
                    'Comments${_conversation.isEmpty ? '' : ' (${_conversation.length})'}',
              ),
            ],
          ),
        ),
        bottomNavigationBar:
            pr == null || !pr.isActive || _tabs.index != _commentsTab
            ? null
            : CommentComposer(onSubmit: _comment, busy: _acting),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading || _acting || _changesLoading)
              const LinearProgressIndicator(),
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
                      controller: _tabs,
                      children: [
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _Overview(
                            pr: pr,
                            checks: _checks,
                            workItems: _workItems,
                            onWorkItemTap: _openWorkItem,
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _Files(
                            changes: _changes,
                            iterations: _iterations,
                            iteration: _iteration,
                            onSelectIteration: _selectIteration,
                            onTap: _openFile,
                          ),
                        ),
                        RefreshIndicator(
                          onRefresh: _load,
                          child: _Conversation(
                            threads: _conversation,
                            keyFor: (id) =>
                                _threadKeys.putIfAbsent(id, GlobalKey.new),
                            scroller: _threadScroll,
                            highlighted: _highlighted,
                            filter: _threadFilter,
                            onFilter: (f) => setState(() => _threadFilter = f),
                            canAct: pr.isActive,
                            busy: _acting,
                            onReply: _reply,
                            onSetStatus: _setThreadStatus,
                            onOpenThread: _openThread,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.pr,
    required this.checks,
    required this.workItems,
    required this.onWorkItemTap,
  });

  final PullRequest pr;
  final List<PrCheck> checks;
  final List<WorkItem> workItems;
  final ValueChanged<WorkItem> onWorkItemTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final merge = mergeStatusLabel(context, pr.mergeStatus);
    final blocking = checks
        .where((c) => c.isBlocking && c.state == PrCheckState.failed)
        .length;
    return ContentColumn(
      child: ListView(
        // Short pages must still answer a pull-to-refresh.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: scrollEndPadding(context),
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
          // From tablet width the description sits beside the checks,
          // reviewers and linked work items.
          SideBySide(
            startFlex: 3,
            endFlex: 2,
            start: [
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
            ],
            end: [
              if (merge != null || checks.isNotEmpty) ...[
                _SectionTitle(
                  'Checks${blocking > 0 ? ' · $blocking blocking' : ''}',
                ),
                if (merge != null)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      pr.mergeStatus == 'succeeded'
                          ? Icons.check_circle
                          : Icons.warning_amber,
                      color: merge.$2,
                    ),
                    title: Text(merge.$1),
                  ),
                for (final c in checks)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      checkIcon(c.state, isBlocking: c.isBlocking),
                      color: checkColor(
                        context,
                        c.state,
                        isBlocking: c.isBlocking,
                      ),
                    ),
                    title: Text(c.name),
                    subtitle: c.detail == null || c.detail!.isEmpty
                        ? null
                        : Text(c.detail!),
                    // "optional" is said out loud on a failing policy that
                    // does not block: the absence of "required" was the
                    // only signal, and it was easy to miss next to a red
                    // row (finding k).
                    trailing: Text(
                      c.isBlocking
                          ? 'required'
                          : (c.state == PrCheckState.failed ? 'optional' : ''),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
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

/// "Iteration 3 of 4 · push · 2 h ago" with a menu of all iterations.
class IterationPicker extends StatelessWidget {
  const IterationPicker({
    super.key,
    required this.iterations,
    required this.selected,
    required this.onSelect,
    this.dense = false,
  });

  final List<PrIteration> iterations;
  final int? selected;
  final ValueChanged<int> onSelect;
  final bool dense;

  static String describe(PrIteration it) => [
    if (it.reason != null && it.reason!.isNotEmpty) it.reason!,
    if (it.createdDate != null) relativeTime(it.createdDate),
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = iterations.cast<PrIteration?>().firstWhere(
      (i) => i?.id == selected,
      orElse: () => null,
    );
    final title = current == null
        ? 'Iterations'
        : 'Iteration ${current.id} of ${iterations.length}';
    return PopupMenuButton<int>(
      tooltip: 'Choose iteration',
      enabled: iterations.length > 1,
      onSelected: onSelect,
      itemBuilder: (context) => [
        for (final it in iterations.reversed)
          PopupMenuItem(
            value: it.id,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: it.id == selected
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Iteration ${it.id}'),
                      Text(
                        [
                          if (it.description.isNotEmpty) it.description,
                          describe(it),
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: dense
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current == null ? '' : 'it. ${current.id}',
                    style: theme.textTheme.labelLarge,
                  ),
                  if (iterations.length > 1)
                    const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            )
          : ListTile(
              leading: const Icon(Icons.history),
              title: Text(title),
              subtitle: current == null
                  ? null
                  : Text(
                      [
                        if (current.description.isNotEmpty) current.description,
                        describe(current),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              trailing: iterations.length > 1
                  ? const Icon(Icons.arrow_drop_down)
                  : null,
            ),
    );
  }
}

class _Files extends StatelessWidget {
  const _Files({
    required this.changes,
    required this.iterations,
    required this.iteration,
    required this.onSelectIteration,
    required this.onTap,
  });

  final List<PrFileChange> changes;
  final List<PrIteration> iterations;
  final int? iteration;
  final ValueChanged<int> onSelectIteration;
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
    return ContentColumn(
      child: ListView(
        // Short pages must still answer a pull-to-refresh.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: scrollEndPadding(context),
        children: [
          if (iterations.isNotEmpty)
            IterationPicker(
              iterations: iterations,
              selected: iteration,
              onSelect: onSelectIteration,
            ),
          if (iterations.isNotEmpty) const Divider(height: 1),
          if (changes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(Spacing.xl),
              child: Text(
                'No changed files.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
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
  const _Conversation({
    required this.threads,
    required this.keyFor,
    required this.scroller,
    required this.highlighted,
    required this.filter,
    required this.onFilter,
    required this.canAct,
    required this.busy,
    required this.onReply,
    required this.onSetStatus,
    required this.onOpenThread,
  });

  final List<PrThread> threads;

  /// One stable key per thread id, so `?thread={id}` has something to
  /// scroll to (research/14 §4.2).
  final GlobalKey Function(int id) keyFor;

  /// The thread list's own controller, so the anchor can page down to a
  /// thread that has not been built yet.
  final ScrollController scroller;

  /// The thread a deep link landed on; tinted for two seconds.
  final int? highlighted;

  final PrConversationFilter filter;
  final ValueChanged<PrConversationFilter> onFilter;
  final bool canAct;
  final bool busy;
  final Future<bool> Function(PrThread thread, String text) onReply;
  final Future<bool> Function(PrThread thread, String status) onSetStatus;
  final ValueChanged<PrThread> onOpenThread;

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
    final shown = PullRequestRepository.filterConversation(threads, filter);
    final counts = {
      for (final f in PrConversationFilter.values)
        f: PullRequestRepository.filterConversation(threads, f).length,
    };
    return ContentColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.sm,
              Spacing.lg,
              0,
            ),
            child: Row(
              children: [
                for (final f in PrConversationFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: ChoiceChip(
                      label: Text('${f.label} (${counts[f]})'),
                      selected: filter == f,
                      onSelected: (_) => onFilter(f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      switch (filter) {
                        PrConversationFilter.active =>
                          'Every comment has been resolved.',
                        PrConversationFilter.resolved =>
                          'No comment has been resolved yet.',
                        PrConversationFilter.all => 'No comments yet.',
                      },
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    controller: scroller,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.sm,
                      Spacing.lg,
                      Spacing.xxl,
                    ),
                    children: [
                      for (final t in shown)
                        Padding(
                          key: keyFor(t.id),
                          padding: const EdgeInsets.only(bottom: Spacing.md),
                          child: AnchorHighlight(
                            active: t.id == highlighted,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (t.isFileThread)
                                  _ThreadFileHeader(
                                    thread: t,
                                    onTap: () => onOpenThread(t),
                                  ),
                                ThreadCard(
                                  thread: t,
                                  canAct: canAct,
                                  busy: busy,
                                  onReply: (text) => onReply(t, text),
                                  onSetStatus: (status) =>
                                      onSetStatus(t, status),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Above a file-anchored thread: which file and line it hangs on, tapping
/// opens the diff there.
class _ThreadFileHeader extends StatelessWidget {
  const _ThreadFileHeader({required this.thread, required this.onTap});

  final PrThread thread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = thread.filePath ?? '';
    final name = path.substring(path.lastIndexOf('/') + 1);
    final line = thread.rightLine ?? thread.leftLine;
    return InkWell(
      onTap: onTap,
      borderRadius: Radii.card,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.sm,
          Spacing.xs,
          Spacing.sm,
          Spacing.xs,
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 14,
              color: scheme.primary,
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                line == null ? name : '$name:$line',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
