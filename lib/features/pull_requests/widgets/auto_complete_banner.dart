import 'package:flutter/material.dart';

import '../../../data/models/pr_check.dart';
import '../../../data/models/pull_request.dart';
import '../../../theme/theme.dart';
import 'merge_box.dart';

/// "Auto-complete set by Kelly Kamm · waiting on 2 policies" with one tap to
/// cancel (R2).
///
/// GitHub Mobile shows its auto-merge state the same way and offers the
/// one-tap disable from the merge box; the wording here names the person
/// because on a shared pull request it is often not you.
class AutoCompleteBanner extends StatelessWidget {
  const AutoCompleteBanner({
    super.key,
    required this.pr,
    required this.checks,
    required this.onCancel,
    this.busy = false,
  });

  final PullRequest pr;
  final List<PrCheck> checks;
  final VoidCallback onCancel;
  final bool busy;

  /// What the service is still waiting for, counted from the blocking rows
  /// the merge box shows.
  static int waitingOn(PullRequest pr, List<PrCheck> checks) {
    var n = checks
        .where(
          (c) =>
              c.isBlocking &&
              (c.state == PrCheckState.failed ||
                  c.state == PrCheckState.pending ||
                  c.state == PrCheckState.error),
        )
        .length;
    if (!prMergeReady(pr)) n++;
    return n;
  }

  static String describe(PullRequest pr, List<PrCheck> checks) {
    final who = pr.autoCompleteSetBy?.displayName ?? 'someone';
    final n = waitingOn(pr, checks);
    final strategy = pr.completionOptions?.mergeStrategy?.label;
    return [
      'Auto-complete set by $who',
      if (n > 0) 'waiting on $n ${n == 1 ? 'check' : 'checks'}',
      if (n == 0) 'merging',
      if (strategy != null) strategy.toLowerCase(),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (!pr.isAutoCompleteSet) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, Spacing.sm),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: Radii.card,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.sm,
            Spacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule_send,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  describe(pr, checks),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              TextButton(
                onPressed: busy ? null : onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
