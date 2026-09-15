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

/// How much bigger than the default the user's text is, capped where chart
/// axes stop being readable.
///
/// A chart's axis labels are laid out in a box of a fixed width, so at xxxL
/// a two-digit number wrapped onto two lines and the dates ran into each
/// other (iPhone 17, research/19 D-C). Every chart sizes its reserved axis
/// space and thins its ticks with this.
double axisTextScale(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 1.6);

/// A chart's y axis: a round maximum at or above the data, and the gridline
/// interval that divides it.
///
/// Charts used to take `dataMax * 1.1` as the axis maximum and let fl_chart
/// pick the interval from that, which put the headroom value itself on the
/// axis: nine items read **9.9**, seventeen read **18.7**, a bar of two read
/// **2.3** (D-D walkthrough). Rounding the maximum first makes every label a
/// number the data could actually take.
@immutable
class ChartAxis {
  const ChartAxis(this.max, this.interval);

  /// The axis maximum: [interval] times a whole number of divisions.
  final double max;

  /// The gap between gridlines, and so between labels.
  final double interval;

  /// Whether the label at [value] is drawn.
  ///
  /// The topmost one is not: fl_chart centres it on the plot area's top
  /// edge, so half of it lands in the caption above the chart. Comparing
  /// against a half interval rather than against the maximum itself is what
  /// makes that reliable — the generated values accumulate rounding, so a
  /// `value >= max` test let `9.9` through whenever the last step landed an
  /// epsilon low.
  bool showsLabel(double value) => value >= 0 && value <= max - interval * 0.5;

  /// [value] written with exactly the precision this axis needs.
  ///
  /// A shared one-decimal formatter printed a gridline at 0.25 as **0.3** and
  /// the one at 0.75 as **0.8**, so the axis named numbers it was not drawing
  /// (D-D walkthrough). Trailing zeros are trimmed, so a whole-number axis
  /// still reads `0 2 4`, not `0.00 2.00 4.00`.
  String label(double value) {
    final text = value.toStringAsFixed(_decimals);
    if (!text.contains('.')) return text;
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// How many decimals [interval] needs to be written exactly.
  int get _decimals {
    for (var d = 0; d <= 3; d++) {
      final scaled = interval * math.pow(10, d);
      if ((scaled - scaled.roundToDouble()).abs() < 1e-9) return d;
    }
    return 3;
  }
}

/// The nice-number steps an axis may use, smallest first within a decade.
const _axisSteps = [1.0, 2.0, 2.5, 5.0];

/// A [ChartAxis] covering `0 … dataMax` in at most [ticks] divisions.
///
/// [integral] keeps the interval a whole number, which is what a count of
/// work items wants: "2.5 items" is not a quantity. [strict] adds a division
/// when the data lands exactly on the maximum, for a chart whose marks have
/// width of their own — a scatter dot at the top would otherwise be drawn
/// half outside the plot area.
ChartAxis chartAxis(
  double dataMax, {
  int ticks = 5,
  bool integral = false,
  bool strict = false,
}) {
  if (!dataMax.isFinite || dataMax <= 0) {
    return strict ? const ChartAxis(2, 1) : const ChartAxis(1, 1);
  }
  for (var power = -6; power <= 15; power++) {
    final magnitude = math.pow(10, power).toDouble();
    for (final mantissa in _axisSteps) {
      final step = mantissa * magnitude;
      if (integral && (step < 1 || step != step.roundToDouble())) continue;
      // The epsilon keeps a maximum that is already a multiple of the step
      // from gaining a whole empty division to floating-point noise.
      var divisions = (dataMax / step - 1e-9).ceil();
      if (strict && step * divisions <= dataMax + 1e-9) divisions += 1;
      if (divisions >= 1 && divisions <= ticks) {
        return ChartAxis(step * divisions, step);
      }
    }
  }
  return ChartAxis(dataMax, dataMax);
}

/// How many gridlines a chart of this text size can carry.
///
/// At xxxL the labels are half again as tall, and five of them on a card's
/// 220 dp chart run together.
int axisTicks(double textScale) => textScale > 1.3 ? 3 : 5;

/// The padding around a chart's plot area.
///
/// The right side is the load-bearing one: the last x label is centred on
/// the plot area's right edge, so without room for its own second half
/// `15 Sep` printed as `15 Se` against the card's edge (D-D walkthrough).
/// Half a `d MMM` label at `labelSmall` is about 16 dp, and it grows with
/// the text.
EdgeInsets chartInsets(double textScale) =>
    EdgeInsets.only(top: Spacing.sm, right: Spacing.sm + 14 * textScale);

/// How far a menu opened from an app bar's trailing action is nudged away
/// from that edge.
///
/// On iOS and macOS the floating glass rail sits just outside the page's
/// trailing edge in landscape, so a popup menu aligned to its button's own
/// edge opened hard against the rail, the two separated only by the rail's
/// shadow margin (iPad walkthrough). Pulling the menu inward gives them a
/// real gap. In portrait, where the bar lies along the bottom, this simply
/// keeps the menu a little clear of the screen edge, which is no worse.
const Offset kTrailingMenuOffset = Offset(-Spacing.xxl, Spacing.sm);

/// Bottom padding for a scroll view that sets its own `padding`.
///
/// A `ListView` with a null `padding` consumes the ambient
/// `MediaQuery.padding`, which is how a page's last row clears the home
/// indicator and the shell's floating glass bar. Setting `padding`
/// suppresses that, so the end of the list slid under the bar and the
/// last row could not be reached (found on the project home page when
/// the bar moved down to Apple's own height, 2026-09-12). This keeps
/// [extra] as the breathing room a page wants and grows to the inset
/// whenever the inset is larger.
EdgeInsets scrollEndPadding(
  BuildContext context, {
  double extra = Spacing.xxl,
}) => EdgeInsets.only(
  bottom: math.max(extra, MediaQuery.paddingOf(context).bottom),
);

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
  ///
  /// 880, not 960: the iPhone Duo's inner display (ships 2026-10-23) is a
  /// regular x regular window where [widthFor] yields 903 pt of content,
  /// so a 960 threshold would have left the fold showing one column on a
  /// screen with room for two (research/12b, Kelly approved 2026-09-12).
  /// 880 still keeps a phone in landscape and a small tablet on one
  /// column: an iPad Pro 11" in portrait gives 834.
  static const double twoColumnMin = 880;

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
