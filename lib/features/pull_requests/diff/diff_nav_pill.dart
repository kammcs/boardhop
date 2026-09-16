import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'diff_cursor.dart';

/// The ▲▼ control of R6: a floating pill over the diff on a phone
/// ([DiffNavPill]) and a pair of app-bar icon buttons on a tablet
/// ([DiffNavBarControls]). Both show the same "n / m" indicator and open the
/// same mode menu, and both turn an arrow into "Next file: name" or "Back to
/// files" at the ends (R7).
class DiffNavPill extends StatelessWidget {
  const DiffNavPill({
    super.key,
    required this.cursor,
    required this.counts,
    required this.onUp,
    required this.onDown,
    required this.onMode,
  });

  final DiffCursor cursor;

  /// How many stops each mode offers, for the menu's "Changes (12)".
  final Map<DiffNavMode, int> counts;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<DiffNavMode> onMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      borderRadius: BorderRadius.circular(Radii.pill),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        // A "Next file: some-long-name.dart" must not push the pill off a
        // phone; the label ellipsises instead.
        constraints: const BoxConstraints(maxWidth: 320),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Arrow(up: true, label: cursor.upLabel, onPressed: onUp),
            // Flexible so that at xxxL the indicator gives way rather than
            // pushing the pill off the screen.
            Flexible(
              child: DiffNavIndicator(
                cursor: cursor,
                counts: counts,
                onMode: onMode,
                menuOffset: const Offset(0, -196),
              ),
            ),
            _Arrow(up: false, label: cursor.downLabel, onPressed: onDown),
          ],
        ),
      ),
    );
  }
}

/// The middle of the pill: "3 / 12 · Changes", and the mode menu behind it.
class DiffNavIndicator extends StatelessWidget {
  const DiffNavIndicator({
    super.key,
    required this.cursor,
    required this.counts,
    required this.onMode,
    this.showMode = true,
    this.menuOffset = Offset.zero,
  });

  final DiffCursor cursor;
  final Map<DiffNavMode, int> counts;
  final ValueChanged<DiffNavMode> onMode;
  final bool showMode;

  /// Where the mode menu opens. The floating pill sits at the bottom of
  /// the screen, so its menu has to come up over the diff instead of down
  /// off the end of it.
  final Offset menuOffset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<DiffNavMode>(
      tooltip: 'What the arrows step through',
      offset: menuOffset,
      onSelected: onMode,
      itemBuilder: (context) => [
        for (final mode in DiffNavMode.values)
          CheckedPopupMenuItem(
            value: mode,
            checked: mode == cursor.mode,
            child: Text('${mode.label} (${counts[mode] ?? 0})'),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(cursor.mode.icon, size: 16),
            const SizedBox(width: Spacing.xs),
            Flexible(
              child: Text(
                showMode
                    ? '${cursor.indicator} · ${cursor.mode.label}'
                    : cursor.indicator,
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.up,
    required this.label,
    required this.onPressed,
  });

  final bool up;
  final String? label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down;
    if (label == null) {
      return IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: up ? 'Previous' : 'Next',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      );
    }
    // At an end the arrow says where it goes instead (R7). One flexible
    // child and nothing beside it: the label ellipsises rather than
    // pushing the pill off a narrow screen.
    return Flexible(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label!, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _edgeIcon(DiffNavEdge edge, {required bool up}) => switch (edge) {
  DiffNavEdge.stop => up ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
  DiffNavEdge.file => up ? Icons.skip_previous : Icons.skip_next,
  DiffNavEdge.back => Icons.list,
};

/// The same pair in an app bar, which is where the control lives from the
/// expanded breakpoint up (R6).
class DiffNavBarControls extends StatelessWidget {
  const DiffNavBarControls({
    super.key,
    required this.cursor,
    required this.counts,
    required this.onUp,
    required this.onDown,
    required this.onMode,
  });

  final DiffCursor cursor;
  final Map<DiffNavMode, int> counts;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final ValueChanged<DiffNavMode> onMode;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        onPressed: onUp,
        tooltip: cursor.upLabel ?? 'Previous',
        icon: Icon(_edgeIcon(cursor.upEdge, up: true)),
      ),
      DiffNavIndicator(
        cursor: cursor,
        counts: counts,
        onMode: onMode,
        showMode: true,
      ),
      IconButton(
        onPressed: onDown,
        tooltip: cursor.downLabel ?? 'Next',
        icon: Icon(_edgeIcon(cursor.downEdge, up: false)),
      ),
    ],
  );
}
