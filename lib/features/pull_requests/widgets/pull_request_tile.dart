import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/pull_request.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_visuals.dart';
import 'pr_visuals.dart';

/// One pull request as the inbox draws it: author avatar, title, the
/// repository and `!id` line, draft badge, auto-complete badge, why it is
/// in your inbox, overall vote and the branches.
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
    this.meId,
  });

  final PullRequest pr;
  final VoidCallback onTap;

  /// Prefixes the subtitle with the project, for a list that spans more
  /// than one (the org inbox, an All-projects search).
  final bool showProject;

  /// The signed-in identity, which is what turns a row into a reason
  /// (R13). Null — a search hit outside the inbox — draws no reason.
  final String? meId;

  /// Why this pull request is in front of you (R13).
  ///
  /// Author first: a pull request you raised is yours whatever else you are
  /// on it. A draft with no other reason says so, because "why is this
  /// here" is then the draft itself. Labels, comment counts and reviewer
  /// avatars stay out of the row (decision R13).
  static String? reasonFor(PullRequest pr, String? meId) {
    if (meId != null) {
      if (pr.createdBy.id == meId) return 'Author';
      final mine = pr.reviewer(meId);
      if (mine != null) {
        return mine.isRequired ? 'Required reviewer' : 'Reviewer';
      }
    }
    return pr.isDraft ? 'Draft' : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vote = pr.overallVote;
    final reason = reasonFor(pr, meId);
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
              '${pr.repositoryName} · !${pr.id}'
              '${reason == null ? '' : ' · $reason'}',
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
                if (pr.isAutoCompleteSet) ...[
                  const AutoCompleteBadge(),
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

/// The inbox's auto-complete marker, drawn like the draft badge so the two
/// read as one family (R13).
class AutoCompleteBadge extends StatelessWidget {
  const AutoCompleteBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: Radii.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule_send,
            size: 12,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 2),
          Text(
            'Auto-complete',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
