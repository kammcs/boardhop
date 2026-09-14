import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../auth/auth_service.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/routes.dart';
import '../../core/text/mention.dart';
import '../../core/util/format.dart';
import '../../data/mention_recents.dart';
import '../../data/models/work_item.dart';
import '../../data/models/work_item_form.dart';
import '../../data/repositories/people_repository.dart';
import '../../data/repositories/pull_request_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/repositories/work_item_form_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../data/write_queue.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import '../shared/anchor_highlight.dart';
import '../shared/mention/mention_source.dart';
import '../shared/mention/mention_sources.dart';
import '../shared/widgets/tab_count_badge.dart';
import 'form/controls/attachments_section.dart';
import 'form/controls/links_section.dart';
import 'form/new_work_item_button.dart';
import 'form/type_chooser.dart';
import 'form/work_item_form_page.dart';
import 'form/work_item_form_state.dart';
import 'widgets/rich_text_view.dart';
import 'widgets/work_item_actions.dart';
import 'widgets/work_item_field_groups.dart';
import 'widgets/work_item_visuals.dart';

/// One work item in three tabs — Details, Related, Comments — so a long item
/// is read a part at a time rather than as one endless scroll (Kelly,
/// 2026-09-14). Details is the header, the facts and the type's own fields;
/// Related is the links and the attachments; Comments is the discussion from
/// the preview Comments API with the composer under it. Lightweight writes:
/// post a comment, change state, assign to me / unassign.
class WorkItemDetailPage extends StatefulWidget {
  const WorkItemDetailPage({
    super.key,
    required this.org,
    required this.project,
    required this.id,
    this.embedded = false,
    this.initialCommentId,
    this.initialTab,
  });

  final String org;
  final String project;
  final int id;

  /// Which tab to open on: `details`, `related` or `comments` from
  /// `?tab=` on either work item route. Anything else opens Details, which
  /// is also where a link with no `tab` lands.
  final String? initialTab;

  /// A pushed comment notification lands here (`?comment={id}`,
  /// research/14 §4.2): once the discussion is read the page scrolls that
  /// comment into view and tints it for two seconds. An id that is not in
  /// the list -- deleted, or older than the page that was read -- scrolls
  /// to the Discussion heading and says nothing.
  final int? initialCommentId;

  /// True inside the tablet list+detail pane: no back button, the pane's
  /// own list stays visible.
  final bool embedded;

  @override
  State<WorkItemDetailPage> createState() => _WorkItemDetailPageState();
}

class _WorkItemDetailPageState extends State<WorkItemDetailPage>
    with SingleTickerProviderStateMixin {
  /// Details, Related, Comments. Owned here rather than through a
  /// `DefaultTabController` so the scaffold rebuilds when the tab changes
  /// and can take its composer away, the way the pull request page does.
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: _initialIndex)
        ..addListener(() {
          if (mounted) setState(() {});
        });

  static const int _detailsTab = 0;
  static const int _relatedTab = 1;

  /// The composer posts a discussion comment, which means nothing under
  /// Details or Related.
  static const int _commentsTab = 2;

  /// `?tab=` from a link or a push; a `?comment=` anchor implies Comments,
  /// because that is where the comment lives.
  int get _initialIndex => switch (widget.initialTab) {
    'related' => _relatedTab,
    'comments' => _commentsTab,
    'details' => _detailsTab,
    _ => widget.initialCommentId != null ? _commentsTab : _detailsTab,
  };

  /// The item's drift stream, held rather than rebuilt: a tab change
  /// rebuilds this page many times a second while the strip animates, and
  /// a fresh stream each time would resubscribe on every frame.
  late final Stream<WorkItem?> _items = context
      .read<WorkItemRepository>()
      .watchItem(widget.org, widget.id);

  /// Reading and opening the item's attachments on the Related tab. Built
  /// once the bearer token is known; no `upload`, because adding a file is
  /// the form's job.
  AttachmentSource? _attachments;

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

  /// The Discussion section and one key per comment, so a pushed
  /// `?comment={id}` can be scrolled to (research/14 §4.2).
  final _discussionKey = GlobalKey();
  final Map<int, GlobalKey> _commentKeys = {};

  /// The comment the anchor tinted, and the timer that clears the tint.
  int? _highlighted;
  Timer? _highlightTimer;

  /// The anchor is honoured once per deep link, not on every pull to
  /// refresh: someone reading further down must not be yanked back.
  int? _anchoredFor;

  /// The item as it was last read, for the mention picker's participants —
  /// the body itself is drawn from the drift stream.
  WorkItem? _item;

  /// The Discussion composer's picker (research/16 §4.5) and the names any
  /// `@<guid>` in a Markdown-format field resolves to. A comment arrives as
  /// server-rendered HTML with the name already inside the anchor, so the
  /// map is only needed for the fields.
  MentionSources? _sources;
  MentionSource? _mentions;
  Map<String, String> _mentionNames = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(WorkItemDetailPage old) {
    super.didUpdateWidget(old);
    // A second push naming another comment on the same item reuses this
    // state, so a new anchor is honoured again.
    if (old.initialCommentId != widget.initialCommentId) {
      _anchoredFor = null;
      _anchorComment();
    } else if (old.initialTab != widget.initialTab &&
        widget.initialTab != null) {
      _tabs.animateTo(_initialIndex);
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  /// Scrolls to the pushed comment and tints it for [kAnchorHighlight].
  ///
  /// The comments now live on a tab of their own, so the tab is selected
  /// first and the scroll waits for the frame after that: the list does not
  /// exist until the strip has moved. The discussion block is what the
  /// scroller aims at until the card itself has been built.
  void _anchorComment() {
    final id = widget.initialCommentId;
    final comments = _comments;
    if (id == null || comments == null || _anchoredFor == id) return;
    _anchoredFor = id;
    if (_tabs.index != _commentsTab) _tabs.animateTo(_commentsTab);
    final known = comments.any((c) => c.id == id);
    final key = known ? _commentKeys.putIfAbsent(id, GlobalKey.new) : null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (key == null) {
        // Not in the list -- deleted, or past the page of comments that
        // was read: land on the Discussion heading, no error.
        await revealAnchor(target: _discussionKey, alignment: 0);
        return;
      }
      final found = await revealAnchor(target: key, fallback: _discussionKey);
      if (!found || !mounted) return;
      setState(() => _highlighted = id);
      _highlightTimer?.cancel();
      _highlightTimer = Timer(kAnchorHighlight, () {
        if (mounted) setState(() => _highlighted = null);
      });
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    final repo = context.read<WorkItemRepository>();
    final forms = context.read<WorkItemFormRepository>();
    final auth = context.read<AuthService>();
    final accountId = AccountScope.of(context);
    try {
      final token = await auth.accessToken(accountId: accountId);
      _headers = {'Authorization': 'Bearer $token'};
      _attachments = AttachmentSource(
        bytes: forms.attachmentBytes,
        headers: _headers,
      );
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
      if (mounted) {
        setState(() {
          _item = item;
          _comments = comments;
        });
        _anchorComment();
        unawaited(_prepareMentions());
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
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// The Discussion composer's picker, off the page's critical path.
  ///
  /// The people already on the item are seeded into the identity memory
  /// first, so a `@<guid>` in one of its fields can be named without a call
  /// (M9), and the source itself is built once: a new instance would make an
  /// open picker reload its bands.
  Future<void> _prepareMentions() async {
    final people = context.read<PeopleRepository>();
    unawaited(people.rememberIdentities(widget.org, _participants()));
    final item = _item;
    final names = await MentionSources.namesFor(people, widget.org, [
      if (item != null)
        for (final value in item.fields.values)
          if (value is String) value,
    ]);
    if (!mounted) return;
    if (names.isNotEmpty && names.length != _mentionNames.length) {
      setState(() => _mentionNames = names);
    }
    if (_mentions != null) return;
    final sources = _sources ??= MentionSources(
      org: widget.org,
      project: widget.project,
      people: people,
      forms: context.read<WorkItemFormRepository>(),
      recents: context.read<MentionRecents>(),
      workItems: context.read<WorkItemRepository>(),
      pullRequests: context.read<PullRequestRepository>(),
      search: context.read<SearchRepository>(),
      // The Links row already resolved these, and they are the items most
      // likely to be named in a comment about this one (M8).
      extraWorkItems: () => _linked.values.toList(),
    );
    final me = await sources.me(uniqueName: _me);
    if (!mounted || _mentions != null) return;
    setState(() {
      _mentions = sources.source(
        participants: () async => _participants(),
        participantReason: MentionSources.onThisItem,
        me: me,
      );
    });
  }

  /// Everybody already on this item, newest commenter first.
  List<IdentityRef> _participants() => MentionSources.workItemParticipants(
    item: _item,
    comments: _comments ?? const [],
  );

  /// A `#123` or `!456` tapped in a comment or a field (M10). The project is
  /// this page's own: a reference is written against the item being read.
  void _openMention(MentionKind kind, String id) {
    final account = AccountScope.of(context);
    switch (kind) {
      case MentionKind.workItem:
        if (id == '${widget.id}') return;
        context.push(Routes.workItem(account, widget.org, widget.project, id));
      case MentionKind.pullRequest:
        context.push(Routes.pullRequest(account, widget.org, id));
      case MentionKind.person:
        break;
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
                mentionNames: _mentionNames,
                onOpenMention: _openMention,
              ),
            ),
      if (spec != null && groups.isNotEmpty)
        ...workItemFieldSections(
          spec: spec,
          item: item,
          groups: groups,
          headers: _headers,
          mentionNames: _mentionNames,
          onOpenMention: _openMention,
        ),
    ];
  }

  /// The Related tab: what this item links to, and the files hanging off
  /// it. Read-only — adding is the More menu's Add child / Add related and
  /// the form's own Attachments page.
  List<Widget> _related(WorkItem item) {
    final theme = Theme.of(context);
    final attachments = [
      for (final relation in item.attachmentRelations)
        AttachmentInfo.of(relation),
    ];
    if (item.linkRelations.isEmpty && attachments.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.xl,
            Spacing.lg,
            0,
          ),
          child: Text(
            'Nothing linked yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    final source = _attachments;
    return [
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
      if (attachments.isNotEmpty)
        DetailSection(
          title: 'Attachments',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final info in attachments)
                AttachmentRow(
                  key: ValueKey(info.relation.key),
                  info: info,
                  source: source,
                  onOpen: source == null ? null : () => _openAttachment(info),
                ),
            ],
          ),
        ),
    ];
  }

  /// Opens one attachment through the same path the form's Attachments page
  /// uses, so the bytes are fetched and cached in one place.
  Future<void> _openAttachment(AttachmentInfo info) async {
    final source = _attachments;
    if (source == null) return;
    final message = await openAttachment(context, info: info, source: source);
    if (message != null && mounted) setState(() => _error = message);
  }

  /// One tab's scroller: every tab answers a pull to refresh with the same
  /// [_refresh], and none of them refetch when the tab is merely switched.
  Widget _tabBody({Key? key, required List<Widget> children}) =>
      RefreshIndicator(
        onRefresh: _refresh,
        child: ContentColumn(
          child: ListView(
            key: key,
            physics: const AlwaysScrollableScrollPhysics(),
            // A swipe down the discussion puts the keyboard away
            // (Kelly, 2026-09-14).
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: scrollEndPadding(context),
            children: children,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return StreamBuilder<WorkItem?>(
      stream: _items,
      builder: (context, snapshot) {
        final item = snapshot.data;
        // Links plus files: what the Related tab has to show. Unknown
        // until the item is read, and the badge then shows nothing.
        final related = item == null
            ? null
            : item.linkRelations.length + item.attachmentRelations.length;
        return Scaffold(
          // The composer writes a discussion comment, so it belongs to the
          // Comments tab alone (the pull request page does the same).
          bottomNavigationBar: _tabs.index != _commentsTab
              ? null
              : CommentComposer(
                  onSubmit: _postComment,
                  busy: _writing,
                  mentions: _mentions,
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
                offset: kTrailingMenuOffset,
                enabled: !_refreshing && !_writing,
                onSelected: (value) => _addLinked(related: value == 'related'),
                itemBuilder: (context) => [
                  // A Task has no backlog level below it, so it is never a
                  // parent.
                  if (_childTypes.isNotEmpty)
                    const PopupMenuItem(
                      value: 'child',
                      child: Text('Add child'),
                    ),
                  const PopupMenuItem(
                    value: 'related',
                    child: Text('Add related'),
                  ),
                ],
              ),
            ],
            // The strip divides the width evenly while the three labels
            // and their pills fit, and scrolls when they no longer do.
            bottom: CountedTabBar(
              controller: _tabs,
              tabs: [
                const TabCount('Details'),
                TabCount('Related', related),
                TabCount('Comments', _comments?.length),
              ],
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_refreshing || _writing) const LinearProgressIndicator(),
              if (_error != null)
                ListTile(
                  leading: Icon(Icons.error_outline, color: scheme.error),
                  title: Text(_error!),
                ),
              Expanded(
                child: item == null
                    ? (_error == null
                          ? const Center(
                              child: CircularProgressIndicator.adaptive(),
                            )
                          : const SizedBox.shrink())
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _tabBody(
                            children: [
                              _Header(
                                item: item,
                                visuals: _visuals,
                                onStateTap: _writing
                                    ? null
                                    : () => _changeState(item),
                                onAssignTap: _writing
                                    ? null
                                    : () => _changeAssignment(item),
                              ),
                              _Facts(item: item),
                              ..._fields(item),
                            ],
                          ),
                          _tabBody(children: _related(item)),
                          _tabBody(
                            children: [
                              // The tab's own label and badge say
                              // "Comments (12)", so no heading repeats it;
                              // the key is what a `?comment=` anchor aims
                              // at until the card itself is built.
                              Padding(
                                key: _discussionKey,
                                padding: const EdgeInsets.fromLTRB(
                                  Spacing.lg,
                                  Spacing.lg,
                                  Spacing.lg,
                                  0,
                                ),
                                child: _Discussion(
                                  comments: _comments,
                                  headers: _headers,
                                  onOpenMention: _openMention,
                                  keyFor: (id) => _commentKeys.putIfAbsent(
                                    id,
                                    GlobalKey.new,
                                  ),
                                  highlighted: _highlighted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
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
              // "User Story 15558" runs 29 pt past the window at xxxL
              // (iPhone, 2026-09-13), so the type line wraps rather than
              // overflowing; the id stays with it on the second line.
              Expanded(
                child: Text(
                  '${item.type} ${item.id}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
  const _Discussion({
    required this.comments,
    required this.headers,
    required this.keyFor,
    this.highlighted,
    this.onOpenMention,
  });

  final List<WorkItemComment>? comments;
  final Map<String, String> headers;

  /// Tapping a `#123` or `!456` the service linked in a comment (M10).
  final void Function(MentionKind kind, String id)? onOpenMention;

  /// One stable key per comment id, so a pushed `?comment={id}` has
  /// something to scroll to (research/14 §4.2).
  final GlobalKey Function(int id) keyFor;

  /// The comment the deep link landed on; tinted for two seconds.
  final int? highlighted;

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
            key: keyFor(c.id),
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: AnchorHighlight(
              active: c.id == highlighted,
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
                        RichTextView(
                          content: c.renderedText,
                          headers: headers,
                          onOpenMention: onOpenMention,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
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
                width: DetailFactRow.labelWidthFor(context),
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
