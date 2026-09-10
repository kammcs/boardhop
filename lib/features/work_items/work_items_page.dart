import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../theme/theme.dart';
import 'widgets/query_picker.dart';
import 'work_item_detail_page.dart';
import 'widgets/work_item_visuals.dart';

/// Work item lists in one project: "assigned to me", "recently updated" or
/// a saved query, rendered from the drift cache and refreshed on open, on
/// pull and when the list changes.
class WorkItemsPage extends StatefulWidget {
  const WorkItemsPage({super.key, required this.org, required this.project});

  final String org;
  final String project;

  @override
  State<WorkItemsPage> createState() => _WorkItemsPageState();
}

class _WorkItemsPageState extends State<WorkItemsPage> {
  String? _error;
  bool _refreshing = false;
  bool _loadedOnce = false;
  WorkItemVisuals _visuals = const WorkItemVisuals({});
  String _listKey = WorkItemRepository.assignedToMeKey;
  String _listLabel = 'Assigned to me';
  List<SavedQuery>? _queries;
  SavedQuery? _query;
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _error = null;
    });
    final repo = context.read<WorkItemRepository>();
    try {
      final types = await repo.types(widget.org, widget.project);
      if (mounted) {
        setState(
          () => _visuals = WorkItemVisuals({for (final t in types) t.name: t}),
        );
      }
      if (_listKey == WorkItemRepository.assignedToMeKey) {
        await repo.refreshAssignedToMe(widget.org, widget.project);
      } else if (_listKey == WorkItemRepository.recentlyUpdatedKey) {
        await repo.refreshRecentlyUpdated(widget.org, widget.project);
      } else if (_query != null) {
        await repo.refreshQuery(widget.org, widget.project, _query!.id);
      }
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _loadedOnce = true;
        });
      }
    }
  }

  void _select(String key, String label, {SavedQuery? query}) {
    if (key == _listKey) return;
    setState(() {
      _listKey = key;
      _listLabel = label;
      _query = query;
      _loadedOnce = false;
    });
    _refresh();
  }

  Future<void> _pickQuery() async {
    final repo = context.read<WorkItemRepository>();
    var tree = _queries;
    if (tree == null) {
      setState(() => _refreshing = true);
      try {
        tree = await repo.queries(widget.org, widget.project);
        _queries = tree;
      } on AdoException catch (e) {
        if (mounted) setState(() => _error = e.message);
        return;
      } finally {
        if (mounted) setState(() => _refreshing = false);
      }
    }
    if (!mounted) return;
    final picked = await pickSavedQuery(
      context,
      tree: tree,
      selectedId: _query?.id,
    );
    if (picked == null || !mounted) return;
    _select(WorkItemRepository.queryKey(picked.id), picked.name, query: picked);
  }

  void _open(WorkItem item) {
    if (context.breakpoint.isAtLeastMedium) {
      setState(() => _selectedId = item.id);
      return;
    }
    context.push(
      '/orgs/${Uri.encodeComponent(widget.org)}/projects/'
      '${Uri.encodeComponent(widget.project)}/work-items/${item.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.project, overflow: TextOverflow.ellipsis),
            Text(
              _listLabel,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        leading: IconButton(
          tooltip: 'Projects',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('/orgs/${Uri.encodeComponent(widget.org)}/projects'),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = Breakpoint.fromWidth(constraints.maxWidth)
              .isAtLeastMedium;
          final list = _list(context);
          if (!wide) return list;
          final theme = Theme.of(context);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: (constraints.maxWidth * 0.42).clamp(320, 480),
                child: list,
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selectedId == null
                    ? Center(
                        child: Text(
                          'Select a work item',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : WorkItemDetailPage(
                        key: ValueKey(_selectedId),
                        org: widget.org,
                        project: widget.project,
                        id: _selectedId!,
                        embedded: true,
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _list(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: StreamBuilder<List<WorkItem>>(
        stream: context.read<WorkItemRepository>().watchList(
          widget.org,
          widget.project,
          _listKey,
        ),
        builder: (context, snapshot) {
          final items = snapshot.data ?? const <WorkItem>[];
          return ContentColumn(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_refreshing) const LinearProgressIndicator(),
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.lg,
                      vertical: Spacing.xs,
                    ),
                    children: [
                      ChoiceChip(
                        label: const Text('Assigned to me'),
                        selected:
                            _listKey == WorkItemRepository.assignedToMeKey,
                        onSelected: (_) => _select(
                          WorkItemRepository.assignedToMeKey,
                          'Assigned to me',
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      ChoiceChip(
                        label: const Text('Recently updated'),
                        selected:
                            _listKey == WorkItemRepository.recentlyUpdatedKey,
                        onSelected: (_) => _select(
                          WorkItemRepository.recentlyUpdatedKey,
                          'Recently updated',
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      ChoiceChip(
                        avatar: const Icon(
                          Icons.manage_search_outlined,
                          size: 18,
                        ),
                        label: Text(_query?.name ?? 'Saved query'),
                        selected: _query != null,
                        onSelected: (_) => _pickQuery(),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  ListTile(
                    leading: Icon(Icons.error_outline, color: scheme.error),
                    title: Text(_error!),
                  ),
                if (items.isEmpty && _loadedOnce && !_refreshing)
                  Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 40,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: Spacing.sm),
                        Text(
                          _listKey == WorkItemRepository.assignedToMeKey
                              ? 'Nothing is assigned to you in ${widget.project}.'
                              : 'No work items in "$_listLabel".',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                for (final item in items)
                  _WorkItemTile(
                    item: item,
                    visuals: _visuals,
                    selected: item.id == _selectedId,
                    onTap: () => _open(item),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WorkItemTile extends StatelessWidget {
  const _WorkItemTile({
    required this.item,
    required this.visuals,
    required this.onTap,
    this.selected = false,
  });

  final WorkItem item;
  final WorkItemVisuals visuals;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iteration = pathLeaf(item.iterationPath);
    return ListTile(
      selected: selected,
      selectedTileColor: scheme.secondaryContainer.withValues(alpha: 0.4),
      leading: Icon(
        visuals.typeIcon(item),
        color: visuals.typeColor(context, item),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Row(
          children: [
            Text(
              '${item.type} ${item.id}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            StateDot(color: visuals.stateColor(context, item)),
            const SizedBox(width: Spacing.xs),
            Text(item.state, style: theme.textTheme.labelMedium),
            if (iteration.isNotEmpty) ...[
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: Text(
                  iteration,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
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
