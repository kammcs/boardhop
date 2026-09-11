import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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

  RepoRepository get _repo => context.read<RepoRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
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
    try {
      await _repo.setFavorite(org: widget.org, repo: r, favorite: !wasFavorite);
    } on AdoException catch (e) {
      if (!mounted) return;
      setState(() {
        _favorites = wasFavorite
            ? {..._favorites, r.id}
            : (_favorites.toSet()..remove(r.id));
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ReposPageErrors.favoriteError(e))));
    }
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
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ContentColumn(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
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
                      : Text(
                          'Showing the list from ${relativeTime(_shownAt)}.',
                        ),
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
              if (sections.favorites.isNotEmpty) ...[
                const _SectionLabel('Favorites'),
                for (final r in sections.favorites) _tile(r),
              ],
              if (sections.recents.isNotEmpty) ...[
                const _SectionLabel('Recent'),
                for (final r in sections.recents) _tile(r),
              ],
              if (sections.all.isNotEmpty) ...[
                if (sections.favorites.isNotEmpty ||
                    sections.recents.isNotEmpty)
                  const _SectionLabel('All repositories'),
                for (final r in sections.all) _tile(r),
              ],
              if (sections.inactive.isNotEmpty) ...[
                const _SectionLabel('Disabled'),
                for (final r in sections.inactive) _tile(r),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(GitRepository r) => RepoTile(
    repo: r,
    languages: _languages[r.name] ?? const [],
    favorite: _favorites.contains(r.id),
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
    this.onFavorite,
    this.onTap,
  });

  final GitRepository repo;
  final List<RepoLanguage> languages;
  final bool favorite;
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
    return ListTile(
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
              tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
              icon: Icon(
                favorite ? Icons.star : Icons.star_border,
                color: favorite ? scheme.tertiary : scheme.onSurfaceVariant,
              ),
              onPressed: onFavorite,
            ),
      onTap: onTap,
    );
  }
}
