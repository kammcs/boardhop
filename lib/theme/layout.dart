import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/display_environment.dart';
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

/// Whether a root-tab app bar should drop its project-name title.
///
/// A phone in portrait leaves the title about 60 dp once the project tile,
/// the bell or another action and a three-segment pill are in the bar, so
/// "DevOps Mobile App" read as "De…" (Kelly, 2026-09-16). The tile already
/// names the project, so on a compact width in portrait the Home, Work and
/// Board bars show no title at all; landscape phones and tablets keep it.
bool hidesProjectTitle(BuildContext context) =>
    context.breakpoint.isCompact &&
    MediaQuery.orientationOf(context) == Orientation.portrait;

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

// MARK: the crease (research/23 §4.4, D3)

/// The active fold's keep-out band in the coordinates of the box [context]
/// lays out, or null when nothing is folded, the display does not fold, or
/// the band misses this box.
///
/// [DisplayScope] reports the band in **window** coordinates (a zero-width
/// crease line with 20 pt of margin on each side: 40 x 669 at x 455.5 in the
/// Duo's wide pose), and a page's box is not the window — the shell keeps
/// 84 pt for the system's bar column, so a pane that split its own box in
/// half would miss the crease by 42 pt. The conversion is the box's own
/// [RenderBox.localToGlobal], which is why this takes a context that is
/// inside a `LayoutBuilder` rather than a bare size.
///
/// **One frame of lag.** The render object's transform is the one the last
/// layout left, so on the very first layout of a box there is nothing to
/// convert and this answers null; a rebuild is requested for the next frame,
/// and from then on the answer is current. Reading the scope also subscribes
/// the caller to it, so a fold, an unfold or a rotation rebuilds the box on
/// its own — which is the whole point of [DisplayEnvironment] pushing rather
/// than the page polling (§9.2).
Rect? creaseInBox(BuildContext context, BoxConstraints constraints) {
  final band = DisplayScope.maybeOf(context)?.creaseBand;
  if (band == null) return null;
  final object = context.findRenderObject();
  if (object is! RenderBox || !object.attached || !object.hasSize) {
    _rebuildNextFrame(context);
    return null;
  }
  final local = band.shift(-object.localToGlobal(Offset.zero));
  final box =
      Offset.zero &
      Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : object.size.width,
        constraints.hasBoundedHeight
            ? constraints.maxHeight
            : object.size.height,
      );
  return local.overlaps(box) ? local : null;
}

/// Marks [context] dirty once this frame is over, so a box that had no
/// transform yet gets a second chance at [creaseInBox].
void _rebuildNextFrame(BuildContext context) {
  final element = context as Element;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (element.mounted) element.markNeedsBuild();
  });
}

/// Whether [band] is a crease that runs top to bottom (the book pose),
/// which is the one that splits a row of panes.
bool isVerticalCrease(Rect? band) => band != null && band.height > band.width;

/// The width of a master/detail pane, put **on** the crease when there is
/// one.
///
/// Without a fold this is the screen's own rule: [fraction] of [maxWidth],
/// clamped to `[min, max]`. With an active vertical crease whose leading
/// edge falls inside that same range, the pane ends exactly where the
/// keep-out band begins, so the divider can fill the band and the detail
/// pane starts on the other panel (research/23 D3). A crease outside the
/// range is ignored — a 200 pt list pane is worse than a divider off the
/// fold.
double paneWidthFor({
  required double maxWidth,
  required double fraction,
  required double min,
  required double max,
  Rect? creaseBand,
}) {
  if (isVerticalCrease(creaseBand)) {
    final edge = creaseBand!.left;
    if (edge >= min && edge <= max && creaseBand.right < maxWidth) return edge;
  }
  return (maxWidth * fraction).clamp(min, max);
}

/// How wide the divider between a master pane and its detail is: the whole
/// keep-out band when [paneWidthFor] landed the pane on the crease, and a
/// hairline everywhere else.
///
/// A [VerticalDivider] draws its 1 pt line centred in the width it is
/// given, so a divider the band's width puts the line on the crease itself
/// and leaves the 20 pt margins on each side empty — which is exactly what
/// the band asks for.
double paneDividerWidth(Rect? creaseBand, double paneWidth) =>
    isVerticalCrease(creaseBand) && (creaseBand!.left - paneWidth).abs() < 0.5
    ? creaseBand.width
    : 1;

/// Pads a page so its content does not come to rest inside an active
/// **horizontal** crease band (the laptop and tent poses).
///
/// The shell wraps every page in one of these, so pages need nothing. What
/// it changes is `MediaQuery.padding` — the inset a `ListView` with a null
/// `padding` consumes, that [scrollEndPadding] grows to, and that every
/// bottom-anchored control in the app already reads:
///
/// * Band in the lower part of the box: the bottom inset grows to the
///   band's top, so the **end** of the content rests above the fold.
/// * Band in the upper part: the top inset grows to the band's bottom, so
///   the content **starts** below it.
///
/// A list long enough to scroll still travels through the band on its way
/// past — nothing short of snapping every row could stop that, and snapping
/// a reading list would be worse than the fold. What this guarantees is
/// that content at rest, and anything anchored to an edge, is clear of it.
///
/// A vertical crease does nothing here: the shell puts the rail on the
/// outer edge and the panes handle the split themselves ([paneWidthFor],
/// [SideBySide]).
class CreasePadding extends StatelessWidget {
  const CreasePadding({super.key, required this.child});

  final Widget child;

  /// A region thinner than this is not worth flowing into — about two rows
  /// of a list — so the band is treated as belonging to the edge it is
  /// near and the other region takes the content.
  static const double minRegion = 96;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (DisplayScope.maybeOf(context)?.creaseAxis != Axis.horizontal) {
        return child;
      }
      final band = creaseInBox(context, constraints);
      if (band == null || !constraints.hasBoundedHeight) return child;
      final height = constraints.maxHeight;
      final above = band.top;
      final below = height - band.bottom;
      if (above <= 0 || below <= 0) return child;
      final inset = MediaQuery.paddingOf(context);
      // Ties go to the upper region: content reads from the top down, and
      // the Duo's band sits within a few points of the box's centre.
      final flowsUp = above >= below || below < minRegion;
      final padding = flowsUp
          ? inset.copyWith(bottom: math.max(inset.bottom, height - band.top))
          : inset.copyWith(top: math.max(inset.top, band.bottom));
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: padding),
        child: child,
      );
    },
  );
}

/// Snaps a sideways scroller to a lattice of rest positions.
///
/// The boards use it for two things at once (research/23 D3): a column
/// boundary always comes to rest on the active crease, and with the gap
/// between columns widened to the band the fold then falls in empty space
/// instead of through a card. [pitch] is the column's width plus that gap
/// and [origin] the offset at which a boundary sits on the crease, so the
/// rest positions are `origin + n * pitch`.
///
/// Modelled on [PageScrollPhysics]: the parent's own ballistic simulation
/// decides where the fling would end, and that endpoint is rounded to the
/// lattice before a spring carries the viewport there.
class ColumnSnapPhysics extends ScrollPhysics {
  const ColumnSnapPhysics({
    required this.pitch,
    required this.origin,
    super.parent,
  });

  /// The distance between two rest positions: a column plus its gap.
  final double pitch;

  /// Any one rest position, in scroll offsets. The lattice runs both ways
  /// from it and is clamped to the scrollable's own extent.
  final double origin;

  @override
  ColumnSnapPhysics applyTo(ScrollPhysics? ancestor) => ColumnSnapPhysics(
    pitch: pitch,
    origin: origin,
    parent: buildParent(ancestor),
  );

  /// The rest position nearest [target], inside `[min, max]`.
  double snap(double target, {required double min, required double max}) {
    if (!pitch.isFinite || pitch <= 0) return target.clamp(min, max);
    final steps = ((target - origin) / pitch).roundToDouble();
    return (origin + steps * pitch).clamp(min, max);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Out of range, or already settling into an overscroll: the parent's
    // answer is the right one.
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final free = super.createBallisticSimulation(position, velocity);
    final end = free?.x(double.infinity) ?? position.pixels;
    final target = snap(
      end,
      min: position.minScrollExtent,
      max: position.maxScrollExtent,
    );
    final tolerance = toleranceFor(position);
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      velocity,
      tolerance: tolerance,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
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
///
/// **On an active vertical crease the boundary moves onto the fold**
/// (research/23 D3): the [start] column ends where the keep-out band
/// begins, the gap *is* the band, and [end] starts on the other panel. The
/// flex weights are then not used — the fold decides the split — and the
/// two-column threshold drops to [creaseMinColumn] per column, because a
/// half-folded display has two regions whatever its total width says.
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

  /// Narrowest half a crease may split this into.
  ///
  /// Well under [minWidth] / 2, because a fold's halves are not the window's:
  /// the Duo's inner display leaves 867 pt of content beside the system's bar
  /// column, and the crease sits at 455.5 of it, so a [ContentColumn] centred
  /// in that gives about 442 pt on one side and 358 on the other (measured
  /// 2026-09-20). Held to a balanced split this would stack — on a screen
  /// that is physically two panels. 320 is the same floor the master/detail
  /// panes use, and a column of list rows reads well at it.
  static const double creaseMinColumn = 320;

  Widget _column(List<Widget> children) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final band = creaseInBox(context, constraints);
        if (isVerticalCrease(band) &&
            band!.left >= creaseMinColumn &&
            constraints.maxWidth - band.right >= creaseMinColumn) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: band.left, child: _column(start)),
              SizedBox(width: band.width),
              Expanded(child: _column(end)),
            ],
          );
        }
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
            Expanded(flex: startFlex, child: _column(start)),
            const SizedBox(width: Spacing.lg),
            Expanded(flex: endFlex, child: _column(end)),
          ],
        );
      },
    );
  }
}
