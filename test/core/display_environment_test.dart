import 'dart:ui' as ui;

import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/core/display_environment.dart';
import 'package:boardhop/theme/theme_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The display environment against the poses measured on the iPhone Duo
/// simulator (research/23 §2), plus the Runner's push.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DisplayCutout.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  // ---------------------------------------------------------------- poses
  //
  // Every number below came off the device through the Display
  // diagnostics page (research/23 §2), not from guidance.

  Map<String, Object?> region(
    String kind,
    double x,
    double y,
    double w,
    double h, {
    bool active = true,
    double margin = 0,
    String axis = 'vertical',
  }) => {
    'kind': kind,
    'x': x,
    'y': y,
    'width': w,
    'height': h,
    'active': active,
    'marginLeft': axis == 'vertical' ? margin : 0.0,
    'marginRight': axis == 'vertical' ? margin : 0.0,
    'marginTop': axis == 'vertical' ? 0.0 : margin,
    'marginBottom': axis == 'vertical' ? 0.0 : margin,
    'source': 'flutterView',
  };

  Map<String, Object?> state({
    List<Map<String, Object?>> regions = const [],
    String barEdge = 'unspecified',
    Map<String, Object?> hinge = const {'status': 'none'},
    String orientation = 'portrait',
  }) => {
    'regions': regions,
    'verticalBarEdge': barEdge,
    'hinge': hinge,
    'interfaceOrientation': orientation,
  };

  /// The cover panel: no division at all, so the pre-27.1 cutout answer
  /// still applies there (§2).
  final coverPortrait = state(
    barEdge: 'trailing',
    hinge: const {'status': 'closed', 'angle': 0.0},
    orientation: 'portrait',
    regions: [region('occlusion', 382, 0, 84, 170)],
  );

  /// Wide pose, flat: the division is reported but inactive.
  final wideFlat = state(
    barEdge: 'trailing',
    hinge: const {'status': 'fullyOpen', 'angle': 3.14},
    orientation: 'landscapeLeft',
    regions: [
      region('division', 455.5, 0, 40, 669, active: false),
      region('occlusion', 867, 0, 84, 120),
    ],
  );

  /// Wide pose, half folded: the same rect, now active, with 20 pt of
  /// margin on each side of a zero-width crease at x = 475.5.
  final wideBook = state(
    barEdge: 'trailing',
    hinge: const {'status': 'partiallyOpen', 'angle': 2.23},
    orientation: 'landscapeLeft',
    regions: [
      region('division', 455.5, 0, 40, 669, margin: 20),
      region('occlusion', 867, 0, 84, 120),
    ],
  );

  final tallFlat = state(
    hinge: const {'status': 'fullyOpen', 'angle': 3.14},
    orientation: 'portrait',
    regions: [
      region('division', 0, 455.5, 669, 40, active: false, axis: 'horizontal'),
      region('occlusion', 535, 0, 134, 82),
    ],
  );

  final tallBook = state(
    hinge: const {'status': 'partiallyOpen', 'angle': 2.23},
    orientation: 'portrait',
    regions: [
      region('division', 0, 455.5, 669, 40, margin: 20, axis: 'horizontal'),
      region('occlusion', 535, 0, 134, 82),
    ],
  );

  // ------------------------------------------------------------- channel

  /// A live environment with the Runner mocked. [answers] is what
  /// `displayState` returns; null stands for a platform with no channel.
  Future<DisplayEnvironment> live(Map<String, Object?>? answers) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'displayState') throw MissingPluginException();
      if (answers == null) throw MissingPluginException();
      return answers;
    });
    final environment = DisplayEnvironment();
    addTearDown(environment.dispose);
    await pumpEventQueue();
    return environment;
  }

  /// What the Runner does when the hinge moves: `displayChanged` with the
  /// same payload a fresh poll would return.
  Future<void> pushed(Map<String, Object?> payload) =>
      messenger.handlePlatformMessage(
        DisplayCutout.channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('displayChanged', payload),
        ),
        (_) {},
      );

  test('displayState is decoded whole, in one round trip', () async {
    final environment = await live(wideBook);
    expect(environment.supported, isTrue);
    expect(environment.barEdge, BarEdge.trailing);
    expect(environment.hinge.status, HingeStatus.partiallyOpen);
    expect(environment.hinge.angle, closeTo(2.23, 1e-9));
    expect(environment.regions.regions, hasLength(2));
    expect(environment.regions.regions.first.source, 'flutterView');
    // A fold makes the orientation answer meaningless.
    expect(environment.cutoutSide, CutoutSide.unknown);
  });

  test('a push replaces the state and notifies, with no poll', () async {
    // The fold that phase 0 could not see: flat to half folded, no metrics
    // change, no size change, nothing but this call (§9.2).
    final environment = await live(wideFlat);
    var notifications = 0;
    environment.addListener(() => notifications++);
    expect(environment.crease, isNull, reason: 'open flat');
    expect(environment.pushes, 0);
    expect(environment.lastPush, isNull);

    await pushed(wideBook);

    expect(environment.pushes, 1);
    expect(environment.lastPush, isNotNull);
    expect(notifications, 1);
    expect(environment.hinge.status, HingeStatus.partiallyOpen);
    expect(environment.crease?.left, closeTo(475.5, 1e-9));

    // And back again: the push is the only thing that unfolds it too.
    await pushed(wideFlat);
    expect(environment.pushes, 2);
    expect(environment.crease, isNull);
  });

  test('a push of something else on the channel is ignored', () async {
    final environment = await live(wideFlat);
    await messenger.handlePlatformMessage(
      DisplayCutout.channelName,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('somethingElse'),
      ),
      (_) {},
    );
    expect(environment.pushes, 0);
  });

  test(
    'a device before iOS 27.1 answers nothing, not "nothing there"',
    () async {
      final environment = await live(null);
      expect(environment.supported, isFalse);
      expect(environment.barEdge, BarEdge.unspecified);
      expect(environment.hinge.status, HingeStatus.none);
      expect(environment.folds, isFalse);
      expect(environment.crease, isNull);
      expect(environment.creaseAxis, isNull);
      expect(environment.halves(const Size(874, 402)), isEmpty);
      expect(environment.railSide(TextDirection.ltr), isNull);
      expect(environment.compactPane, isFalse);
    },
  );

  // ------------------------------------------------------------- derived

  /// The same decoding without a channel: [DisplayScope.override]'s path,
  /// and what every widget test will use from phase 2 on.
  DisplayEnvironment fixed(Map<String, Object?> pose, Size window) {
    final map = pose;
    return DisplayEnvironment.fixed(
      regions: DisplayCutout.decodeRegions(
        map['regions'] as List<dynamic>?,
        orientation: map['interfaceOrientation'] as String?,
      ),
      barEdge: DisplayCutout.decodeBarEdge(map['verticalBarEdge']),
      hinge: DisplayCutout.decodeHinge(map['hinge']),
      window: window,
    );
  }

  test('cover panel: a vertical bar edge, no fold at all', () {
    const window = Size(466, 678);
    final environment = fixed(coverPortrait, window);
    expect(environment.folds, isFalse, reason: 'no division on the cover');
    expect(environment.crease, isNull);
    expect(environment.creaseAxis, isNull);
    expect(environment.halves(window), isEmpty);
    expect(environment.barEdge, BarEdge.trailing);
    expect(environment.railSide(TextDirection.ltr), RailSide.right);
    // 466 pt is compact, and the system does want a bar there.
    expect(environment.compactPane, isTrue);
    expect(environment.hinge.status, HingeStatus.closed);
  });

  test('wide pose, flat: it folds, but nothing is in the way yet', () {
    const window = Size(951, 669);
    final environment = fixed(wideFlat, window);
    expect(environment.folds, isTrue, reason: 'an inactive division is a fold');
    expect(environment.crease, isNull);
    expect(environment.creaseBand, isNull);
    expect(environment.creaseAxis, isNull);
    expect(environment.halves(window), isEmpty);
    expect(environment.railSide(TextDirection.ltr), RailSide.right);
    expect(environment.compactPane, isFalse, reason: '951 pt is not a pane');
  });

  test('wide pose, book: a vertical crease down the middle', () {
    const window = Size(951, 669);
    final environment = fixed(wideBook, window);
    expect(environment.creaseAxis, Axis.vertical);
    // The band is the 40 pt keep-out strip; the crease is the line in it.
    expect(environment.creaseBand, const Rect.fromLTWH(455.5, 0, 40, 669));
    expect(environment.crease, const Rect.fromLTRB(475.5, 0, 475.5, 669));
    expect(environment.crease!.width, 0);

    // Halves come off the margins, so neither loses the 20 pt it could
    // have used (§9.7): they meet on the line, not on the band's edges.
    expect(environment.halves(window), [
      const Rect.fromLTRB(0, 0, 475.5, 669),
      const Rect.fromLTRB(475.5, 0, 951, 669),
    ]);
  });

  test('tall pose, flat and book: the crease turns with the device', () {
    const window = Size(669, 951);
    expect(fixed(tallFlat, window).crease, isNull);
    expect(fixed(tallFlat, window).folds, isTrue);
    // The tall pose is the one the system wants no vertical bar in.
    expect(fixed(tallFlat, window).barEdge, BarEdge.unspecified);
    expect(fixed(tallFlat, window).railSide(TextDirection.ltr), isNull);

    final environment = fixed(tallBook, window);
    expect(environment.creaseAxis, Axis.horizontal);
    expect(environment.creaseBand, const Rect.fromLTWH(0, 455.5, 669, 40));
    expect(environment.crease, const Rect.fromLTRB(0, 475.5, 669, 475.5));
    expect(environment.crease!.height, 0);
    expect(environment.halves(window), [
      const Rect.fromLTRB(0, 0, 669, 475.5),
      const Rect.fromLTRB(0, 475.5, 669, 951),
    ]);
    expect(environment.railSide(TextDirection.ltr), isNull);
  });

  test('Split View: each pane puts the rail on its outer edge', () {
    // Not measured on the device yet (§9.5); the sizes are the plan's
    // 50/50 pane and the edges are what the HIG describes.
    const pane = Size(475, 669);
    final left = fixed(
      state(barEdge: 'leading', orientation: 'landscapeLeft'),
      pane,
    );
    expect(left.railSide(TextDirection.ltr), RailSide.left);
    expect(left.compactPane, isTrue);

    final right = fixed(
      state(barEdge: 'trailing', orientation: 'landscapeLeft'),
      pane,
    );
    expect(right.railSide(TextDirection.ltr), RailSide.right);
    expect(right.compactPane, isTrue);
  });

  test('the bar edge is a reading direction, not a side', () {
    const pane = Size(475, 669);
    final leading = fixed(state(barEdge: 'leading'), pane);
    expect(leading.railSide(TextDirection.ltr), RailSide.left);
    expect(leading.railSide(TextDirection.rtl), RailSide.right);
    final trailing = fixed(state(barEdge: 'trailing'), pane);
    expect(trailing.railSide(TextDirection.ltr), RailSide.right);
    expect(trailing.railSide(TextDirection.rtl), RailSide.left);
  });

  test('a compact window with no bar edge is a phone, not a pane', () {
    final environment = fixed(state(), const Size(402, 874));
    expect(environment.compactPane, isFalse);
  });

  test('displayFeatures win over the channel once the engine has them', () {
    // flutter/flutter#192515: when the iOS engine starts reporting the
    // fold, the rectangles come from there and nothing else changes.
    const window = Size(951, 669);
    final environment = DisplayEnvironment.fixed(
      regions: DisplayCutout.decodeRegions(
        wideFlat['regions'] as List<dynamic>?,
      ),
      barEdge: BarEdge.trailing,
      window: window,
      displayFeatures: const [
        ui.DisplayFeature(
          bounds: Rect.fromLTWH(470, 0, 10, 669),
          type: ui.DisplayFeatureType.fold,
          state: ui.DisplayFeatureState.postureHalfOpened,
        ),
      ],
    );
    expect(environment.creaseAxis, Axis.vertical);
    expect(environment.creaseBand, const Rect.fromLTWH(470, 0, 10, 669));
    expect(environment.crease, const Rect.fromLTRB(475, 0, 475, 669));
    expect(environment.halves(window), [
      const Rect.fromLTRB(0, 0, 470, 669),
      const Rect.fromLTRB(480, 0, 951, 669),
    ]);
    expect(environment.folds, isTrue);
  });

  test('a flat displayFeature folds but does not divide', () {
    const window = Size(951, 669);
    final environment = DisplayEnvironment.fixed(
      window: window,
      displayFeatures: const [
        ui.DisplayFeature(
          bounds: Rect.fromLTWH(475, 0, 0, 669),
          type: ui.DisplayFeatureType.fold,
          state: ui.DisplayFeatureState.postureFlat,
        ),
      ],
    );
    expect(environment.folds, isTrue);
    expect(environment.crease, isNull);
    expect(environment.halves(window), isEmpty);
  });

  // --------------------------------------------------------------- scope

  testWidgets('DisplayScope hands the environment down and rebuilds', (
    tester,
  ) async {
    final environment = DisplayEnvironment.fixed(
      barEdge: BarEdge.trailing,
      window: const Size(951, 669),
    );
    addTearDown(environment.dispose);
    var builds = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DisplayScope(
          environment: environment,
          child: Builder(
            builder: (context) {
              builds++;
              final side = DisplayScope.of(context)
                  .railSide(Directionality.of(context));
              return Text('${side?.name}');
            },
          ),
        ),
      ),
    );
    expect(find.text('right'), findsOneWidget);
    expect(builds, 1);

    environment.notifyListeners();
    await tester.pump();
    expect(builds, 2, reason: 'an InheritedNotifier rebuilds its dependents');
  });

  testWidgets('DisplayScope.override is enough for a widget test', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: DisplayScope.override(
          barEdge: BarEdge.leading,
          window: const Size(475, 669),
          regions: DisplayCutout.decodeRegions(
            wideBook['regions'] as List<dynamic>?,
          ),
          child: Builder(
            builder: (context) {
              final display = DisplayScope.of(context);
              return Text(
                '${display.railSide(TextDirection.ltr)?.name} '
                '${display.compactPane} ${display.creaseAxis?.name}',
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('left true vertical'), findsOneWidget);
  });

  testWidgets('maybeOf answers null with no scope above', (tester) async {
    DisplayEnvironment? seen;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = DisplayScope.maybeOf(context);
          return const SizedBox.shrink();
        },
      ),
    );
    expect(seen, isNull);
  });
}
