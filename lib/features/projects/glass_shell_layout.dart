import 'package:flutter/material.dart';

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
///   the rounded corners of an iPhone in landscape) with a [SafeArea], and
///   the rail sits outside those insets as well. A SafeArea inside the
///   rail's own 72 pt box would shrink the rail by the inset instead of
///   moving it: an iPhone 17 in landscape showed a 13 pt sliver of rail
///   (2026-09-11).
/// * Vertical pages are padded clear of the rail by [railGutter]. Pages
///   whose content scrolls sideways ([bleedsUnderRail], the board) get the
///   gutter as safe-area padding instead, so their columns rest clear of
///   the rail and slide under it when scrolled.
/// * In portrait the rail lies along the bottom and pages get its height
///   as bottom safe-area padding ([barGutter]), so vertical content
///   scrolls under the bar and its end still clears it, the usual
///   home-indicator mechanism.
/// * The rail spans [heightFactor] of the safe height (or width in
///   portrait), centered, destinations spread along it; only larger text
///   can make it longer.
class GlassShellLayout extends StatelessWidget {
  const GlassShellLayout({
    super.key,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.bleedsUnderRail,
    required this.railOnRight,
  });

  final Widget body;
  final List<GlassRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// The current page scrolls sideways and may run under the rail.
  final bool bleedsUnderRail;

  /// Landscape: the rail floats on the right (Settings > Appearance).
  final bool railOnRight;

  /// Share of the safe height (landscape) or width (portrait) the rail
  /// spans, centered.
  static const double heightFactor = 0.8;

  /// Room between the safe edge and the rail for its shadow to fade (its
  /// blur radius).
  static const double margin = Spacing.xl;

  /// What a page keeps clear beside the rail in landscape.
  static const double railGutter =
      margin + GlassNavigationRail.width + Spacing.lg;

  /// What a page keeps clear above the bar in portrait.
  static const double barGutter =
      margin + GlassNavigationRail.thickness + Spacing.lg;

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
                      bottom: inset.bottom + barGutter,
                    ),
                  ),
                  child: body,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: margin,
              child: SafeArea(
                top: false,
                child: Center(
                  child: FractionallySizedBox(
                    widthFactor: heightFactor,
                    child: _rail(Axis.horizontal),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final page = bleedsUnderRail
        ? MediaQuery(
            data: mq.copyWith(
              padding: inset.copyWith(
                left: inset.left + (railOnRight ? 0 : railGutter),
                right: inset.right + (railOnRight ? railGutter : 0),
              ),
            ),
            child: body,
          )
        : SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: railOnRight ? 0 : railGutter,
                right: railOnRight ? railGutter : 0,
              ),
              child: body,
            ),
          );
    final railEdge = margin + (railOnRight ? inset.right : inset.left);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: page),
          Positioned(
            left: railOnRight ? null : railEdge,
            right: railOnRight ? railEdge : null,
            top: inset.top,
            bottom: inset.bottom,
            width: GlassNavigationRail.width,
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
