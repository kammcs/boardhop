import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes.dart';
import '../../../../data/models/work_item.dart';
import '../../../../data/repositories/work_item_repository.dart';
import '../../../shared/account_scope.dart';
import '../../../work_items/widgets/work_item_visuals.dart';
import '../dashboard_card.dart';
import 'work_item_rows.dart';

/// Assigned to Me: the signed-in person's open work in this project, which
/// is exactly the list the Work items page opens on, from the same cache.
class AssignedToMeCard extends StatefulWidget {
  const AssignedToMeCard({super.key, required this.args});

  final DashboardCardArgs args;

  @override
  State<AssignedToMeCard> createState() => _AssignedToMeCardState();
}

class _AssignedToMeCardState extends State<AssignedToMeCard>
    with DashboardCardMixin {
  List<WorkItem>? _items;
  WorkItemVisuals _visuals = const WorkItemVisuals({});

  @override
  Future<void> fetch({required bool refresh}) async {
    final repo = context.read<WorkItemRepository>();
    final org = widget.args.org;
    final project = widget.args.project;
    final cached = await repo
        .watchList(org, project, WorkItemRepository.assignedToMeKey)
        .first;
    if (cached.isNotEmpty) apply(() => _items = cached);
    final types = await repo.types(org, project);
    apply(() => _visuals = WorkItemVisuals({for (final t in types) t.name: t}));
    final items = await repo.refreshAssignedToMe(org, project);
    apply(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return DashboardCard(
      title: widget.args.widget.name.isNotEmpty
          ? widget.args.widget.name
          : 'Assigned to me',
      icon: Icons.assignment_ind_outlined,
      filled: widget.args.filled,
      maxBodyHeight: widget.args.maxBodyHeight,
      loading: loading && items == null,
      error: error,
      padBody: false,
      child: WorkItemRows(
        items: items ?? const [],
        visuals: _visuals,
        rows: rowsFor(widget.args),
        empty: 'Nothing is assigned to you here.',
        onSeeAll: () => context.go(
          Routes.workItems(
            AccountScope.of(context),
            widget.args.org,
            widget.args.project,
          ),
        ),
        onOpen: (item) => openWorkItem(context, widget.args, item),
      ),
    );
  }
}
