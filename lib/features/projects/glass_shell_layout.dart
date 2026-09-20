import 'dart:math' as math;

// The theme's own motion tokens, not Flutter's `Durations`.
import 'package:flutter/material.dart' hide Durations;

import '../../core/display_cutout.dart';
import '../../theme/layout.dart';
import '../../theme/theme_controller.dart' show RailSide;
import '../../theme/tokens.dart';
import '../shared/widgets/glass_navigation_rail.dart';

/// The project shell's chrome on Apple platforms: the page with a floating
/// [GlassNavigationRail] over it, beside the page in landscape (on the
/// side [railOnRight] says) and along the bottom in portrait. Liquid
/// glass: the rail floats above the page (a later Stack child) and shows
/// what passes under it through its blur; there is no rail column and no
/// divider, so the scaffold color runs edge to edge and the page app bar
/// keeps its full width up to the gutter.
///
/// Pure layout, so the placement rules are testable without the router:
///
/// * The page keeps clear of the display's sides (the Dynamic Island and
///   the rounded corners of an iPhone in landscape) with a [SafeArea]. A
///   SafeArea inside the rail's own 72 pt box would shrink the rail by the
///   inset instead of moving it: an iPhone 17 in landscape showed a 13 pt
///   sliver of rail (2026-09-11).
/// * iOS reports the same side inset on both sides, but the island is on
///   one of them ([cutoutSide], from [DisplayCutout]). The rail keeps only
///   its [margin] from an edge known to be free of the island (the inset
///   plus the margin there was far too much, Kelly, 2026-09-11) and clears
///   the inset on the island's side, or when the side is unknown.
/// * Vertical pages are padded clear of the rail by [railGutter]. Pages
///   whose content scrolls sideways ([bleedsUnderRail], the board) get the
///   gutter as safe-area padding instead, so their columns rest clear of
///   the rail and slide under it when scrolled.
/// * In portrait the rail lies along the bottom as a tab bar the size and
///   place of Apple's own: 56 pt tall, [barBottomMargin] off the bottom
///   edge of the screen and, on a phone, [barSideMargin] off each side.
///   Pages get [barGutter] as bottom safe-area padding, so vertical
///   content scrolls under the bar and its end still clears it, the usual
///   home-indicator mechanism.
/// * In landscape the rail spans [heightFactor] of the safe height,
///   centered, destinations spread along it; only larger text can make it
///   longer.
///
/// **On a display whose system asks for a vertical bar** ([systemRailSide],
/// `UITraitCollection.verticalBarEdge` through `DisplayScope`; an iPhone
/// Duo's inner display, its cover, and each Split View pane) those rules
/// give way to the system's (research/23 D1, D6):
///
/// * The rail is vertical on that edge in **every** orientation and
///   breakpoint, and the Settings switch is ignored — the cover display is
///   portrait and compact and still gets a side rail.
/// * It sits **inside** the column iOS has already reserved there — the
///   84 pt of `MediaQuery.padding` on that edge — not beside it, and it
///   drops the glass pill for bare destinations
///   ([GlassRailChrome.bare]): the pill was too wide for the column and
///   its icons did not line up under the stacked status cluster the way
///   Apple's own vertical tab bar does (Kelly, 2026-09-20). The page
///   therefore keeps no gutter beyond that inset: 867 pt of content on the
///   Duo's inner display, 382 on its cover.
/// * The column is centered on the status cluster's own x (the active
///   occlusion region from [occlusions], which is also the reserved
///   column's centre) and starts **below** it — the cluster measures
///   120 pt on the inner display and 170 on the cover, which the inset
///   alone does not say. The destinations are stacked with
///   [GlassNavigationRail.bareGap] between them and centered in what is
///   left; the 80 % rule is the pill's, not theirs.
/// * The selected destination keeps its capsule of brighter glass behind
///   icon and label, the one thing the bare chrome keeps.
/// * The page fades out at the column's inner edge ([columnFade]), on a
///   cliff [fadeWidth] wide, so nothing shows under the destinations or
///   the status cluster. A sideways scroller still scrolls under the
///   column — its last card reaches the visible area because the column
///   is its end padding — it is simply invisible there, instead of
///   cluttering glyphs that have no glass behind them any more (Kelly,
///   2026-09-20).
/// * The rail never spans an active horizontal crease: with one it centers
///   in the lower half, the half nearer the hands ([creaseBand]).
///
/// Every page is wrapped in a [CreasePadding], which keeps content at rest
/// out of an active **horizontal** crease band (research/23 D3). A vertical
/// crease is the panes' own business ([paneWidthFor], [SideBySide]).
///
/// Every move between those places is animated ([Durations.normal],
/// [Motion.standard], research/23 D7): the rail's box is an
/// [AnimatedPositioned] and the page's gutter an [AnimatedPadding], so a
/// fold or a rotation slides the rail from the bottom bar to the side edge
/// instead of cutting to it. The rail is laid out at its **target** size
/// inside that moving box (see [_RailSlot]), so no frame of the animation
/// squeezes a four-item bar into a 72 pt column.
class GlassShellLayout extends StatelessWidget {
  const GlassShellLayout({
    super.key,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.bleedsUnderRail,
    required this.railOnRight,
    this.cutoutSide = CutoutSide.unknown,
    this.systemRailSide,
    this.occlusions = const [],
    this.creaseBand,
    this.creaseAxis,
  });

  final Widget body;
  final List<GlassRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// The current page scrolls sideways and may run under the rail.
  final bool bleedsUnderRail;

  /// Landscape: the rail floats on the right (Settings > Appearance).
  /// Ignored wherever [systemRailSide] answers.
  final bool railOnRight;

  /// Which side of the screen holds the display cutout in landscape.
  final CutoutSide cutoutSide;

  /// The edge iOS puts its own vertical bar on, resolved to a side, or
  /// null where it asks for none and today's rules stand (an iPad, an
  /// iPhone, anything before iOS 27.1).
  final RailSide? systemRailSide;

  /// Active occlusion regions in window coordinates — on an iPhone Duo the
  /// stacked status bar in the corner of the bar edge. The rail keeps
  /// clear of the ones that fall on its own edge.
  final List<Rect> occlusions;

  /// The active fold's keep-out band, margins included, or null when
  /// nothing is folded.
  final Rect? creaseBand;

  /// Which way the crease runs; null when nothing is folded.
  final Axis? creaseAxis;

  /// Share of the safe height (landscape) the rail spans, centered, and of
  /// the width on a tablet in portrait.
  static const double heightFactor = 0.8;

  /// What the bar along the bottom keeps clear of the screen's bottom
  /// edge in portrait. Apple's floating tab bar sits *inside* the
  /// home-indicator band: 20 pt off the edge on an iPhone 17, measured
  /// off an App Store screenshot (Kelly, 2026-09-12). Clearing the 34 pt
  /// inset and a 24 pt margin on top of it left ours floating far too
  /// high, so the bar ignores the bottom inset and takes this instead.
  static const double barBottomMargin = 20;

  /// What the bar keeps clear of each side of a phone in portrait, again
  /// Apple's own. A tablet keeps the [heightFactor] fraction instead: a
  /// bar that wide across an iPad reads as a slab.
  static const double barSideMargin = 22;

  /// The bar's width in portrait for a screen this wide.
  static double barWidthFor(double screenWidth) =>
      Breakpoint.fromWidth(screenWidth).isCompact
      ? screenWidth - 2 * barSideMargin
      : screenWidth * heightFactor;

  /// Room between the safe edge and the rail for its shadow to fade (its
  /// blur radius).
  static const double margin = Spacing.xl;

  /// What a page keeps clear beside the rail in landscape, measured from
  /// the screen edge (plus that side's inset when the rail must clear it),
  /// at the ordinary text size; [railGutterFor] follows the rail when the
  /// text is larger.
  static const double railGutter =
      margin + GlassNavigationRail.width + Spacing.lg;

  static double railGutterFor(BuildContext context) =>
      margin + GlassNavigationRail.widthFor(context) + Spacing.lg;

  /// What a page keeps clear at the bottom in portrait, at the ordinary
  /// text size, measured from the screen's bottom edge: the bar overlaps
  /// the home-indicator inset, so this replaces that inset rather than
  /// adding to it. [barGutterFor] follows the bar when the text is larger.
  static const double barGutter =
      barBottomMargin + GlassNavigationRail.thickness + Spacing.sm;

  static double barGutterFor(BuildContext context) =>
      barBottomMargin + GlassNavigationRail.thicknessFor(context) + Spacing.sm;

  /// How wide the cliff is where the page fades out beside the system's
  /// bar column: short enough to read as an edge rather than a vignette.
  static const double fadeWidth = Spacing.md;

  /// The mask that hides whatever passes under the system's bar column:
  /// the page whole across its width, gone from the column's inner
  /// boundary on, with [fadeWidth] of falloff between the two.
  ///
  /// White and transparent are alpha here, not color: the gradient is
  /// composited onto the page with [BlendMode.dstIn], so only its alpha
  /// channel is read.
  static LinearGradient columnFade({
    required double width,
    required double column,
    required bool onRight,
  }) {
    const opaque = Color(0xFFFFFFFF);
    const clear = Color(0x00FFFFFF);
    // The column's inner boundary, and where the page is still whole.
    final inner = onRight ? width - column : column;
    final outer = onRight ? inner - fadeWidth : inner + fadeWidth;
    double at(double x) => width <= 0 ? 0.0 : (x / width).clamp(0.0, 1.0);
    final first = at(math.min(inner, outer));
    final second = at(math.max(inner, outer));
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: onRight
          ? const [opaque, opaque, clear, clear]
          : const [clear, clear, opaque, opaque],
      stops: [0, first, second, 1],
    );
  }

  /// The page, kept clear of an active **horizontal** crease.
  ///
  /// Wrapped here rather than in each page so nothing below has to know
  /// about the fold: [CreasePadding] only changes `MediaQuery.padding`,
  /// which every list and every bottom-anchored control in the app already
  /// reads. It sits *inside* each plan's own media query, so it grows from
  /// the gutter the bar or the rail has already claimed.
  Widget get _page => CreasePadding(child: body);

  /// The page's box, shortened by the keyboard.
  ///
  /// The bar is drawn outside this, from the full-height stack, so it stays
  /// under the keyboard the way Apple's tab bar does.
  static Widget _keyboardSafe(
    BuildContext context,
    double keyboard,
    Widget child,
  ) => keyboard <= 0
      ? child
      : Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          // The inset is spent here; a page's own Scaffold must not shrink
          // for it a second time.
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: child,
          ),
        );

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // How much of the screen the keyboard covers. The bar sits under it (see
    // below), but the page above must not: a `Scaffold` never lifts its own
    // `bottomNavigationBar` — it is the box the page is given that shrinks —
    // so with the shell's own Scaffold no longer resizing, every composer
    // anchored that way (the work item Discussion box) was left behind the
    // keyboard. [_keyboardSafe] takes the inset off the page's box and off
    // the media query below it, which is exactly what a resizing Scaffold
    // does for its body.
    final keyboard = mq.viewInsets.bottom;
    // A vertical rail wherever the system asks for one, whatever the
    // orientation (research/23 D1), and otherwise in landscape as before.
    final vertical =
        systemRailSide != null || mq.orientation == Orientation.landscape;
    final (:box, :axis, :chrome, :page) = vertical
        ? _railPlan(context, mq, keyboard)
        : _barPlan(context, mq, keyboard);
    return Scaffold(
      // The keyboard covers the bar, as it covers Apple's own tab bar. With
      // the default the whole stack, bar included, rose above the keyboard
      // inset (a page's focused search field on the iPad put the dock a
      // third of the way up the screen, 2026-09-14). Each page's Scaffold
      // still resizes for the keyboard on its own.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: page),
          // One `AnimatedPositioned` for both places the rail can be, so a
          // pose change slides it rather than cutting (D7). Its four
          // properties are always given, never swapped for `right` or
          // `bottom`: an implicit animation cannot tween a property that
          // arrives null.
          AnimatedPositioned(
            duration: Durations.normal,
            curve: Motion.standard,
            left: box.left,
            top: box.top,
            width: box.width,
            height: box.height,
            child: _RailSlot(
              size: box.size,
              child: switch (chrome) {
                // Bare destinations take only the room they need, centered
                // in the column below the status cluster.
                GlassRailChrome.bare => Center(child: _rail(axis, chrome)),
                GlassRailChrome.pill when axis == Axis.vertical => Center(
                  child: ConstrainedBox(
                    // Centered, four fifths of the safe height (Kelly's
                    // iPad feedback), taller only when the destinations
                    // need it.
                    constraints: BoxConstraints(
                      minHeight: box.height * heightFactor,
                    ),
                    child: _rail(axis, chrome),
                  ),
                ),
                GlassRailChrome.pill => _rail(axis, chrome),
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The bar along the bottom, in portrait with no system edge.
  ({Rect box, Axis axis, GlassRailChrome chrome, Widget page}) _barPlan(
    BuildContext context,
    MediaQueryData mq,
    double keyboard,
  ) {
    final inset = mq.padding;
    final size = mq.size;
    final width = barWidthFor(size.width);
    final height = GlassNavigationRail.thicknessFor(context);
    return (
      // No safe area: like Apple's tab bar the glass sits over the
      // home-indicator band, not above it.
      box: Rect.fromLTWH(
        (size.width - width) / 2,
        size.height - barBottomMargin - height,
        width,
        height,
      ),
      axis: Axis.horizontal,
      chrome: GlassRailChrome.pill,
      page: SafeArea(
        top: false,
        bottom: false,
        child: _keyboardSafe(
          context,
          keyboard,
          MediaQuery(
            // The sides are consumed by the SafeArea above; the bar
            // joins the bottom inset the page still handles itself.
            data: mq.copyWith(
              viewInsets: mq.viewInsets.copyWith(bottom: 0),
              padding: inset.copyWith(
                left: 0,
                right: 0,
                // Measured from the screen's edge, so it already
                // covers the home indicator the bar sits over. With
                // the keyboard up the bar is behind it and there is
                // nothing left to clear.
                bottom: keyboard > 0
                    ? inset.bottom
                    : math.max(inset.bottom, barGutterFor(context)),
              ),
            ),
            child: _page,
          ),
        ),
      ),
    );
  }

  /// The rail beside the page: in landscape, and in any orientation on a
  /// display whose system asks for a vertical bar.
  ({Rect box, Axis axis, GlassRailChrome chrome, Widget page}) _railPlan(
    BuildContext context,
    MediaQueryData mq,
    double keyboard,
  ) {
    final inset = mq.padding;
    final size = mq.size;
    final system = systemRailSide;
    final onRight = system != null ? system == RailSide.right : railOnRight;
    final railWidth = GlassNavigationRail.widthFor(context);
    // Where the rail's column starts, and what the page keeps clear of it
    // measured from the screen edge.
    final double left;
    final double gutter;
    Rect? cluster;
    if (system != null) {
      // The system's own bar column: what iOS reserved on that edge — the
      // 84 pt of inset the stacked status cluster sits in — or the rail's
      // own width where it reserved nothing (a Split View pane's outer
      // edge). The page stops at the column; it gets no gutter of its own.
      final reserved = math.max(onRight ? inset.right : inset.left, railWidth);
      final column = onRight
          ? Rect.fromLTRB(size.width - reserved, 0, size.width, size.height)
          : Rect.fromLTRB(0, 0, reserved, size.height);
      cluster = _clusterIn(column);
      // Under the status cluster, the way Apple's vertical tab bar lines
      // up with it; the reserved column's own centre where none is
      // reported.
      final centerX = cluster?.center.dx ?? column.center.dx;
      // Clamped to the window: at an accessibility text size the rail is
      // wider than the column iOS reserved, and lining its centre up with
      // the cluster would hang it off the edge.
      left = (centerX - railWidth / 2).clamp(0.0, size.width - railWidth);
      gutter = reserved;
    } else {
      // iOS reports the same side inset on both sides, but the island is
      // on one of them, and the rail keeps only its margin from an edge
      // known to be free of it.
      final railSideInset = onRight ? inset.right : inset.left;
      final railSideClear =
          cutoutSide == CutoutSide.none ||
          cutoutSide == (onRight ? CutoutSide.left : CutoutSide.right);
      final edge = margin + (railSideClear ? 0 : railSideInset);
      left = onRight ? size.width - edge - railWidth : edge;
      gutter = railGutterFor(context) + (railSideClear ? 0 : railSideInset);
    }
    final page = _keyboardSafe(
      context,
      keyboard,
      bleedsUnderRail
          ? MediaQuery(
              data: mq.copyWith(
                viewInsets: mq.viewInsets.copyWith(bottom: 0),
                padding: inset.copyWith(
                  left: onRight ? inset.left : gutter,
                  right: onRight ? gutter : inset.right,
                ),
              ),
              child: _page,
            )
          : SafeArea(
              top: false,
              bottom: false,
              child: AnimatedPadding(
                duration: Durations.normal,
                curve: Motion.standard,
                // The SafeArea already took the inset off this side.
                padding: EdgeInsets.only(
                  left: onRight ? 0 : math.max(0, gutter - inset.left),
                  right: onRight ? math.max(0, gutter - inset.right) : 0,
                ),
                child: _page,
              ),
            ),
    );
    final chrome = system != null ? GlassRailChrome.bare : GlassRailChrome.pill;
    // The page stops dead at the column's inner edge. Only the page body
    // is masked — the Scaffold's own overlays (a floating snackbar, a
    // sheet) are outside it — and a ShaderMask takes no taps, so a
    // sideways scroller still scrolls where it cannot be seen.
    final masked = system == null
        ? page
        : ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => columnFade(
              width: bounds.width,
              column: gutter,
              onRight: onRight,
            ).createShader(bounds),
            child: page,
          );
    return (
      box: _railBox(
        context,
        mq,
        left: left,
        width: railWidth,
        cluster: cluster,
        chrome: chrome,
      ),
      axis: Axis.vertical,
      chrome: chrome,
      page: masked,
    );
  }

  /// The active occlusion in the system's bar column: the stacked status
  /// cluster (84 x 120 on the Duo's inner display, 84 x 170 on its cover,
  /// research/23 section 2). `MediaQuery.padding` reports the same 84 pt,
  /// but only as "this much of that side"; the region says where the
  /// cluster is and how far down it reaches, which is what the rail lines
  /// up with and starts below.
  Rect? _clusterIn(Rect column) {
    for (final region in occlusions) {
      if (region.right <= column.left || region.left >= column.right) continue;
      return region;
    }
    return null;
  }

  /// The strip the rail is centered in: the safe height, minus whatever of
  /// the system's own chrome falls on this edge, minus the half of the
  /// window an active crease has cut off.
  Rect _railBox(
    BuildContext context,
    MediaQueryData mq, {
    required double left,
    required double width,
    Rect? cluster,
    required GlassRailChrome chrome,
  }) {
    final size = mq.size;
    final inset = mq.padding;
    var top = inset.top;
    var bottom = size.height - inset.bottom;
    if (cluster != null) {
      // Below the status cluster, whichever end of the column it is at.
      if (cluster.center.dy <= (top + bottom) / 2) {
        top = math.max(top, cluster.bottom);
      } else {
        bottom = math.min(bottom, cluster.top);
      }
    }
    final band = creaseBand;
    if (band != null && creaseAxis == Axis.horizontal && band.bottom < bottom) {
      // The lower half, the one nearer the hands (research/23 D3). Measured
      // from the band's far edge rather than the crease line inside it, so
      // no destination lands in the keep-out margin.
      top = math.max(top, band.bottom);
    }
    // Nothing sensible left (a crease or an occlusion covering the side):
    // the safe height, as before, beats a sliver of rail.
    if (bottom - top < 2 * kMinTapTarget) {
      top = inset.top;
      bottom = size.height - inset.bottom;
    }
    // Never shorter than the destinations themselves. The window can be
    // that short on its own — the Duo reports one about 140 pt tall for a
    // frame while it switches panels, and a rail held to four fifths of
    // that overflowed (debug log, 2026-09-20).
    final length = GlassNavigationRail.lengthFor(
      context,
      destinations.length,
      chrome,
    );
    if (bottom - top < length) {
      final center = (top + bottom) / 2;
      top = center - length / 2;
      bottom = center + length / 2;
      // Nudged back on screen where there is room; in a window shorter
      // than the rail itself it simply hangs off both ends, which is what
      // that frame is worth.
      if (size.height >= length) {
        if (top < 0) {
          bottom -= top;
          top = 0;
        } else if (bottom > size.height) {
          top -= bottom - size.height;
          bottom = size.height;
        }
      }
    }
    return Rect.fromLTRB(left, top, left + width, bottom);
  }

  Widget _rail(Axis axis, GlassRailChrome chrome) => GlassNavigationRail(
    axis: axis,
    chrome: chrome,
    // The pill is held to a length and spreads its destinations along it;
    // a bare column is only as long as they are.
    spread: chrome == GlassRailChrome.pill,
    destinations: destinations,
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
  );
}

/// Holds the rail at the size its box is *heading for* while that box is
/// still moving.
///
/// The rail's shape changes with its place — four destinations across a
/// 56 pt bar, or down a 72 pt column — and an [AnimatedPositioned] hands
/// its child every size in between. Laying the rail out in those would
/// squeeze a horizontal bar into a column's width (and print the overflow
/// to prove it). Given its target size instead, it simply glides from one
/// edge to the other. At rest the box and the target are the same, so this
/// is the identity.
class _RailSlot extends StatelessWidget {
  const _RailSlot({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) => OverflowBox(
    minWidth: size.width,
    maxWidth: size.width,
    minHeight: size.height,
    maxHeight: size.height,
    child: child,
  );
}
