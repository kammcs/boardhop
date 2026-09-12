import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/display_cutout.dart';
import '../../theme/layout.dart';
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
  });

  final Widget body;
  final List<GlassRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// The current page scrolls sideways and may run under the rail.
  final bool bleedsUnderRail;

  /// Landscape: the rail floats on the right (Settings > Appearance).
  final bool railOnRight;

  /// Which side of the screen holds the display cutout in landscape.
  final CutoutSide cutoutSide;

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

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final inset = mq.padding;
    if (mq.orientation == Orientation.portrait) {
      return Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                top: false,
                bottom: false,
                child: MediaQuery(
                  // The sides are consumed by the SafeArea above; the bar
                  // joins the bottom inset the page still handles itself.
                  data: mq.copyWith(
                    padding: inset.copyWith(
                      left: 0,
                      right: 0,
                      // Measured from the screen's edge, so it already
                      // covers the home indicator the bar sits over.
                      bottom: math.max(inset.bottom, barGutterFor(context)),
                    ),
                  ),
                  child: body,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              // No SafeArea: like Apple's tab bar the glass sits over the
              // home-indicator band, not above it.
              bottom: barBottomMargin,
              child: Center(
                child: SizedBox(
                  width: barWidthFor(mq.size.width),
                  child: _rail(Axis.horizontal),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final railSideInset = railOnRight ? inset.right : inset.left;
    final railSideClear =
        cutoutSide == CutoutSide.none ||
        cutoutSide == (railOnRight ? CutoutSide.left : CutoutSide.right);
    // From the screen edge: where the rail starts, and where the page's
    // content starts beside it.
    final railEdge = margin + (railSideClear ? 0 : railSideInset);
    final railWidth = GlassNavigationRail.widthFor(context);
    final gutter = railGutterFor(context) + (railSideClear ? 0 : railSideInset);
    final page = bleedsUnderRail
        ? MediaQuery(
            data: mq.copyWith(
              padding: inset.copyWith(
                left: railOnRight ? inset.left : gutter,
                right: railOnRight ? gutter : inset.right,
              ),
            ),
            child: body,
          )
        : SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              // The SafeArea already took the inset off this side.
              padding: EdgeInsets.only(
                left: railOnRight ? 0 : math.max(0, gutter - inset.left),
                right: railOnRight ? math.max(0, gutter - inset.right) : 0,
              ),
              child: body,
            ),
          );
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: page),
          Positioned(
            left: railOnRight ? null : railEdge,
            right: railOnRight ? railEdge : null,
            top: inset.top,
            bottom: inset.bottom,
            width: railWidth,
            // Centered, four fifths of the safe height (Kelly's iPad
            // feedback), taller only when the destinations need it.
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight * heightFactor,
                  ),
                  child: _rail(Axis.vertical),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rail(Axis axis) => GlassNavigationRail(
    axis: axis,
    spread: true,
    destinations: destinations,
    selectedIndex: selectedIndex,
    onDestinationSelected: onDestinationSelected,
  );
}
