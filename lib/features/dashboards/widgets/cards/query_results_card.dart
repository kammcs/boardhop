import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes.dart';
import '../../../../data/models/dashboard.dart';
import '../../../../data/models/work_item.dart';
import '../../../../data/repositories/work_item_repository.dart';
import '../../../shared/account_scope.dart';
import '../../../work_items/widgets/work_item_visuals.dart';
import '../dashboard_card.dart';
import 'work_item_rows.dart';

/// Query Results: the first rows of a saved query, then "See all".
///
/// `refreshQuery` is the call the Work items page already makes for a saved
/// query — `wiql/{id}` then `workitemsbatch` — so the rows land in the same
/// `query:{id}` cache and the See-all opens instantly.
class QueryResultsCard extends StatefulWidget {
  const QueryResultsCard({
    super.key,
    required this.args,
    required this.settings,
  });

  final DashboardCardArgs args;
  final QueryResultsSettings settings;

  @override
  State<QueryResultsCard> createState() => _QueryResultsCardState();
}

class _QueryResultsCardState extends State<QueryResultsCard>
    with DashboardCardMixin {
  List<WorkItem>? _items;
  WorkItemVisuals _visuals = const WorkItemVisuals({});

  @override
  Future<void> fetch({required bool refresh}) async {
    final repo = context.read<WorkItemRepository>();
    final org = widget.args.org;
    final project = widget.args.project;
    // Offline first: whatever the query cached last time, before anything
    // touches the network.
    final cached = await repo
        .watchList(
          org,
          project,
          WorkItemRepository.queryKey(widget.settings.queryId),
        )
        .first;
    if (cached.isNotEmpty) apply(() => _items = cached);
    final types = await repo.types(org, project);
    apply(() => _visuals = WorkItemVisuals({for (final t in types) t.name: t}));
    final items = await repo.refreshQuery(
      org,
      project,
      widget.settings.queryId,
    );
    apply(() => _items = items);
  }

  void _openQuery() {
    context.go(
      Routes.workItems(
        AccountScope.of(context),
        widget.args.org,
        widget.args.project,
        query: widget.settings.queryId,
        queryName: widget.settings.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return DashboardCard(
      title: widget.args.widget.name.isNotEmpty
          ? widget.args.widget.name
          : widget.settings.label ?? 'Query results',
      icon: Icons.list_alt_outlined,
      filled: widget.args.filled,
      maxBodyHeight: widget.args.maxBodyHeight,
      loading: loading && items == null,
      error: error,
      padBody: false,
      child: WorkItemRows(
        items: items ?? const [],
        visuals: _visuals,
        rows: rowsFor(widget.args),
        empty: 'No work items in this query.',
        onSeeAll: _openQuery,
        onOpen: (item) => openWorkItem(context, widget.args, item),
      ),
    );
  }
}
