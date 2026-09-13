import 'package:flutter/material.dart';

import '../../../data/models/pr_check.dart';
import '../../../data/models/pull_request.dart';
import '../../../theme/theme.dart';

/// The Checks row's icon. A failing policy that does not block the merge
/// gets a warning triangle rather than the blocking red X: the two read
/// identically otherwise, so an optional build failure looked as though it
/// stopped the PR (iPhone walkthrough, finding k). [isBlocking] is false
/// for PR statuses, which never block on their own.
IconData checkIcon(PrCheckState state, {bool isBlocking = true}) =>
    switch (state) {
      PrCheckState.succeeded => Icons.check_circle,
      PrCheckState.failed =>
        isBlocking ? Icons.cancel : Icons.warning_amber_rounded,
      PrCheckState.pending => Icons.schedule,
      PrCheckState.error => Icons.error_outline,
      PrCheckState.notApplicable => Icons.remove_circle_outline,
    };

/// The Checks row's color; see [checkIcon] for [isBlocking].
Color checkColor(
  BuildContext context,
  PrCheckState state, {
  bool isBlocking = true,
}) {
  final colors = context.boardhopColors;
  final scheme = Theme.of(context).colorScheme;
  return switch (state) {
    PrCheckState.succeeded => colors.voteApproved,
    PrCheckState.failed =>
      isBlocking ? colors.voteRejected : colors.voteWaiting,
    PrCheckState.pending => colors.voteWaiting,
    PrCheckState.error => scheme.error,
    PrCheckState.notApplicable => scheme.onSurfaceVariant,
  };
}

/// Text and color for `mergeStatus` on the overview; null when the service
/// has not evaluated the merge yet.
(String, Color)? mergeStatusLabel(BuildContext context, String? status) {
  final colors = context.boardhopColors;
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'succeeded' => ('No merge conflicts', colors.voteApproved),
    'conflicts' => ('Merge conflicts', colors.voteRejected),
    'queued' => ('Merge check pending', colors.voteWaiting),
    'failure' => ('Merge failed', scheme.error),
    'rejectedByPolicy' => ('Merge rejected by policy', scheme.error),
    _ => null,
  };
}

IconData voteIcon(PrVote vote) => switch (vote) {
  PrVote.approved => Icons.check_circle,
  PrVote.approvedWithSuggestions => Icons.check_circle_outline,
  PrVote.waitingForAuthor => Icons.hourglass_top,
  PrVote.rejected => Icons.cancel,
  PrVote.none => Icons.radio_button_unchecked,
};

Color voteColor(BuildContext context, PrVote vote) {
  final colors = context.boardhopColors;
  return switch (vote) {
    PrVote.approved => colors.voteApproved,
    PrVote.approvedWithSuggestions => colors.voteApprovedWithSuggestions,
    PrVote.waitingForAuthor => colors.voteWaiting,
    PrVote.rejected => colors.voteRejected,
    PrVote.none => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

Color prStatusColor(BuildContext context, String status) {
  final colors = context.boardhopColors;
  return switch (status) {
    'completed' => colors.prCompleted,
    'abandoned' => colors.prAbandoned,
    _ => colors.prActive,
  };
}

class DraftChip extends StatelessWidget {
  const DraftChip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Radii.chip,
      ),
      child: Text('Draft', style: Theme.of(context).textTheme.labelSmall),
    );
  }
}
