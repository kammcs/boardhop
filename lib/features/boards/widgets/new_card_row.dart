import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// The `+ New item` row at the bottom of a board column (research/11 §4.1):
/// a card-shaped outline in the column's own quiet palette, so it reads as
/// the next, empty card rather than as a button.
class NewCardRow extends StatelessWidget {
  const NewCardRow({super.key, required this.onTap, this.label = 'New item'});

  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: Radii.card,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Padding(
                padding: Spacing.card,
                child: Row(
                  children: [
                    Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: Spacing.sm),
                    Flexible(
                      child: Text(
                        label,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
