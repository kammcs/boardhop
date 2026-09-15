import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../theme/theme.dart';
import '../shared/account_scope.dart';
import 'form/new_work_item_button.dart';
import 'widgets/query_picker.dart';
import 'work_item_detail_page.dart';
import 'widgets/work_item_list_tile.dart';
import 'widgets/work_item_visuals.dart';
import 'widgets/work_view_switch.dart';

/// The item the list should show after a create: the new one from medium
/// up, where the detail pane is on screen beside the list, and none on a
/// phone, which pushed the detail route from the form instead (iPad
/// walkthrough: the pane kept saying "Select a work item").
int? selectionAfterCreate(int? created, Breakpoint breakpoint) =>
    breakpoint.isAtLeastMedium ? created : null;

/// The loaded list narrowed by what was typed in the filter field
/// (decision D10 of research/15).
///
/// Local only: it looks at the id, title, type, state and assignee of the
/// items already on the device, so it answers while the field is being
/// typed in and works offline. Every word has to match something, so
/// "bug ada" finds Ada's bugs; search (the magnifier on Home) is what
/// reaches the rest of the project.
List<WorkItem> filterWorkItems(List<WorkItem> items, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return items;
  return [
    for (final item in items)
      if (words.every(
        (word) => [
          '${item.id}',
          item.title,
          item.type,
          item.state,
          item.assignedTo?.displayName ?? '',
        ].any((field) => field.toLowerCase().contains(word)),
      ))
        item,
  ];
}

/// Work item lists in one project: "assigned to me", "recently updated" or
/// a saved query, rendered from the drift cache and refreshed on open, on
/// pull and when the list changes.
class WorkItemsPage extends StatefulWidget {
  const WorkItemsPage({
    super.key,
    required this.org,
    required this.project,
    this.initialQueryId,
    this.initialQueryName,
  });

  final String org;
  final String project;

  /// A saved query GUID from the route (`?query=`), which is how a
  /// dashboard's query-backed card opens its query here (research/19 D7).
  /// Null means the page's own default list, Assigned to me.
  final String? initialQueryId;

  /// The label to show until the query tree has been read; the id is what
  /// selects the list.
  final String? initialQueryName;

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
  final _filterController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final queryId = widget.initialQueryId;
    if (queryId != null && queryId.isNotEmpty) {
      _listKey = WorkItemRepository.queryKey(queryId);
      _listLabel = widget.initialQueryName?.trim().isNotEmpty ?? false
          ? widget.initialQueryName!
          : 'Saved query';
      // Enough of a `SavedQuery` for `_refresh` to run it; the picker
      // replaces it wholesale when the person opens the tree.
      _query = SavedQuery(
        id: queryId,
        name: _listLabel,
        path: '',
        isFolder: false,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(WorkItemsPage old) {
    super.didUpdateWidget(old);
    // A second tap on a dashboard card while this page is already up: the
    // route changed under the same State.
    final queryId = widget.initialQueryId;
    if (queryId == old.initialQueryId || queryId == null || queryId.isEmpty) {
      return;
    }
    _select(
      WorkItemRepository.queryKey(queryId),
      widget.initialQueryName?.trim().isNotEmpty ?? false
          ? widget.initialQueryName!
          : 'Saved query',
      query: SavedQuery(
        id: queryId,
        name: widget.initialQueryName ?? 'Saved query',
        path: '',
        isFolder: false,
      ),
    );
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
      // The filter belongs to the list that was on screen.
      _filterController.clear();
      _filter = '';
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

  /// After a create: the list reloads, and in the two-pane layout the new
  /// item opens in the detail pane.
  void _onCreated(int? id) {
    final selected = selectionAfterCreate(id, context.breakpoint);
    if (selected != null) setState(() => _selectedId = selected);
    _refresh();
  }

  void _open(WorkItem item) {
    if (context.breakpoint.isAtLeastMedium) {
      setState(() => _selectedId = item.id);
      return;
    }
    context.push(
      '${orgRoute(context, widget.org)}/projects/'
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
              context.go('${orgRoute(context, widget.org)}/projects'),
        ),
        actions: [
          NewWorkItemButton(
            org: widget.org,
            project: widget.project,
            onCreated: _onCreated,
          ),
          // The switch stays rightmost so it never moves when an action
          // appears next to it.
          WorkViewSwitch(
            org: widget.org,
            project: widget.project,
            current: WorkView.items,
          ),
          const SizedBox(width: Spacing.sm),
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
          final all = snapshot.data ?? const <WorkItem>[];
          final items = filterWorkItems(all, _filter);
          return ContentColumn(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (_refreshing) const LinearProgressIndicator(),
                SizedBox(
                  // The row follows the text scale: at the largest sizes a
                  // fixed 48 clipped the chips' labels (iPad walkthrough).
                  height: MediaQuery.textScalerOf(context)
                      .scale(48)
                      .clamp(48.0, 96.0),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.xs,
                    Spacing.lg,
                    Spacing.sm,
                  ),
                  child: TextField(
                    controller: _filterController,
                    textInputAction: TextInputAction.search,
                    onChanged: (text) => setState(() => _filter = text),
                    decoration: InputDecoration(
                      hintText: 'Filter these items',
                      hintMaxLines: 1,
                      isDense: true,
                      prefixIcon: const Icon(Icons.filter_alt_outlined),
                      suffixIcon: _filter.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear filter',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _filterController.clear();
                                setState(() => _filter = '');
                              },
                            ),
                    ),
                  ),
                ),
                if (_error != null)
                  ListTile(
                    leading: Icon(Icons.error_outline, color: scheme.error),
                    title: Text(_error!),
                  ),
                if (items.isEmpty && all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Spacing.xl),
                    child: Text(
                      'No item here matches "$_filter".',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (all.isEmpty && _loadedOnce && !_refreshing)
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
                  WorkItemListTile(
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
