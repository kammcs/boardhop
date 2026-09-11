import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/git_repository.dart';
import '../../../data/models/work_item.dart';
import '../../../theme/theme.dart';
import '../../work_items/widgets/work_item_visuals.dart';

/// Avatar for a commit author: commits carry only a name and email, so the
/// initials fall back through [IdentityAvatar] without a Graph lookup.
class CommitAvatar extends StatelessWidget {
  const CommitAvatar({super.key, required this.name, this.radius = 16});

  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) => IdentityAvatar(
    identity: name == null || name!.isEmpty
        ? null
        : IdentityRef(displayName: name!),
    radius: radius,
  );
}

/// `+3 ~2 −1` for a commit's change counts.
class ChangeCounts extends StatelessWidget {
  const ChangeCounts({super.key, required this.commit});

  final GitCommit commit;

  @override
  Widget build(BuildContext context) {
    final colors = context.boardhopColors;
    final style = Theme.of(context).textTheme.labelSmall;
    final scheme = Theme.of(context).colorScheme;
    if (!commit.hasCounts) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if ((commit.added ?? 0) > 0)
          Text(
            '+${commit.added} ',
            style: style?.copyWith(color: colors.diffAdded),
          ),
        if ((commit.edited ?? 0) > 0)
          Text(
            '~${commit.edited} ',
            style: style?.copyWith(color: scheme.onSurfaceVariant),
          ),
        if ((commit.deleted ?? 0) > 0)
          Text(
            '−${commit.deleted}',
            style: style?.copyWith(color: colors.diffRemoved),
          ),
      ],
    );
  }
}

/// One commit row: avatar, subject, author · time · short id, counts.
class CommitTile extends StatelessWidget {
  const CommitTile({
    super.key,
    required this.commit,
    this.onTap,
    this.selected = false,
  });

  final GitCommit commit;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final who = [
      if (commit.authorName != null) commit.authorName!,
      if (commit.authorDate != null) relativeTime(commit.authorDate),
      commit.shortId,
    ].join(' · ');
    return ListTile(
      selected: selected,
      leading: CommitAvatar(name: commit.authorName),
      title: Text(
        commit.subject.isEmpty ? '(no message)' : commit.subject,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              who,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (commit.isMerge)
            Padding(
              padding: const EdgeInsets.only(left: Spacing.sm),
              child: Icon(
                Icons.call_merge,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: Spacing.sm),
            child: ChangeCounts(commit: commit),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// Letter badge for a change type: A / M / D / R.
class ChangeBadge extends StatelessWidget {
  const ChangeBadge({super.key, required this.change});

  final GitChange change;

  @override
  Widget build(BuildContext context) {
    final colors = context.boardhopColors;
    final scheme = Theme.of(context).colorScheme;
    final (String letter, Color color) = change.isAdd
        ? ('A', colors.diffAdded)
        : change.isDelete
        ? ('D', colors.diffRemoved)
        : change.isRename
        ? ('R', scheme.tertiary)
        : ('M', scheme.primary);
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: Radii.chip,
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// One changed file row for a commit or a comparison.
class ChangeTile extends StatelessWidget {
  const ChangeTile({super.key, required this.change, this.onTap});

  final GitChange change;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folder = RepoPaths.parent(change.path);
    return ListTile(
      leading: ChangeBadge(change: change),
      title: Text(change.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        change.isRename && change.originalPath != null
            ? '${change.originalPath} → $folder'
            : folder,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Route to the diff page for one changed file between two commits.
String diffRoute(
  String base, {
  required GitChange change,
  required String oldRef,
  required String newRef,
}) {
  final q = <String, String>{
    'path': change.path,
    'old': oldRef,
    'new': newRef,
    'change': change.changeType,
    if (change.originalPath != null) 'original': change.originalPath!,
  };
  return '$base/diff?${q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
}
