import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../core/util/format.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../theme/theme.dart';
import 'widgets/work_item_visuals.dart';

/// "Assigned to me" in one project: rendered from the drift cache, refreshed
/// on open and on pull.
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
      await repo.refreshAssignedToMe(widget.org, widget.project);
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

  void _open(WorkItem item) => context.push(
    '/orgs/${Uri.encodeComponent(widget.org)}/projects/'
    '${Uri.encodeComponent(widget.project)}/work-items/${item.id}',
  );

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
              'Assigned to me',
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: StreamBuilder<List<WorkItem>>(
          stream: context.read<WorkItemRepository>().watchList(
            widget.org,
            widget.project,
            WorkItemRepository.assignedToMeKey,
          ),
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <WorkItem>[];
            return ContentColumn(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_refreshing) const LinearProgressIndicator(),
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
                            'Nothing is assigned to you in ${widget.project}.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  for (final item in items) _WorkItemTile(
                    item: item,
                    visuals: _visuals,
                    onTap: () => _open(item),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WorkItemTile extends StatelessWidget {
  const _WorkItemTile({
    required this.item,
    required this.visuals,
    required this.onTap,
  });

  final WorkItem item;
  final WorkItemVisuals visuals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iteration = pathLeaf(item.iterationPath);
    return ListTile(
      leading: Icon(
        visuals.typeIcon(item),
        color: visuals.typeColor(context, item),
      ),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
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
