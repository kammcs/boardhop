import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/pull_request.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'pr_visuals.dart';

/// One pull request as the inbox draws it: author avatar, title, the
/// repository and `!id` line, draft badge, overall vote and the branches.
///
/// Lifted out of `PullRequestsPage` so search can show a pull request hit
/// exactly as the list does (research/15 §4: "PR rows as the PR list draws
/// them"); the list is still its only other caller.
class PullRequestTile extends StatelessWidget {
  const PullRequestTile({
    super.key,
    required this.pr,
    required this.onTap,
    this.showProject = false,
  });

  final PullRequest pr;
  final VoidCallback onTap;

  /// Prefixes the subtitle with the project, for a list that spans more
  /// than one (the org inbox, an All-projects search).
  final bool showProject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vote = pr.overallVote;
    return ListTile(
      leading: IdentityAvatar(identity: pr.createdBy, radius: 16),
      title: Text(pr.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: Spacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${showProject ? '${pr.projectName} / ' : ''}'
              '${pr.repositoryName} · !${pr.id}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                if (pr.isDraft) ...[
                  const DraftChip(),
                  const SizedBox(width: Spacing.xs),
                ],
                Icon(voteIcon(vote), size: 14, color: voteColor(context, vote)),
                const SizedBox(width: Spacing.xs),
                Flexible(
                  child: Text(
                    '${pr.sourceBranch} → ${pr.targetBranch}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      trailing: Text(
        relativeTime(pr.creationDate),
        style: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}
