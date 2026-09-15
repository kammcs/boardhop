import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/routes.dart';
import '../../data/models/wiki.dart';
import '../../data/repositories/wiki_repository.dart';
import '../../theme/theme.dart';
import '../projects/widgets/home_view_switch.dart';
import '../shared/account_scope.dart';
import '../shared/reload_on_return.dart';
import 'widgets/wiki_page_view.dart';
import 'widgets/wiki_picker_sheet.dart';
import 'widgets/wiki_tree_view.dart';
import 'wiki_prefs.dart';

/// The Wiki view: the Home tab's third segment and the hub's landing page
/// (research/20 K1, K2, K6).
///
/// The page owns the **wiki and its tree**; the reader owns a page. On a
/// phone that is all this page draws and a tap pushes the reader over the
/// shell; from the medium breakpoint the reader sits beside the tree in the
/// work-items list+detail shape and the tree's selection is the pane's page
/// (K6).
class WikiTreePage extends StatefulWidget {
  const WikiTreePage({
    super.key,
    required this.org,
    required this.project,
    this.wikiIdOrName,
    this.path,
  });

  final String org;
  final String project;

  /// `?wiki=` — a wiki GUID or name. Null means the one last opened here,
  /// and failing that the project wiki (K1).
  final String? wikiIdOrName;

  /// `?path=` — the page the tree is expanded along, and the tablet's
  /// selection.
  final String? path;

  @override
  State<WikiTreePage> createState() => _WikiTreePageState();
}

class _WikiTreePageState extends State<WikiTreePage> with ReloadOnReturn {
  List<Wiki> _wikis = const [];
  Wiki? _wiki;
  WikiPageNode? _tree;
  List<WikiRecent> _recents = const [];

  /// The tree rows whose children are showing (K2).
  final _expanded = <String>{};

  /// The page the reader pane shows, from the medium breakpoint (K6).
  String? _selected;

  /// The branch a code wiki is being read at (K8). Null is the wiki's own.
  String? _version;

  bool _loading = false;
  String? _error;
  String? _unavailable;
  DateTime? _shownAt;
  bool _offline = false;

  /// K1's first visit: the wiki's home page is opened once, after the tree
  /// has loaded, and never again for this mount.
  bool _openedFirst = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.path;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_load()));
  }

  @override
  void didUpdateWidget(WikiTreePage old) {
    super.didUpdateWidget(old);
    if (widget.path != old.path && widget.path != _selected) {
      setState(() => _selected = widget.path);
      _expandAlong(widget.path);
    }
    if (widget.wikiIdOrName == old.wikiIdOrName) return;
    if (widget.wikiIdOrName == _wiki?.id) return;
    unawaited(_load());
  }

  @override
  Future<void> reload() => _load();

  WikiRepository get _repo => context.read<WikiRepository>();

  // -------------------------------------------------------------- loading

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _unavailable = null;
    });
    if (!refresh) await _drawCached();
    try {
      final wikis = await _repo.wikis(
        widget.org,
        widget.project,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _wikis = wikis;
        _offline = false;
      });
      if (wikis.isEmpty) {
        setState(() {
          _wiki = null;
          _tree = null;
          _loading = false;
        });
        markLoaded();
        return;
      }
      final chosen = await _choose(wikis);
      if (!mounted || chosen == null) return;
      setState(() {
        _wiki = chosen;
        _version ??= chosen.isProjectWiki ? null : chosen.version;
      });
      unawaited(WikiPrefs.setLastWiki(widget.org, widget.project, chosen.id));
      final tree = await _repo.tree(
        widget.org,
        widget.project,
        chosen.id,
        version: _version,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _shownAt = null;
        _offline = false;
      });
      await _restore(chosen, tree);
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
        if (_tree == null && _wikis.isEmpty) {
          _error = e.message;
        } else {
          _offline = true;
        }
      });
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        markLoaded();
      }
    }
  }

  /// The cached wiki list and tree, drawn before anything touches the
  /// network (K7). Which wiki that is, is itself remembered: without a
  /// wiki id there is no tree cache key to look up and a cold offline open
  /// is blank.
  Future<void> _drawCached() async {
    if (_tree != null) return;
    final wikis = await _repo.cachedWikis(widget.org, widget.project);
    if (wikis == null || wikis.isEmpty || !mounted) return;
    final chosen = await _choose(wikis);
    if (chosen == null || !mounted) return;
    final version = chosen.isProjectWiki ? null : chosen.version;
    final tree = await _repo.cachedTree(
      widget.org,
      widget.project,
      chosen.id,
      version: version,
    );
    if (!mounted || _tree != null) return;
    setState(() {
      _wikis = wikis;
      _wiki = chosen;
      _version ??= version;
      _tree = tree;
      _shownAt = DateTime.now();
    });
    if (tree != null) await _restore(chosen, tree);
  }

  /// The wiki to open: the route's, then the one last opened here, then the
  /// project wiki, then the first (K1).
  Future<Wiki?> _choose(List<Wiki> wikis) async {
    if (wikis.isEmpty) return null;
    final wanted =
        widget.wikiIdOrName ??
        await WikiPrefs.lastWiki(widget.org, widget.project);
    if (wanted != null && wanted.isNotEmpty) {
      final lower = wanted.toLowerCase();
      for (final wiki in wikis) {
        if (wiki.id.toLowerCase() == lower) return wiki;
      }
      for (final wiki in wikis) {
        if (wiki.name.toLowerCase() == lower) return wiki;
      }
    }
    for (final wiki in wikis) {
      if (wiki.isProjectWiki) return wiki;
    }
    return wikis.first;
  }

  /// K1: the tree opens expanded along the page last read, with the recents
  /// above it — and on the very first visit, with no last path and no
  /// recents, the wiki's home page is opened.
  Future<void> _restore(Wiki wiki, WikiPageNode tree) async {
    final recents = await WikiPrefs.recents(
      widget.org,
      widget.project,
      wiki.id,
    );
    final last =
        widget.path ??
        _selected ??
        await WikiPrefs.lastPath(widget.org, widget.project, wiki.id);
    if (!mounted) return;
    setState(() => _recents = recents);
    _expandAlong(last);
    if (last != null && last.isNotEmpty) {
      if (_selected == null && context.breakpoint.isAtLeastMedium) {
        setState(() => _selected = last);
      }
      return;
    }
    if (_openedFirst || recents.isNotEmpty) return;
    final home = tree.subPages.firstOrNull;
    if (home == null) return;
    _openedFirst = true;
    _open(home.path);
  }

  void _expandAlong(String? path) {
    final ancestors = ancestorPathsOf(path);
    if (ancestors.isEmpty || !mounted) return;
    setState(() => _expanded.addAll(ancestors));
  }

  // ----------------------------------------------------------- navigation

  /// A page: selected in the pane from the medium breakpoint, pushed over
  /// the shell on a phone (K6).
  void _open(String path) {
    final wiki = _wiki;
    if (wiki == null || path.isEmpty) return;
    final account = AccountScope.of(context);
    if (context.breakpoint.isAtLeastMedium) {
      setState(() => _selected = path);
      context.go(
        Routes.wiki(
          account,
          widget.org,
          widget.project,
          wiki: wiki.id,
          path: path,
        ),
      );
      return;
    }
    // The reader remembers the page it read; the strip has to catch up
    // when the push comes back (the Home branch never loses its ticker, so
    // `ReloadOnReturn` does not fire on a pop).
    unawaited(
      context
          .push(
            Routes.wikiPage(
              account,
              widget.org,
              widget.project,
              wiki.id,
              path: path,
              version: _version,
            ),
          )
          .then((_) => _reloadRecents()),
    );
  }

  Future<void> _reloadRecents() async {
    final wiki = _wiki;
    if (wiki == null) return;
    final recents = await WikiPrefs.recents(
      widget.org,
      widget.project,
      wiki.id,
    );
    if (mounted) setState(() => _recents = recents);
  }

  Future<void> _pick() async {
    final picked = await showWikiPicker(
      context,
      wikis: _wikis,
      currentId: _wiki?.id,
      projectName: widget.project,
    );
    if (picked == null || !mounted || picked.id == _wiki?.id) return;
    setState(() {
      _wiki = picked;
      _tree = null;
      _recents = const [];
      _selected = null;
      _version = picked.isProjectWiki ? null : picked.version;
      _expanded.clear();
      _shownAt = null;
    });
    unawaited(WikiPrefs.setLastWiki(widget.org, widget.project, picked.id));
    context.go(
      Routes.wiki(
        AccountScope.of(context),
        widget.org,
        widget.project,
        wiki: picked.id,
      ),
    );
    await _load();
  }

  /// K8: a code wiki is published per branch, so the branch is part of every
  /// read. Unverified against a real code wiki — none exists in puremedia.
  Future<void> _pickVersion(String version) async {
    if (version == _version) return;
    setState(() {
      _version = version;
      _tree = null;
      _selected = null;
      _expanded.clear();
    });
    await _load();
  }

  /// The project's wiki on the web, which is where a project with no wiki
  /// gets one.
  Future<void> _openOnWeb() async {
    final uri = Uri.parse(
      'https://dev.azure.com/${Uri.encodeComponent(widget.org)}'
      '/${Uri.encodeComponent(widget.project)}/_wiki',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final compact = context.breakpoint.isCompact;
    final wiki = _wiki;
    final several = _wikis.length > 1;
    final title = wiki?.name ?? 'Wiki';
    // The branch shown is the one being read, not the wiki's first: the
    // pill switches it (K8). On a phone the title column is barely 120 dp
    // wide, where "Code wiki · wiki-docs-v2" ellipsises away exactly the
    // half that matters, so a code wiki's line there is the branch alone.
    final subtitle = wiki == null
        ? widget.project
        : compact && !wiki.isProjectWiki
        ? (_version ?? wiki.version)
        : wikiSubtitle(wiki, version: _version);
    final branches =
        wiki != null && !wiki.isProjectWiki && wiki.versions.length > 1;
    final titleRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: compact
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.titleLarge,
              ),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style:
                    (compact
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.labelMedium)
                        ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // The chevron appears only when there is something to pick: one
        // wiki is the common case and a dead affordance is worse than none.
        if (several)
          Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: scheme.onSurfaceVariant,
            semanticLabel: 'Choose wiki',
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: several
                  ? InkWell(
                      onTap: _pick,
                      borderRadius: Radii.chip,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: Spacing.xs,
                        ),
                        child: titleRow,
                      ),
                    )
                  : titleRow,
            ),
          ],
        ),
        leadingWidth: compact ? 44 : null,
        leading: IconButton(
          tooltip: 'Projects',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('${orgRoute(context, widget.org)}/projects'),
        ),
        // No compact action: the three-segment pill leaves about 84 dp on a
        // phone (research/20 §4.2).
        actions: [
          // The branch switcher is an icon action to the left of the view
          // switch. It was a labelled chip beside the title, which on the
          // iPhone squeezed the wiki's name down to one letter and, on the
          // longer of the two branch names, off the bar entirely (spike
          // w38); at the medium breakpoint the three-segment view switch
          // carries its own labels and leaves the title barely 50 dp, so a
          // chip overflows there too. The branch is named in the subtitle
          // on every width instead.
          if (branches) _branchPill(theme, wiki),
          HomeViewSwitch(
            org: widget.org,
            project: widget.project,
            current: HomeView.wiki,
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = Breakpoint.fromWidth(constraints.maxWidth)
                .isAtLeastMedium;
            final tree = RefreshIndicator(
              onRefresh: () => _load(refresh: true),
              child: ContentColumn(child: _scroller(theme)),
            );
            if (!wide || wiki == null) return tree;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: (constraints.maxWidth * 0.4).clamp(280.0, 420.0),
                  child: tree,
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _selected == null
                      ? Center(
                          child: Text(
                            'Select a page',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : WikiPageView(
                          key: ValueKey('${wiki.id}$_version$_selected'),
                          org: widget.org,
                          project: widget.project,
                          wiki: wiki,
                          path: _selected,
                          version: _version,
                          embedded: true,
                          onOpenPage: (path, {anchor}) => _open(path),
                          onRead: _reloadRecents,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The branch switcher (K8): an icon action, with the branch it is on
  /// named in the app bar's subtitle rather than on a second label the bar
  /// has no room for.
  Widget _branchPill(ThemeData theme, Wiki wiki) {
    final current = _version ?? wiki.version;
    return PopupMenuButton<String>(
      key: const Key('wikiBranchPill'),
      tooltip: 'Branch',
      onSelected: _pickVersion,
      itemBuilder: (context) => [
        for (final version in wiki.versions)
          PopupMenuItem(
            value: version,
            child: Row(
              children: [
                const Icon(Icons.alt_route, size: 18),
                const SizedBox(width: Spacing.sm),
                Expanded(child: Text(version, overflow: TextOverflow.ellipsis)),
                if (version == current) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
      ],
      icon: const Icon(Icons.alt_route),
    );
  }

  Widget _scroller(ThemeData theme) {
    final rows = visibleWikiRows(_tree, _expanded);
    final wiki = _wiki;
    final empty = !_loading && _wikis.isEmpty && _unavailable == null;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_loading && _tree == null)
          const SliverToBoxAdapter(child: LinearProgressIndicator()),
        SliverToBoxAdapter(
          child: WikiCacheLine(shownAt: _shownAt, offline: _offline),
        ),
        if (_unavailable != null)
          SliverToBoxAdapter(
            child: WikiNotice(
              message: _unavailable!,
              icon: Icons.lock_outline,
              tone: WikiNoticeTone.quiet,
            ),
          ),
        if (_error != null)
          SliverToBoxAdapter(
            child: WikiNotice(
              message: _error!,
              onDismiss: () => setState(() => _error = null),
            ),
          ),
        if (empty)
          SliverToBoxAdapter(
            child: WikiEmptyState(
              title: 'This project has no wiki',
              body:
                  'A project wiki is created on the web, and code wikis are '
                  'published from a repository folder. Boardhop reads them; '
                  'it does not create them.',
              actionLabel: 'Open on web',
              onAction: _openOnWeb,
            ),
          )
        else ...[
          if (_recents.isNotEmpty)
            SliverToBoxAdapter(
              child: WikiRecentsStrip(
                recents: _recents,
                onOpen: (recent) => _open(recent.path),
              ),
            ),
          if (wiki != null && _tree != null && rows.isEmpty)
            SliverToBoxAdapter(
              child: WikiEmptyState(
                title: 'This wiki has no pages yet',
                body: 'Pages are added on the web.',
                actionLabel: 'Open on web',
                onAction: _openOnWeb,
              ),
            ),
          SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return WikiTreeTile(
                row: row,
                expanded: _expanded.contains(row.node.path),
                selected: row.node.path == _selected,
                onTap: () => _open(row.node.path),
                onToggle: () => setState(() {
                  if (!_expanded.remove(row.node.path)) {
                    _expanded.add(row.node.path);
                  }
                }),
              );
            },
          ),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: scrollEndPadding(context).bottom),
        ),
      ],
    );
  }
}
