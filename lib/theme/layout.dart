import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Width classes following Material 3 window size classes. Phones are
/// `compact`; small tablets and phones in landscape are `medium`; large
/// tablets are `expanded`. The decision for v1 is a responsive layout, with
/// multi-pane treatment added later for `medium` and `expanded`.
enum Breakpoint {
  compact,
  medium,
  expanded;

  static Breakpoint fromWidth(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    return expanded;
  }

  bool get isCompact => this == compact;
  bool get isAtLeastMedium => this != compact;
}

extension BreakpointContext on BuildContext {
  Breakpoint get breakpoint =>
      Breakpoint.fromWidth(MediaQuery.sizeOf(this).width);
}

/// Centers content and caps its width on wide screens so list rows and
/// forms do not stretch across a tablet.
///
/// The cap follows the space: up to [readable] the column takes the full
/// width; beyond it, it grows with the window (keeping a [Spacing.xl]
/// margin on each side) up to [wide]. Material's 840 dp column alone left a
/// third of an iPad in landscape empty (Kelly, 2026-09-11).
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.child,
    this.maxWidth,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;

  /// Fixed cap; null follows [widthFor].
  final double? maxWidth;
  final Alignment alignment;

  /// Width up to which content fills the window.
  static const double readable = 840;

  /// Largest content width on tablets.
  static const double wide = 1120;

  /// Content width from which [SideBySide] puts its halves next to each
  /// other.
  static const double twoColumnMin = 960;

  static double widthFor(double available) => math.min(
    available,
    math.max(readable, math.min(wide, available - 2 * Spacing.xl)),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? widthFor(constraints.maxWidth),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Two groups of sections that sit next to each other when there is room
/// ([ContentColumn.twoColumnMin] or more) and stack, [start] first, when
/// there is not. Meant as one child of a page's vertical `ListView`.
class SideBySide extends StatelessWidget {
  const SideBySide({
    super.key,
    required this.start,
    required this.end,
    this.startFlex = 1,
    this.endFlex = 1,
    this.minWidth = ContentColumn.twoColumnMin,
  });

  final List<Widget> start;
  final List<Widget> end;
  final int startFlex;
  final int endFlex;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [...start, ...end],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: startFlex,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: start,
              ),
            ),
            const SizedBox(width: Spacing.lg),
            Expanded(
              flex: endFlex,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: end,
              ),
            ),
          ],
        );
      },
    );
  }
}
