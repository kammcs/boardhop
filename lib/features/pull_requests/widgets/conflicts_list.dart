import 'package:flutter/material.dart';

import '../../../data/models/pull_request.dart';
import '../../../theme/theme.dart';

/// The merge conflicts behind `mergeStatus: conflicts`, read-only (R2).
///
/// Resolving one is out of v1 (research/22 §6), so these rows say which
/// file clashes and how, and nothing more: the work belongs in a checkout.
class ConflictsList extends StatelessWidget {
  const ConflictsList({super.key, required this.conflicts, this.max = 20});

  final List<PrConflict> conflicts;

  /// A rebase gone wrong can produce hundreds; the rest are counted.
  final int max;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.boardhopColors;
    final unresolved = [
      for (final c in conflicts)
        if (!c.isResolved) c,
    ];
    final shown = unresolved.take(max).toList();
    final rest = unresolved.length - shown.length;
    if (unresolved.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in shown)
          ListTile(
            dense: true,
            leading: Icon(Icons.merge_type, color: colors.voteRejected),
            title: Text(
              c.path.substring(c.path.lastIndexOf('/') + 1),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${c.typeLabel} · ${c.path}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (rest > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.sm,
            ),
            child: Text(
              'and $rest more.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
