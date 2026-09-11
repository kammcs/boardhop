import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/ado_tiles.dart';
import '../../core/util/format.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import '../shared/widgets/ado_tile.dart';
import 'widgets/repo_visuals.dart';

/// The Repos tab: every repository of the project with its language,
/// default branch and size; favorites (the Azure DevOps star) first, then
/// the ones opened recently on this device, then the rest, with disabled
/// repositories badged at the bottom.
class ReposPage extends StatefulWidget {
  const ReposPage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  State<ReposPage> createState() => _ReposPageState();
}

class _ReposPageState extends State<ReposPage> {
  List<GitRepository> _repos = const [];
  Map<String, List<RepoLanguage>> _languages = const {};
  Set<String> _favorites = const {};
  List<String> _recents = const [];
  DateTime? _shownAt;
  String? _error;
  bool _loading = false;
  bool _loadedOnce = false;
  String _query = '';
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _list = ListController();

  /// Row index of each repository in the list as last built, for the
  /// "Show" action of the favorites toast.
  Map<String, int> _rowOf = const {};

  /// Repository whose row is tinted after a scroll-to, briefly.
  String? _flashId;
  Timer? _flashTimer;

  RepoRepository get _repo => context.read<RepoRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _list.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = _repo;
    final org = widget.org;
    final project = widget.project;
    if (!_loadedOnce) {
      final cached = await repo.cachedList(org, project);
      final languages = await repo.cachedLanguages(org, project);
      final recents = await repo.recents(org, project);
      Map<String, String>? favorites;
      if (cached != null && cached.items.isNotEmpty) {
        favorites = await repo.cachedFavorites(
          org,
          cached.items.first.projectId,
        );
      }
      if (mounted && cached != null) {
        setState(() {
          _repos = cached.items;
          _shownAt = cached.fetchedAt;
          _languages = languages ?? const {};
          _favorites = favorites?.keys.toSet() ?? const {};
          _recents = recents;
          _loadedOnce = true;
        });
      }
    }
    try {
      final repos = await repo.list(org, project);
      if (mounted) {
        setState(() {
          _repos = repos;
          _shownAt = DateTime.now();
          _recents = List.of(_recents);
        });
      }
      // Languages and favorites are decoration: each may fail on its own.
      final projectId = repos.isEmpty ? null : repos.first.projectId;
      final results = await Future.wait<Object?>([
        repo.languages(org, project).catchError((Object e) {
          debugPrintError('languages', e);
          return <String, List<RepoLanguage>>{};
        }),
        if (projectId != null)
          repo.favorites(org, projectId).catchError((Object e) {
            debugPrintError('favorites', e);
            return <String, String>{};
          }),
      ]);
      if (mounted) {
        setState(() {
          final languages = results[0] as Map<String, List<RepoLanguage>>;
          if (languages.isNotEmpty) _languages = languages;
          if (results.length > 1) {
            _favorites = (results[1] as Map<String, String>).keys.toSet();
          }
        });
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
      if (mounted) {
        setState(() {
          _loading = false;
          _loadedOnce = true;
        });
      }
    }
  }

  static void debugPrintError(String what, Object e) {
    debugPrint('repos $what: $e');
  }

  Future<void> _toggleFavorite(GitRepository r) async {
    final wasFavorite = _favorites.contains(r.id);
    setState(() {
      _favorites = wasFavorite
          ? (_favorites.toSet()..remove(r.id))
          : {..._favorites, r.id};
    });
    // The row has just moved to another section, usually off screen: the
    // toast says where it went and "Show" scrolls there.
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          wasFavorite
              ? '${r.name} removed from favorites'
              : '${r.name} added to favorites',
        ),
        action: SnackBarAction(label: 'Show', onPressed: () => _reveal(r.id)),
        duration: const Duration(seconds: 6),
        // Flutter 3.47 keeps a snackbar with an action open until it is
        // dismissed, which also blocks every later snackbar; this one is a
        // transient confirmation.
        persist: false,
      ),
    );
    try {
      await _repo.setFavorite(org: widget.org, repo: r, favorite: !wasFavorite);
    } on AdoException catch (e) {
      if (!mounted) return;
      setState(() {
        _favorites = wasFavorite
            ? {..._favorites, r.id}
            : (_favorites.toSet()..remove(r.id));
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ReposPageErrors.favoriteError(e))),
        );
    }
  }

  /// Scrolls the repository's row into view and tints it for a moment.
  void _reveal(String repoId) {
    final index = _rowOf[repoId];
    if (index == null || !mounted || !_scroll.hasClients) return;
    _list.animateToItem(
      index: index,
      scrollController: _scroll,
      alignment: 0.25,
      duration: (distance) =>
          Duration(milliseconds: (distance / 3).clamp(250, 700).round()),
      curve: (_) => Curves.easeOutCubic,
    );
    _flashTimer?.cancel();
    setState(() => _flashId = repoId);
    _flashTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  void _open(GitRepository r) {
    _repo.markOpened(widget.org, widget.project, r.id);
    setState(() {
      _recents = [
        r.id,
        ..._recents.where((id) => id != r.id),
      ].take(RepoRepository.maxRecents).toList();
    });
    context.push(
      '${projectRoute(context, widget.org, widget.project)}'
      '/repos/${Uri.encodeComponent(r.name)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sections = RepoSections.build(
      _repos,
      favoriteIds: _favorites,
      recentIds: _recents,
      query: _query,
    );
    final rows = _rows(context, sections);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project, overflow: TextOverflow.ellipsis),
            Text(
              'Repositories',
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
        actions: [
          IconButton(
            tooltip: 'Search code',
            icon: const Icon(Icons.manage_search),
            onPressed: () => context.push(
              '${projectRoute(context, widget.org, widget.project)}/code-search',
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ContentColumn(
          child: SuperListView.builder(
            controller: _scroll,
            listController: _list,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: rows.length,
            itemBuilder: (context, i) => rows[i],
          ),
        ),
      ),
    );
  }

  /// Every row of the list in order; fills [_rowOf] so a repository's row
  /// can be scrolled to by index even while it is not built.
  List<Widget> _rows(BuildContext context, RepoSections sections) {
    final scheme = Theme.of(context).colorScheme;
    final rowOf = <String, int>{};
    final rows = <Widget>[
      if (_loading) const LinearProgressIndicator(),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
          Spacing.lg,
          Spacing.xs,
        ),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Filter repositories',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
            isDense: true,
          ),
        ),
      ),
      if (_error != null)
        ListTile(
          leading: Icon(Icons.error_outline, color: scheme.error),
          title: Text(_error!),
          subtitle: _shownAt == null || _repos.isEmpty
              ? null
              : Text('Showing the list from ${relativeTime(_shownAt)}.'),
        ),
      if (sections.isEmpty && _loadedOnce && !_loading)
        Padding(
          padding: const EdgeInsets.all(Spacing.xl),
          child: Text(
            _query.isEmpty
                ? 'This project has no repositories.'
                : 'No repository matches "$_query".',
            textAlign: TextAlign.center,
          ),
        ),
    ];
    void section(String? label, List<GitRepository> repos) {
      if (repos.isEmpty) return;
      if (label != null) rows.add(_SectionLabel(label));
      for (final r in repos) {
        rowOf[r.id] = rows.length;
        rows.add(_tile(r));
      }
    }

    section('Favorites', sections.favorites);
    section('Recent', sections.recents);
    section(
      sections.favorites.isNotEmpty || sections.recents.isNotEmpty
          ? 'All repositories'
          : null,
      sections.all,
    );
    section('Disabled', sections.inactive);
    _rowOf = rowOf;
    return rows;
  }

  Widget _tile(GitRepository r) => RepoTile(
    key: ValueKey(r.id),
    repo: r,
    languages: _languages[r.name] ?? const [],
    favorite: _favorites.contains(r.id),
    flash: _flashId == r.id,
    onFavorite: r.isActive ? () => _toggleFavorite(r) : null,
    onTap: r.isActive ? () => _open(r) : null,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.lg,
      Spacing.lg,
      Spacing.xs,
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// Messages shared by the repository pages.
abstract final class ReposPageErrors {
  /// Favorites are the only write that needs a scope beyond `vso.code`:
  /// a 401 here means the app registration lacks `vso.profile_write`.
  static String favoriteError(AdoException e) => e is AdoAuthException
      ? 'Favorites need the "vso.profile_write" permission on the Boardhop '
            'app registration.'
      : e.message;
}

/// One repository row: tile, name, "language · branch · size", star.
class RepoTile extends StatelessWidget {
  const RepoTile({
    super.key,
    required this.repo,
    required this.languages,
    required this.favorite,
    this.flash = false,
    this.onFavorite,
    this.onTap,
  });

  final GitRepository repo;
  final List<RepoLanguage> languages;
  final bool favorite;

  /// Tints the row briefly after a scroll-to.
  final bool flash;
  final VoidCallback? onFavorite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final language = languages.isEmpty ? null : languages.first.name;
    final parts = <String>[
      ?language,
      ?repo.defaultBranchName,
      if (repo.size != null && repo.size! > 0) formatBytes(repo.size),
    ];
    final badge = repo.isDisabled
        ? 'Disabled'
        : repo.isInMaintenance
        ? 'In maintenance'
        : repo.isEmpty
        ? 'Empty'
        : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 360),
      color: flash
          ? scheme.primary.withValues(alpha: 0.18)
          : Colors.transparent,
      child: ListTile(
        enabled: onTap != null,
        leading: AdoTile(
          name: repo.name,
          color: AdoTiles.serviceColor(repo.name),
          initials: AdoTiles.serviceInitials(repo.name),
        ),
        title: Text(repo.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            if (language != null) ...[
              LanguageDot(language: language),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                [
                  if (parts.isNotEmpty) parts.join(' · '),
                  if (repo.isFork && repo.parentRepositoryName != null)
                    'forked from ${repo.parentRepositoryName}',
                  ?badge,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        trailing: onFavorite == null
            ? null
            : IconButton(
                tooltip: favorite
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: Icon(
                  favorite ? Icons.star : Icons.star_border,
                  color: favorite ? scheme.tertiary : scheme.onSurfaceVariant,
                ),
                onPressed: onFavorite,
              ),
        onTap: onTap,
      ),
    );
  }
}
