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
import 'form/controls/links_section.dart';
import 'form/new_work_item_button.dart';
import 'form/type_chooser.dart';
import 'form/work_item_form_page.dart';
import 'form/work_item_form_state.dart';
import 'widgets/rich_text_view.dart';
import 'widgets/work_item_actions.dart';
import 'widgets/work_item_field_groups.dart';
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
  /// The fallback rendering, for an item whose type's layout is not there
  /// yet (the first open of a cached item without a connection): the
  /// long-text fields of the stock types. Once the spec arrives, the
  /// layout decides what is shown.
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

  /// The item's linked work items, resolved through one batch read and
  /// keyed by id: the compact Links row groups the relations by kind, the
  /// same way the form's Links page does (phase 5).
  Map<int, WorkItem> _linked = const {};

  /// The types "Add child" may offer: the backlog level below this item's
  /// own. Empty on the lowest level (a Task), where the overflow leaves the
  /// action out altogether (iPad walkthrough).
  Set<String> _childTypes = const {};

  /// The overflow button, which the type chooser drops from as a menu from
  /// medium up, the same way the Work `+` does.
  final _moreKey = GlobalKey();

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
      await _loadChildTypes(item);
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

  /// What a child of [item] could be. Cached for a day by the repository,
  /// and never worth an error: a refusal just leaves "Add child" offered.
  Future<void> _loadChildTypes(WorkItem item) async {
    try {
      final backlog = await context.read<WorkItemFormRepository>().backlogTypes(
        widget.org,
        widget.project,
      );
      if (!mounted) return;
      setState(() => _childTypes = backlog.childTypeNames(item.type).toSet());
    } on AdoException {
      // Keep whatever was known before.
    }
  }

  /// Resolves every work item [item] links to, in one batch read. Links
  /// are a nicety: a refusal leaves the row off rather than failing the
  /// page.
  Future<void> _loadLinks(WorkItemRepository repo, WorkItem item) async {
    final ids = <int>{
      for (final r in item.linkRelations)
        if (r.targetId != null) r.targetId!,
    };
    if (ids.isEmpty) {
      if (mounted) setState(() => _linked = const {});
      return;
    }
    try {
      final linked = await repo.batch(widget.org, widget.project, ids.toList());
      if (!mounted) return;
      setState(() => _linked = {for (final w in linked) w.id: w});
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
        if (limitTo.isEmpty) return;
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
        setState(() => _writing = false);
        final choice = await showTypeChooser(
          context,
          model: data.model,
          templates: data.templates,
          // The same anchored menu the Work `+` opens at this width; a
          // phone still gets the sheet (iPad walkthrough).
          anchor: _moreKey.currentContext?.findRenderObject() as RenderBox?,
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

  /// The item's own fields, the way the web's read view shows them: the
  /// type's form layout decides which groups appear and in which order
  /// (Kelly's report on #15303, whose custom fields were invisible).
  ///
  /// Until the spec is there — the first open of a cached item without a
  /// connection, or a refused read — the stock long-text fields stand in,
  /// so nothing is lost while the layout is on its way.
  List<Widget> _fields(WorkItem item) {
    final spec = _spec;
    final groups = spec == null
        ? const <FormGroupView>[]
        : detailGroupsFor(spec, item);
    return [
      // Nothing but the service's own panels (or no spec at all): the stock
      // long-text fields stand in for the layout.
      if (groups.every((g) => g.isPanel))
        for (final entry in _longTextFields.entries)
          if ((item.field<String>(entry.key) ?? '').trim().isNotEmpty)
            DetailSection(
              title: entry.value,
              child: RichTextView(
                content: item.field<String>(entry.key)!,
                format: item.formatOf(entry.key),
                headers: _headers,
              ),
            ),
      if (spec != null && groups.isNotEmpty)
        ...workItemFieldSections(
          spec: spec,
          item: item,
          groups: groups,
          headers: _headers,
        ),
    ];
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
            key: _moreKey,
            tooltip: 'More',
            enabled: !_refreshing && !_writing,
            onSelected: (value) => _addLinked(related: value == 'related'),
            itemBuilder: (context) => [
              // A Task has no backlog level below it, so it is never a
              // parent.
              if (_childTypes.isNotEmpty)
                const PopupMenuItem(value: 'child', child: Text('Add child')),
              const PopupMenuItem(value: 'related', child: Text('Add related')),
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
                padding: scrollEndPadding(context),
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
                    ..._fields(item),
                    if (item.linkRelations.isNotEmpty)
                      DetailSection(
                        title: 'Links',
                        child: _Links(
                          relations: item.linkRelations,
                          linked: _linked,
                          visuals: _visuals,
                          onOpen: _openLinked,
                        ),
                      ),
                    DetailSection(
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
    final rows = <(String, String)>[
      ('Area', item.areaPath ?? ''),
      ('Iteration', item.iterationPath ?? ''),
      if (item.reason != null) ('Reason', item.reason!),
      // `System.AttachedFileCount` is not in the item read, not even with
      // `\$expand=all` (spike s36), so the relations are counted.
      if (item.attachmentRelations.isNotEmpty)
        ('Attachments', '${item.attachmentRelations.length}'),
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
            if (value.isNotEmpty) DetailFactRow(label: label, value: value),
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

/// The compact Links row: every work item link grouped by kind, each row
/// opening that item. Adding and removing is the form's Links page
/// (phase 5), which shares [groupLinkRelations] with this.
class _Links extends StatelessWidget {
  const _Links({
    required this.relations,
    required this.linked,
    required this.visuals,
    required this.onOpen,
  });

  final List<WorkItemRelation> relations;

  /// The resolved targets by id; an id the batch could not read shows as
  /// the bare id.
  final Map<int, WorkItem> linked;

  final WorkItemVisuals visuals;
  final ValueChanged<WorkItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget row(String caption, WorkItemRelation relation) {
      final item = linked[relation.targetId];
      final kind = LinkKind.of(relation.rel);
      return InkWell(
        onTap: item == null ? null : () => onOpen(item),
        borderRadius: Radii.chip,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: DetailFactRow.labelWidth,
                child: Text(
                  caption,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                item == null ? kind.icon : visuals.typeIcon(item),
                size: 16,
                color: item == null
                    ? scheme.onSurfaceVariant
                    : visuals.typeColor(context, item),
              ),
              const SizedBox(width: Spacing.xs),
              Expanded(
                child: Text(
                  item == null
                      ? '#${relation.targetId}'
                      : '#${item.id} ${item.title}',
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groupLinkRelations(relations))
          for (var i = 0; i < group.relations.length; i++)
            row(
              i > 0
                  ? ''
                  : group.relations.length > 1
                  ? '${group.kind.heading} (${group.relations.length})'
                  : group.kind.label,
              group.relations[i],
            ),
      ],
    );
  }
}
