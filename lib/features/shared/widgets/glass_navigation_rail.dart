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

  /// Width of one destination and so of a vertical rail.
  static const double width = 72;

  /// Cross-axis size of a horizontal rail: icon pill, gap, label line and
  /// the item's vertical padding. The shell uses it as the page inset.
  static const double thickness = 32 + Spacing.xs + 16 + 2 * Spacing.sm;

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
    final radius = BorderRadius.circular(Radii.xl);
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
                  : const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Flex(
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
                      onTap: () => onDestinationSelected(i),
                    ),
                ],
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
    required this.onTap,
  });

  final GlassRailDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final indicator =
        theme.navigationRailTheme.indicatorColor ?? scheme.secondaryContainer;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w600 : null,
    );
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: destination.label,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.lg),
            child: SizedBox(
              width: GlassNavigationRail.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: Durations.fast,
                      width: 56,
                      height: 32,
                      decoration: BoxDecoration(
                        color: selected ? indicator : Colors.transparent,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                      child: Icon(
                        selected ? destination.selectedIcon : destination.icon,
                        color: selected
                            ? scheme.onSecondaryContainer
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      destination.label,
                      style: labelStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
