import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme_controller.dart' show RailSide;
import 'display_cutout.dart';

/// What the display is shaped like right now, kept live for the whole app.
///
/// [DisplayCutout] is the thin wrapper that asks the Runner a question and
/// gets an answer. This is the standing answer: it reads `displayState`
/// once, then **listens** for the Runner's `displayChanged` pushes and
/// notifies its listeners, so a page never polls.
///
/// The push is not an optimisation. Folding an iPhone Duo changes nothing
/// Flutter can see — `MediaQuery.size`, `padding` and `orientation` are
/// identical flat and half-folded, and `didChangeMetrics` does not fire at
/// all (research/23 §9.2) — so without the push a fold would never reach
/// Dart. `didChangeMetrics` is still listened to, because a rotation or a
/// Split View resize does change the window and the regions with it.
///
/// Everything derived from those answers ([crease], [creaseAxis], [halves],
/// [railSide], [compactPane]) is a pure function of the fields, so the
/// layout work in phases 2 and 3 can be unit-tested without a device.
///
/// **Two sources, one answer.** `MediaQuery.displayFeatures` is consulted
/// first wherever it is non-empty: Flutter populates it on Android today
/// and will on iOS once flutter/flutter#192515 lands, and when it does this
/// class takes the rectangles from there without any other change. The
/// channel still answers what `displayFeatures` cannot say — the vertical
/// bar edge, the hinge status, and "this display folds but is flat right
/// now" (Flutter's list has no inactive feature).
class DisplayEnvironment extends ChangeNotifier with WidgetsBindingObserver {
  /// Reads the platform and keeps listening. One of these lives in
  /// `app.dart` above the router, inside a [DisplayScope].
  DisplayEnvironment({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(DisplayCutout.channelName),
      _live = true {
    _channel.setMethodCallHandler(_onPlatformCall);
    WidgetsBinding.instance.addObserver(this);
    _readWindow();
    unawaited(refresh());
  }

  /// Fixed values, no channel and no observer: for widget tests, which
  /// drive [DisplayScope.override] instead of a device.
  DisplayEnvironment.fixed({
    DisplayRegions regions = const DisplayRegions(),
    BarEdge barEdge = BarEdge.unspecified,
    HingeState hinge = const HingeState(),
    Size? window,
    List<ui.DisplayFeature> displayFeatures = const [],
  }) : _channel = const MethodChannel(DisplayCutout.channelName),
       _live = false {
    _regions = regions;
    _barEdge = barEdge;
    _hinge = hinge;
    _window = window;
    _displayFeatures = displayFeatures;
  }

  final MethodChannel _channel;

  /// False for a [DisplayEnvironment.fixed]: nothing to unhook on dispose,
  /// and nothing to ask.
  final bool _live;

  DisplayRegions _regions = const DisplayRegions();
  BarEdge _barEdge = BarEdge.unspecified;
  HingeState _hinge = const HingeState();
  Size? _window;
  List<ui.DisplayFeature> _displayFeatures = const [];
  int _pushes = 0;
  DateTime? _lastPush;

  /// The reserved regions, whether the platform answered at all, and the
  /// cutout side the interface orientation implies.
  DisplayRegions get regions => _regions;

  /// Where iOS puts its own vertical bar, which is where the glass rail
  /// belongs (research/23 D1). [BarEdge.unspecified] everywhere else.
  BarEdge get barEdge => _barEdge;

  /// How far open the fold is. [HingeStatus.none] on hardware that does
  /// not fold.
  HingeState get hinge => _hinge;

  /// Which side of the window the Dynamic Island is on in landscape, or
  /// [CutoutSide.unknown] on a folding display where the question has no
  /// answer.
  CutoutSide get cutoutSide => _regions.cutoutSide;

  /// The platform answered the reserved-regions query. False is "not
  /// asked", which is not the same as "nothing in the way".
  bool get supported => _regions.supported;

  /// The window in logical pixels, as the engine reports it, or null
  /// before the first view exists.
  Size? get window => _window;

  /// What the engine says about folds, which is empty on iOS until
  /// flutter/flutter#192515 lands.
  List<ui.DisplayFeature> get displayFeatures => _displayFeatures;

  /// How many `displayChanged` pushes have arrived, and when the last one
  /// did. Diagnostics only: the Display page shows them so a fold can be
  /// seen to reach Dart with nothing touched.
  int get pushes => _pushes;
  DateTime? get lastPush => _lastPush;

  // MARK: the platform

  Future<Object?> _onPlatformCall(MethodCall call) async {
    if (call.method != 'displayChanged') return null;
    _apply(call.arguments);
    _pushes++;
    _lastPush = DateTime.now();
    notifyListeners();
    return null;
  }

  /// Asks the Runner for the whole state again. Called once at startup,
  /// on every metrics change, and by the Display diagnostics page's
  /// pull-to-refresh.
  Future<void> refresh() async {
    _readWindow();
    if (!_live) {
      notifyListeners();
      return;
    }
    Object? raw;
    try {
      raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('displayState');
    } on MissingPluginException {
      // Android, tests, and any build whose Runner is older than this.
      raw = null;
    } on PlatformException {
      raw = null;
    }
    _apply(raw);
    notifyListeners();
  }

  /// `{regions, verticalBarEdge, hinge, interfaceOrientation}`, the shape
  /// both `displayState` and `displayChanged` carry.
  void _apply(Object? raw) {
    final map = raw is Map ? raw.cast<String, dynamic>() : null;
    _regions = DisplayCutout.decodeRegions(
      map?['regions'] as List<dynamic>?,
      orientation: map?['interfaceOrientation'] as String?,
    );
    _barEdge = DisplayCutout.decodeBarEdge(map?['verticalBarEdge']);
    _hinge = DisplayCutout.decodeHinge(map?['hinge']);
  }

  void _readWindow() {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return;
    final size = view.physicalSize / view.devicePixelRatio;
    _window = size.isEmpty ? null : size;
    _displayFeatures = view.displayFeatures;
  }

  @override
  void didChangeMetrics() {
    // A fold does not come this way (§9.2), but a rotation and a Split
    // View resize do, and they move the regions.
    unawaited(refresh());
  }

  @override
  void dispose() {
    if (_live) {
      _channel.setMethodCallHandler(null);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  // MARK: derived answers, all pure

  /// The engine's fold, if it has one. Empty on iOS until #192515.
  ui.DisplayFeature? get _foldFeature {
    for (final f in _displayFeatures) {
      if (f.type == ui.DisplayFeatureType.fold ||
          f.type == ui.DisplayFeatureType.hinge) {
        return f;
      }
    }
    return null;
  }

  /// A flat fold is not in the way; a hinge (a physical gap between two
  /// panels) always is.
  static bool _featureIsActive(ui.DisplayFeature f) =>
      f.type == ui.DisplayFeatureType.hinge ||
      f.state == ui.DisplayFeatureState.postureHalfOpened;

  /// The fold's **keep-out band**: the whole reported frame, margins
  /// included, or null when nothing is folded right now.
  ///
  /// On an iPhone Duo this is 40 pt wide (or tall) with 20 pt of margin on
  /// each side of a zero-width crease, so the band is the strip that must
  /// hold no tap target and the [crease] is the line inside it that panes
  /// and dividers align to (research/23 §2).
  Rect? get creaseBand {
    final feature = _foldFeature;
    if (feature != null) {
      return _featureIsActive(feature) ? feature.bounds : null;
    }
    return _regions.creaseBand;
  }

  /// The fold **line**: [creaseBand]'s centre, as a zero-width (vertical
  /// crease) or zero-height (horizontal crease) [Rect] in window
  /// coordinates. Null when nothing is folded.
  Rect? get crease {
    final band = creaseBand;
    if (band == null) return null;
    return creaseAxis == Axis.vertical
        ? Rect.fromLTRB(band.center.dx, band.top, band.center.dx, band.bottom)
        : Rect.fromLTRB(band.left, band.center.dy, band.right, band.center.dy);
  }

  /// [Axis.vertical] when the band is taller than it is wide — the book
  /// pose, where the crease runs top to bottom and splits the window left
  /// and right. Null when nothing is folded.
  Axis? get creaseAxis {
    final band = creaseBand;
    if (band == null) return null;
    return band.height > band.width ? Axis.vertical : Axis.horizontal;
  }

  /// The occlusions in force right now, in window coordinates: on an
  /// iPhone Duo the stacked status bar in the corner of the bar edge
  /// (84 x 120 in the wide pose, 84 x 170 on the cover, research/23 §2).
  ///
  /// `MediaQuery.padding` reports the same 84 pt, but only as "this much
  /// of that side", which is why the rail takes the rectangle instead: it
  /// says how far **down** the corner reaches, and so how much of the edge
  /// the rail can still have (research/23 §4.3). Inactive regions are left
  /// out, so the camera on the panel that is not in use is not in the way.
  List<Rect> get occlusions => [
    for (final r in _regions.regions)
      if (r.kind == ReservedRegionKind.occlusion && r.active) r.rect,
  ];

  /// The display can fold, whether or not it is folded now. An iPhone Duo
  /// lying flat still reports its division, which is how a page decides to
  /// prefer an even number of columns.
  bool get folds => _regions.folds || _foldFeature != null;

  /// The two usable rectangles either side of an active crease, in window
  /// coordinates; empty when nothing is folded.
  ///
  /// Measured from the region's **margins**, not its frame: the 40 pt band
  /// is 20 pt of keep-out on each side of a zero-width line, so splitting
  /// on the frame would throw away 20 pt each half could have used
  /// (research/23 §9.7). Content that must not sit *in* the band is the
  /// job of the band itself, not of the halves.
  List<Rect> halves(Size window) {
    final axis = creaseAxis;
    final line = _creaseObstruction;
    if (axis == null || line == null) return const [];
    if (axis == Axis.vertical) {
      return [
        Rect.fromLTRB(0, 0, line.left, window.height),
        Rect.fromLTRB(line.right, 0, window.width, window.height),
      ];
    }
    return [
      Rect.fromLTRB(0, 0, window.width, line.top),
      Rect.fromLTRB(0, line.bottom, window.width, window.height),
    ];
  }

  /// The obstruction itself: the band with its margins taken off, which on
  /// an iPhone Duo is the zero-width centre line.
  Rect? get _creaseObstruction {
    final feature = _foldFeature;
    if (feature != null) {
      return _featureIsActive(feature) ? feature.bounds : null;
    }
    return _regions.activeDivision?.inner;
  }

  /// [barEdge] resolved against the reading direction, or null where the
  /// system asks for no vertical bar and today's rules stay (research/23
  /// D1, D6).
  RailSide? railSide(TextDirection direction) => switch (_barEdge) {
    BarEdge.leading =>
      direction == TextDirection.ltr ? RailSide.left : RailSide.right,
    BarEdge.trailing =>
      direction == TextDirection.ltr ? RailSide.right : RailSide.left,
    BarEdge.unspecified => null,
  };

  /// A narrow window that still wants a vertical bar: Boardhop in one half
  /// of Split View, where the rail keeps its width but the margin tightens
  /// (research/23 §4.3). False on a plain iPhone, whose compact width comes
  /// with no bar edge at all.
  bool get compactPane {
    final width = _window?.width;
    return width != null && width < 600 && _barEdge != BarEdge.unspecified;
  }
}

/// Makes the [DisplayEnvironment] available below `MaterialApp` and
/// rebuilds dependents when the display changes. Installed in `app.dart`
/// beside [ThemeScope]; read it with `DisplayScope.of(context)`.
class DisplayScope extends InheritedNotifier<DisplayEnvironment> {
  const DisplayScope({
    super.key,
    required DisplayEnvironment environment,
    required super.child,
  }) : super(notifier: environment);

  /// Fixed values for a widget test, with no channel behind them.
  DisplayScope.override({
    Key? key,
    DisplayRegions regions = const DisplayRegions(),
    BarEdge barEdge = BarEdge.unspecified,
    HingeState hinge = const HingeState(),
    Size? window,
    List<ui.DisplayFeature> displayFeatures = const [],
    required Widget child,
  }) : this(
         key: key,
         environment: DisplayEnvironment.fixed(
           regions: regions,
           barEdge: barEdge,
           hinge: hinge,
           window: window,
           displayFeatures: displayFeatures,
         ),
         child: child,
       );

  static DisplayEnvironment of(BuildContext context) {
    final environment = maybeOf(context);
    assert(environment != null, 'No DisplayScope above this widget');
    return environment!;
  }

  static DisplayEnvironment? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DisplayScope>()?.notifier;
}
