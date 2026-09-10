import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../auth/auth_service.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../theme/theme.dart';
import 'widgets/rich_text_view.dart';
import 'widgets/work_item_actions.dart';
import 'widgets/work_item_visuals.dart';

/// One work item: header, key fields, long-text fields rendered as HTML or
/// Markdown, and the discussion from the preview Comments API. Lightweight
/// writes: post a comment, change state, assign to me / unassign.
class WorkItemDetailPage extends StatefulWidget {
  const WorkItemDetailPage({
    super.key,
    required this.org,
    required this.project,
    required this.id,
  });

  final String org;
  final String project;
  final int id;

  @override
  State<WorkItemDetailPage> createState() => _WorkItemDetailPageState();
}

class _WorkItemDetailPageState extends State<WorkItemDetailPage> {
  static const _longTextFields = <String, String>{
    'System.Description': 'Description',
    'Microsoft.VSTS.TCM.ReproSteps': 'Repro steps',
    'Microsoft.VSTS.Common.AcceptanceCriteria': 'Acceptance criteria',
    'Microsoft.VSTS.TCM.SystemInfo': 'System info',
    'Microsoft.VSTS.Common.Resolution': 'Resolution',
  };

  String? _error;
  bool _refreshing = false;
  bool _writing = false;
  List<WorkItemComment>? _comments;
  Map<String, String> _headers = const {};
  WorkItemVisuals _visuals = const WorkItemVisuals({});
  String? _me;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    final repo = context.read<WorkItemRepository>();
    final auth = context.read<AuthService>();
    try {
      final token = await auth.accessToken();
      _headers = {'Authorization': 'Bearer $token'};
      _me ??= (await auth.currentAccount())?.username;
      final types = await repo.types(widget.org, widget.project);
      _visuals = WorkItemVisuals({for (final t in types) t.name: t});
      await repo.refreshItem(widget.org, widget.project, widget.id);
      final comments = await repo.comments(
        widget.org,
        widget.project,
        widget.id,
      );
      if (mounted) setState(() => _comments = comments);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _describe(AdoException e) => e is AdoValidationException
      ? e.ruleErrors
            .map((r) => '${r.fieldReferenceName}: ${r.errorMessage}')
            .join('\n')
      : e.message;

  Future<void> _write(WorkItem item, Map<String, Object?> values) async {
    setState(() {
      _writing = true;
      _error = null;
    });
    final repo = context.read<WorkItemRepository>();
    try {
      await repo.updateFields(widget.org, widget.project, item, values);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoStaleRevisionException {
      if (mounted) {
        setState(
          () => _error =
              'This item changed elsewhere; it was reloaded, try again.',
        );
      }
      await _refresh();
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _changeState(WorkItem item) async {
    final state = await pickState(context, item: item, visuals: _visuals);
    if (state == null || state == item.state || !mounted) return;
    await _write(item, {'System.State': state});
  }

  Future<void> _changeAssignment(WorkItem item) async {
    final action = await pickAssignment(context, item: item, meLabel: _me);
    if (action == null || !mounted) return;
    await _write(item, {
      'System.AssignedTo': action == AssignAction.toMe ? _me : '',
    });
  }

  Future<bool> _postComment(String text) async {
    setState(() {
      _writing = true;
      _error = null;
    });
    final repo = context.read<WorkItemRepository>();
    try {
      await repo.addComment(widget.org, widget.project, widget.id, text);
      final comments = await repo.comments(
        widget.org,
        widget.project,
        widget.id,
      );
      if (mounted) setState(() => _comments = comments);
      return true;
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
      return false;
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
      return false;
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      bottomNavigationBar: CommentComposer(
        onSubmit: _postComment,
        busy: _writing,
      ),
      appBar: AppBar(
        title: Text('${widget.project} · #${widget.id}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: StreamBuilder<WorkItem?>(
        stream: context.read<WorkItemRepository>().watchItem(
          widget.org,
          widget.id,
        ),
        builder: (context, snapshot) {
          final item = snapshot.data;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ContentColumn(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: Spacing.xxl),
                children: [
                  if (_refreshing || _writing) const LinearProgressIndicator(),
                  if (_error != null)
                    ListTile(
                      leading: Icon(Icons.error_outline, color: scheme.error),
                      title: Text(_error!),
                    ),
                  if (item == null && !_refreshing && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(Spacing.xl),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    ),
                  if (item != null) ...[
                    _Header(
                      item: item,
                      visuals: _visuals,
                      onStateTap: _writing ? null : () => _changeState(item),
                      onAssignTap: _writing
                          ? null
                          : () => _changeAssignment(item),
                    ),
                    _Facts(item: item),
                    for (final entry in _longTextFields.entries)
                      if ((item.field<String>(entry.key) ?? '').trim().isNotEmpty)
                        _Section(
                          title: entry.value,
                          child: RichTextView(
                            content: item.field<String>(entry.key)!,
                            format: item.formatOf(entry.key),
                            headers: _headers,
                          ),
                        ),
                    _Section(
                      title: _comments == null
                          ? 'Discussion'
                          : 'Discussion (${_comments!.length})',
                      child: _Discussion(
                        comments: _comments,
                        headers: _headers,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.visuals,
    this.onStateTap,
    this.onAssignTap,
  });

  final WorkItem item;
  final WorkItemVisuals visuals;
  final VoidCallback? onStateTap;
  final VoidCallback? onAssignTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeColor = visuals.typeColor(context, item);
    return Padding(
      padding: Spacing.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(visuals.typeIcon(item), size: 18, color: typeColor),
              const SizedBox(width: Spacing.xs),
              Text(
                '${item.type} ${item.id}',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          SelectableText(item.title, style: theme.textTheme.titleLarge),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ActionChip(
                avatar: StateDot(color: visuals.stateColor(context, item)),
                label: Text(item.state),
                tooltip: 'Change state',
                visualDensity: VisualDensity.compact,
                onPressed: onStateTap,
              ),
              ActionChip(
                avatar: IdentityAvatar(identity: item.assignedTo, radius: 10),
                label: Text(item.assignedTo?.displayName ?? 'Unassigned'),
                tooltip: 'Change assignee',
                visualDensity: VisualDensity.compact,
                onPressed: onAssignTap,
              ),
              if (item.priority != null)
                Chip(
                  label: Text('Priority ${item.priority}'),
                  visualDensity: VisualDensity.compact,
                ),
              for (final tag in item.tags)
                Chip(
                  avatar: const Icon(Icons.label_outline, size: 16),
                  label: Text(tag),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.item});

  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = <(String, String)>[
      ('Area', item.areaPath ?? ''),
      ('Iteration', item.iterationPath ?? ''),
      if (item.reason != null) ('Reason', item.reason!),
      (
        'Created',
        '${relativeTime(item.createdDate)}'
            '${item.createdBy == null ? '' : ' by ${item.createdBy!.displayName}'}',
      ),
      (
        'Changed',
        '${relativeTime(item.changedDate)}'
            '${item.changedBy == null ? '' : ' by ${item.changedBy!.displayName}'}',
      ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Column(
        children: [
          for (final (label, value) in rows)
            if (value.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 88,
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(value, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.xl,
        Spacing.lg,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: Spacing.sm),
          child,
        ],
      ),
    );
  }
}

class _Discussion extends StatelessWidget {
  const _Discussion({required this.comments, required this.headers});

  final List<WorkItemComment>? comments;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final list = comments;
    if (list == null) {
      return Text(
        'Loading comments…',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    if (list.isEmpty) {
      return Text(
        'No comments yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in list)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IdentityAvatar(identity: c.createdBy, radius: 16),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.createdBy.displayName,
                              style: theme.textTheme.labelLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            relativeTime(c.createdDate),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.xs),
                      RichTextView(content: c.renderedText, headers: headers),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
