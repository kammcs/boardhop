import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/ado_tiles.dart';
import '../../core/util/format.dart';
import '../../data/models/git_repository.dart';
import '../../data/models/pipeline.dart';
import '../../data/models/project.dart';
import '../../data/models/pull_request.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/pipeline_repository.dart';
import '../../data/repositories/project_repository.dart';
import '../../data/repositories/pull_request_repository.dart';
import '../../data/repositories/repo_repository.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../theme/theme.dart';
import '../pipelines/pipelines_page.dart' show RunTile;
import '../shared/account_scope.dart';
import '../shared/reload_on_return.dart';
import '../shared/widgets/ado_tile.dart';
import '../work_items/widgets/work_item_visuals.dart';

/// Landing tab of a project (phase 4 of the repos plan): the project's
/// tile and description, then what matters to the signed-in person in
/// this project: pinned repositories, pull requests to review or of their
/// own, work items assigned to them, and the latest pipeline runs. Every
/// section loads and fails on its own; cached copies show first.
class ProjectHomePage extends StatefulWidget {
  const ProjectHomePage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  State<ProjectHomePage> createState() => _ProjectHomePageState();
}

class _ProjectHomePageState extends State<ProjectHomePage> with ReloadOnReturn {
  static const _limit = 5;

  List<GitRepository>? _repos;
  bool _reposArePins = true;
  List<PullRequest>? _prs;
  List<WorkItem>? _items;
  List<BuildRun>? _runs;
  final _errors = <String, String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String get _base => projectRoute(context, widget.org, widget.project);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errors.clear();
    });
    await Future.wait([
      _guard('repos', _loadRepos),
      _guard('prs', _loadPrs),
      _guard('items', _loadItems),
      _guard('runs', _loadRuns),
    ]);
    markLoaded();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Future<void> reload() => _load();

  Future<void> _guard(String key, Future<void> Function() fn) async {
    try {
      await fn();
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
      if (mounted) setState(() => _errors[key] = e.message);
    }
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _loadRepos() async {
    final repos = context.read<RepoRepository>();
    final org = widget.org;
    final project = widget.project;
    Future<void> apply(List<GitRepository> all) async {
      if (all.isEmpty) {
        _set(() => _repos = const []);
        return;
      }
      final projectId = all.first.projectId;
      final favorites =
          await repos.cachedFavorites(org, projectId) ??
          const <String, String>{};
      final recents = await repos.recents(org, project);
      final byId = {for (final r in all) r.id: r};
      var pins = [
        for (final r in all)
          if (favorites.containsKey(r.id) && r.isActive) r,
      ];
      var arePins = true;
      if (pins.isEmpty) {
        arePins = false;
        pins = [
          for (final id in recents)
            if (byId[id] case final r? when r.isActive) r,
        ];
      }
      _set(() {
        _repos = pins.take(_limit).toList();
        _reposArePins = arePins;
      });
    }

    final cached = await repos.cachedList(org, project);
    if (cached != null) await apply(cached.items);
    final fresh = await repos.list(org, project);
    if (fresh.isNotEmpty) {
      try {
        await repos.favorites(org, fresh.first.projectId);
      } on AdoException {
        // Favorites need an extra scope; the cached set is fine.
      }
    }
    await apply(fresh);
  }

  Future<void> _loadPrs() async {
    final prs = context.read<PullRequestRepository>();
    List<PullRequest> merge(List<PullRequest> a, List<PullRequest> b) {
      final seen = <int>{};
      final out = [
        for (final p in [...a, ...b])
          if (seen.add(p.id)) p,
      ];
      out.sort((x, y) {
        final tx = x.creationDate?.millisecondsSinceEpoch ?? 0;
        final ty = y.creationDate?.millisecondsSinceEpoch ?? 0;
        return ty.compareTo(tx);
      });
      return out.take(_limit).toList();
    }

    final cachedReview = await prs.cachedList(
      widget.org,
      project: widget.project,
      filter: PrListFilter.toReview,
    );
    final cachedMine = await prs.cachedList(
      widget.org,
      project: widget.project,
      filter: PrListFilter.mine,
    );
    if (cachedReview != null || cachedMine != null) {
      _set(
        () => _prs = merge(
          cachedReview?.items ?? const [],
          cachedMine?.items ?? const [],
        ),
      );
    }
    final results = await Future.wait([
      prs.list(
        widget.org,
        project: widget.project,
        filter: PrListFilter.toReview,
      ),
      prs.list(widget.org, project: widget.project, filter: PrListFilter.mine),
    ]);
    _set(() => _prs = merge(results[0], results[1]));
  }

  Future<void> _loadItems() async {
    final items = context.read<WorkItemRepository>();
    final cached = await items
        .watchList(
          widget.org,
          widget.project,
          WorkItemRepository.assignedToMeKey,
        )
        .first;
    if (cached.isNotEmpty) _set(() => _items = cached.take(_limit).toList());
    final fresh = await items.refreshAssignedToMe(widget.org, widget.project);
    _set(() => _items = fresh.take(_limit).toList());
  }

  Future<void> _loadRuns() async {
    final pipelines = context.read<PipelineRepository>();
    final cached = await pipelines.cachedRuns(widget.org, widget.project);
    if (cached != null) _set(() => _runs = cached.items.take(_limit).toList());
    // A short read must not replace the Pipelines tab's cached list.
    final fresh = await pipelines.runs(
      widget.org,
      widget.project,
      top: _limit,
      cache: false,
    );
    _set(() => _runs = fresh.take(_limit).toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = _base;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.project, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          tooltip: 'Projects',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('${orgRoute(context, widget.org)}/projects'),
        ),
      ),
      body: StreamBuilder<List<Project>>(
        stream: context.read<ProjectRepository>().watch(widget.org),
        builder: (context, snapshot) {
          Project? current;
          for (final p in snapshot.data ?? const <Project>[]) {
            if (p.name == widget.project) current = p;
          }
          final description = current?.description;
          return RefreshIndicator(
            onRefresh: _load,
            child: ContentColumn(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: scrollEndPadding(context),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  Padding(
                    padding: Spacing.page,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdoTile(
                          name: widget.project,
                          color: AdoTiles.serviceColor(widget.project),
                          initials: AdoTiles.serviceInitials(widget.project),
                          source: current?.tileSource(widget.org),
                          size: 56,
                        ),
                        const SizedBox(width: Spacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.project,
                                style: theme.textTheme.titleLarge,
                              ),
                              if (description != null && description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: Spacing.xs,
                                  ),
                                  child: Text(
                                    description,
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
                  // Two columns from tablet width: repositories and work
                  // items on the left, pull requests and runs on the right.
                  SideBySide(
                    start: [
                      _Section(
                        title: _reposArePins
                            ? 'Pinned repositories'
                            : 'Recent repositories',
                        icon: Icons.source_outlined,
                        error: _errors['repos'],
                        loaded: _repos != null,
                        empty: 'Star a repository to pin it here.',
                        onSeeAll: () => context.go('$base/repos'),
                        children: [
                          for (final r in _repos ?? const <GitRepository>[])
                            ListTile(
                              leading: AdoTile(
                                name: r.name,
                                color: AdoTiles.serviceColor(r.name),
                                initials: AdoTiles.serviceInitials(r.name),
                                size: 32,
                              ),
                              title: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: r.defaultBranchName == null
                                  ? null
                                  : Text(r.defaultBranchName!),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => context.push(
                                '$base/repos/${Uri.encodeComponent(r.name)}',
                              ),
                            ),
                        ],
                      ),
                      _Section(
                        title: 'My work items',
                        icon: Icons.assignment_outlined,
                        error: _errors['items'],
                        loaded: _items != null,
                        empty: 'Nothing assigned to you here.',
                        onSeeAll: () => context.go('$base/work-items'),
                        children: [
                          for (final w in _items ?? const <WorkItem>[])
                            _WorkItemRow(
                              item: w,
                              onTap: () =>
                                  context.push('$base/work-items/${w.id}'),
                            ),
                        ],
                      ),
                    ],
                    end: [
                      _Section(
                        title: 'My pull requests',
                        icon: Icons.call_merge,
                        error: _errors['prs'],
                        loaded: _prs != null,
                        empty: 'Nothing to review and nothing of yours open.',
                        onSeeAll: () => context.push('$base/pull-requests'),
                        children: [
                          for (final pr in _prs ?? const <PullRequest>[])
                            ListTile(
                              leading: IdentityAvatar(
                                identity: pr.createdBy,
                                radius: 16,
                              ),
                              title: Text(
                                pr.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${pr.repositoryName} · !${pr.id}'
                                '${pr.isDraft ? ' · draft' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                relativeTime(pr.creationDate),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              onTap: () => context.push(
                                '${orgRoute(context, widget.org)}/pull-requests/${pr.id}',
                              ),
                            ),
                        ],
                      ),
                      _Section(
                        title: 'Latest runs',
                        icon: Icons.play_circle_outline,
                        error: _errors['runs'],
                        loaded: _runs != null,
                        empty: 'No pipeline runs yet.',
                        onSeeAll: () => context.go('$base/pipelines'),
                        children: [
                          for (final run in _runs ?? const <BuildRun>[])
                            RunTile(
                              run: run,
                              onTap: () => context.push(
                                '$base/pipelines/runs/${run.id}',
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.view_kanban_outlined),
                    title: const Text('Board'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('$base/boards'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.manage_search),
                    title: const Text('Search code'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('$base/code-search'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.error,
    required this.loaded,
    required this.empty,
    required this.onSeeAll,
    required this.children,
  });

  final String title;
  final IconData icon;
  final String? error;
  final bool loaded;
  final String empty;
  final VoidCallback onSeeAll;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.md,
            Spacing.sm,
            0,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: scheme.primary,
                  ),
                ),
              ),
              TextButton(onPressed: onSeeAll, child: const Text('See all')),
            ],
          ),
        ),
        if (error != null)
          ListTile(
            dense: true,
            leading: Icon(Icons.error_outline, color: scheme.error, size: 20),
            title: Text(error!, style: theme.textTheme.bodySmall),
          )
        else if (loaded && children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.xs,
              Spacing.lg,
              Spacing.md,
            ),
            child: Text(
              empty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

class _WorkItemRow extends StatelessWidget {
  const _WorkItemRow({required this.item, required this.onTap});

  final WorkItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const visuals = WorkItemVisuals({});
    return ListTile(
      leading: Icon(
        visuals.typeIcon(item),
        color: visuals.typeColor(context, item),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${item.type} ${item.id} · ${item.state}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        relativeTime(item.changedDate),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}
