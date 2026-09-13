import 'dart:math' as math;

import 'package:flutter/material.dart' hide Durations;

import '../../theme/theme.dart';

/// Landing a pushed notification on the exact thing it is about
/// (research/14 §4.2): the page scrolls the anchored card into view and
/// tints it for about two seconds so the eye finds it among its neighbours.
///
/// Three pages share this: a work item comment, a pull request thread and a
/// pending approval.

/// How long an anchored card stays tinted.
const Duration kAnchorHighlight = Duration(seconds: 2);

/// The tint an anchored card wears, fading away when [active] turns false.
///
/// A fill behind the child and a hairline drawn over its edge: a work item
/// comment has no background of its own and takes the fill, while a thread
/// card and an approval card paint their own surface over it, so the ring is
/// what marks them. Inactive both are the same colours at zero opacity, so a
/// card that was never anchored looks exactly as it did before R2.5.
class AnchorHighlight extends StatelessWidget {
  const AnchorHighlight({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = scheme.secondaryContainer;
    final edge = scheme.onSecondaryContainer;
    return AnimatedContainer(
      duration: Durations.slow,
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: Radii.card,
        color: active ? tint : tint.withValues(alpha: 0),
      ),
      // Painted over the child, so it costs no layout and shows on a card
      // that has a background of its own.
      foregroundDecoration: BoxDecoration(
        borderRadius: Radii.card,
        border: Border.all(
          color: edge.withValues(alpha: active ? 0.85 : 0),
          width: 2,
        ),
      ),
      child: child,
    );
  }
}

/// Scrolls the widget carrying [target] into view, and returns whether it
/// got there.
///
/// The anchored card usually sits below the fold of a lazy list, so its key
/// has no element yet. Two ways to bring it into being, one frame at a time:
/// scrolling [fallback] (the section or list header) into view inflates the
/// rows under it, and a [scroller] on the list itself is paged forward until
/// the row is built. Up to [attempts] frames are spent on that; a card that
/// never appears -- a comment deleted, or past the page that was read --
/// leaves the page where it is with no error, which is what research/14
/// §4.2 asks for.
Future<bool> revealAnchor({
  required GlobalKey target,
  GlobalKey? fallback,
  ScrollController? scroller,
  double alignment = 0.15,
  int attempts = 12,
}) async {
  for (var i = 0; i < attempts; i++) {
    final anchored = target.currentContext;
    if (anchored != null && anchored.mounted) {
      await Scrollable.ensureVisible(
        anchored,
        alignment: alignment,
        duration: Durations.normal,
        curve: Curves.easeOut,
      );
      return true;
    }
    final below = fallback?.currentContext;
    if (below != null && below.mounted) {
      await Scrollable.ensureVisible(
        below,
        alignment: 0,
        duration: Durations.fast,
        curve: Curves.easeOut,
      );
    } else if (scroller != null && scroller.hasClients) {
      // Page down the list itself; the rows build as they come within
      // reach, and the final ensureVisible places the one we want.
      final position = scroller.position;
      if (position.pixels >= position.maxScrollExtent) return false;
      position.jumpTo(
        math.min(
          position.pixels + position.viewportDimension * 0.8,
          position.maxScrollExtent,
        ),
      );
    }
    await WidgetsBinding.instance.endOfFrame;
  }
  return target.currentContext != null;
}
