import 'package:boardhop/features/diagnostics/display_probe_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Duo measuring tape (research/23 phase 0) with the Runner mocked: the
/// page must show what the channel says, not what it hopes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.kammcs.boardhop/display');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void answer({
    String orientation = 'landscapeLeft',
    List<Map<String, Object?>> regions = const [],
    String barEdge = 'unspecified',
    Map<String, Object?> hinge = const {'status': 'none'},
  }) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'interfaceOrientation':
          return orientation;
        case 'reservedRegions':
          return regions;
        case 'verticalBarEdge':
          return barEdge;
        case 'hinge':
          return hinge;
      }
      throw MissingPluginException();
    });
  }

  /// A window tall enough that every card is built: the page is one
  /// `ListView` and an off-screen row is no row at all.
  Future<void> show(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: DisplayProbePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('an iPhone Duo book pose is reported whole', (tester) async {
    answer(
      barEdge: 'trailing',
      hinge: {'status': 'partiallyOpen', 'angle': 1.5},
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
    await show(tester);

    expect(find.text('Display (Duo phase 0)'), findsOneWidget);
    expect(find.text('trailing'), findsOneWidget);
    expect(find.text('partiallyOpen at 1.5 rad'), findsOneWidget);
    expect(find.text('reservedRegions (1)'), findsOneWidget);
    expect(find.text('division (active)'), findsOneWidget);
    expect(find.text('320.0, 0.0 30.0 x 951.0'), findsOneWidget);
    expect(find.textContaining('flutterView'), findsOneWidget);
    // The window is reported as-is, with the breakpoint it lands in.
    expect(find.text('600.0 x 1800.0'), findsOneWidget);
    expect(find.text('medium'), findsOneWidget);
  });

  testWidgets('a platform with no display channel says so', (tester) async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw MissingPluginException(),
    );
    await show(tester);

    // Not asked is not the same as nothing in the way.
    expect(find.text('false'), findsNWidgets(2)); // supported, folds
    expect(find.text('unspecified'), findsOneWidget);
    expect(find.text('reservedRegions (0)'), findsOneWidget);
    expect(find.text('nothing reserved, or not asked'), findsOneWidget);
    // Flutter populates displayFeatures on Android only, so far.
    expect(find.text('displayFeatures (0)'), findsOneWidget);
  });

  testWidgets('a metrics change re-asks the channel', (tester) async {
    var asked = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'verticalBarEdge') {
        asked++;
        return asked > 1 ? 'leading' : 'trailing';
      }
      if (call.method == 'reservedRegions') return const [];
      if (call.method == 'hinge') return const {'status': 'none'};
      return 'portrait';
    });
    await show(tester);
    expect(find.text('trailing'), findsOneWidget);

    // What a fold looks like from Dart: the shell is told metrics changed.
    tester.view.physicalSize = const Size(700, 1800);
    await tester.pumpAndSettle();

    expect(asked, greaterThan(1));
    expect(find.text('leading'), findsOneWidget);
  });
}
