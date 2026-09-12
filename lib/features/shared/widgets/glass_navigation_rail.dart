import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide Durations;

import '../../../theme/tokens.dart';

/// One entry of a [GlassNavigationRail].
class GlassRailDestination {
  const GlassRailDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The tablet rail on iOS: a floating, translucent, blurred pill that
/// sits over the page (sized to its destinations, or spread along a given
/// length), vertical beside the page or horizontal along its bottom,
/// in the spirit of iOS 26's glass sidebars. Unlike [NavigationRail] it
/// paints no full-height column of its own, so the scaffold background
/// stays one color from edge to edge and the page's app bar keeps its
/// full width to the right of the gutter.
///
/// Follows Apple's Liquid Glass material: the page scrolls under the rail
/// and stays visible through it (a blur plus a mild saturation boost, so
/// what lies behind reads as color rather than mud), a thin translucent
/// tint, a specular highlight along the top edge and a soft shadow that
/// lifts it off the page. Colors come from the theme: the tint is the
/// surface tone, the selected destination reuses the rail indicator
/// color, and text and icons use the on-surface roles, so both modes read
/// the same way.
class GlassNavigationRail extends StatelessWidget {
  const GlassNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.spread = false,
    this.axis = Axis.vertical,
  });

  final List<GlassRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Vertical along a side of the screen, or horizontal along the bottom
  /// (a tablet in portrait).
  final Axis axis;

  /// When true the destinations are spaced evenly along the rail, which
  /// then takes whatever length it is held to beyond their own (the shell
  /// holds it to at least 80% of the screen, centered); when false it is
  /// only as long as its destinations.
  final bool spread;

  /// Width of one destination and so of a vertical rail at the ordinary
  /// text size.
  static const double width = 72;

  /// How far the rail follows the text scale before the label gives way.
  /// The rail is chrome of a fixed shape, so it cannot grow without
  /// limit; the label is held to the same factor.
  static const double maxScale = 2;

  /// The text scale in force, as a factor of the label's own size and
  /// capped at [maxScale].
  static double scaleOf(BuildContext context) {
    const label = 12.0; // labelMedium, the destination's own size.
    final scale = MediaQuery.textScalerOf(context).scale(label) / label;
    return scale.clamp(1.0, maxScale);
  }

  /// The rail's width for the text size in force. The label is the widest
  /// part of a destination, and at accessibility sizes "Pipelines" no
  /// longer fit the 72 pt box and read "Pipelin…" (iPad walkthrough).
  /// A single word cannot wrap, so the rail follows the text scale
  /// instead.
  static double widthFor(BuildContext context) => width * scaleOf(context);

  /// Cross-axis size of a horizontal rail, and so the height of the bar
  /// along the bottom: the bar's own inset around the selected capsule,
  /// the item's padding, the icon, the gap and the label line. 56 pt, the
  /// height Apple's floating tab bar measures on an iPhone 17 (taken off
  /// an App Store screenshot, Kelly 2026-09-12; ours was 68 and read as a
  /// slab). The shell uses it as the page inset.
  static const double thickness =
      2 * barInset + 2 * itemPadY + iconBox + iconGap + _labelLine;

  /// Gap between the bar's own edge and a destination's capsule, so the
  /// selected capsule reads as a piece of glass lifted out of the bar
  /// rather than a block filling it.
  static const double barInset = 3;

  /// A destination's padding above its icon and below its label, inside
  /// the capsule.
  static const double itemPadY = 4;

  /// Box the destination's icon is drawn in, and its size.
  static const double iconBox = 24;

  /// Gap between the icon and its label.
  static const double iconGap = 2;

  static const double _labelLine = 16;

  /// [thickness] for the text size in force: only the label line grows.
  static double thicknessFor(BuildContext context) =>
      thickness + _labelLine * (scaleOf(context) - 1);

  /// Height of a destination's label line at the text size in force. The
  /// label is drawn in a box of exactly this height so the bar's height
  /// is [thicknessFor] and not whatever the font happens to measure.
  static double labelLineFor(BuildContext context) =>
      _labelLine * scaleOf(context);

  /// Blur radius of the glass; the shell keeps this much margin around
  /// the rail so the shadow can fade.
  static const double blurSigma = 20;

  /// Saturation boost applied to whatever shows through the glass.
  static const double _saturation = 1.25;

  static ColorFilter _saturate(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return ColorFilter.matrix(<double>[
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // A bar along the bottom is a true pill, like Apple's floating tab
    // bar; a tall rail beside the page keeps the softer rounded rect (a
    // pill's semicircular ends read wrong down a whole screen).
    final radius = BorderRadius.circular(
      axis == Axis.horizontal ? Radii.pill : Radii.xl,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: _saturate(_saturation),
            inner: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.42),
              borderRadius: radius,
            ),
            // Painted over the content so they do not change the layout
            // width: the hairline edge, and a specular sheen along the top
            // that fades out, the way glass picks up the light above it.
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.35, 1],
                colors: [
                  scheme.surfaceBright.withValues(alpha: 0.35),
                  scheme.surfaceBright.withValues(alpha: 0.04),
                  scheme.onSurface.withValues(alpha: 0.03),
                ],
              ),
            ),
            child: Padding(
              padding: axis == Axis.vertical
                  ? const EdgeInsets.symmetric(vertical: Spacing.sm)
                  : const EdgeInsets.all(barInset),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Along the bottom the destinations share the bar's
                  // width, so the selected capsule is a tab-shaped
                  // stadium (72 x 50 on an iPhone 17, Apple's own
                  // proportion) rather than the near-circular blob a
                  // 72 pt slot gave. It is also what keeps four items at
                  // a large text scale from overflowing a narrow bar; the
                  // label scales down inside its item.
                  var itemWidth = widthFor(context);
                  if (axis == Axis.horizontal &&
                      constraints.maxWidth.isFinite &&
                      destinations.isNotEmpty) {
                    itemWidth = constraints.maxWidth / destinations.length;
                  }
                  return Flex(
                    direction: axis,
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: spread
                        ? MainAxisAlignment.spaceEvenly
                        : MainAxisAlignment.start,
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        _GlassRailItem(
                          destination: destinations[i],
                          selected: i == selectedIndex,
                          width: itemWidth,
                          axis: axis,
                          onTap: () => onDestinationSelected(i),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassRailItem extends StatelessWidget {
  const _GlassRailItem({
    required this.destination,
    required this.selected,
    required this.width,
    required this.axis,
    required this.onTap,
  });

  final GlassRailDestination destination;
  final bool selected;
  final double width;
  final Axis axis;
  final VoidCallback onTap;

  /// How far the capsule sits inside its slot. Along the bottom it keeps
  /// off its neighbours and, more to the point, off the bar's own rounded
  /// ends: filling the slot edge to edge made the first destination's
  /// capsule merge into the left end of the bar, so the bar read as a
  /// white blob with a grey tail rather than as four tabs.
  EdgeInsets get _capsuleInset => axis == Axis.horizontal
      ? const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 1)
      : const EdgeInsets.symmetric(
          horizontal: GlassNavigationRail.barInset,
          vertical: 2,
        );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // The selected destination is a capsule of brighter glass behind its
    // icon and label together, lifted off the bar by a soft shadow, the
    // way iOS 26's floating tab bar marks the current tab. A Material
    // indicator pill behind the icon alone read as Android (Kelly,
    // 2026-09-12).
    final fill = scheme.surfaceBright.withValues(alpha: dark ? 0.26 : 0.85);
    // The neutral slate theme's primary (#575f6b light) is all but the
    // same value as onSurfaceVariant (#474648), so tinting the selected
    // glyph carries no signal. The capsule and the glyph's own weight do
    // the work instead: selected is full-strength onSurface and semibold,
    // unselected is dimmed.
    final tint = selected
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: 0.7);
    final radius = BorderRadius.circular(Radii.pill);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: tint,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
    // Painted behind the destination rather than around it: a decoration
    // wrapping the content added its border to the rail's own width and
    // height (72 became 80).
    final capsule = Positioned.fill(
      child: Padding(
        padding: _capsuleInset,
        child: AnimatedContainer(
          duration: Durations.fast,
          decoration: BoxDecoration(
            color: selected ? fill : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? scheme.outlineVariant.withValues(alpha: dark ? 0.35 : 0.45)
                  : Colors.transparent,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.shadow.withValues(
                        alpha: dark ? 0.22 : 0.10,
                      ),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: destination.label,
        // The slot's width is set on the content, not on the Stack: a
        // Stack hands its non-positioned child loose constraints, so a
        // width on the Stack let the icon and label shrink to their own
        // size and pin to the left of the slot.
        child: Stack(
          children: [
            capsule,
            SizedBox(
              width: width,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: radius,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: GlassNavigationRail.itemPadY,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: GlassNavigationRail.iconBox,
                          child: Icon(
                            selected
                                ? destination.selectedIcon
                                : destination.icon,
                            size: GlassNavigationRail.iconBox,
                            color: tint,
                          ),
                        ),
                        const SizedBox(height: GlassNavigationRail.iconGap),
                        // Held to an exact line box so the bar measures
                        // [GlassNavigationRail.thicknessFor] whatever the
                        // font reports. The rail follows the text scale
                        // only as far as [GlassNavigationRail.maxScale], so
                        // the label is held to the same factor and scaled
                        // down inside that if a longer word still will not
                        // fit — whole and smaller rather than "Pipelin…".
                        SizedBox(
                          height: GlassNavigationRail.labelLineFor(context),
                          child: MediaQuery.withClampedTextScaling(
                            maxScaleFactor: GlassNavigationRail.maxScale,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                destination.label,
                                style: labelStyle,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
