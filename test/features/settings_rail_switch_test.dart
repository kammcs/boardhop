import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/core/display_environment.dart';
import 'package:boardhop/core/notifications/notification_service.dart';
import 'package:boardhop/features/settings/settings_page.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:boardhop/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Settings > Appearance offers "Tab rail on the right" only where the
/// choice is the user's. On a display whose system names the edge its own
/// vertical bar belongs on — an iPhone Duo's inner display, its cover, a
/// Split View pane — the rail follows that edge and the switch would be a
/// control over nothing (research/23 D6).
void main() {
  Future<void> pump(WidgetTester tester, {required BarEdge edge}) async {
    // An iPad-sized window: the switch is hidden at compact width anyway.
    tester.view.physicalSize = const Size(1032, 1376);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<NotificationService>.value(
        value: NotificationService.fake(),
        child: MaterialApp(
          theme: BoardhopTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: ThemeScope(
            controller: ThemeController.inMemory(),
            child: DisplayScope.override(
              barEdge: edge,
              window: const Size(1032, 1376),
              child: const SettingsPage(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the switch is offered where iOS names no bar edge', (
    tester,
  ) async {
    await pump(tester, edge: BarEdge.unspecified);
    expect(find.text('Tab rail on the right'), findsOneWidget);
  });

  testWidgets('and hidden where it does', (tester) async {
    await pump(tester, edge: BarEdge.trailing);
    expect(find.text('Tab rail on the right'), findsNothing);
    await pump(tester, edge: BarEdge.leading);
    expect(find.text('Tab rail on the right'), findsNothing);
  });
}
