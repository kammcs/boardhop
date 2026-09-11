import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/ado_tiles.dart';
import '../../core/util/format.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import '../shared/widgets/ado_tile.dart';
import 'repos_page.dart' show ReposPageErrors;
import 'widgets/repo_markdown.dart';
import 'widgets/repo_visuals.dart';

/// One repository: the rows from Kelly's mockup (pull requests, the
/// current branch with a picker, code, commits, search) above the README
/// of that branch.
class RepoPage extends StatefulWidget {
  const RepoPage({
    super.key,
    required this.org,
    required this.project,
    required this.repoName,
  });

  final String org;
  final String project;
  final String repoName;

  @override
  State<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends State<RepoPage> {
  GitRepository? _repo;
  List<RepoLanguage> _languages = const [];
  bool _favorite = false;
  String? _branch;
  GitBranch? _stats;
  int? _prCount;
  String? _readme;
  String? _error;
  bool _loading = true;

  RepoRepository get _repos => context.read<RepoRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<GitRepository?> _find() async {
    final repos = _repos;
    final cached = await repos.cachedList(widget.org, widget.project);
    for (final r in cached?.items ?? const <GitRepository>[]) {
      if (r.name == widget.repoName) return r;
    }
    for (final r in await repos.list(widget.org, widget.project)) {
      if (r.name == widget.repoName) return r;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repos = _repos;
    try {
      final repo = await _find();
      if (repo == null) {
        setState(() => _error = 'Repository "${widget.repoName}" not found.');
        return;
      }
      final branch =
          _branch ?? await repos.lastBranch(repo.id) ?? repo.defaultBranchName;
      final cachedReadme = branch == null
          ? null
          : await repos.cachedReadme(repo.id, branch);
      final languages = await repos.cachedLanguages(widget.org, widget.project);
      final favorites = await repos.cachedFavorites(widget.org, repo.projectId);
      if (!mounted) return;
      setState(() {
        _repo = repo;
        _branch = branch;
        _languages = languages?[repo.name] ?? const [];
        _favorite = favorites?.containsKey(repo.id) ?? false;
        if (cachedReadme != null) _readme = cachedReadme;
        // An empty repository has no branch and nothing to read.
        if (branch == null) _readme = '';
      });
      if (branch == null) return;
      // Each detail arrives on its own; none blocks the page.
      final futures = <Future<void>>[
        repos
            .branch(
              widget.org,
              widget.project,
              repo.id,
              branch,
              defaultBranch: repo.defaultBranchName,
            )
            .then((s) => _set(() => _stats = s)),
        repos
            .activePullRequests(widget.org, widget.project, repo.id)
            .then((n) => _set(() => _prCount = n)),
        repos
            .readme(widget.org, widget.project, repo.id, branch)
            .then((r) => _set(() => _readme = r)),
        if (favorites == null)
          repos
              .favorites(widget.org, repo.projectId)
              .then((f) => _set(() => _favorite = f.containsKey(repo.id))),
      ];
      await Future.wait(futures.map((f) => f.catchError(_report)));
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

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  void _report(Object e) {
    if (e is AdoAuthException) throw e;
    debugPrint('repo page: $e');
    if (e is AdoException) _set(() => _error ??= e.message);
  }

  Future<void> _toggleFavorite() async {
    final repo = _repo;
    if (repo == null) return;
    final was = _favorite;
    setState(() => _favorite = !was);
    try {
      await _repos.setFavorite(org: widget.org, repo: repo, favorite: !was);
    } on AdoException catch (e) {
      if (!mounted) return;
      setState(() => _favorite = was);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ReposPageErrors.favoriteError(e))));
    }
  }

  String get _base =>
      '${projectRoute(context, widget.org, widget.project)}'
      '/repos/${Uri.encodeComponent(widget.repoName)}';

  Future<void> _pickBranch() async {
    final repo = _repo;
    if (repo == null) return;
    final picked = await context.push<String>(
      '$_base/branches?current=${Uri.encodeQueryComponent(_branch ?? '')}',
    );
    if (picked == null || picked == _branch || !mounted) return;
    setState(() {
      _branch = picked;
      _stats = null;
      _readme = null;
    });
    await _repos.setLastBranch(repo.id, picked);
    await _load();
  }

  Future<void> _openInBrowser() async {
    final url = _repo?.webUrl;
    if (url == null) return;
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the browser.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repo = _repo;
    final branch = _branch;
    final stats = _stats;
    final language = _languages.isEmpty ? null : _languages.first.name;
    final branchSubtitle = stats == null
        ? (branch == null ? 'Empty repository' : null)
        : [
            if (stats.isDefault)
              'default branch'
            else
              '${stats.aheadCount} ahead · ${stats.behindCount} behind',
            if (stats.authorName != null) stats.authorName!,
            if (stats.date != null) relativeTime(stats.date),
          ].join(' · ');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.repoName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(
              _favorite ? Icons.star : Icons.star_border,
              color: _favorite ? scheme.tertiary : null,
            ),
            onPressed: repo == null ? null : _toggleFavorite,
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: repo?.webUrl == null ? null : _openInBrowser,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ContentColumn(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: Spacing.xxl),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                ListTile(
                  leading: Icon(Icons.error_outline, color: scheme.error),
                  title: Text(_error!),
                ),
              if (repo != null)
                Padding(
                  padding: Spacing.page,
                  child: Row(
                    children: [
                      AdoTile(
                        name: repo.name,
                        color: AdoTiles.serviceColor(repo.name),
                        initials: AdoTiles.serviceInitials(repo.name),
                        size: 56,
                      ),
                      const SizedBox(width: Spacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(repo.name, style: theme.textTheme.titleLarge),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (language != null) ...[
                                  LanguageDot(language: language),
                                  const SizedBox(width: 6),
                                ],
                                Expanded(
                                  child: Text(
                                    [
                                      ?language,
                                      if (repo.size != null && repo.size! > 0)
                                        formatBytes(repo.size),
                                      if (repo.isFork &&
                                          repo.parentRepositoryName != null)
                                        'forked from ${repo.parentRepositoryName}',
                                    ].join(' · '),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (repo != null) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.call_merge),
                  title: const Text('Pull requests'),
                  subtitle: Text(
                    _prCount == null
                        ? 'Active pull requests'
                        : _prCount == 0
                        ? 'No active pull requests'
                        : _prCount == 1
                        ? '1 active pull request'
                        : '${_prCount! >= 100 ? '100+' : _prCount} active pull requests',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    '${projectRoute(context, widget.org, widget.project)}'
                    '/pull-requests?repoId=${Uri.encodeQueryComponent(repo.id)}'
                    '&repo=${Uri.encodeQueryComponent(repo.name)}',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.fork_right),
                  title: Text(branch ?? 'No branches'),
                  subtitle: branchSubtitle == null
                      ? null
                      : Text(branchSubtitle),
                  trailing: branch == null
                      ? null
                      : const Icon(Icons.unfold_more),
                  onTap: branch == null ? null : _pickBranch,
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('Code'),
                  subtitle: branch == null
                      ? null
                      : Text('Browse files on $branch'),
                  trailing: const Icon(Icons.chevron_right),
                  enabled: branch != null,
                  onTap: () => context.push(
                    '$_base/code?ref=${Uri.encodeQueryComponent(branch ?? '')}',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Commits'),
                  subtitle: stats?.subject.isNotEmpty == true
                      ? Text(
                          stats!.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  enabled: branch != null,
                  onTap: () => context.push(
                    '$_base/commits?ref=${Uri.encodeQueryComponent(branch ?? '')}',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.search),
                  title: const Text('Search in this repository'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('$_base/search'),
                ),
                const Divider(height: 1),
                Padding(
                  padding: Spacing.page,
                  child: _readme == null
                      ? Text(
                          'Loading README…',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      : _readme!.isEmpty
                      ? _NoReadme(languages: _languages)
                      : RepoMarkdown(
                          data: _readme!,
                          org: widget.org,
                          project: widget.project,
                          repo: repo,
                          ref: branch ?? '',
                          path: '/README.md',
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown instead of a README: the language breakdown bar.
class _NoReadme extends StatelessWidget {
  const _NoReadme({required this.languages});

  final List<RepoLanguage> languages;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No README on this branch.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (languages.isNotEmpty) ...[
          const SizedBox(height: Spacing.lg),
          Text('Languages', style: theme.textTheme.titleSmall),
          const SizedBox(height: Spacing.sm),
          ClipRRect(
            borderRadius: Radii.chip,
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (final l in languages.take(6))
                    Expanded(
                      flex: (l.percentage * 10).round().clamp(1, 1000),
                      child: ColoredBox(color: languageColor(context, l.name)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.lg,
            runSpacing: Spacing.xs,
            children: [
              for (final l in languages.take(6))
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LanguageDot(language: l.name),
                    const SizedBox(width: 6),
                    Text(
                      '${l.name} ${l.percentage.toStringAsFixed(1)}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
