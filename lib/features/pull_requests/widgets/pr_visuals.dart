import 'package:flutter/material.dart';

import '../../../data/models/pull_request.dart';
import '../../../theme/theme.dart';

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
