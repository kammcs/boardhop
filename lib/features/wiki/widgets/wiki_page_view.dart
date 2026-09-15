import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../auth/auth_bloc.dart';
import '../../../auth/auth_service.dart';
import '../../../core/http/ado_exceptions.dart';
import '../../../core/routes.dart';
import '../../../core/text/mention.dart';
import '../../../core/text/wiki_link.dart';
import '../../../data/models/wiki.dart';
import '../../../data/repositories/people_repository.dart';
import '../../../data/repositories/wiki_repository.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';
import '../../shared/attachments/inline_attachment_source.dart';
import '../../shared/mention/mention_sources.dart';
import '../../work_items/form/controls/attachments_section.dart';
import '../wiki_prefs.dart';
import 'toc_sheet.dart';
import 'wiki_find.dart';
import 'wiki_markdown.dart';
import 'wiki_source_page.dart';
import 'wiki_tree_view.dart';

/// One wiki page: the reader (K9).
///
/// The same widget is the body of the standalone route (`WikiPagePage`, over
/// the shell, which is what a phone pushes) and the right-hand pane of the
/// tree page from the medium breakpoint (K6). [embedded] is the only
/// difference: the pane has no back arrow of its own, and a link inside it
/// selects in the pane rather than pushing a second reader.
class WikiPageView extends StatefulWidget {
  const WikiPageView({
    super.key,
    required this.org,
    required this.project,
    required this.wiki,
    this.path,
    this.id,
    this.version,
    this.anchor,
    this.embedded = false,
    this.onOpenPage,
    this.onRead,
  });

  final String org;
  final String project;
  final Wiki wiki;

  /// The page, by its title-form path or by its id. One of the two is
  /// required — a page is read by either (research/20 §1).
  final String? path;
  final int? id;

  /// The branch, for a code wiki (K8). Null means the wiki's own.
  final String? version;

  /// A heading to scroll to once the body is on screen.
  final String? anchor;

  final bool embedded;

  /// Set by the tablet's tree page: a link to another page of this wiki
  /// changes the selection instead of pushing a reader over the pane.
  final void Function(String path, {String? anchor})? onOpenPage;

  /// Called once the page has been read and remembered, so the tree page's
  /// Recent strip catches up without polling the preferences (K11).
  final VoidCallback? onRead;

  @override
  State<WikiPageView> createState() => _WikiPageViewState();
}

/// "14 Sep 2026" — the footer's date, the format the sprint header already
/// uses.
final _dayMonthYear = DateFormat('d MMM y');

class _WikiPageViewState extends State<WikiPageView> {
  final _headings = WikiHeadings();
  final _scroll = ScrollController();
  final _find = WikiFindController();
  final _body = WikiBodyController();

  /// Lower-cased identity GUID → display name for the `@<guid>` runs on
  /// this page, resolved once per page (research/16 M9).
  Map<String, String> _names = const {};

  WikiPage? _page;
  WikiPageChange? _change;
  List<WikiPageNode> _ancestors = const [];

  /// The page's child pages from the cached tree, for `[[_TOSP_]]`.
  ///
  /// The page GET answers `subPages` only when it was asked for a recursion
  /// level, and the reader asks for content: `/Boardhop` drew "This page has
  /// no child pages" on the iPhone with four of them in the tree beside it.
  /// The tree is always read before a page is opened from it, so its node is
  /// the honest answer.
  List<WikiPageNode> _subPages = const [];
  Map<String, String> _headers = const {};

  bool _loading = false;
  String? _error;
  String? _unavailable;
  DateTime? _shownAt;
  bool _offline = false;

  /// The anchor still to be scrolled to once the body has been laid out.
  String? _pendingAnchor;

  @override
  void initState() {
    super.initState();
    _pendingAnchor = widget.anchor;
    _find.addListener(_onFind);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  @override
  void didUpdateWidget(WikiPageView old) {
    super.didUpdateWidget(old);
    if (old.path == widget.path &&
        old.id == widget.id &&
        old.wiki.id == widget.wiki.id &&
        old.version == widget.version) {
      if (old.anchor != widget.anchor && widget.anchor != null) {
        _pendingAnchor = widget.anchor;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToPending());
      }
      return;
    }
    setState(() {
      _page = null;
      _change = null;
      _ancestors = const [];
      _subPages = const [];
      _shownAt = null;
      _offline = false;
      _error = null;
      _unavailable = null;
      _pendingAnchor = widget.anchor;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _headings.dispose();
    _scroll.dispose();
    _find.dispose();
    super.dispose();
  }

  WikiRepository get _repo => context.read<WikiRepository>();

  String? get _version =>
      widget.version ??
      (widget.wiki.isProjectWiki ? null : widget.wiki.version);

  /// The path the page is known by: the route's, and once it has been read
  /// the service's own (a read by id starts without one).
  String get _path => _page?.path ?? widget.path ?? '';

  // -------------------------------------------------------------- loading

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _unavailable = null;
    });
    if (!refresh) await _drawCached();
    try {
      final page = await _repo.page(
        widget.org,
        widget.project,
        widget.wiki.id,
        path: widget.path,
        id: widget.id,
        version: _version,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _shownAt = null;
        _offline = false;
      });
      await _remember(page);
      widget.onRead?.call();
      unawaited(_loadSide(page));
    } on WikiUnavailable catch (e) {
      if (mounted) setState(() => _unavailable = e.message);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoNetworkException catch (e) {
      if (!mounted) return;
      setState(() {
        if (_page == null) {
          _error = e.message;
        } else {
          _offline = true;
        }
      });
    } on AdoException catch (e) {
      if (mounted && _page == null) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The cached copy, drawn before anything touches the network (K7).
  Future<void> _drawCached() async {
    if (_page != null) return;
    final cached = await _repo.cachedPage(
      widget.org,
      widget.project,
      widget.wiki.id,
      path: widget.path,
      id: widget.id,
      version: _version,
    );
    if (cached == null || !mounted || _page != null) return;
    setState(() {
      _page = cached.page;
      _shownAt = cached.fetchedAt;
    });
    unawaited(_loadAncestors(cached.page.path));
  }

  /// Everything the page can be drawn without: the breadcrumb, the bearer
  /// token its images need and the footer's last-change line (K9).
  Future<void> _loadSide(WikiPage page) async {
    await _loadAncestors(page.path);
    await _loadHeaders();
    unawaited(_loadNames(page));
    if (!mounted) return;
    try {
      final change = await _repo.lastChange(
        widget.org,
        widget.project,
        widget.wiki,
        page.gitItemPath,
        version: _version,
      );
      if (mounted) setState(() => _change = change);
    } on AdoException {
      // The footer line is not worth an error: it simply stays hidden.
    }
  }

  /// The ancestors of the page, from the cached tree — the breadcrumb must
  /// never cost a call of its own, and the tree is always read before a
  /// page is opened from it.
  Future<void> _loadAncestors(String path) async {
    if (path.isEmpty) return;
    final tree = await _repo.cachedTree(
      widget.org,
      widget.project,
      widget.wiki.id,
      version: _version,
    );
    if (tree == null || !mounted) return;
    setState(() {
      _ancestors = tree.ancestorsOf(path);
      _subPages = tree.find(path)?.subPages ?? const [];
    });
  }

  Future<void> _loadHeaders() async {
    if (_headers.isNotEmpty || !mounted) return;
    try {
      final auth = context.read<AuthService>();
      final token = await auth.accessToken(accountId: AccountScope.of(context));
      if (mounted) {
        setState(() => _headers = {'Authorization': 'Bearer $token'});
      }
    } catch (_) {
      // Without a token the images draw as broken, which is the honest
      // result; nothing else on the page depends on it.
    }
  }

  /// The display name behind every `@<guid>` on the page, in one batched
  /// identities read (W-C item 9).
  ///
  /// Supplied to the body **once**, after the fact: `MarkdownBody` builds its
  /// children in `didChangeDependencies` and would never redraw a name that
  /// arrived from the network, which is why `MentionScope` exists — a new map
  /// re-parses the body exactly once, and a GUID nobody answers for keeps
  /// reading `@someone` (M9).
  Future<void> _loadNames(WikiPage page) async {
    if (!page.content.contains('@<')) return;
    try {
      final names = await MentionSources.namesFor(
        context.read<PeopleRepository>(),
        widget.org,
        [page.content],
      );
      if (mounted && names.isNotEmpty) setState(() => _names = names);
    } on AdoException {
      // A name is cosmetic; the page is already on screen without it.
    }
  }

  void _onFind() {
    if (!mounted) return;
    setState(() {});
    _scrollToHit();
  }

  /// Puts the find bar's current hit on screen: the run itself when the
  /// body drew it, the section it is in on the lazy body (K4).
  void _scrollToHit() {
    if (_find.term.isEmpty || _find.total == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _find.target;
      final section = target.section;
      if (section != null && _body.jumpToSection(section)) return;
      final context = target.key?.currentContext;
      if (context == null) return;
      unawaited(
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 220),
          alignment: 0.3,
        ),
      );
    });
  }

  /// K1 and K11: the page just read is the one a cold open restores and the
  /// first chip of the Recent strip.
  Future<void> _remember(WikiPage page) async {
    if (page.path.isEmpty) return;
    await WikiPrefs.setLastPath(
      widget.org,
      widget.project,
      widget.wiki.id,
      page.path,
    );
    await WikiPrefs.addRecent(
      widget.org,
      widget.project,
      widget.wiki.id,
      WikiRecent(path: page.path, title: page.title),
    );
  }

  // ----------------------------------------------------------- navigation

  void _openPage(String path, {String? anchor}) {
    final open = widget.onOpenPage;
    if (open != null) {
      open(path, anchor: anchor);
      return;
    }
    context.push(
      Routes.wikiPage(
        AccountScope.of(context),
        widget.org,
        widget.project,
        widget.wiki.id,
        path: path,
        version: widget.version,
        anchor: anchor,
      ),
    );
  }

  void _openMention(MentionKind kind, String id) {
    final account = AccountScope.of(context);
    switch (kind) {
      case MentionKind.workItem:
        // Inside the tablet's pane this page is *in* the shell, so the
        // branch route keeps the dock; the standalone reader is already
        // over the shell and must push the standalone item, or go_router
        // keys two pages the same (see Routes.workItemStandalone).
        context.push(
          widget.embedded
              ? Routes.workItem(account, widget.org, widget.project, id)
              : Routes.workItemStandalone(
                  account,
                  widget.org,
                  widget.project,
                  id,
                ),
        );
      case MentionKind.pullRequest:
        context.push(Routes.pullRequest(account, widget.org, id));
      case MentionKind.person:
        // There is no person page (M9).
        break;
    }
  }

  Future<void> _scrollTo(String anchor) async {
    // The lazy body has not built the heading four screens down, so there is
    // no context to reach: the list jumps to its section instead.
    if (_body.jumpToAnchor(anchor)) {
      _pendingAnchor = null;
      return;
    }
    final heading = _headings.find(anchor);
    final target = heading?.key.currentContext;
    if (target == null) {
      _pendingAnchor = anchor;
      return;
    }
    _pendingAnchor = null;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 220),
      alignment: 0.05,
    );
  }

  void _scrollToPending() {
    final anchor = _pendingAnchor;
    if (anchor == null) return;
    unawaited(_scrollTo(anchor));
  }

  /// A file under `/.attachments/`: the image viewer, or the share sheet
  /// for anything else — exactly the way an attachment row opens
  /// (decision T9).
  Future<void> _openAttachment(String path) async {
    final wiki = widget.wiki;
    final url = _repo
        .attachmentUri(
          widget.org,
          widget.project,
          wiki,
          path,
          version: _version,
        )
        .toString();
    await _loadHeaders();
    if (!mounted) return;
    final source = AttachmentSource(
      bytes: (_) => _repo.attachmentBytes(
        widget.org,
        widget.project,
        wiki,
        path,
        version: _version,
      ),
      headers: _headers,
    );
    final message = await openAttachment(
      context,
      info: inlineAttachmentInfo(url),
      source: source,
    );
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ----------------------------------------------------------- app bar

  Future<void> _showContents() async {
    final picked = await showWikiContents(
      context,
      headings: _headings.contents,
      pageTitle: _title,
    );
    if (picked == null || !mounted) return;
    await _scrollTo(picked.anchor);
  }

  /// The branch a URL handed to the web has to name: a code wiki's, and
  /// nothing for a project wiki, which has one (K8).
  String? get _webVersion => widget.wiki.isProjectWiki ? null : _version;

  /// The URL the page is at on the web: its own `remoteUrl` where the
  /// service gave one, else the path form built from what is known.
  ///
  /// A code wiki's `remoteUrl` carries **no** `wikiVersion` (spike w38), so
  /// the branch is put back on it; without that, Open on web from the
  /// second branch lands on the first one.
  String get _webUrl {
    final remote = _page?.remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      return WikiLink.withVersion(remote, _webVersion);
    }
    return WikiLink.pageUrl(
      widget.org,
      widget.project,
      widget.wiki.id,
      _path.isEmpty ? '/' : _path,
      version: _version,
    );
  }

  /// K9's Copy link: the id form the web's own *Copy page URL* writes when
  /// the id is known, and the path form — which needs no id — when it is
  /// not.
  String get _copyUrl {
    final id = _page?.id ?? widget.id;
    if (id == null) return _webUrl;
    return WikiLink.withVersion(
      WikiLink.webUrl(widget.org, widget.project, widget.wiki.name, id, _title),
      _webVersion,
    );
  }

  Future<void> _openOnWeb() async {
    final uri = Uri.tryParse(_webUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: _copyUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  void _showSource() {
    final page = _page;
    if (page == null) return;
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => WikiSourcePage(title: _title, source: page.content),
      ),
    );
  }

  String get _title {
    final page = _page;
    if (page != null && page.title.isNotEmpty) return page.title;
    final path = widget.path;
    if (path != null && path.isNotEmpty) return WikiPageNode.titleOf(path);
    return widget.wiki.name;
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
        titleSpacing: widget.embedded ? Spacing.lg : 0,
        title: Text(_title, overflow: TextOverflow.ellipsis),
        bottom: _find.isOpen ? WikiFindBar(controller: _find) : null,
        actions: [
          IconButton(
            tooltip: 'Find on this page',
            icon: const Icon(Icons.search),
            onPressed: _page == null ? null : _find.open,
          ),
          ListenableBuilder(
            listenable: _headings,
            builder: (context, _) => _headings.hasContents
                ? IconButton(
                    tooltip: 'Contents',
                    icon: const Icon(Icons.toc),
                    onPressed: _showContents,
                  )
                : const SizedBox.shrink(),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            offset: kTrailingMenuOffset,
            onSelected: (value) => switch (value) {
              'web' => unawaited(_openOnWeb()),
              'copy' => unawaited(_copyLink()),
              'source' => _showSource(),
              _ => null,
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'web',
                child: ListTile(
                  leading: Icon(Icons.open_in_new),
                  title: Text('Open on web'),
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.link),
                  title: Text('Copy link'),
                ),
              ),
              PopupMenuItem(
                value: 'source',
                enabled: _page != null,
                child: const ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Show source'),
                ),
              ),
            ],
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _load(refresh: true),
          child: ContentColumn(child: _scrollBody(theme)),
        ),
      ),
    );
  }

  /// Everything above the markdown: the progress line, the cache line, the
  /// notices and the title block.
  List<Widget> _leading(ThemeData theme) => [
    if (_loading && _page == null) const LinearProgressIndicator(),
    WikiCacheLine(shownAt: _shownAt, offline: _offline),
    if (_unavailable != null)
      WikiNotice(
        message: _unavailable!,
        icon: Icons.lock_outline,
        tone: WikiNoticeTone.quiet,
      ),
    if (_error != null)
      WikiNotice(
        message: _error!,
        onDismiss: () => setState(() => _error = null),
      ),
    _header(theme),
  ];

  /// A short page is a `ListView` of blocks, which is what a reader scrolls.
  ///
  /// A long one hands the whole viewport to [WikiMarkdown], whose own
  /// `SuperListView` builds a section at a time and can jump to one exactly
  /// (W-C item 11); the header and the footer ride as rows of that same
  /// list, so the page still has a single scroll and one pull-to-refresh.
  Widget _scrollBody(ThemeData theme) {
    final page = _page;
    if (page != null && WikiMarkdown.isLazy(page.content)) {
      return _markdown(
        lazyLeading: _leading(theme),
        lazyTrailing: [_footer(theme)],
      );
    }
    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: scrollEndPadding(context).bottom + Spacing.xl,
      ),
      children: [
        ..._leading(theme),
        if (page != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: _markdown(),
          ),
        if (page != null) _footer(theme),
      ],
    );
  }

  Widget _header(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_ancestors.isNotEmpty)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final ancestor in _ancestors) ...[
                  InkWell(
                    borderRadius: Radii.chip,
                    onTap: () => _openPage(ancestor.path),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: Spacing.xs,
                        horizontal: Spacing.xs,
                      ),
                      child: Text(
                        ancestor.title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          Text(_title, style: theme.textTheme.headlineSmall),
        ],
      ),
    );
  }

  Widget _markdown({
    List<Widget> lazyLeading = const [],
    List<Widget> lazyTrailing = const [],
  }) {
    final page = _page!;
    return WikiMarkdown(
      content: page.content,
      wiki: widget.wiki,
      pagePath: _path,
      headings: _headings,
      subPages: page.subPages.isNotEmpty ? page.subPages : _subPages,
      onOpenPage: _openPage,
      onOpenAnchor: (anchor) => unawaited(_scrollTo(anchor)),
      onOpenAttachment: (path) => unawaited(_openAttachment(path)),
      onOpenMention: _openMention,
      onOpenOnWeb: () => unawaited(_openOnWeb()),
      onOpenQuery: _openQuery,
      attachmentUri: (path) => _repo.attachmentUri(
        widget.org,
        widget.project,
        widget.wiki,
        path,
        version: _version,
      ),
      headers: _headers,
      names: _names,
      find: _find,
      bodyController: _body,
      lazyLeading: lazyLeading,
      lazyTrailing: lazyTrailing,
    );
  }

  /// A `::: query-table {guid}` card's Open in Boardhop: the saved query in
  /// the Work items page, which is where the app already shows one (K3).
  void _openQuery(String queryId) {
    context.push(
      Routes.workItems(
        AccountScope.of(context),
        widget.org,
        widget.project,
        query: queryId,
        queryName: 'Wiki query',
      ),
    );
  }

  /// K9's footer: who last changed the page and when, and the one way to
  /// change it — the web. Hidden until the commit is known, so the line
  /// never flashes an empty author.
  Widget _footer(ThemeData theme) {
    final change = _change;
    // Hidden entirely until the commit is known: a lone divider under the
    // last paragraph reads as a rendering fault.
    if (change == null) return const SizedBox.shrink();
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          const SizedBox(height: Spacing.xs),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Last changed by ${change.author}'
                '${change.date == null ? '' : ' on ${_dayMonthYear.format(change.date!.toLocal())}'}'
                ' · ',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              InkWell(
                borderRadius: Radii.chip,
                onTap: _openOnWeb,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.xs,
                    vertical: Spacing.xs,
                  ),
                  child: Text(
                    'Edit on the web',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
