import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/routes.dart';
import '../../core/util/format.dart';
import '../../data/models/git_repository.dart';
import '../../data/models/search.dart';
import '../../data/models/wiki.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/search_recents.dart';
import '../../theme/theme.dart';
import '../pull_requests/widgets/pull_request_tile.dart';
import '../repos/widgets/code_hit_list.dart';
import '../shared/account_scope.dart';
import 'widgets/wiki_hit_tile.dart';
import 'widgets/work_item_hit_tile.dart';

/// Where a search looks (decision D1): the project the page was opened
/// from, or every project of the organization.
enum SearchScope {
  project('project'),
  org('org');

  const SearchScope(this.wire);

  /// The value in the route's `scope` query parameter.
  final String wire;

  static SearchScope fromWire(String? value) =>
      value == org.wire ? org : project;
}

/// The kinds the page searches (decision D2, plus wiki from research/20
/// K4). `wire` is the route's `kind` parameter; unset means the grouped
/// view.
enum SearchKind {
  workItems('wi', 'Work items', Icons.assignment_outlined),
  code('code', 'Code', Icons.code),
  pullRequests('pr', 'Pull requests', Icons.call_merge),

  /// The fourth grouped section (research/20 K4): wiki pages of the
  /// project, or of the whole organization in the All scope.
  wiki('wiki', 'Wiki', Icons.menu_book_outlined);

  const SearchKind(this.wire, this.label, this.icon);

  final String wire;
  final String label;
  final IconData icon;

  static SearchKind? fromWire(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

/// One kind's slice of the screen: what is shown, where it came from and
/// what went wrong.
class _Slice<T> {
  T? value;
  String? error;
  bool loading = false;

  /// When what is on screen was read, while it is the cached copy; null
  /// once the live answer has replaced it.
  DateTime? cachedAt;

  /// The live call could not be made at all, so the cached copy stays and
  /// says so.
  bool offline = false;

  void reset() {
    value = null;
    error = null;
    loading = false;
    cachedAt = null;
    offline = false;
  }
}

/// Search across a project or the whole organization (research/15).
///
/// The grouped view shows the first few work items, code hits and pull
/// requests with a See all per kind; `kind` in the route opens one kind's
/// full list, which pages, filters by the facet chips and can be sorted.
///
/// Three things shape the code below:
///
/// * **The answer on screen belongs to one query.** Every send takes a
///   sequence number and a late answer to an older query is dropped, so a
///   slow work item search cannot overwrite what the user has since typed
///   (decision D8).
/// * **Cached first, live second.** Each API kind paints the cached answer
///   for exactly this query before the call is made and says how old it is;
///   offline, that copy is what stays.
/// * **Pull requests are local.** They are matched over the org's active
///   list the inbox already caches, so they appear while the API kinds are
///   still in flight (decision D7).
class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.org,
    required this.project,
    this.initialQuery,
    this.scope = SearchScope.project,
    this.kind,
  });

  final String org;
  final String project;
  final String? initialQuery;
  final SearchScope scope;

  /// Null for the grouped view; a kind for its See-all list.
  final SearchKind? kind;

  /// Decision D8: 400 ms after the last keystroke.
  static const debounce = Duration(milliseconds: 400);

  /// Decision D9: five rows per section in the grouped view.
  static const groupedRows = 5;

  /// Flutter's own cap on an app bar title's text scale
  /// (`_kMaxTitleTextScaleFactor`): the bar is chrome, and its title stops
  /// growing here however large the system type is.
  static const titleScaleCap = 1.34;

  /// The app bar holds a text field, which a fixed 56 dp toolbar clips at
  /// accessibility text sizes. It grows with the type up to the same cap
  /// the `AppBar` puts on the title itself — past that the field no longer
  /// grows either, and a taller bar would only be empty space (measured on
  /// the iPhone at xxxL, 2026-09-14).
  static double toolbarHeightFor(BuildContext context) {
    final scale = math.min(
      MediaQuery.textScalerOf(context).scale(14) / 14,
      titleScaleCap,
    );
    return math.max(
      kToolbarHeight,
      (kToolbarHeight - Spacing.sm) * scale + Spacing.sm,
    );
  }

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  final _scroll = ScrollController();
  Timer? _debounce;

  late SearchScope _scope = widget.scope;
  SearchOrder _order = SearchOrder.relevance;
  final _types = <String>{};
  final _states = <String>{};

  /// The chips to offer. Kept from the last answer to an unfiltered query:
  /// the service returns facets for the query as filtered, so reading them
  /// from every answer would make the chips the user just picked the only
  /// ones left.
  SearchFacets _facets = SearchFacets.empty;

  /// Rises with every send; an answer whose number is no longer current is
  /// an answer to a query that has been typed over.
  int _seq = 0;

  /// True while what is typed has not been searched yet: the debounce is
  /// still running, or the page was opened with a term and its first send
  /// is a post-frame callback away.
  ///
  /// Without it the sections draw as "No work items / No code results / No
  /// pull requests" for those 400 ms — the page answering a question it has
  /// not asked (found on the iPhone, 2026-09-14).
  late bool _pending = SearchRepository.isSearchable(widget.initialQuery ?? '');

  /// The term the results on screen belong to.
  String _query = '';
  bool _loadingMore = false;
  List<String> _recents = const [];

  final _workItems = _Slice<SearchResults<WorkItemSearchHit>>();
  final _code = _Slice<CodeSearchResults>();
  final _pullRequests = _Slice<SearchResults<PullRequestSearchHit>>();

  final _wiki = _Slice<SearchResults<WikiSearchHit>>();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadRecents();
      final initial = widget.initialQuery ?? '';
      if (SearchRepository.isSearchable(initial)) _run(initial);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  SearchRepository get _repository => context.read<SearchRepository>();
  SearchRecents get _recentsStore => context.read<SearchRecents>();

  /// Null in the All-projects scope, which is how the repository asks the
  /// service for the whole organization.
  String? get _projectFilter =>
      _scope == SearchScope.project ? widget.project : null;

  bool _shows(SearchKind kind) => widget.kind == null || widget.kind == kind;

  /// True while [seq] is still the query on screen and the page is alive.
  bool _current(int seq) => mounted && seq == _seq;

  void _apply(int seq, VoidCallback change) {
    if (_current(seq)) setState(change);
  }

  Future<void> _loadRecents() async {
    final recents = await _recentsStore.list(widget.org);
    if (mounted) setState(() => _recents = recents);
  }

  // ------------------------------------------------------------- typing

  void _onChanged(String text) {
    _debounce?.cancel();
    if (!SearchRepository.isSearchable(text)) {
      // Nothing is sent under three characters, and whatever an earlier
      // query left on screen no longer belongs to what is in the field.
      _seq++;
      setState(() {
        _pending = false;
        _query = '';
        _workItems.reset();
        _code.reset();
        _pullRequests.reset();
        _wiki.reset();
      });
      return;
    }
    // The clear button, the recents/hint switch, and the sections waiting
    // for the debounce rather than claiming to have found nothing.
    setState(() => _pending = true);
    _debounce = Timer(SearchPage.debounce, () => _run(text));
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  void _useRecent(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _debounce?.cancel();
    _run(text);
  }

  /// Drops one recent. The list on screen changes in the same frame the
  /// swipe ends: a `Dismissible` that is still in the tree after its
  /// dismissal asserts, and the write to preferences is a frame or two
  /// later.
  void _removeRecent(String text) {
    setState(() => _recents = [..._recents]..remove(text));
    unawaited(
      _recentsStore.remove(widget.org, text).then((kept) {
        if (mounted) setState(() => _recents = kept);
      }),
    );
  }

  Future<void> _clearRecents() async {
    await _recentsStore.clear(widget.org);
    if (mounted) setState(() => _recents = const []);
  }

  void _setScope(SearchScope scope) {
    if (scope == _scope) return;
    setState(() {
      _scope = scope;
      _workItems.reset();
      _code.reset();
      _pullRequests.reset();
      _wiki.reset();
      _facets = SearchFacets.empty;
    });
    _debounce?.cancel();
    if (SearchRepository.isSearchable(_controller.text)) {
      _run(_controller.text);
    }
  }

  void _setOrder(SearchOrder order) {
    if (order == _order) return;
    setState(() {
      _order = order;
      _workItems.reset();
    });
    if (SearchRepository.isSearchable(_controller.text)) {
      _run(_controller.text);
    }
  }

  void _toggleFacet(Set<String> set, String value) {
    setState(() {
      if (!set.remove(value)) set.add(value);
      _workItems.reset();
    });
    if (SearchRepository.isSearchable(_controller.text)) {
      _run(_controller.text);
    }
  }

  // ------------------------------------------------------------ searching

  /// Sends the query every shown kind needs. [force] skips the cached paint
  /// (pull-to-refresh asks for the live answer).
  Future<void> _run(String text, {bool force = false}) async {
    _debounce?.cancel();
    final term = text.trim();
    if (!SearchRepository.isSearchable(term)) return;
    final seq = ++_seq;
    setState(() {
      _pending = false;
      _query = term;
      for (final entry in {
        SearchKind.workItems: _workItems,
        SearchKind.code: _code,
        SearchKind.pullRequests: _pullRequests,
        SearchKind.wiki: _wiki,
      }.entries) {
        entry.value.error = null;
        entry.value.offline = false;
        // Only what this view shows is in flight; a See-all view never
        // sends the other two and their slices must not be left waiting.
        entry.value.loading = _shows(entry.key);
      }
    });
    // A query is remembered when it is sent, not per keystroke (D5).
    final store = _recentsStore;
    unawaited(
      store.add(widget.org, term).then((kept) {
        if (mounted) setState(() => _recents = kept);
      }),
    );
    await Future.wait([
      if (_shows(SearchKind.workItems)) _runWorkItems(seq, term, force: force),
      if (_shows(SearchKind.code)) _runCode(seq, term, force: force),
      if (_shows(SearchKind.pullRequests)) _runPullRequests(seq, term),
      if (_shows(SearchKind.wiki)) _runWiki(seq, term, force: force),
    ]);
  }

  Future<void> _runWorkItems(int seq, String term, {bool force = false}) async {
    final repository = _repository;
    Future<SearchResults<WorkItemSearchHit>> live() =>
        repository.searchWorkItems(
          widget.org,
          project: _projectFilter,
          text: term,
          types: _types.toList(),
          states: _states.toList(),
          order: _order,
        );
    if (!force) {
      final cached = await repository.cachedWorkItems(
        widget.org,
        project: _projectFilter,
        text: term,
        types: _types.toList(),
        states: _states.toList(),
        order: _order,
      );
      if (cached != null) {
        _apply(seq, () {
          _workItems.value = cached.value;
          _workItems.cachedAt = cached.fetchedAt;
        });
      }
    }
    try {
      final results = await live();
      _apply(seq, () {
        _workItems.value = results;
        _workItems.cachedAt = null;
        _workItems.offline = false;
        if (_types.isEmpty && _states.isEmpty && !results.facets.isEmpty) {
          _facets = results.facets;
        }
      });
    } on AdoAuthException catch (e) {
      _authRequired(e);
    } on AdoNetworkException catch (e) {
      _offline(seq, _workItems, e);
    } on AdoException catch (e) {
      _apply(seq, () => _workItems.error = e.message);
    } finally {
      _apply(seq, () => _workItems.loading = false);
    }
  }

  Future<void> _runCode(int seq, String term, {bool force = false}) async {
    final repository = _repository;
    if (!force) {
      final cached = await repository.cachedCode(
        widget.org,
        project: _projectFilter,
        text: term,
      );
      if (cached != null) {
        _apply(seq, () {
          _code.value = cached.value;
          _code.cachedAt = cached.fetchedAt;
        });
      }
    }
    try {
      final results = await repository.searchCode(
        widget.org,
        project: _projectFilter,
        text: term,
      );
      _apply(seq, () {
        _code.value = results;
        _code.cachedAt = null;
        _code.offline = false;
        // infoCode is the service saying it could not run the query
        // (no index yet, a bad wildcard): its own words, not an error.
        _code.error = results.problem;
      });
    } on AdoAuthException catch (e) {
      _authRequired(e);
    } on AdoNetworkException catch (e) {
      _offline(seq, _code, e);
    } on AdoException catch (e) {
      // CodeSearchUnavailable carries its own message about the extension.
      _apply(seq, () => _code.error = e.message);
    } finally {
      _apply(seq, () => _code.loading = false);
    }
  }

  Future<void> _runPullRequests(int seq, String term) async {
    final repository = _repository;
    // The local match over the cached active list is instant; the fetched
    // one replaces it a moment later.
    final cached = await repository.cachedPullRequests(
      widget.org,
      project: _projectFilter,
      text: term,
    );
    if (cached != null) {
      _apply(seq, () {
        _pullRequests.value = cached;
        _pullRequests.cachedAt = null;
      });
    }
    try {
      final results = await repository.searchPullRequests(
        widget.org,
        project: _projectFilter,
        text: term,
      );
      _apply(seq, () {
        _pullRequests.value = results;
        _pullRequests.offline = false;
      });
    } on AdoAuthException catch (e) {
      _authRequired(e);
    } on AdoNetworkException catch (e) {
      _offline(seq, _pullRequests, e);
    } on AdoException catch (e) {
      _apply(seq, () => _pullRequests.error = e.message);
    } finally {
      _apply(seq, () => _pullRequests.loading = false);
    }
  }

  /// `POST wikisearchresults`, cached copy first (research/20 K4). A 404
  /// from the search host is the Code Search extension missing, which the
  /// repository turns into [CodeSearchUnavailable] and its message says.
  Future<void> _runWiki(int seq, String term, {bool force = false}) async {
    final repository = _repository;
    if (!force) {
      final cached = await repository.cachedWiki(
        widget.org,
        project: _projectFilter,
        text: term,
      );
      if (cached != null) {
        _apply(seq, () {
          _wiki.value = cached.value;
          _wiki.cachedAt = cached.fetchedAt;
        });
      }
    }
    try {
      final results = await repository.searchWiki(
        widget.org,
        project: _projectFilter,
        text: term,
      );
      _apply(seq, () {
        _wiki.value = results;
        _wiki.cachedAt = null;
        _wiki.offline = false;
        _wiki.error = null;
      });
    } on AdoAuthException catch (e) {
      _authRequired(e);
    } on AdoNetworkException catch (e) {
      _offline(seq, _wiki, e);
    } on AdoException catch (e) {
      // CodeSearchUnavailable carries its own message about the extension.
      _apply(seq, () => _wiki.error = e.message);
    } finally {
      _apply(seq, () => _wiki.loading = false);
    }
  }

  void _offline(int seq, _Slice<Object?> slice, AdoNetworkException e) =>
      _apply(seq, () {
        if (slice.value == null) {
          slice.error = e.message;
        } else {
          slice.offline = true;
        }
      });

  void _authRequired(AdoAuthException e) {
    if (!mounted) return;
    context.read<AuthBloc>().add(
      AuthInteractionRequired(
        e.message,
        accountId: AccountScope.maybeOf(context),
      ),
    );
  }

  // --------------------------------------------------------------- paging

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore) return;
    if (_scroll.position.extentAfter >= 600) return;
    final kind = widget.kind;
    if (kind == SearchKind.workItems && (_workItems.value?.hasMore ?? false)) {
      _more();
    } else if (kind == SearchKind.code) {
      final have = _code.value;
      if (have != null && have.hits.length < have.count) _more();
    } else if (kind == SearchKind.wiki && (_wiki.value?.hasMore ?? false)) {
      _more();
    }
  }

  /// The next page of the See-all list, appended to what is shown.
  ///
  /// The page belongs to the query that asked for it: if the term, the
  /// scope, a chip or the order changed while it was in flight, the
  /// sequence number has moved on and the rows are dropped.
  Future<void> _more() async {
    final kind = widget.kind;
    if (kind == null || _loadingMore) return;
    final seq = _seq;
    setState(() => _loadingMore = true);
    final repository = _repository;
    try {
      if (kind == SearchKind.workItems) {
        final have = _workItems.value;
        if (have == null) return;
        final next = await repository.searchWorkItems(
          widget.org,
          project: _projectFilter,
          text: _query,
          types: _types.toList(),
          states: _states.toList(),
          order: _order,
          skip: have.skip + have.items.length,
        );
        if (!_current(seq)) return;
        setState(() {
          _workItems.value = SearchResults<WorkItemSearchHit>(
            items: [...have.items, ...next.items],
            total: next.total,
            facets: have.facets,
            skip: have.skip,
          );
        });
      } else if (kind == SearchKind.code) {
        final have = _code.value;
        if (have == null) return;
        final next = await repository.searchCode(
          widget.org,
          project: _projectFilter,
          text: _query,
          skip: have.hits.length,
        );
        if (!_current(seq)) return;
        setState(() {
          _code.value = CodeSearchResults(
            count: next.count,
            hits: [...have.hits, ...next.hits],
            infoCode: next.infoCode,
          );
        });
      } else if (kind == SearchKind.wiki) {
        final have = _wiki.value;
        if (have == null) return;
        final next = await repository.searchWiki(
          widget.org,
          project: _projectFilter,
          text: _query,
          skip: have.skip + have.items.length,
        );
        if (!_current(seq)) return;
        setState(() {
          _wiki.value = SearchResults<WikiSearchHit>(
            items: [...have.items, ...next.items],
            total: next.total,
            facets: have.facets,
            skip: have.skip,
          );
        });
      }
    } on AdoAuthException catch (e) {
      _authRequired(e);
    } on AdoException catch (e) {
      if (mounted) {
        setState(() {
          if (kind == SearchKind.workItems) {
            _workItems.error = e.message;
          } else if (kind == SearchKind.wiki) {
            _wiki.error = e.message;
          } else {
            _code.error = e.message;
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // ----------------------------------------------------------------- taps

  void _openSeeAll(SearchKind kind) => context.push(
    Routes.search(
      AccountScope.of(context),
      widget.org,
      widget.project,
      q: _query,
      scope: _scope.wire,
      kind: kind.wire,
    ),
  );

  void _openWorkItem(WorkItemSearchHit hit) => context.push(
    Routes.workItem(
      AccountScope.of(context),
      widget.org,
      // The hit's own project, so an All-projects result opens where it
      // lives rather than in the project being searched from.
      hit.projectName.isEmpty ? widget.project : hit.projectName,
      '${hit.id}',
    ),
  );

  void _openCode(CodeSearchHit hit) => openCodeHit(
    context,
    org: widget.org,
    project: widget.project,
    hit: hit,
    query: _query,
  );

  /// Opens the page by its wiki id and page path. An org-wide hit carries
  /// its own project GUID, so it opens in the project it lives in rather
  /// than the one being searched from (K4).
  void _openWiki(WikiSearchHit hit) => context.push(
    Routes.wikiPage(
      AccountScope.of(context),
      widget.org,
      hit.projectId.isNotEmpty
          ? hit.projectId
          : (hit.projectName.isEmpty ? widget.project : hit.projectName),
      hit.wikiId,
      path: hit.pagePath,
      version: hit.version.isEmpty ? null : hit.version,
    ),
  );

  void _openPullRequest(PullRequestSearchHit hit) => context.push(
    Routes.pullRequest(
      AccountScope.of(context),
      widget.org,
      '${hit.pullRequest.id}',
    ),
  );

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final compact = context.breakpoint.isCompact;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: SearchPage.toolbarHeightFor(context),
        title: TextField(
          controller: _controller,
          // Opened empty, the field is what the user came for; opened with
          // a term (a See-all push, a deep link) the results are.
          autofocus: (widget.initialQuery ?? '').trim().isEmpty,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (text) => _run(text),
          decoration: InputDecoration(
            hintText: 'Search work items, code, pull requests, wiki',
            hintMaxLines: 1,
            isDense: true,
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.clear),
                    onPressed: _clear,
                  ),
          ),
        ),
        actions: [
          if (widget.kind == SearchKind.workItems)
            PopupMenuButton<SearchOrder>(
              tooltip: 'Sort',
              icon: const Icon(Icons.sort),
              offset: kTrailingMenuOffset,
              onSelected: _setOrder,
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: SearchOrder.relevance,
                  checked: _order == SearchOrder.relevance,
                  child: const Text('Relevance'),
                ),
                CheckedPopupMenuItem(
                  value: SearchOrder.changedDate,
                  checked: _order == SearchOrder.changedDate,
                  child: const Text('Changed date'),
                ),
              ],
            ),
          // The scope switch stays rightmost, as every view switch does.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            child: SegmentedButton<SearchScope>(
              segments: [
                ButtonSegment(
                  value: SearchScope.project,
                  label: compact ? null : const Text('Project'),
                  icon: const Icon(Icons.folder_outlined),
                  tooltip: 'This project',
                ),
                ButtonSegment(
                  value: SearchScope.org,
                  label: compact ? null : const Text('All'),
                  icon: const Icon(Icons.language),
                  tooltip: 'All projects',
                ),
              ],
              selected: {_scope},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onSelectionChanged: (selection) => _setScope(selection.first),
            ),
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _run(_controller.text, force: true),
        child: ContentColumn(
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: scrollEndPadding(context),
            children: _body(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typed = _controller.text.trim();
    final busy =
        _pending ||
        _workItems.loading ||
        _code.loading ||
        _pullRequests.loading ||
        _wiki.loading;
    // Every row of this list carries a key. The list's children come and go
    // — the progress bar at the top most of all — and a `ListView` whose
    // children have no keys reuses its elements by position, so one row
    // appearing at the top re-slots every section below it. The iPad showed
    // the grouped view stuck with only its first section, with the other
    // two neither built nor scrollable to (2026-09-14); keys make the reuse
    // follow the section rather than the slot.
    return [
      if (busy) const LinearProgressIndicator(key: ValueKey('search-busy')),
      if (typed.isEmpty)
        ..._recentsBlock(context)
      else if (!SearchRepository.isSearchable(typed))
        Padding(
          key: const ValueKey('search-too-short'),
          padding: const EdgeInsets.all(Spacing.xl),
          child: Text(
            'Type at least ${SearchRepository.minLength} characters.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        )
      else if (widget.kind == null)
        ..._grouped(context)
      else
        ..._seeAll(context, widget.kind!),
    ];
  }

  // -------------------------------------------------------------- recents

  List<Widget> _recentsBlock(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (_recents.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Text(
            'Search work items, code, pull requests and wiki pages in '
            '${widget.project}. Switch to All to search every project.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.md,
          Spacing.sm,
          0,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Recent',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
            TextButton(onPressed: _clearRecents, child: const Text('Clear')),
          ],
        ),
      ),
      for (final recent in _recents)
        Dismissible(
          key: ValueKey('recent:$recent'),
          direction: DismissDirection.endToStart,
          background: ColoredBox(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.delete_outline,
                  color: scheme.onErrorContainer,
                ),
              ),
            ),
          ),
          onDismissed: (_) => _removeRecent(recent),
          child: ListTile(
            leading: const Icon(Icons.history),
            title: Text(recent, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _useRecent(recent),
          ),
        ),
    ];
  }

  // -------------------------------------------------------------- grouped

  List<Widget> _grouped(BuildContext context) {
    final workItems = _workItems.value;
    final code = _code.value;
    final pullRequests = _pullRequests.value;
    final wiki = _wiki.value;
    // Keyed by kind, not by position: see [_body].
    Widget keyed(SearchKind kind, Widget child) => KeyedSubtree(
      key: ValueKey('search-section-${kind.wire}'),
      child: child,
    );
    return [
      keyed(
        SearchKind.workItems,
        _section(
          context,
          kind: SearchKind.workItems,
          slice: _workItems,
          total: workItems?.total ?? 0,
          empty: 'No work items',
          rows: [
            for (final hit
                in (workItems?.items ?? const <WorkItemSearchHit>[]).take(
                  SearchPage.groupedRows,
                ))
              WorkItemHitTile(
                hit: hit,
                showProject: _scope == SearchScope.org,
                onTap: () => _openWorkItem(hit),
              ),
          ],
        ),
      ),
      keyed(
        SearchKind.code,
        _section(
          context,
          kind: SearchKind.code,
          slice: _code,
          total: code?.count ?? 0,
          empty: 'No code results',
          rows: codeHitRows(
            context: context,
            hits: (code?.hits ?? const <CodeSearchHit>[])
                .take(SearchPage.groupedRows)
                .toList(),
            grouped: false,
            showProject: _scope == SearchScope.org,
            onTap: _openCode,
          ),
        ),
      ),
      keyed(
        SearchKind.pullRequests,
        _section(
          context,
          kind: SearchKind.pullRequests,
          slice: _pullRequests,
          total: pullRequests?.total ?? 0,
          empty: 'No pull requests',
          rows: [
            for (final hit
                in (pullRequests?.items ?? const <PullRequestSearchHit>[]).take(
                  SearchPage.groupedRows,
                ))
              PullRequestTile(
                pr: hit.pullRequest,
                showProject: _scope == SearchScope.org,
                onTap: () => _openPullRequest(hit),
              ),
          ],
        ),
      ),
      keyed(
        SearchKind.wiki,
        _section(
          context,
          kind: SearchKind.wiki,
          slice: _wiki,
          total: wiki?.total ?? 0,
          empty: 'No wiki pages',
          rows: [
            for (final hit in orderWikiHits(
              wiki?.items ?? const <WikiSearchHit>[],
            ).take(SearchPage.groupedRows))
              WikiHitTile(
                hit: hit,
                showProject: _scope == SearchScope.org,
                onTap: () => _openWiki(hit),
              ),
          ],
        ),
      ),
    ];
  }

  /// One kind's section: the header with its total and See all, then its
  /// rows, its error or the one quiet line an empty section shrinks to.
  Widget _section(
    BuildContext context, {
    required SearchKind kind,
    required _Slice<Object?> slice,
    required int total,
    required String empty,
    required List<Widget> rows,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    if (slice.error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          _header(context, kind: kind, total: null, seeAll: false),
          ListTile(
            dense: true,
            leading: Icon(Icons.error_outline, color: scheme.error, size: 20),
            title: Text(slice.error!, style: theme.textTheme.bodySmall),
          ),
        ],
      );
    }
    // `_pending` counts as loading: between the third character and the
    // debounce nothing has been asked yet, so an empty slice must not be
    // drawn as "No work items".
    if ((slice.loading || _pending) && rows.isEmpty) {
      return _searchingLine(context, kind);
    }
    if (rows.isEmpty) {
      // An empty section is one quiet line, not a header and a blank.
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          Spacing.sm,
        ),
        child: Text(empty, style: quiet),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        _header(context, kind: kind, total: total, seeAll: total > rows.length),
        _cacheLine(context, slice),
        ...rows,
      ],
    );
  }

  /// "Searching Work items…", shown while a kind is in flight and while the
  /// debounce is still running.
  Widget _searchingLine(BuildContext context, SearchKind kind) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Text(
              'Searching ${kind.label}…',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The section title, the total and See all. Past 1.5x text the action
  /// drops below the title, as every other section header in the app does
  /// (DESIGN.md: a title and an action cannot share a line at xxxL).
  Widget _header(
    BuildContext context, {
    required SearchKind kind,
    required int? total,
    required bool seeAll,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = Text(
      total == null ? kind.label : '${kind.label} · ${formatCount(total)}',
      style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary),
    );
    final leading = Icon(kind.icon, size: 18, color: scheme.primary);
    final action = seeAll
        ? TextButton(
            onPressed: () => _openSeeAll(kind),
            child: const Text('See all'),
          )
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.sm, 0),
      child: Builder(
        builder: (context) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          if (scale > 1.5 && action != null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading,
                    const SizedBox(width: Spacing.sm),
                    Expanded(child: title),
                  ],
                ),
                Align(alignment: Alignment.centerLeft, child: action),
              ],
            );
          }
          return Row(
            children: [
              leading,
              const SizedBox(width: Spacing.sm),
              Expanded(child: title),
              ?action,
            ],
          );
        },
      ),
    );
  }

  /// "cached · 3m" while the copy on screen came from the cache, and the
  /// offline note when the live call could not be made at all.
  Widget _cacheLine(BuildContext context, _Slice<Object?> slice) {
    final at = slice.cachedAt;
    if (at == null && !slice.offline) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final age = at == null ? '' : ' · ${relativeTime(at)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xs, Spacing.lg, 0),
      child: Row(
        children: [
          Icon(
            slice.offline ? Icons.cloud_off_outlined : Icons.history_toggle_off,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Spacing.xs),
          Expanded(
            child: Text(
              slice.offline
                  ? 'offline · showing the cached copy$age'
                  : 'cached$age',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- see all

  List<Widget> _seeAll(BuildContext context, SearchKind kind) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final slice = switch (kind) {
      SearchKind.workItems => _workItems as _Slice<Object?>,
      SearchKind.code => _code as _Slice<Object?>,
      SearchKind.pullRequests => _pullRequests as _Slice<Object?>,
      SearchKind.wiki => _wiki as _Slice<Object?>,
    };
    final total = switch (kind) {
      SearchKind.workItems => _workItems.value?.total ?? 0,
      SearchKind.code => _code.value?.count ?? 0,
      SearchKind.pullRequests => _pullRequests.value?.total ?? 0,
      SearchKind.wiki => _wiki.value?.total ?? 0,
    };
    final rows = switch (kind) {
      SearchKind.workItems => [
        for (final hit
            in _workItems.value?.items ?? const <WorkItemSearchHit>[])
          WorkItemHitTile(
            hit: hit,
            showProject: _scope == SearchScope.org,
            onTap: () => _openWorkItem(hit),
          ),
      ],
      SearchKind.code => codeHitRows(
        context: context,
        hits: _code.value?.hits ?? const <CodeSearchHit>[],
        showProject: _scope == SearchScope.org,
        onTap: _openCode,
      ),
      SearchKind.pullRequests => [
        for (final hit
            in _pullRequests.value?.items ?? const <PullRequestSearchHit>[])
          PullRequestTile(
            pr: hit.pullRequest,
            showProject: _scope == SearchScope.org,
            onTap: () => _openPullRequest(hit),
          ),
      ],
      SearchKind.wiki => [
        for (final hit in orderWikiHits(
          _wiki.value?.items ?? const <WikiSearchHit>[],
        ))
          WikiHitTile(
            hit: hit,
            showProject: _scope == SearchScope.org,
            onTap: () => _openWiki(hit),
          ),
      ],
    };
    return [
      // Keyed like the grouped view, and for the same reason ([_body]):
      // the chips row and the loading spinner come and go around rows that
      // must not be re-slotted under them.
      if (kind == SearchKind.workItems) ..._facetChips(context),
      if (slice.error != null)
        ListTile(
          key: const ValueKey('search-head'),
          leading: Icon(Icons.error_outline, color: scheme.error),
          title: Text(slice.error!),
        )
      else if ((slice.loading || _pending) && rows.isEmpty)
        // Nothing has been asked yet (the debounce) or nothing has come
        // back: either way the count line would be a false "No results".
        KeyedSubtree(
          key: const ValueKey('search-head'),
          child: _searchingLine(context, kind),
        )
      else ...[
        Padding(
          key: const ValueKey('search-head'),
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.md,
            Spacing.lg,
            0,
          ),
          child: Text(
            total == 0
                ? 'No ${kind.label.toLowerCase()} for "$_query".'
                : '${formatCount(total)} '
                      '${total == 1 ? 'result' : 'results'} for "$_query"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        KeyedSubtree(
          key: const ValueKey('search-cache-line'),
          child: _cacheLine(context, slice),
        ),
      ],
      ...rows,
      if (_loadingMore)
        const Padding(
          key: ValueKey('search-loading-more'),
          padding: EdgeInsets.all(Spacing.lg),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          ),
        ),
    ];
  }

  /// Decision D4: the type and state facets as multi-select chips under the
  /// field, each with the count the service reported.
  List<Widget> _facetChips(BuildContext context) {
    final types = _facets.types;
    final states = _facets.states;
    if (types.isEmpty && states.isEmpty) return const [];
    return [
      SizedBox(
        key: const ValueKey('search-chips'),
        // The row follows the text scale: a fixed height clipped the chip
        // labels at the largest sizes (the work item list, iPad).
        height: MediaQuery.textScalerOf(context).scale(48).clamp(48.0, 96.0),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.xs,
          ),
          children: [
            for (final facet in types) ...[
              FilterChip(
                label: Text('${facet.name} (${formatCount(facet.count)})'),
                selected: _types.contains(facet.name),
                onSelected: (_) => _toggleFacet(_types, facet.name),
              ),
              const SizedBox(width: Spacing.sm),
            ],
            for (final facet in states) ...[
              FilterChip(
                label: Text('${facet.name} (${formatCount(facet.count)})'),
                selected: _states.contains(facet.name),
                onSelected: (_) => _toggleFacet(_states, facet.name),
              ),
              const SizedBox(width: Spacing.sm),
            ],
          ],
        ),
      ),
    ];
  }
}
