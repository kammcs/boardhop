import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/git_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'widgets/item_actions.dart';

/// One folder of a repository on one branch: breadcrumb, folders first,
/// then files. Each folder tapped pushes another browser page so the back
/// gesture walks up; the breadcrumb jumps to any ancestor. Listings come
/// from the cache first so a folder reopens offline.
class CodeBrowserPage extends StatefulWidget {
  const CodeBrowserPage({
    super.key,
    required this.org,
    required this.project,
    required this.repo,
    required this.ref,
    this.path = '/',
  });

  final String org;
  final String project;
  final GitRepository repo;
  final String ref;
  final String path;

  @override
  State<CodeBrowserPage> createState() => _CodeBrowserPageState();
}

class _CodeBrowserPageState extends State<CodeBrowserPage> {
  late String _ref = widget.ref;
  late final String _path = RepoPaths.normalize(widget.path);
  List<GitItem>? _items;
  String? _error;
  bool _loading = true;

  RepoRepository get _repos => context.read<RepoRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repos = _repos;
    final repoId = widget.repo.id;
    try {
      if (_items == null) {
        final cached = await repos.cachedTree(repoId, ref: _ref, path: _path);
        if (cached != null && mounted) setState(() => _items = cached);
      }
      final items = await repos.tree(
        widget.org,
        widget.project,
        repoId,
        ref: _ref,
        path: _path,
      );
      if (mounted) setState(() => _items = items);
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
        setState(() {
          _error = _path == '/'
              ? 'Branch "$_ref" was not found.'
              : 'This folder does not exist on "$_ref".';
          _items = const [];
        });
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _base =>
      '${projectRoute(context, widget.org, widget.project)}'
      '/repos/${Uri.encodeComponent(widget.repo.name)}';

  String _route(String kind, String path) =>
      '$_base/$kind?ref=${Uri.encodeQueryComponent(_ref)}'
      '&path=${Uri.encodeQueryComponent(path)}';

  Future<void> _pickBranch() async {
    final picked = await context.push<String>(
      '$_base/branches?current=${Uri.encodeQueryComponent(_ref)}',
    );
    if (picked == null || picked == _ref || !mounted) return;
    await _repos.setLastBranch(widget.repo.id, picked);
    setState(() {
      _ref = picked;
      _items = null;
    });
    await _load();
  }

  void _open(GitItem item) {
    context.push(_route(item.isFolder ? 'code' : 'file', item.path));
  }

  void _actions(GitItem? item) => showItemActions(
    context,
    org: widget.org,
    project: widget.project,
    repo: widget.repo,
    ref: _ref,
    path: item?.path ?? _path,
    isFolder: item?.isFolder ?? true,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final segments = RepoPaths.segments(_path);
    final items = _items ?? const <GitItem>[];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              segments.isEmpty ? widget.repo.name : segments.last,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              GitVersion.label(_ref),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Switch branch',
            icon: const Icon(Icons.fork_right),
            onPressed: _pickBranch,
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _actions(null),
          ),
        ],
      ),
      body: ContentColumn(
        child: Column(
          children: [
            _Breadcrumb(
              repoName: widget.repo.name,
              segments: segments,
              onTap: (count) =>
                  context.push(_route('code', RepoPaths.prefix(_path, count))),
            ),
            const Divider(height: 1),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return _loading
                          ? const LinearProgressIndicator()
                          : const SizedBox.shrink();
                    }
                    if (i == 1) {
                      if (_error != null) {
                        return ListTile(
                          leading: Icon(
                            Icons.error_outline,
                            color: scheme.error,
                          ),
                          title: Text(_error!),
                        );
                      }
                      if (_items != null && items.isEmpty && !_loading) {
                        return Padding(
                          padding: const EdgeInsets.all(Spacing.xl),
                          child: Text(
                            'This folder is empty.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    final item = items[i - 2];
                    return ListTile(
                      leading: Icon(
                        itemIcon(item),
                        color: item.isFolder
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: item.isFolder
                          ? const Icon(Icons.chevron_right)
                          : null,
                      onTap: () => _open(item),
                      onLongPress: () => _actions(item),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `repo › src › lib`, scrollable, every ancestor tappable. Starts at the
/// left and scrolls to the current folder when the trail is long.
class _Breadcrumb extends StatefulWidget {
  const _Breadcrumb({
    required this.repoName,
    required this.segments,
    required this.onTap,
  });

  final String repoName;
  final List<String> segments;

  /// Called with the number of segments to keep (0 = root).
  final ValueChanged<int> onTap;

  @override
  State<_Breadcrumb> createState() => _BreadcrumbState();
}

class _BreadcrumbState extends State<_Breadcrumb> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final linkStyle = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.primary,
    );
    final currentStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final segments = widget.segments;
    final crumbs = <Widget>[];
    for (var i = 0; i <= segments.length; i++) {
      final label = i == 0 ? widget.repoName : segments[i - 1];
      final current = i == segments.length;
      if (i > 0) {
        crumbs.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
            child: Icon(
              Icons.chevron_right,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
      }
      crumbs.add(
        current
            ? Text(label, style: currentStyle)
            : InkWell(
                borderRadius: Radii.chip,
                onTap: () => widget.onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.xs,
                    vertical: Spacing.xs,
                  ),
                  child: Text(label, style: linkStyle),
                ),
              ),
      );
    }
    return SizedBox(
      height: 44,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          child: ConstrainedBox(
            // At least the viewport wide, so a short trail starts at the
            // left instead of floating in the middle.
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth - Spacing.md * 2,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: crumbs),
          ),
        ),
      ),
    );
  }
}
