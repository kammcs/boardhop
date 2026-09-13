import 'package:flutter/services.dart';

/// Which side of the screen carries the display cutout (the Dynamic
/// Island or notch) while a phone is in landscape.
enum CutoutSide { left, right, none, unknown }

/// What kind of obstruction a [ReservedRegion] is.
///
/// Apple's own kinds, from Tech Talk 111461: a `division` is a fold or
/// hinge that splits the display into halves, an `occlusion` is something
/// sitting on top of it such as a camera housing. Anything the platform
/// adds later arrives as [unknown] rather than being dropped, so a new
/// kind cannot silently become "nothing in the way".
enum ReservedRegionKind { division, occlusion, unknown }

/// One rectangle of the display the UI has to keep clear of, in logical
/// pixels within the Flutter view.
class ReservedRegion {
  const ReservedRegion({
    required this.kind,
    required this.rect,
    this.active = true,
  });

  final ReservedRegionKind kind;
  final Rect rect;

  /// False for a region that exists but is not currently in force, such as
  /// a hinge on a device that is open flat.
  final bool active;

  @override
  String toString() => 'ReservedRegion($kind, $rect, active: $active)';
}

/// Everything the platform will say about obstructions in the display.
class DisplayRegions {
  const DisplayRegions({
    this.regions = const [],
    this.supported = false,
    this.cutoutSide = CutoutSide.unknown,
  });

  final List<ReservedRegion> regions;

  /// The platform answered a reserved-regions query at all. False on
  /// Android, in tests, and on any iOS before the API exists, where the
  /// absence of regions means "not asked", not "nothing in the way".
  final bool supported;

  final CutoutSide cutoutSide;

  /// The active fold, if the display has one. `SideBySide` puts its column
  /// gap here and the shell keeps the rail off it.
  Rect? get hinge {
    for (final r in regions) {
      if (r.kind == ReservedRegionKind.division && r.active) return r.rect;
    }
    return null;
  }

  /// The display folds, whether or not the fold is in force right now. An
  /// iPhone Duo reports its division even when open.
  bool get folds =>
      regions.any((r) => r.kind == ReservedRegionKind.division);
}

/// Asks iOS about the shape of the display.
///
/// Two questions, one channel (`com.kammcs.boardhop/display`):
///
/// * **Where is the cutout?** Flutter's safe-area insets are the same on
///   both sides in landscape (59 pt on a Dynamic Island phone, for the
///   island and the corners alike), so nothing on the Dart side can tell
///   which side actually holds the island; the interface orientation from
///   the Runner's AppDelegate can.
/// * **What is reserved?** iOS 27.1 gives a view its reserved regions
///   (`reservedRegions(kind:)`), which is how a folding device reports its
///   hinge. Boardhop's whole UI is one `UIView` under
///   `FlutterViewController`, so the Runner can ask and hand the
///   rectangles over (research/12b).
///
/// On a folding display the orientation no longer settles where the cutout
/// is — the two halves face different ways and the housing is not at one
/// end of the window — so [side] answers [CutoutSide.unknown] there and
/// the shell falls back to clearing the inset on both sides.
///
/// Elsewhere (Android, tests, iOS before 27.1) the answers are
/// [CutoutSide.unknown] and no regions.
class DisplayCutout {
  DisplayCutout._();

  static const _channel = MethodChannel('com.kammcs.boardhop/display');

  /// Which side the cutout is on, or [CutoutSide.unknown] on a folding
  /// display. Kept as its own call for the shell, which wants only this.
  static Future<CutoutSide> side() async => (await regions()).cutoutSide;

  /// The display's reserved regions and cutout side in one round trip.
  static Future<DisplayRegions> regions() async {
    final orientation = await _invoke<String>('interfaceOrientation');
    final raw = await _invoke<List<dynamic>>('reservedRegions');
    final parsed = <ReservedRegion>[];
    for (final entry in raw ?? const []) {
      final map = (entry as Map?)?.cast<String, dynamic>();
      if (map == null) continue;
      final region = _region(map);
      if (region != null) parsed.add(region);
    }
    final folds = parsed.any(
      (r) => r.kind == ReservedRegionKind.division,
    );
    return DisplayRegions(
      regions: parsed,
      supported: raw != null,
      // A fold makes the orientation answer meaningless, so do not use it.
      cutoutSide: folds ? CutoutSide.unknown : _sideOf(orientation),
    );
  }

  static Future<T?> _invoke<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static ReservedRegion? _region(Map<String, dynamic> map) {
    final width = (map['width'] as num?)?.toDouble();
    final height = (map['height'] as num?)?.toDouble();
    final x = (map['x'] as num?)?.toDouble();
    final y = (map['y'] as num?)?.toDouble();
    if (x == null || y == null || width == null || height == null) return null;
    return ReservedRegion(
      kind: switch (map['kind']) {
        'division' => ReservedRegionKind.division,
        'occlusion' => ReservedRegionKind.occlusion,
        _ => ReservedRegionKind.unknown,
      },
      rect: Rect.fromLTWH(x, y, width, height),
      active: map['active'] as bool? ?? true,
    );
  }

  static CutoutSide _sideOf(String? orientation) => switch (orientation) {
    // UIInterfaceOrientation is named after the side the home button
    // (indicator) is on; the island is at the opposite end.
    'landscapeLeft' => CutoutSide.right,
    'landscapeRight' => CutoutSide.left,
    'portrait' || 'portraitUpsideDown' => CutoutSide.none,
    _ => CutoutSide.unknown,
  };
}
