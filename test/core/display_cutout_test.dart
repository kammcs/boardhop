import 'package:boardhop/core/display_cutout.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.kammcs.boardhop/display');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the channel the way the Runner would. A null answer for a
  /// method stands for a platform that does not implement it.
  void answer({
    String? orientation,
    List<Map<String, Object?>>? regions,
    String? barEdge,
    Map<String, Object?>? hinge,
  }) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'interfaceOrientation') return orientation;
      if (call.method == 'reservedRegions') return regions;
      if (call.method == 'verticalBarEdge') return barEdge;
      if (call.method == 'hinge') return hinge;
      throw MissingPluginException();
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<String, Object?> region(
    String kind,
    double x,
    double y,
    double w,
    double h, {
    bool active = true,
  }) => {
    'kind': kind,
    'x': x,
    'y': y,
    'width': w,
    'height': h,
    'active': active,
  };

  test('the island is opposite the home indicator in landscape', () async {
    answer(orientation: 'landscapeLeft', regions: const []);
    expect(await DisplayCutout.side(), CutoutSide.right);
    answer(orientation: 'landscapeRight', regions: const []);
    expect(await DisplayCutout.side(), CutoutSide.left);
    answer(orientation: 'portrait', regions: const []);
    expect(await DisplayCutout.side(), CutoutSide.none);
    answer(orientation: 'unknown', regions: const []);
    expect(await DisplayCutout.side(), CutoutSide.unknown);
  });

  test('a platform with no display channel answers unknown', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw MissingPluginException(),
    );
    final r = await DisplayCutout.regions();
    expect(r.cutoutSide, CutoutSide.unknown);
    expect(r.regions, isEmpty);
    // Not asked is not the same as nothing in the way.
    expect(r.supported, isFalse);
    expect(r.folds, isFalse);
    expect(r.creaseBand, isNull);
  });

  test('reserved regions are parsed with their kind and rect', () async {
    answer(
      orientation: 'portrait',
      regions: [
        region('occlusion', 160, 0, 120, 36),
        region('division', 0, 430, 900, 14),
      ],
    );
    final r = await DisplayCutout.regions();
    expect(r.supported, isTrue);
    expect(r.regions, hasLength(2));
    expect(r.regions.first.kind, ReservedRegionKind.occlusion);
    expect(r.creaseBand, const Rect.fromLTWH(0, 430, 900, 14));
    expect(r.folds, isTrue);
  });

  test('a fold makes the cutout side unknown', () async {
    // On an iPhone Duo the orientation no longer says where the housing
    // is, so the shell must clear the inset on both sides.
    answer(
      orientation: 'landscapeLeft',
      regions: [region('division', 0, 430, 900, 14)],
    );
    expect(await DisplayCutout.side(), CutoutSide.unknown);

    // The same device with no fold reported keeps the orientation answer.
    answer(orientation: 'landscapeLeft', regions: const []);
    expect(await DisplayCutout.side(), CutoutSide.right);
  });

  test('an inactive fold is still a folding display but not a hinge', () async {
    answer(
      orientation: 'portrait',
      regions: [region('division', 0, 430, 900, 14, active: false)],
    );
    final r = await DisplayCutout.regions();
    expect(r.folds, isTrue, reason: 'the device folds even when open flat');
    expect(r.creaseBand, isNull, reason: 'nothing to lay out around right now');
    expect(r.activeDivision, isNull);
  });

  test('an unrecognised kind is kept, not dropped', () async {
    answer(orientation: 'portrait', regions: [region('sensor', 0, 0, 10, 10)]);
    final r = await DisplayCutout.regions();
    expect(r.regions.single.kind, ReservedRegionKind.unknown);
  });

  test('a region missing its geometry is skipped', () async {
    answer(
      orientation: 'portrait',
      regions: [
        {'kind': 'division'},
        region('occlusion', 1, 2, 3, 4),
      ],
    );
    final r = await DisplayCutout.regions();
    expect(r.regions, hasLength(1));
    expect(r.regions.single.kind, ReservedRegionKind.occlusion);
  });

  test('a region carries its margins and the view that answered', () async {
    answer(
      orientation: 'portrait',
      regions: [
        {
          ...region('division', 460, 0, 30, 951),
          'marginLeft': 8.0,
          'marginRight': 8.0,
          'source': 'flutterView',
        },
      ],
    );
    final r = await DisplayCutout.regions();
    final division = r.regions.single;
    expect(division.margins, const EdgeInsets.only(left: 8, right: 8));
    expect(division.source, 'flutterView');
    // The frame includes the margins; `inner` is the obstruction itself.
    expect(division.inner, const Rect.fromLTWH(468, 0, 14, 951));
  });

  test('a region without margins keeps a zero inset', () async {
    answer(
      orientation: 'portrait',
      regions: [region('occlusion', 0, 0, 10, 10)],
    );
    final r = await DisplayCutout.regions();
    expect(r.regions.single.margins, EdgeInsets.zero);
    expect(r.regions.single.inner, const Rect.fromLTWH(0, 0, 10, 10));
    expect(r.regions.single.source, isNull);
  });

  test('the vertical bar edge is read from the channel', () async {
    answer(barEdge: 'leading');
    expect(await DisplayCutout.verticalBarEdge(), BarEdge.leading);
    answer(barEdge: 'trailing');
    expect(await DisplayCutout.verticalBarEdge(), BarEdge.trailing);
    answer(barEdge: 'unspecified');
    expect(await DisplayCutout.verticalBarEdge(), BarEdge.unspecified);
  });

  test(
    'no vertical bar trait reads as unspecified, never as an edge',
    () async {
      // iOS before 27.1, Android, and the test binding all answer nothing.
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw MissingPluginException(),
      );
      expect(await DisplayCutout.verticalBarEdge(), BarEdge.unspecified);
    },
  );

  test('the hinge is read with its status and angle', () async {
    answer(hinge: {'status': 'partiallyOpen', 'angle': 1.57});
    final hinge = await DisplayCutout.hinge();
    expect(hinge.status, HingeStatus.partiallyOpen);
    expect(hinge.angle, closeTo(1.57, 1e-9));

    answer(hinge: {'status': 'fullyOpen'});
    expect((await DisplayCutout.hinge()).status, HingeStatus.fullyOpen);
    expect((await DisplayCutout.hinge()).angle, isNull);

    answer(hinge: {'status': 'closed'});
    expect((await DisplayCutout.hinge()).status, HingeStatus.closed);
    answer(hinge: {'status': 'unknown'});
    expect((await DisplayCutout.hinge()).status, HingeStatus.unknown);
  });

  test('hardware that does not fold reports none, not unknown', () async {
    answer(hinge: {'status': 'none'});
    expect((await DisplayCutout.hinge()).status, HingeStatus.none);
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw MissingPluginException(),
    );
    expect((await DisplayCutout.hinge()).status, HingeStatus.none);
  });
}
