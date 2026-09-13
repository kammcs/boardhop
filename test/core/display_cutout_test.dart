import 'package:boardhop/core/display_cutout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.kammcs.boardhop/display');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the channel the way the Runner would. A null answer for a
  /// method stands for a platform that does not implement it.
  void answer({String? orientation, List<Map<String, Object?>>? regions}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'interfaceOrientation') return orientation;
      if (call.method == 'reservedRegions') return regions;
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
    expect(r.hinge, isNull);
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
    expect(r.hinge, const Rect.fromLTWH(0, 430, 900, 14));
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
    expect(r.hinge, isNull, reason: 'nothing to lay out around right now');
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
}
