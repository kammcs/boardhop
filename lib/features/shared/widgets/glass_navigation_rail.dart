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

/// The tablet rail on iOS: a floating, translucent, blurred pill that is
/// only as tall as its destinations and sits over the page background,
/// in the spirit of iOS 26's glass sidebars. Unlike [NavigationRail] it
/// paints no full-height column of its own, so the scaffold background
/// stays one color from edge to edge and the page's app bar keeps its
/// full width to the right of the gutter.
///
/// Colors come from the theme: the tint is a translucent container tone,
/// the selected destination reuses the rail indicator color, and text and
/// icons use the on-surface roles, so both modes read the same way.
class GlassNavigationRail extends StatelessWidget {
  const GlassNavigationRail({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<GlassRailDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Width of one destination and so of the whole rail.
  static const double width = 72;

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
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: radius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
