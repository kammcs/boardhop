import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'widgets/commit_visuals.dart';

/// History of a branch (or of one path on it), newest first, more pages as
/// the list nears its end. The first page is cached so it opens offline.
class CommitsPage extends StatefulWidget {
  const CommitsPage({
    super.key,
    required this.org,
    required this.project,
    required this.repo,
    required this.ref,
    this.path,
  });

  final String org;
  final String project;
  final GitRepository repo;
  final String ref;

  /// File or folder whose history this is; null for the whole branch.
  final String? path;

  @override
  State<CommitsPage> createState() => _CommitsPageState();
}

class _CommitsPageState extends State<CommitsPage> {
  late String _ref = widget.ref;
  List<GitCommit>? _commits;
  bool _loading = true;
  bool _loadingMore = false;
  bool _exhausted = false;
  String? _error;
  final _scroll = ScrollController();

  RepoRepository get _repos => context.read<RepoRepository>();

  String? get _path {
    final p = widget.path;
    return p == null || RepoPaths.normalize(p) == '/' ? null : p;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || _exhausted || _loading) return;
    if (_scroll.position.extentAfter < 600) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repos = _repos;
    try {
      if (_commits == null) {
        final cached = await repos.cachedCommits(
          widget.repo.id,
          ref: _ref,
          path: _path,
        );
        if (cached != null && mounted) setState(() => _commits = cached);
      }
      final page = await repos.commits(
        widget.org,
        widget.project,
        widget.repo.id,
        ref: _ref,
        path: _path,
      );
      if (mounted) {
        setState(() {
          _commits = page;
          _exhausted = page.length < RepoRepository.commitsPage;
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final have = _commits;
    if (have == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repos.commits(
        widget.org,
        widget.project,
        widget.repo.id,
        ref: _ref,
        path: _path,
        skip: have.length,
      );
      if (!mounted) return;
      setState(() {
        final seen = have.map((c) => c.id).toSet();
        _commits = [...have, ...page.where((c) => !seen.contains(c.id))];
        _exhausted = page.length < RepoRepository.commitsPage;
      });
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  String get _base =>
      '${projectRoute(context, widget.org, widget.project)}'
      '/repos/${Uri.encodeComponent(widget.repo.name)}';

  Future<void> _pickBranch() async {
    final picked = await context.push<String>(
      '$_base/branches?current=${Uri.encodeQueryComponent(_ref)}',
    );
    if (picked == null || picked == _ref || !mounted) return;
    setState(() {
      _ref = picked;
      _commits = null;
      _exhausted = false;
    });
    await _load();
  }

  void _compare() {
    final base = widget.repo.defaultBranchName;
    if (base == null) return;
    context.push(
      '$_base/compare?base=${Uri.encodeQueryComponent(base)}'
      '&ref=${Uri.encodeQueryComponent(_ref)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final commits = _commits ?? const <GitCommit>[];
    final path = _path;
    final canCompare =
        widget.repo.defaultBranchName != null &&
        _ref != widget.repo.defaultBranchName &&
        !GitVersion.isCommit(_ref);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              path == null ? 'Commits' : 'History',
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              path == null
                  ? '${widget.repo.name} · ${GitVersion.label(_ref)}'
                  : '${GitVersion.label(_ref)} · $path',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (canCompare)
            IconButton(
              tooltip: 'Compare with ${widget.repo.defaultBranchName}',
              icon: const Icon(Icons.compare_arrows),
              onPressed: _compare,
            ),
          if (!GitVersion.isCommit(_ref))
            IconButton(
              tooltip: 'Switch branch',
              icon: const Icon(Icons.fork_right),
              onPressed: _pickBranch,
            ),
        ],
      ),
      body: ContentColumn(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: commits.length + 3,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _loading
                    ? const LinearProgressIndicator()
                    : const SizedBox.shrink();
              }
              if (i == 1) {
                if (_error != null) {
                  return ListTile(
                    leading: Icon(Icons.error_outline, color: scheme.error),
                    title: Text(_error!),
                  );
                }
                if (_commits != null && commits.isEmpty && !_loading) {
                  return Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Text(
                      'No commits here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }
              if (i == commits.length + 2) {
                return Padding(
                  padding: const EdgeInsets.all(Spacing.lg),
                  child: Center(
                    child: _loadingMore
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _exhausted || commits.isEmpty
                        ? null
                        : TextButton(
                            onPressed: _loadMore,
                            child: const Text('Load more'),
                          ),
                  ),
                );
              }
              final c = commits[i - 2];
              return CommitTile(
                commit: c,
                onTap: () => context.push('$_base/commits/${c.id}'),
              );
            },
          ),
        ),
      ),
    );
  }
}
