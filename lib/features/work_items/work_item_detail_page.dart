import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../auth/auth_service.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/work_item.dart';
import '../../data/models/work_item_form.dart';
import '../../data/repositories/work_item_form_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../data/write_queue.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'form/new_work_item_button.dart';
import 'form/type_chooser.dart';
import 'form/work_item_form_page.dart';
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
    this.embedded = false,
  });

  final String org;
  final String project;
  final int id;

  /// True inside the tablet list+detail pane: no back button, the pane's
  /// own list stays visible.
  final bool embedded;

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

  /// The type's form spec, for the state sheet's Reason rules. Cached for a
  /// day by the repository, and not worth an error when it fails: the sheet
  /// falls back to the transitions the type list already carries (spike
  /// s32).
  FormSpec? _spec;

  /// The item's linked work items, resolved through the batch read: the
  /// parent and the children the compact Links row lists (phase 5 builds
  /// the full Links page).
  WorkItem? _parent;
  List<WorkItem> _children = const [];

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
    final accountId = AccountScope.of(context);
    try {
      final token = await auth.accessToken(accountId: accountId);
      _headers = {'Authorization': 'Bearer $token'};
      _me ??= auth.accountById(accountId)?.username;
      final types = await repo.types(widget.org, widget.project);
      _visuals = WorkItemVisuals({for (final t in types) t.name: t});
      final item = await repo.refreshItem(
        widget.org,
        widget.project,
        widget.id,
      );
      _spec = await _formSpec(item);
      await _loadLinks(repo, item);
      final comments = await repo.comments(
        widget.org,
        widget.project,
        widget.id,
      );
      if (mounted) setState(() => _comments = comments);
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
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// Resolves the parent and the children of [item] in one batch read.
  /// Links are a nicety: a refusal leaves the row off rather than failing
  /// the page.
  Future<void> _loadLinks(WorkItemRepository repo, WorkItem item) async {
    final parentId = item.parentRelation?.targetId;
    final childIds = <int>[
      for (final r in item.childRelations)
        if (r.targetId != null) r.targetId!,
    ];
    final ids = <int>[?parentId, ...childIds];
    if (ids.isEmpty) {
      if (mounted) {
        setState(() {
          _parent = null;
          _children = const [];
        });
      }
      return;
    }
    try {
      final linked = await repo.batch(widget.org, widget.project, ids);
      final byId = {for (final w in linked) w.id: w};
      if (!mounted) return;
      setState(() {
        _parent = parentId == null ? null : byId[parentId];
        _children = [
          for (final id in childIds)
            if (byId[id] != null) byId[id]!,
        ];
      });
    } on AdoException {
      // Keep whatever was shown before; the links row is not the page.
    }
  }

  /// "Add child" and "Add related" from the overflow: the child's type
  /// comes from the backlog level below the parent's (research/11 4.1);
  /// a related item may be of any type, so the full chooser is shown.
  Future<void> _addLinked({required bool related}) async {
    final item = await context
        .read<WorkItemRepository>()
        .watchItem(widget.org, widget.id)
        .first;
    if (item == null || !mounted) return;
    final forms = context.read<WorkItemFormRepository>();
    setState(() => _writing = true);
    try {
      Set<String>? limitTo;
      if (!related) {
        final backlog = await forms.backlogTypes(widget.org, widget.project);
        limitTo = backlog.childTypeNames(item.type).toSet();
      }
      if (!mounted) return;
      final data = await loadTypeChooserData(
        context,
        org: widget.org,
        project: widget.project,
        limitTo: limitTo,
      );
      if (!mounted) return;
      String? typeName = data.model.all.length == 1
          ? data.model.all.first.name
          : null;
      WorkItemTemplate? template;
      if (typeName == null) {
        if (data.model.all.isEmpty) return;
        final choice = await showTypeChooser(
          context,
          model: data.model,
          templates: data.templates,
        );
        if (choice == null || !mounted) return;
        typeName = choice.typeName;
        template = choice.template;
      }
      if (!mounted) return;
      setState(() => _writing = false);
      await openWorkItemForm(
        context,
        org: widget.org,
        project: widget.project,
        typeName: typeName,
        parentId: widget.id,
        relation: related ? 'related' : 'child',
        templateId: template?.id,
      );
      if (mounted) await _refresh();
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
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<FormSpec?> _formSpec(WorkItem item) async {
    if (item.type.isEmpty) return null;
    try {
      return await context.read<WorkItemFormRepository>().formSpec(
        widget.org,
        widget.project,
        item.type,
      );
    } on AdoException {
      return _spec;
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
    final queue = context.read<WriteQueue>();
    try {
      await repo.updateFields(widget.org, widget.project, item, values);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoNetworkException {
      await queue.enqueuePatch(
        org: widget.org,
        project: widget.project,
        item: item,
        ops: [
          for (final e in values.entries)
            {'op': 'add', 'path': '/fields/${e.key}', 'value': e.value},
        ],
        description:
            'Update ${values.keys.map((k) => k.split('.').last).join(', ')} '
            'on ${item.id}',
      );
      await repo.applyLocally(widget.org, widget.project, item, values);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline: the change will sync later.')),
        );
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

  /// The state chip: the legal transitions from where the item is, and the
  /// reason for the move when the type's rules require one (research/11
  /// §4.3). The quick action keeps the offline queue.
  Future<void> _changeState(WorkItem item) async {
    final spec = _spec;
    final change = await pickState(
      context,
      item: item,
      visuals: _visuals,
      transitions: spec?.transitionsFrom(item.state) ?? const [],
      reason: spec?.fields['System.Reason'],
    );
    if (change == null || change.state == item.state || !mounted) return;
    await _write(item, {
      'System.State': change.state,
      if (change.reason != null) 'System.Reason': change.reason,
    });
  }

  Future<void> _changeAssignment(WorkItem item) async {
    final action = await pickAssignment(context, item: item, meLabel: _me);
    if (action == null || !mounted) return;
    await _write(item, {
      'System.AssignedTo': action == AssignAction.toMe ? _me : '',
    });
  }

  /// The pencil opens the full form in edit mode: the route on a phone, the
  /// same box as a dialog over this page from medium up (research/11 §4.5).
  Future<void> _edit() async {
    final bool? saved;
    if (context.breakpoint.isCompact) {
      saved = await context.push<bool>(
        '${orgRoute(context, widget.org)}/projects/'
        '${Uri.encodeComponent(widget.project)}/work-items/'
        '${widget.id}/edit',
      );
    } else {
      saved = await showDialog<bool>(
        context: context,
        // The account's repositories are provided by the `/a/:account` shell
        // route, which the root navigator sits above.
        useRootNavigator: false,
        builder: (_) => WorkItemFormPage.edit(
          org: widget.org,
          project: widget.project,
          id: widget.id,
          asDialog: true,
        ),
      );
    }
    if (!mounted) return;
    await _refresh();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  Future<bool> _postComment(String text) async {
    setState(() {
      _writing = true;
      _error = null;
    });
    final repo = context.read<WorkItemRepository>();
    final queue = context.read<WriteQueue>();
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
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
      return false;
    } on AdoNetworkException {
      await queue.enqueueComment(
        org: widget.org,
        project: widget.project,
        id: widget.id,
        text: text,
        description: 'Comment on ${widget.id}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Offline: the comment will post later.'),
          ),
        );
      }
      return true;
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
      return false;
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  void _openLinked(WorkItem item) => context.push(
    '${orgRoute(context, widget.org)}/projects/'
    '${Uri.encodeComponent(widget.project)}/work-items/${item.id}',
  );

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
        title: Text(
          widget.embedded
              ? '#${widget.id}'
              : '${widget.project} · #${widget.id}',
        ),
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _refreshing || _writing ? null : _edit,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            enabled: !_refreshing && !_writing,
            onSelected: (value) => _addLinked(related: value == 'related'),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'child', child: Text('Add child')),
              PopupMenuItem(value: 'related', child: Text('Add related')),
            ],
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
                      child: Center(
                        child: CircularProgressIndicator.adaptive(),
                      ),
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
                    if (_parent != null || _children.isNotEmpty)
                      _Section(
                        title: 'Links',
                        child: _Links(
                          parent: _parent,
                          children: _children,
                          visuals: _visuals,
                          onOpen: _openLinked,
                        ),
                      ),
                    for (final entry in _longTextFields.entries)
                      if ((item.field<String>(entry.key) ?? '')
                          .trim()
                          .isNotEmpty)
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
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, 0),
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

/// The compact Links row: the parent and the children with their titles,
/// each opening that item. The full Links page (add, remove, other link
/// types) is phase 5.
class _Links extends StatelessWidget {
  const _Links({
    required this.parent,
    required this.children,
    required this.visuals,
    required this.onOpen,
  });

  final WorkItem? parent;
  final List<WorkItem> children;
  final WorkItemVisuals visuals;
  final ValueChanged<WorkItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget row(String caption, WorkItem item) => InkWell(
      onTap: () => onOpen(item),
      borderRadius: Radii.chip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(
                caption,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            Icon(
              visuals.typeIcon(item),
              size: 16,
              color: visuals.typeColor(context, item),
            ),
            const SizedBox(width: Spacing.xs),
            Expanded(
              child: Text(
                '#${item.id} ${item.title}',
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (parent != null) row('Parent', parent!),
        for (var i = 0; i < children.length; i++)
          row(i == 0 ? 'Children (${children.length})' : '', children[i]),
      ],
    );
  }
}
