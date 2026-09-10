import 'package:flutter/widgets.dart';

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
class ContentColumn extends StatelessWidget {
  const ContentColumn({
    super.key,
    required this.child,
    this.maxWidth = 840,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
