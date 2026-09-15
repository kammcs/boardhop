import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes.dart';
import '../../../../data/models/pull_request.dart';
import '../../../../data/repositories/pull_request_repository.dart';
import '../../../../theme/theme.dart';
import '../../../pull_requests/widgets/pull_request_tile.dart';
import '../../../shared/account_scope.dart';
import '../dashboard_card.dart';
import 'work_item_rows.dart';

/// Pull Requests: what is waiting on this person's review first, then their
/// own open ones — the order the web widget uses and the one the project
/// home page already merges.
class PullRequestsCard extends StatefulWidget {
  const PullRequestsCard({super.key, required this.args});

  final DashboardCardArgs args;

  @override
  State<PullRequestsCard> createState() => _PullRequestsCardState();
}

class _PullRequestsCardState extends State<PullRequestsCard>
    with DashboardCardMixin {
  List<PullRequest>? _prs;

  List<PullRequest> _merge(List<PullRequest> toReview, List<PullRequest> mine) {
    final seen = <int>{};
    return [
      for (final pr in [...toReview, ...mine])
        if (seen.add(pr.id)) pr,
    ];
  }

  @override
  Future<void> fetch({required bool refresh}) async {
    final repo = context.read<PullRequestRepository>();
    final org = widget.args.org;
    final project = widget.args.project;
    final cachedReview = await repo.cachedList(
      org,
      project: project,
      filter: PrListFilter.toReview,
    );
    final cachedMine = await repo.cachedList(
      org,
      project: project,
      filter: PrListFilter.mine,
    );
    if (cachedReview != null || cachedMine != null) {
      apply(
        () => _prs = _merge(
          cachedReview?.items ?? const [],
          cachedMine?.items ?? const [],
        ),
      );
    }
    final results = await Future.wait([
      repo.list(org, project: project, filter: PrListFilter.toReview),
      repo.list(org, project: project, filter: PrListFilter.mine),
    ]);
    apply(() => _prs = _merge(results[0], results[1]));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prs = _prs;
    final rows = rowsFor(widget.args);
    final shown = (prs ?? const <PullRequest>[]).take(rows).toList();
    return DashboardCard(
      title: widget.args.widget.name.isNotEmpty
          ? widget.args.widget.name
          : 'Pull requests',
      icon: Icons.call_merge,
      filled: widget.args.filled,
      maxBodyHeight: widget.args.maxBodyHeight,
      loading: loading && prs == null,
      error: error,
      padBody: false,
      child: shown.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.md,
              ),
              child: Text(
                'Nothing to review and nothing of yours open.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final pr in shown)
                  PullRequestTile(
                    pr: pr,
                    onTap: () => context.push(
                      Routes.pullRequest(
                        AccountScope.of(context),
                        widget.args.org,
                        '${pr.id}',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
