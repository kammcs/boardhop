import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes.dart';
import '../../../../data/models/work_item.dart';
import '../../../../theme/theme.dart';
import '../../../shared/account_scope.dart';
import '../../../work_items/widgets/work_item_list_tile.dart';
import '../../../work_items/widgets/work_item_visuals.dart';
import '../dashboard_card.dart';

/// How many rows a list card shows before "See all". A card on a phone is
/// as wide as the screen but has to share it with the rest of the
/// dashboard, and a tablet's card is one cell of a packed grid: in both,
/// four rows and a way out beats a scroller inside a scroller.
int rowsFor(DashboardCardArgs args) => args.widget.rowSpan >= 2 ? 6 : 4;

/// The dashboards page lives **inside** the project shell, so a work item
/// opens on [Routes.workItem] and keeps the dock under it;
/// `workItemStandalone` is only for a push that starts over the shell.
void openWorkItem(
  BuildContext context,
  DashboardCardArgs args,
  WorkItem item,
) => context.push(
  Routes.workItem(
    AccountScope.of(context),
    args.org,
    args.project,
    '${item.id}',
  ),
);

/// The body every work-item list card shares: N rows drawn exactly as the
/// Work items page draws them, an empty line when there are none, and a
/// "See all" that opens the full list.
class WorkItemRows extends StatelessWidget {
  const WorkItemRows({
    super.key,
    required this.items,
    required this.visuals,
    required this.rows,
    required this.empty,
    required this.onSeeAll,
    required this.onOpen,
  });

  final List<WorkItem> items;
  final WorkItemVisuals visuals;
  final int rows;
  final String empty;
  final VoidCallback onSeeAll;
  final ValueChanged<WorkItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.md,
          0,
          Spacing.md,
          Spacing.md,
        ),
        child: Text(
          empty,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final shown = items.take(rows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in shown)
          WorkItemListTile(
            item: item,
            visuals: visuals,
            dense: true,
            onTap: () => onOpen(item),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
            child: TextButton(
              onPressed: onSeeAll,
              child: Text(
                items.length > shown.length
                    ? 'See all ${items.length}'
                    : 'See all',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
