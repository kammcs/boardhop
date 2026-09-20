import 'package:flutter/painting.dart';
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

/// The edge iOS puts its own vertical bar on (`UITraitCollection
/// .verticalBarEdge`, iOS 27.1).
///
/// The trait "reflects the system's preferred edge regardless of whether a
/// vertical bar is currently visible", so it answers for the glass rail as
/// well (research/23 D1). [unspecified] is both "this hardware never has
/// one" and "not in this orientation", and is what every OS before 27.1
/// and every other platform reports.
enum BarEdge { leading, trailing, unspecified }

/// How far open the fold is (`UIHinge.status`, iOS 27.1).
///
/// [none] is hardware that does not fold, which is not the same as
/// [unknown]: the latter is a hinge whose position the system cannot read.
enum HingeStatus { closed, partiallyOpen, fullyOpen, unknown, none }

/// The fold's state: how far open, and by how much in radians when the
/// platform says.
class HingeState {
  const HingeState({
    this.status = HingeStatus.none,
    this.angle,
    this.updates = 0,
    this.view,
  });

  final HingeStatus status;

  /// How many hinge updates the platform has delivered, and the view the
  /// interaction sits on. Diagnostics only: they tell "the system says
  /// unknown" apart from "no update has arrived yet" (research/23 §9).
  final int updates;
  final String? view;

  /// Radians, or null when the platform reports no angle. Apple warns the
  /// rate and precision are system policy, so nothing lays out from it
  /// (research/23 D7).
  final double? angle;

  @override
  String toString() => 'HingeState($status, angle: $angle)';
}

/// One rectangle of the display the UI has to keep clear of, in logical
/// pixels within the Flutter view.
class ReservedRegion {
  const ReservedRegion({
    required this.kind,
    required this.rect,
    this.active = true,
    this.margins = EdgeInsets.zero,
    this.source,
  });

  final ReservedRegionKind kind;

  /// The region including its margins, which is what UIKit reports.
  final Rect rect;

  /// The part of [rect] that is margin rather than obstruction: the space
  /// UIKit keeps clear around the reserved rect for interactive content.
  final EdgeInsets margins;

  /// False for a region that exists but is not currently in force, such as
  /// a hinge on a device that is open flat.
  final bool active;

  /// Which `UIView` answered ("flutterView", "rootView" or "window"), for
  /// diagnostics. Null anywhere the platform does not say.
  final String? source;

  /// [rect] with the margins taken off: the obstruction itself.
  Rect get inner =>
      margins == EdgeInsets.zero ? rect : margins.deflateRect(rect);

  @override
  String toString() =>
      'ReservedRegion($kind, $rect, margins: $margins, active: $active)';
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

  /// The active fold's **keep-out band**, if the display has one: the
  /// whole reported frame, margins included.
  ///
  /// On an iPhone Duo that band is 40 pt wide with 20 pt of margin on each
  /// side, so the crease itself is the zero-width line down its middle
  /// (research/23 §2). Named for the band rather than the hinge because
  /// [HingeState] already owns that word: this is geometry, that is the
  /// fold's status. `DisplayEnvironment.crease` is the line.
  ReservedRegion? get activeDivision {
    for (final r in regions) {
      if (r.kind == ReservedRegionKind.division && r.active) return r;
    }
    return null;
  }

  /// [activeDivision]'s frame, or null when nothing is folded right now.
  Rect? get creaseBand => activeDivision?.rect;

  /// The display folds, whether or not the fold is in force right now. An
  /// iPhone Duo reports its division even when open.
  bool get folds => regions.any((r) => r.kind == ReservedRegionKind.division);
}

/// Asks iOS about the shape of the display.
///
/// Four questions, one channel (`com.kammcs.boardhop/display`):
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
///   rectangles over (research/12b). Each region carries its margins and
///   whether it is active right now.
/// * **Where does the system put its vertical bar?** iOS 27.1's
///   `UITraitCollection.verticalBarEdge`, which is where Boardhop's glass
///   rail belongs on an iPhone Duo (research/23 D1).
/// * **How far open is the fold?** `UIHinge.status` through a
///   `UIHingeInteraction` on the Flutter view.
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

  /// The channel the Runner answers on, and pushes `displayChanged` over
  /// (`lib/core/display_environment.dart`).
  static const channelName = 'com.kammcs.boardhop/display';

  static const _channel = MethodChannel(channelName);

  /// Which side the cutout is on, or [CutoutSide.unknown] on a folding
  /// display. Kept as its own call for the shell, which wants only this.
  static Future<CutoutSide> side() async => (await regions()).cutoutSide;

  /// The edge iOS wants its vertical bar on, or [BarEdge.unspecified]
  /// where it wants none (and on every platform without the trait).
  static Future<BarEdge> verticalBarEdge() async =>
      decodeBarEdge(await _invoke<String>('verticalBarEdge'));

  /// The fold's status and angle. [HingeStatus.none] where nothing folds.
  static Future<HingeState> hinge() async =>
      decodeHinge(await _invoke<Map<dynamic, dynamic>>('hinge'));

  /// The display's reserved regions and cutout side in one round trip.
  static Future<DisplayRegions> regions() async {
    final orientation = await _invoke<String>('interfaceOrientation');
    final raw = await _invoke<List<dynamic>>('reservedRegions');
    return decodeRegions(raw, orientation: orientation);
  }

  /// `"leading" | "trailing" | anything else` from the channel.
  static BarEdge decodeBarEdge(Object? raw) => switch (raw) {
    'leading' => BarEdge.leading,
    'trailing' => BarEdge.trailing,
    _ => BarEdge.unspecified,
  };

  /// `{left, top, right, bottom}` from the channel, in points; anything
  /// else is [EdgeInsets.zero], which is also what iOS answers on a
  /// display with no rounded corner in the way.
  static EdgeInsets decodeInsets(Object? raw) {
    if (raw is! Map) return EdgeInsets.zero;
    final map = raw.cast<String, dynamic>();
    double at(String key) => (map[key] as num?)?.toDouble() ?? 0;
    return EdgeInsets.fromLTRB(
      at('left'),
      at('top'),
      at('right'),
      at('bottom'),
    );
  }

  /// `{name: {left, top, right, bottom}}` from the channel: every layout
  /// region the Runner measured, for the Display probe page.
  static Map<String, EdgeInsets> decodeInsetMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        '${entry.key}': decodeInsets(entry.value),
    };
  }

  /// `{status, angle, updates, view}` from the channel; a null map is a
  /// platform that does not fold.
  static HingeState decodeHinge(Object? raw) {
    if (raw is! Map) return const HingeState();
    final map = raw.cast<String, dynamic>();
    return HingeState(
      status: switch (map['status']) {
        'closed' => HingeStatus.closed,
        'partiallyOpen' => HingeStatus.partiallyOpen,
        'fullyOpen' => HingeStatus.fullyOpen,
        'unknown' => HingeStatus.unknown,
        _ => HingeStatus.none,
      },
      angle: (map['angle'] as num?)?.toDouble(),
      updates: (map['updates'] as num?)?.toInt() ?? 0,
      view: map['view'] as String?,
    );
  }

  /// The reserved-region list from the channel, with the cutout side the
  /// interface orientation implies. A null list is "not asked", which is
  /// not the same as "nothing in the way", and keeps [supported] false.
  static DisplayRegions decodeRegions(
    List<dynamic>? raw, {
    String? orientation,
  }) {
    final parsed = <ReservedRegion>[];
    for (final entry in raw ?? const []) {
      final map = (entry as Map?)?.cast<String, dynamic>();
      if (map == null) continue;
      final region = _region(map);
      if (region != null) parsed.add(region);
    }
    final folds = parsed.any((r) => r.kind == ReservedRegionKind.division);
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
    double margin(String key) => (map[key] as num?)?.toDouble() ?? 0;
    return ReservedRegion(
      kind: switch (map['kind']) {
        'division' => ReservedRegionKind.division,
        'occlusion' => ReservedRegionKind.occlusion,
        _ => ReservedRegionKind.unknown,
      },
      rect: Rect.fromLTWH(x, y, width, height),
      active: map['active'] as bool? ?? true,
      margins: EdgeInsets.fromLTRB(
        margin('marginLeft'),
        margin('marginTop'),
        margin('marginRight'),
        margin('marginBottom'),
      ),
      source: map['source'] as String?,
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
