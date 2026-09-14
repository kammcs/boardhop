import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'widgets/code_hit_list.dart';

/// Code search over the project, or one repository of it, through the
/// Code Search extension. Results carry no snippets, so a hit opens the
/// file and the viewer finds the first line with the term.
class CodeSearchPage extends StatefulWidget {
  const CodeSearchPage({
    super.key,
    required this.org,
    required this.project,
    this.repoName,
    this.initialQuery,
  });

  final String org;
  final String project;

  /// Limits the search to one repository when set.
  final String? repoName;
  final String? initialQuery;

  @override
  State<CodeSearchPage> createState() => _CodeSearchPageState();
}

class _CodeSearchPageState extends State<CodeSearchPage> {
  late final _controller = TextEditingController(text: widget.initialQuery);
  final _scroll = ScrollController();
  String _query = '';
  List<CodeSearchHit>? _hits;
  int _count = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final q = widget.initialQuery;
    if (q != null && q.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _search(q));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final hits = _hits;
    if (hits == null || _loadingMore || _loading || hits.length >= _count) {
      return;
    }
    if (_scroll.hasClients && _scroll.position.extentAfter < 600) _more();
  }

  Future<void> _search(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final generation = ++_generation;
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
      _hits = null;
    });
    try {
      final page = await context.read<SearchRepository>().searchCode(
        widget.org,
        project: widget.project,
        text: q,
        repositoryName: widget.repoName,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _hits = page.hits;
        _count = page.count;
        _error = page.problem;
      });
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoNotFoundException {
      if (mounted) {
        setState(
          () => _error =
              'Code search is not enabled on this organization. An '
              'administrator can install the Code Search extension.',
        );
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _more() async {
    final have = _hits;
    if (have == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await context.read<SearchRepository>().searchCode(
        widget.org,
        project: widget.project,
        text: _query,
        repositoryName: widget.repoName,
        skip: have.length,
      );
      if (!mounted) return;
      setState(() {
        _hits = [...have, ...page.hits];
        _count = page.count;
      });
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _open(CodeSearchHit hit) => openCodeHit(
    context,
    org: widget.org,
    project: widget.project,
    hit: hit,
    query: _query,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hits = _hits ?? const <CodeSearchHit>[];
    final rows = codeHitRows(
      context: context,
      hits: hits,
      // A repository-scoped search has one group; its header would only
      // repeat what the app bar already says.
      grouped: widget.repoName == null,
      onTap: _open,
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Code search'),
            Text(
              widget.repoName ?? widget.project,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: ContentColumn(
        child: Column(
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
                controller: _controller,
                autofocus: widget.initialQuery == null,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: widget.repoName == null
                      ? 'Search code in ${widget.project}'
                      : 'Search code in ${widget.repoName}',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            setState(() {
                              _hits = null;
                              _error = null;
                              _query = '';
                            });
                          },
                        ),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            if (_error != null)
              ListTile(
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: Text(_error!),
              ),
            if (_hits != null && _error == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _count == 0
                        ? 'No results for "$_query".'
                        : '$_count result${_count == 1 ? '' : 's'} for "$_query"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                controller: _scroll,
                children: [
                  ...rows,
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.all(Spacing.lg),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (_hits == null && !_loading && _error == null)
                    Padding(
                      padding: const EdgeInsets.all(Spacing.xl),
                      child: Text(
                        'Search file contents and names. Quotes match a '
                        'phrase; a trailing * matches a prefix.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
