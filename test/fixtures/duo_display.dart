import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/core/display_environment.dart';
import 'package:flutter/widgets.dart';

/// The iPhone Duo's measured poses as a [DisplayScope] a widget test can
/// wrap a page in (research/23 section 2, phase 0 on the device).
///
/// Every number here came off the simulator: the inner display is
/// 951 x 669 in the wide pose and 669 x 951 in the tall one, the division
/// region is a 40 pt band on the short axis' centre with 20 pt of margin on
/// each side of a zero-width crease, and the stacked status bar takes 84 pt
/// of the trailing edge.
abstract final class Duo {
  /// The inner display, wide pose.
  static const wide = Size(951, 669);

  /// The inner display after one rotation.
  static const tall = Size(669, 951);

  static const wideInsets = EdgeInsets.fromLTRB(0, 0, 84, 34);
  static const tallInsets = EdgeInsets.fromLTRB(0, 82, 0, 34);

  /// The wide pose's division band, margins included.
  static const wideBand = Rect.fromLTWH(455.5, 0, 40, 669);

  /// The tall pose's division band.
  static const tallBand = Rect.fromLTWH(0, 455.5, 669, 40);

  /// The crease line itself: the band's centre.
  static const creaseLine = 475.5;

  static const _margins20 = EdgeInsets.all(20);

  /// A folded display. [band] is the keep-out band in window coordinates.
  static DisplayRegions folded(Rect band) => DisplayRegions(
    supported: true,
    regions: [
      ReservedRegion(
        kind: ReservedRegionKind.division,
        rect: band,
        margins: _margins20,
      ),
    ],
  );

  /// The same display lying flat: the division is reported but inactive,
  /// so nothing in the layout may react to it.
  static DisplayRegions flat(Rect band) => DisplayRegions(
    supported: true,
    regions: [
      ReservedRegion(
        kind: ReservedRegionKind.division,
        rect: band,
        margins: _margins20,
        active: false,
      ),
    ],
  );

  /// Wraps [child] in a [DisplayScope] reporting [regions] and a window of
  /// [window]; `null` regions is a display that does not fold at all.
  static Widget scope({
    required Widget child,
    DisplayRegions? regions,
    Size window = wide,
  }) => DisplayScope.override(
    regions: regions ?? const DisplayRegions(),
    window: window,
    child: child,
  );
}
