import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'mention_controller.dart';

/// The quiet line a composer puts above its Send button while the draft
/// contains an `@word` nobody picked (research/16 M7).
///
/// A hand-typed `@kelly` is not a mention and notifies nobody — the service
/// creates a mention from `@<guid>`, never from what the text looks like
/// (research/16 §1) — so the user has to be told, once, without a dialog in
/// the way of posting.
class MentionHint extends StatelessWidget {
  const MentionHint({super.key, required this.controller, this.padding});

  final MentionController controller;

  /// Defaults to a small gap above the buttons.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final words = controller.unresolvedAtWords;
        if (words.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding:
              padding ??
              const EdgeInsets.only(top: Spacing.xs, bottom: Spacing.xs),
          child: Text(
            '${words.first} is not a mention. '
            'Pick from the list to notify someone.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );
      },
    );
  }
}
