import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/core/display_environment.dart';
import 'package:boardhop/features/diagnostics/display_probe_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Duo measuring tape (research/23) with the Runner mocked: the page
/// must show what the channel says, not what it hopes — and it must move
/// on a push, with nothing touched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(DisplayCutout.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<String, Object?> state({
    String orientation = 'landscapeLeft',
    List<Map<String, Object?>> regions = const [],
    String barEdge = 'unspecified',
    Map<String, Object?> hinge = const {'status': 'none'},
  }) => {
    'regions': regions,
    'verticalBarEdge': barEdge,
    'hinge': hinge,
    'interfaceOrientation': orientation,
  };

  /// The half-folded wide pose, as measured (§2).
  final wideBook = state(
    barEdge: 'trailing',
    hinge: const {'status': 'partiallyOpen', 'angle': 1.5},
    regions: [
      {
        'kind': 'division',
        'x': 320.0,
        'y': 0.0,
        'width': 30.0,
        'height': 951.0,
        'active': true,
        'marginLeft': 8.0,
        'marginRight': 8.0,
        'source': 'flutterView',
      },
    ],
  );

  void answer(Map<String, Object?>? payload) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'displayState' || payload == null) {
        throw MissingPluginException();
      }
      return payload;
    });
  }

  /// A window tall enough that every card is built: the page is one
  /// `ListView` and an off-screen row is no row at all.
  Future<DisplayEnvironment> show(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final environment = DisplayEnvironment();
    addTearDown(environment.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DisplayScope(
          environment: environment,
          child: const DisplayProbePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return environment;
  }

  Future<void> push(WidgetTester tester, Map<String, Object?> payload) async {
    await messenger.handlePlatformMessage(
      DisplayCutout.channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('displayChanged', payload),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an iPhone Duo book pose is reported whole', (tester) async {
    answer(wideBook);
    await show(tester);

    expect(find.text('Display'), findsOneWidget);
    expect(find.text('trailing'), findsOneWidget);
    expect(find.text('partiallyOpen at 1.5 rad'), findsOneWidget);
    expect(find.text('reservedRegions (1)'), findsOneWidget);
    expect(find.text('division (active)'), findsOneWidget);
    // Once in the region list, once as the derived keep-out band.
    expect(find.text('320.0, 0.0 30.0 x 951.0'), findsNWidgets(2));
    expect(find.textContaining('flutterView'), findsOneWidget);
    // The derived answers the layout phases will read.
    expect(find.text('vertical'), findsOneWidget);
    expect(
      find.text('335.0, 0.0 0.0 x 951.0'),
      findsOneWidget,
      reason: 'the crease line',
    );
    // The window is reported as-is, with the breakpoint it lands in.
    expect(find.text('600.0 x 2400.0'), findsOneWidget);
    expect(find.text('medium'), findsOneWidget);
    // No refresh button: pull-to-refresh instead (DESIGN).
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets('a platform with no display channel says so', (tester) async {
    answer(null);
    await show(tester);

    // Not asked is not the same as nothing in the way.
    expect(
      find.text('false'),
      findsNWidgets(3),
    ); // supported, folds, compactPane
    expect(find.text('unspecified'), findsOneWidget);
    expect(find.text('reservedRegions (0)'), findsOneWidget);
    expect(find.text('nothing reserved, or not asked'), findsOneWidget);
    // Flutter populates displayFeatures on Android only, so far.
    expect(find.text('displayFeatures (0)'), findsOneWidget);
    expect(find.text('none yet'), findsOneWidget);
  });

  testWidgets('a push updates the page with nothing touched', (tester) async {
    // The phase 1 check, in miniature: a fold changes no metric, so the
    // metrics counter stays at 0 while the push counter rises and the
    // division flips to active (research/23 §9.2).
    answer(state(barEdge: 'trailing'));
    await show(tester);
    expect(find.text('0'), findsNWidgets(2)); // pushes, metrics changes
    expect(find.text('reservedRegions (0)'), findsOneWidget);

    await push(tester, wideBook);

    expect(find.text('1'), findsOneWidget, reason: 'one push received');
    expect(find.text('division (active)'), findsOneWidget);
    expect(find.text('partiallyOpen at 1.5 rad'), findsOneWidget);
    // Nothing Flutter itself reports has changed.
    expect(find.text('0'), findsOneWidget, reason: 'metrics changes');
  });

  testWidgets('a metrics change re-asks the channel', (tester) async {
    var asked = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'displayState') throw MissingPluginException();
      asked++;
      return state(barEdge: asked > 1 ? 'leading' : 'trailing');
    });
    await show(tester);
    expect(find.text('trailing'), findsOneWidget);

    // A rotation or a Split View resize, unlike a fold, does come this way.
    tester.view.physicalSize = const Size(700, 2400);
    await tester.pumpAndSettle();

    expect(asked, greaterThan(1));
    expect(find.text('leading'), findsOneWidget);
  });
}
